//! PURE per-service pricing rules: the platform commission and the cancellation fee. No
//! DB/HTTP imports — 100% unit-testable (the only shared import is the error TYPE, like
//! [`crate::domain::cancellation`]).
//!
//! Two knobs live on a catalog service (migration 0010) and are SNAPSHOT onto every booking
//! created from it ([`PricingSnapshot`]):
//!
//!   * `commission_percent` — the platform's cut of ONE guard's pay. Deducted from the GUARD,
//!     never added to the customer: `guard_net = guard_gross − guard_gross × pct / 100`.
//!   * `cancellation_fee` — a flat ฿ amount kept when the CUSTOMER cancels before work starts
//!     (`fee_charged = min(fee, amount_paid)`, so an unpaid booking costs nothing).
//!
//! This module validates the ADMIN's input only. The arithmetic that spends these numbers is
//! the payment service's (`payment::domain::pricing`) — booking owns what may be STORED, not
//! what is charged.

use rust_decimal::Decimal;

use shared::error::AppError;

/// Machine-readable `error.code` for a commission outside 0..=100. Clients branch on this
/// instead of the English message (`AppError::BadRequestCode`), like the cancel-reason codes.
pub const COMMISSION_PERCENT_INVALID_CODE: &str = "COMMISSION_PERCENT_INVALID";

/// Machine-readable `error.code` for a negative / absurd cancellation fee.
pub const CANCELLATION_FEE_INVALID_CODE: &str = "CANCELLATION_FEE_INVALID";

/// The platform may not take more than the whole of a guard's pay — 100% already means the
/// guard works for nothing, and anything above it would compute a NEGATIVE wage.
pub const MAX_COMMISSION_PERCENT: i64 = 100;

/// Upper bound on the flat cancellation fee (defensive, mirrors `MAX_SERVICE_BASE_FEE`): a
/// fat-fingered ฿100,000,000 would also overflow the column's `NUMERIC(12,2)` and surface as
/// an opaque 500 instead of a typed 400.
pub const MAX_CANCELLATION_FEE: i64 = 1_000_000;

/// Decimal places both values are normalized to — the scale of their columns
/// (`NUMERIC(5,2)` / `NUMERIC(12,2)`), via `Decimal::round_dp` like every other money rounding
/// in the workspace (payment's proration/pricing). Rounding HERE rather than binding the raw
/// value and letting the `NUMERIC` cast do it means the number the admin gets back in the
/// response is byte-for-byte the number stored — and it is OUR rounding rule, not Postgres'
/// (which rounds halves away from zero, where `round_dp` rounds them to even).
pub const MONEY_SCALE: u32 = 2;

/// Validate an admin-supplied commission percent and normalize it to the column's scale.
///
/// Rules: `0 <= pct <= 100`, then rounded to [`MONEY_SCALE`] decimal places. Out of range →
/// 400 [`COMMISSION_PERCENT_INVALID_CODE`].
///
/// The range check runs BEFORE the rounding on purpose: `100.004` is out of range and must be
/// REFUSED, not quietly rounded down into a legal `100.00`. Rounding a value INTO range is
/// exactly the kind of silent correction that hides a fat finger on a money field.
pub fn validate_commission_percent(percent: Decimal) -> Result<Decimal, AppError> {
    if percent < Decimal::ZERO || percent > Decimal::from(MAX_COMMISSION_PERCENT) {
        return Err(AppError::BadRequestCode {
            code: COMMISSION_PERCENT_INVALID_CODE,
            message: format!("commission_percent must be between 0 and {MAX_COMMISSION_PERCENT}"),
        });
    }
    Ok(percent.round_dp(MONEY_SCALE))
}

/// Validate an admin-supplied flat cancellation fee and normalize it to the column's scale.
///
/// Rules: `0 <= fee <= `[`MAX_CANCELLATION_FEE`], rounded to [`MONEY_SCALE`] decimal places.
/// Out of range → 400 [`CANCELLATION_FEE_INVALID_CODE`]. A fee of 0 (the default) means "this
/// service charges nothing for a pre-arrival cancel" — the pre-0010 behaviour.
pub fn validate_cancellation_fee(fee: Decimal) -> Result<Decimal, AppError> {
    if fee < Decimal::ZERO || fee > Decimal::from(MAX_CANCELLATION_FEE) {
        return Err(AppError::BadRequestCode {
            code: CANCELLATION_FEE_INVALID_CODE,
            message: format!("cancellation_fee must be between 0 and {MAX_CANCELLATION_FEE}"),
        });
    }
    Ok(fee.round_dp(MONEY_SCALE))
}

/// The catalog money COPIED onto a booking at creation — the whole point being that the money
/// of a booking already made never moves when an admin edits the catalog afterwards.
///
/// Built by the API layer from the chosen `ServiceCatalogItem` (the domain deliberately does
/// not import the DB-backed model). Absence of a snapshot — the customer picked no catalog
/// service — is represented by `Option<PricingSnapshot>` at the call site, NOT by a variant
/// here: in that case `base_fee` must fall to its server-owned column DEFAULT, which is a
/// property of the INSERT, while commission/fee are simply [`PricingSnapshot::NONE_SELECTED`]'s
/// zeroes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PricingSnapshot {
    /// ฿ per hour per guard — the catalog's authoritative rate.
    pub base_fee: Decimal,
    /// The platform's cut of the guard's pay, in percent (0 = the platform takes nothing).
    pub commission_percent: Decimal,
    /// Flat ฿ kept when the CUSTOMER cancels pre-arrival (0 = free cancellation).
    pub cancellation_fee: Decimal,
}

