//! PURE selection logic for stream ② *ยอดที่โดนหักเข้าระบบ* — the PLATFORM-CUT sweep. No DB, no
//! HTTP; 100% unit-testable. The money math itself lives in [`crate::domain::settlement`]; this is
//! only "which jobs does this run cover, and which items may a void release".
//!
//! It is the SHORTEST of the three streams' selection modules, and the reason is structural rather
//! than an omission. A payout run picks GUARDS and a refund run picks CUSTOMERS, because each of
//! those files carries one credit line per recipient and the admin ticks who gets paid. An `OAT`
//! sweep credits ONE destination — the company's own revenue account — so the file has a SINGLE
//! `TXNDET` and there is nobody to tick: the only thing to choose is the DAY WINDOW. Offering a
//! per-job tick-list would let an admin sweep half a day's cut and leave the rest looking unswept
//! for no reason anyone could reconstruct later.

use chrono::NaiveDate;
use shared::error::AppError;
use uuid::Uuid;

/// WHICH settled jobs one preview/export run covers. Both ends optional and inclusive (Thai
/// calendar days); all-`None` is the default "sweep the whole unswept backlog", exactly like
/// [`crate::domain::payout::PayoutSelection`] and [`crate::domain::refund_export::RefundSelection`].
///
/// "The whole backlog" is bounded at the REPO, not here: `repo::unswept_deduction_rows` refuses a run
/// larger than `repo::MAX_SWEEP_BACKLOG_ROWS` with a typed "narrow the window" 400 rather than
/// truncating it, because a short total on a money screen looks exactly like a correct one. That is a
/// runaway guard on an I/O query, so it lives with the query; this type stays pure.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DeductionSelection {
    /// Inclusive first day the job was SETTLED (Thai local date).
    pub from: Option<NaiveDate>,
    /// Inclusive last day the job was SETTLED (Thai local date).
    pub to: Option<NaiveDate>,
}

impl DeductionSelection {
    /// Reject a window that cannot mean anything. PURE: no I/O, so the API layer validates before
    /// touching the DB.
    pub fn validate(&self) -> Result<(), AppError> {
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

/// Upper bound on how many jobs ONE per-item void may name. Same reasoning as the other two
/// streams': a longer list is a client bug, and this is an admin correcting the handful of jobs a
/// sweep should not have collected, never a bulk operation.
pub const MAX_VOIDED_DEDUCTION_ITEMS: usize = 500;

/// Normalise the `payment_ids` of a per-item void into the list the repo may act on:
/// DE-DUPLICATED (order preserved), non-empty, and within [`MAX_VOIDED_DEDUCTION_ITEMS`].
///
/// De-duplicating is not tidiness — it is what keeps the repo's "every named job must have been
/// released" count honest. `[p, p]` updates ONE row, so a repo comparing `rows_affected` against the
/// requested length would see 1 ≠ 2 and refuse a request that is really just clumsy; and not
/// comparing at all would let a genuinely wrong id pass silently.
///
/// An EMPTY list is refused rather than treated as "all of them": the whole-batch void is a
/// different, more dangerous action with its own endpoint, and a client bug must never escalate into
/// it. PURE: no I/O, so the API layer validates before touching the DB.
pub fn normalize_voided_payment_ids(ids: &[Uuid]) -> Result<Vec<Uuid>, AppError> {
    if ids.is_empty() {
        return Err(AppError::BadRequest(
            "เลือกงานอย่างน้อย 1 รายการที่ต้องการดึงกลับเข้าคิวรอหักเข้าระบบ".to_string(),
        ));
    }
    if ids.len() > MAX_VOIDED_DEDUCTION_ITEMS {
        return Err(AppError::BadRequest(format!(
            "ดึงงานกลับได้ไม่เกิน {MAX_VOIDED_DEDUCTION_ITEMS} รายการต่อครั้ง"
        )));
    }
    let mut out: Vec<Uuid> = Vec::with_capacity(ids.len());
    for id in ids {
        if !out.contains(id) {
            out.push(*id);
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn day(y: i32, m: u32, d: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, d).expect("valid date")
    }

    #[test]
    fn the_default_selection_is_the_whole_unswept_backlog() {
        let sel = DeductionSelection::default();
        assert_eq!((sel.from, sel.to), (None, None));
        assert!(sel.validate().is_ok());
    }

    #[test]
    fn a_window_is_inclusive_at_both_ends_and_may_be_a_single_day() {
        assert!(DeductionSelection {
            from: Some(day(2026, 9, 1)),
            to: Some(day(2026, 9, 30)),
        }
        .validate()
        .is_ok());
        // "sweep exactly today's cut" is a legitimate run.
        assert!(DeductionSelection {
            from: Some(day(2026, 9, 7)),
            to: Some(day(2026, 9, 7)),
        }
        .validate()
        .is_ok());
        // One open end is fine too (everything up to a cut-off, or everything since).
        for sel in [
            DeductionSelection {
                from: Some(day(2026, 9, 1)),
                to: None,
            },
            DeductionSelection {
                from: None,
                to: Some(day(2026, 9, 30)),
            },
        ] {
            assert!(sel.validate().is_ok());
        }
    }

    #[test]
    fn an_inverted_window_is_refused_before_the_database_is_touched() {
        let inverted = DeductionSelection {
            from: Some(day(2026, 9, 30)),
            to: Some(day(2026, 9, 1)),
        };
        assert!(matches!(inverted.validate(), Err(AppError::BadRequest(_))));
    }

    #[test]
    fn voided_payment_ids_are_deduplicated_bounded_and_never_empty() {
        let a = Uuid::new_v4();
        let b = Uuid::new_v4();
        assert_eq!(
            normalize_voided_payment_ids(&[a, b, a]).expect("valid"),
            vec![a, b],
            "order preserved, the exact repeat dropped"
        );
        // Empty is NOT "all of them" — that is the whole-batch void's job, and it is the more
        // dangerous action.
        assert!(matches!(
            normalize_voided_payment_ids(&[]),
            Err(AppError::BadRequest(_))
        ));
        let many: Vec<Uuid> = (0..MAX_VOIDED_DEDUCTION_ITEMS + 1)
            .map(|_| Uuid::new_v4())
            .collect();
        assert!(matches!(
            normalize_voided_payment_ids(&many),
            Err(AppError::BadRequest(_))
        ));
        // …and exactly at the cap is still fine (an off-by-one here would refuse a legal request).
        let at_cap: Vec<Uuid> = (0..MAX_VOIDED_DEDUCTION_ITEMS)
            .map(|_| Uuid::new_v4())
            .collect();
        assert_eq!(
            normalize_voided_payment_ids(&at_cap)
                .expect("at the cap")
                .len(),
            MAX_VOIDED_DEDUCTION_ITEMS
        );
    }
}
