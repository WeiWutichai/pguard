//! PURE guard-payout money math — no DB/HTTP. The ONE place that turns a completed job's pricing
//! inputs into the three payout figures the SCB file carries. 100% unit-testable.
//!
//! It mirrors the EXISTING guard-earnings model (the figure the guard already sees on their
//! earnings screen) so a payout never disagrees with what the guard was shown:
//!   gross      = base_fee × hours                      (ONE guard's share; NO tip, NO guard_count)
//!   commission = gross × commission_percent / 100      (the platform's cut, out of the guard's pay)
//!   income     = gross − commission                    (the guard's assessable income / pay basis)
//!   wht        = income × wht_rate_percent / 100        (ภ.ง.ด.53 withholding)
//!   transfer   = income − wht                          (the actual PromptPay amount)
//! Every figure is rounded to 2 dp (banker's, matching the rest of the money path). `hours` is the
//! ACTUAL worked hours when reconciled (else the booked hours — resolved by the caller, not here).

use chrono::NaiveDate;
use rust_decimal::Decimal;
use shared::error::AppError;
use uuid::Uuid;

/// WHICH guards, over WHICH finished-job window, this payout run covers. Both parts are optional
/// and independent: `None`/`None` = the default "pay the WHOLE unpaid backlog, everyone" the export
/// has always done. `guard_ids = Some([..])` is the admin cherry-picking recipients on the preview
/// screen; `from`/`to` bound the jobs by the day they were finished + reconciled (inclusive, Thai
/// calendar days). A guard the admin did NOT tick keeps their jobs unpaid and in the next backlog —
/// selection never marks anything paid outside it (the paid-markers are written from the same
/// filtered rows).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PayoutSelection {
    /// The guards to pay; `None` = every guard with an unpaid, payable job.
    pub guard_ids: Option<Vec<Uuid>>,
    /// Inclusive first day of the finished-job window (Thai local date).
    pub from: Option<NaiveDate>,
    /// Inclusive last day of the finished-job window (Thai local date).
    pub to: Option<NaiveDate>,
}

/// Upper bound on how many guards ONE export may name — a longer list is a client bug, not an
/// admin action (and the file is uploaded to SCB by hand). The backlog-wide default is unbounded.
pub const MAX_SELECTED_GUARDS: usize = 500;

impl PayoutSelection {
    /// Reject a selection that cannot mean anything: an EXPLICIT but empty guard list (the admin
    /// ticked nobody — silently paying everyone would be a money bug), an absurdly long list, or an
    /// inverted date window. PURE: no I/O, so the API layer can validate before touching the DB.
    pub fn validate(&self) -> Result<(), AppError> {
        if let Some(ids) = &self.guard_ids {
            if ids.is_empty() {
                return Err(AppError::BadRequest(
                    "เลือก รปภ อย่างน้อย 1 คนก่อนสร้างไฟล์".to_string(),
                ));
            }
            if ids.len() > MAX_SELECTED_GUARDS {
                return Err(AppError::BadRequest(format!(
                    "เลือก รปภ ได้ไม่เกิน {MAX_SELECTED_GUARDS} คนต่อไฟล์"
                )));
            }
        }
        if let (Some(from), Some(to)) = (self.from, self.to) {
            if from > to {
                return Err(AppError::BadRequest(
                    "ช่วงวันที่ไม่ถูกต้อง (วันเริ่มต้องไม่เกินวันสิ้นสุด)".to_string(),
                ));
            }
        }
        Ok(())
    }
}

/// The three payout figures for one completed job. `transfer` is what is actually PromptPay-ed to
/// the guard; `income`/`wht` are what the ภ.ง.ด.53 certificate records.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PayoutAmounts {
    pub income: Decimal,
    pub wht: Decimal,
    pub transfer: Decimal,
}

