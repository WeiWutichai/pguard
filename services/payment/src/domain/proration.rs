//! PURE proration logic — no DB, no HTTP, no NATS. 100% unit-testable.
//!
//! Ported VERBATIM (rules + arithmetic) from v1
//! `../guard-dispatch/services/booking/src/service.rs` `compute_proration` (~line 2564),
//! then lifted into v2's pure `domain/` layer so the money math is exhaustively testable
//! without a DB. ALL money is [`rust_decimal::Decimal`] — never `f64` (CLAUDE.md money rules).
//!
//! Rules (unchanged from v1):
//! - `actual_seconds` is clamped to `[0, booked_hours]` — overtime never adds to the bill
//!   (the customer can tip separately).
//! - `booked_hours <= 0` is a no-op: keep the original price (no factual basis to prorate).
//! - `final_amount = original * (actual / booked)`, rounded to 2 dp.
//! - `refund_amount = max(0, original - final)`.

use rust_decimal::Decimal;

const SECONDS_PER_HOUR: i64 = 3600;

/// The result of prorating a charge against the hours actually worked.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Proration {
    /// Hours actually worked, clamped to `[0, booked_hours]`, rounded to 2 dp.
    pub actual_hours: Decimal,
    /// The prorated amount the customer ultimately owes, rounded to 2 dp.
    pub final_amount: Decimal,
    /// `max(0, original - final)` — what is returned to the customer.
    pub refund_amount: Decimal,
}

/// Compute the prorated final amount + resulting refund.
///
/// VERBATIM port of v1 `compute_proration`. `original_amount` is the amount charged,
/// `booked_hours` the duration the customer paid for, `actual_seconds` the seconds the
/// guard actually worked.
pub fn compute_proration(
    original_amount: Decimal,
    booked_hours: i32,
    actual_seconds: i64,
) -> Proration {
    // Clamp hours worked to non-negative seconds first to avoid surprises from clock-skew
    // or out-of-order timestamps.
    let secs = actual_seconds.max(0);
    let raw_hours = Decimal::from(secs) / Decimal::from(SECONDS_PER_HOUR);

    if booked_hours <= 0 {
        // No booking duration recorded → can't prorate; keep original.
        return Proration {
            actual_hours: raw_hours,
            final_amount: original_amount,
            refund_amount: Decimal::ZERO,
        };
    }

    let booked_dec = Decimal::from(booked_hours);
    let actual = if raw_hours > booked_dec {
        booked_dec
    } else {
        raw_hours
    };

    let final_amount = if actual.is_zero() {
        Decimal::ZERO
    } else {
        (original_amount * actual / booked_dec).round_dp(2)
    };

    let refund = if original_amount > final_amount {
        original_amount - final_amount
    } else {
        Decimal::ZERO
    };

    Proration {
        // Round actual hours to 2 dp to match the DB NUMERIC(6,2).
        actual_hours: actual.round_dp(2),
        final_amount,
        refund_amount: refund,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros_inline::dec;

    /// Tiny local `dec!` so we don't pull a macro crate: parse a literal into Decimal.
    mod rust_decimal_macros_inline {
        macro_rules! dec {
            ($lit:literal) => {{
                let s = stringify!($lit);
                s.parse::<rust_decimal::Decimal>()
                    .expect("valid decimal literal")
            }};
        }
        pub(crate) use dec;
    }

    #[test]
    fn actual_less_than_booked_prorates_and_refunds() {
        // 4h booked at 400.00, worked 2h (7200s) → half → 200.00 final, 200.00 refund.
        let p = compute_proration(dec!(400.00), 4, 7200);
        assert_eq!(p.actual_hours, dec!(2.00));
        assert_eq!(p.final_amount, dec!(200.00));
        assert_eq!(p.refund_amount, dec!(200.00));
    }

    #[test]
    fn actual_equals_booked_no_refund() {
        // 4h booked, worked exactly 4h (14400s) → full charge, no refund.
        let p = compute_proration(dec!(400.00), 4, 14400);
        assert_eq!(p.actual_hours, dec!(4.00));
        assert_eq!(p.final_amount, dec!(400.00));
        assert_eq!(p.refund_amount, dec!(0));
    }

    #[test]
    fn actual_greater_than_booked_clamps_to_booked_no_overtime() {
        // Worked 6h (21600s) on a 4h booking → clamped to 4h; no overtime added.
        let p = compute_proration(dec!(400.00), 4, 21600);
        assert_eq!(p.actual_hours, dec!(4.00));
        assert_eq!(p.final_amount, dec!(400.00));
        assert_eq!(p.refund_amount, dec!(0));
    }

    #[test]
    fn actual_zero_charges_nothing_full_refund() {
        let p = compute_proration(dec!(400.00), 4, 0);
        assert_eq!(p.actual_hours, dec!(0));
        assert_eq!(p.final_amount, dec!(0));
        assert_eq!(p.refund_amount, dec!(400.00));
    }

    #[test]
    fn negative_seconds_clamped_to_zero() {
        // Clock-skew: negative actual seconds → treated as 0 worked.
        let p = compute_proration(dec!(400.00), 4, -5000);
        assert_eq!(p.actual_hours, dec!(0));
        assert_eq!(p.final_amount, dec!(0));
        assert_eq!(p.refund_amount, dec!(400.00));
    }

    #[test]
    fn booked_hours_zero_keeps_original_no_refund() {
        // No factual basis to prorate → keep the original charge, no refund.
        let p = compute_proration(dec!(400.00), 0, 7200);
        assert_eq!(p.final_amount, dec!(400.00));
        assert_eq!(p.refund_amount, dec!(0));
    }

    #[test]
    fn booked_hours_negative_keeps_original() {
        let p = compute_proration(dec!(123.45), -3, 3600);
        assert_eq!(p.final_amount, dec!(123.45));
        assert_eq!(p.refund_amount, dec!(0));
    }

    #[test]
    fn rounds_final_amount_to_two_dp() {
        // 3h booked at 100.00, worked 1h (3600s) → 100/3 = 33.333... → 33.33 to 2dp.
        let p = compute_proration(dec!(100.00), 3, 3600);
        assert_eq!(p.final_amount, dec!(33.33));
        // refund = 100.00 - 33.33 = 66.67
        assert_eq!(p.refund_amount, dec!(66.67));
        // final + refund reconstructs the original exactly (no money lost to rounding gaps).
        assert_eq!(p.final_amount + p.refund_amount, dec!(100.00));
    }

    #[test]
    fn refund_never_negative() {
        // Even pathological inputs never produce a negative refund (max(0, ...)).
        let p = compute_proration(dec!(50.00), 2, 14400); // worked >> booked
        assert!(p.refund_amount >= Decimal::ZERO);
    }

    #[test]
    fn large_amounts_stay_exact() {
        // A large charge prorated to half stays exact (no float drift).
        let p = compute_proration(dec!(9999999.99), 10, 18000); // 5h of 10h booked
                                                                // 9999999.99 * 5 / 10 = 4999999.995 → round_dp(2) = 5000000.00 (banker's? round_dp
                                                                // uses MidpointAwayFromZero) → 5000000.00.
        assert_eq!(p.final_amount, dec!(5000000.00));
        assert_eq!(p.refund_amount, dec!(4999999.99));
    }

    #[test]
    fn rounding_half_up_at_two_dp() {
        // 7h booked at 100.00, worked 1h → 100/7 = 14.2857... → 14.29.
        let p = compute_proration(dec!(100.00), 7, 3600);
        assert_eq!(p.final_amount, dec!(14.29));
    }
}