impl PricingSnapshot {
    /// What a booking created with NO catalog service snapshots for the two 0010 columns:
    /// literal zeroes, not NULL. NULL is reserved for pre-migration rows; a booking made today
    /// always states its terms, and "no service chosen" states them as "no cut, no fee".
    pub const NONE_SELECTED: (Decimal, Decimal) = (Decimal::ZERO, Decimal::ZERO);

    /// The `(commission_percent, cancellation_fee)` pair to persist — the snapshot's own values,
    /// or [`Self::NONE_SELECTED`] when the customer picked no catalog service.
    pub fn terms_or_zero(snapshot: Option<&Self>) -> (Decimal, Decimal) {
        match snapshot {
            Some(s) => (s.commission_percent, s.cancellation_fee),
            None => Self::NONE_SELECTED,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dec(s: &str) -> Decimal {
        s.parse().expect("parse decimal")
    }

    fn code_of(err: &AppError) -> Option<&'static str> {
        match err {
            AppError::BadRequestCode { code, .. } => Some(code),
            _ => None,
        }
    }

    // ----- commission percent: 0..=100 -----

    #[test]
    fn commission_accepts_the_whole_legal_range() {
        for ok in ["0", "0.01", "7", "12.50", "99.99", "100"] {
            let got = validate_commission_percent(dec(ok))
                .unwrap_or_else(|e| panic!("{ok}% must be a legal commission: {e}"));
            assert_eq!(got, dec(ok).round_dp(MONEY_SCALE), "{ok}");
        }
    }

    #[test]
    fn commission_rejects_negative_and_over_one_hundred() {
        // Above 100% would pay the guard a NEGATIVE wage; below 0 would pay them a bonus out of
        // the platform's pocket. Both are typed 400s, not silent clamps.
        for bad in ["-0.01", "-1", "100.01", "101", "999.99"] {
            let err = validate_commission_percent(dec(bad))
                .expect_err("out-of-range commission must be refused");
            assert_eq!(
                code_of(&err),
                Some(COMMISSION_PERCENT_INVALID_CODE),
                "percent {bad}"
            );
        }
    }

    #[test]
    fn commission_is_rounded_to_the_column_scale() {
        // NUMERIC(5,2) would round on write; doing it here means the admin's response echoes
        // exactly what was stored.
        assert_eq!(
            validate_commission_percent(dec("7.126")).unwrap(),
            dec("7.13")
        );
        assert_eq!(
            validate_commission_percent(dec("7.124")).unwrap(),
            dec("7.12")
        );
        // Rounding UP to the cap is fine — the value was already legal before rounding.
        assert_eq!(
            validate_commission_percent(dec("99.996")).unwrap(),
            dec("100.00")
        );
        // …but an out-of-range value is REFUSED, never rounded INTO range.
        assert!(
            validate_commission_percent(dec("100.004")).is_err(),
            "100.004 is over the cap; rounding it down to a legal 100.00 would hide the typo"
        );
    }

    // ----- cancellation fee: >= 0 -----

    #[test]
    fn cancellation_fee_accepts_zero_and_positive() {
        for ok in ["0", "0.50", "150", "1500.00", "1000000"] {
            let got = validate_cancellation_fee(dec(ok))
                .unwrap_or_else(|e| panic!("฿{ok} must be a legal fee: {e}"));
            assert_eq!(got, dec(ok).round_dp(MONEY_SCALE), "{ok}");
        }
    }

    #[test]
    fn cancellation_fee_rejects_negative_and_absurd() {
        // A negative fee would PAY the customer for cancelling; an absurd one overflows
        // NUMERIC(12,2) into a 500.
        for bad in ["-0.01", "-100", "1000000.01", "99999999999"] {
            let err =
                validate_cancellation_fee(dec(bad)).expect_err("out-of-range fee must be refused");
            assert_eq!(
                code_of(&err),
                Some(CANCELLATION_FEE_INVALID_CODE),
                "fee {bad}"
            );
        }
    }

    #[test]
    fn cancellation_fee_is_rounded_to_the_column_scale() {
        assert_eq!(
            validate_cancellation_fee(dec("150.006")).unwrap(),
            dec("150.01")
        );
        assert_eq!(
            validate_cancellation_fee(dec("150.004")).unwrap(),
            dec("150.00")
        );
        // `round_dp` is half-to-EVEN (the workspace's money convention, cf. payment's
        // proration): an exact half goes to the even hundredth, NOT away from zero the way a
        // raw `::numeric(12,2)` cast in Postgres would. Rounding here is what keeps the two
        // from ever disagreeing.
        assert_eq!(
            validate_cancellation_fee(dec("150.005")).unwrap(),
            dec("150.00")
        );
        assert_eq!(
            validate_cancellation_fee(dec("150.015")).unwrap(),
            dec("150.02")
        );
    }

    // ----- the snapshot -----

    #[test]
    fn no_service_snapshots_zeroes_not_nulls() {
        let (pct, fee) = PricingSnapshot::terms_or_zero(None);
        assert_eq!(pct, Decimal::ZERO);
        assert_eq!(fee, Decimal::ZERO);
    }

    #[test]
    fn a_chosen_service_snapshots_its_own_terms() {
        let snap = PricingSnapshot {
            base_fee: dec("230.00"),
            commission_percent: dec("12.50"),
            cancellation_fee: dec("150.00"),
        };
        let (pct, fee) = PricingSnapshot::terms_or_zero(Some(&snap));
        assert_eq!(pct, dec("12.50"));
        assert_eq!(fee, dec("150.00"));
    }
}