/// Compute one job's payout figures. `commission_percent` is the per-service snapshot (`None`, or a
/// job that predates commissions, → 0%; clamped to `0..=100` defensively). `wht_rate_percent` is the
/// batch withholding rate (0 → no WHT withheld, `wht == 0`, `transfer == income`).
pub fn compute_payout(
    base_fee: Decimal,
    hours: Decimal,
    commission_percent: Option<Decimal>,
    wht_rate_percent: Decimal,
) -> PayoutAmounts {
    let hundred = Decimal::from(100);
    let pct = commission_percent
        .unwrap_or(Decimal::ZERO)
        .clamp(Decimal::ZERO, hundred);
    let gross = (base_fee * hours).round_dp(2);
    let commission = (gross * pct / hundred).round_dp(2);
    let income = gross - commission;
    let wht = (income * wht_rate_percent / hundred).round_dp(2);
    let transfer = income - wht;
    PayoutAmounts {
        income,
        wht,
        transfer,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(s: &str) -> Decimal {
        s.parse().unwrap()
    }

    #[test]
    fn standard_job_with_commission_and_wht() {
        // 200/hr × 4h = 800 gross; 10% commission = 80 → income 720; 3% WHT = 21.60 → transfer 698.40.
        let a = compute_payout(d("200"), d("4"), Some(d("10")), d("3"));
        assert_eq!(a.income, d("720.00"));
        assert_eq!(a.wht, d("21.60"));
        assert_eq!(a.transfer, d("698.40"));
    }

    #[test]
    fn no_commission_none_treated_as_zero() {
        let a = compute_payout(d("100"), d("2"), None, d("3"));
        assert_eq!(a.income, d("200.00"), "no commission → income == gross");
        assert_eq!(a.wht, d("6.00"));
        assert_eq!(a.transfer, d("194.00"));
    }

    #[test]
    fn zero_wht_rate_transfers_full_income() {
        let a = compute_payout(d("150"), d("3"), Some(d("20")), d("0"));
        assert_eq!(a.income, d("360.00")); // 450 − 90
        assert_eq!(a.wht, d("0.00"));
        assert_eq!(a.transfer, d("360.00"));
    }

    #[test]
    fn commission_clamped_to_0_100() {
        // A bogus >100% snapshot cannot make the guard's income negative — clamp at 100 (income 0).
        let a = compute_payout(d("100"), d("1"), Some(d("150")), d("3"));
        assert_eq!(a.income, d("0.00"));
        assert_eq!(a.wht, d("0.00"));
        assert_eq!(a.transfer, d("0.00"));
        // A negative snapshot clamps at 0 (never PAYS the guard extra commission).
        let b = compute_payout(d("100"), d("1"), Some(d("-5")), d("3"));
        assert_eq!(b.income, d("100.00"));
    }

    #[test]
    fn fractional_hours_and_rounding() {
        // 175/hr × 1.5h = 262.50 gross; 7.5% commission = 19.6875 → round 19.69 → income 242.81;
        // 3% WHT = 7.2843 → round 7.28 → transfer 235.53.
        let a = compute_payout(d("175"), d("1.5"), Some(d("7.5")), d("3"));
        assert_eq!(a.income, d("242.81"));
        assert_eq!(a.wht, d("7.28"));
        assert_eq!(a.transfer, d("235.53"));
    }

    // ----- selection (which guards / which window) -----

    fn day(y: i32, m: u32, d: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, d).unwrap()
    }

    #[test]
    fn default_selection_is_everyone_whole_backlog() {
        let sel = PayoutSelection::default();
        assert_eq!(sel.guard_ids, None);
        assert_eq!((sel.from, sel.to), (None, None));
        assert!(sel.validate().is_ok());
    }

    #[test]
    fn many_guards_and_a_valid_window_are_accepted() {
        let sel = PayoutSelection {
            guard_ids: Some(vec![Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4()]),
            from: Some(day(2026, 9, 1)),
            to: Some(day(2026, 9, 30)),
        };
        assert!(sel.validate().is_ok(), "a multi-guard batch is the point");
        // a single-day window (from == to) is a legitimate "pay today's finished jobs" run.
        let same_day = PayoutSelection {
            guard_ids: None,
            from: Some(day(2026, 9, 4)),
            to: Some(day(2026, 9, 4)),
        };
        assert!(same_day.validate().is_ok());
    }

    #[test]
    fn explicit_empty_guard_list_is_rejected() {
        // Ticking nobody must NOT silently fall back to paying the whole backlog.
        let sel = PayoutSelection {
            guard_ids: Some(vec![]),
            ..Default::default()
        };
        assert!(matches!(sel.validate(), Err(AppError::BadRequest(_))));
    }

    #[test]
    fn oversized_guard_list_is_rejected() {
        let sel = PayoutSelection {
            guard_ids: Some(vec![Uuid::new_v4(); MAX_SELECTED_GUARDS + 1]),
            ..Default::default()
        };
        assert!(matches!(sel.validate(), Err(AppError::BadRequest(_))));
        let at_limit = PayoutSelection {
            guard_ids: Some(vec![Uuid::new_v4(); MAX_SELECTED_GUARDS]),
            ..Default::default()
        };
        assert!(at_limit.validate().is_ok(), "the limit itself is allowed");
    }

    #[test]
    fn inverted_window_is_rejected() {
        let sel = PayoutSelection {
            guard_ids: None,
            from: Some(day(2026, 9, 30)),
            to: Some(day(2026, 9, 1)),
        };
        assert!(matches!(sel.validate(), Err(AppError::BadRequest(_))));
        // one-sided windows stay valid (open start / open end).
        for (from, to) in [(Some(day(2026, 9, 1)), None), (None, Some(day(2026, 9, 1)))] {
            let sel = PayoutSelection {
                guard_ids: None,
                from,
                to,
            };
            assert!(sel.validate().is_ok());
        }
    }

    #[test]
    fn income_minus_wht_always_equals_transfer() {
        for (bf, h, c, r) in [
            ("200", "4", "10", "3"),
            ("99.99", "2.25", "12.5", "5"),
            ("1000", "8", "0", "1"),
        ] {
            let a = compute_payout(d(bf), d(h), Some(d(c)), d(r));
            assert_eq!(
                a.transfer,
                a.income - a.wht,
                "transfer = income − wht for {bf}/{h}"
            );
        }
    }
}
