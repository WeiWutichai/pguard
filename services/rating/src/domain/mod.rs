//! PURE domain logic — no DB, no HTTP, no NATS. 100% unit-testable.
//!
//! - [`validate_review`] — rating-range validation (overall required, categories optional;
//!   all whole-star `1..=5`). Ported from v1 `submit_review`'s range checks.
//! - [`compute_summary`] — the visible-reviews aggregation (AVG + COUNT) other services
//!   consume for guard discovery. The caller (repo) passes only `is_visible = true` scores,
//!   so admin-hidden reviews never affect the public summary.

use rust_decimal::Decimal;

/// Whole-star rating bounds (mirrors the DB CHECK + v1's 1..=5).
pub const MIN_RATING: i32 = 1;
pub const MAX_RATING: i32 = 5;
/// Upper bound on a review's free-text (chars). Bounds stored size + the public response
/// payload; the DB CHECK + OpenAPI `maxLength` mirror this. Counts Unicode scalar values so
/// the limit is consistent for Thai/English (the DB uses `char_length`, which agrees).
pub const MAX_REVIEW_TEXT_LEN: usize = 2000;

/// Why a review submission was rejected (pure error — the API maps it to a 400).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RatingError {
    Overall,
    Punctuality,
    Professionalism,
    Communication,
    Appearance,
    ReviewTextTooLong,
}

impl RatingError {
    /// A generic client message (no internal leak). Names the offending field + the range.
    pub fn message(self) -> &'static str {
        match self {
            RatingError::Overall => "overall_rating must be between 1 and 5",
            RatingError::Punctuality => "punctuality must be between 1 and 5",
            RatingError::Professionalism => "professionalism must be between 1 and 5",
            RatingError::Communication => "communication must be between 1 and 5",
            RatingError::Appearance => "appearance must be between 1 and 5",
            RatingError::ReviewTextTooLong => "review_text must be at most 2000 characters",
        }
    }
}

fn in_range(v: i32) -> bool {
    (MIN_RATING..=MAX_RATING).contains(&v)
}

/// Validate a review: `overall` is required and must be `1..=5`; each category, when present,
/// must also be `1..=5`; `review_text`, when present, must be at most [`MAX_REVIEW_TEXT_LEN`]
/// chars (bounds stored size + the public payload). Pure — no I/O, exhaustively unit-testable.
pub fn validate_review(
    overall: i32,
    punctuality: Option<i32>,
    professionalism: Option<i32>,
    communication: Option<i32>,
    appearance: Option<i32>,
    review_text: Option<&str>,
) -> Result<(), RatingError> {
    if !in_range(overall) {
        return Err(RatingError::Overall);
    }
    for (val, err) in [
        (punctuality, RatingError::Punctuality),
        (professionalism, RatingError::Professionalism),
        (communication, RatingError::Communication),
        (appearance, RatingError::Appearance),
    ] {
        if let Some(v) = val {
            if !in_range(v) {
                return Err(err);
            }
        }
    }
    if let Some(t) = review_text {
        if t.chars().count() > MAX_REVIEW_TEXT_LEN {
            return Err(RatingError::ReviewTextTooLong);
        }
    }
    Ok(())
}

/// A review is only legitimate once the job is actually `completed` (the customer can't rate
/// a job that did not happen). Pure rule over the booking status text (mirrors payment's
/// `is_finalizable_status`), so it lives in one place and is unit-testable without a DB.
pub fn is_reviewable_status(status: &str) -> bool {
    status == "completed"
}

/// A guard's rating summary: how many visible reviews + their average overall rating.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RatingSummary {
    pub count: i64,
    /// `None` when there are no visible reviews (avoid a misleading 0.0 average).
    pub average: Option<Decimal>,
}

/// Aggregate the overall ratings of a guard's VISIBLE reviews into `{ count, average }`.
/// The average is rounded to 2 dp; an empty input yields `count = 0, average = None`.
/// Pure: the caller filters `is_visible = true` before passing scores in.
pub fn compute_summary(overall_scores: &[i32]) -> RatingSummary {
    let count = overall_scores.len() as i64;
    if count == 0 {
        return RatingSummary {
            count: 0,
            average: None,
        };
    }
    let sum: i64 = overall_scores.iter().map(|&s| s as i64).sum();
    let average = (Decimal::from(sum) / Decimal::from(count)).round_dp(2);
    RatingSummary {
        count,
        average: Some(average),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dec(s: &str) -> Decimal {
        s.parse().unwrap()
    }

    #[test]
    fn accepts_overall_only() {
        assert!(validate_review(5, None, None, None, None, None).is_ok());
        assert!(validate_review(1, None, None, None, None, None).is_ok());
    }

    #[test]
    fn accepts_all_categories_in_range() {
        assert!(validate_review(4, Some(5), Some(3), Some(4), Some(2), Some("ok")).is_ok());
    }

    #[test]
    fn rejects_overall_out_of_range() {
        assert_eq!(
            validate_review(0, None, None, None, None, None),
            Err(RatingError::Overall)
        );
        assert_eq!(
            validate_review(6, None, None, None, None, None),
            Err(RatingError::Overall)
        );
    }

    #[test]
    fn rejects_each_category_out_of_range() {
        assert_eq!(
            validate_review(5, Some(0), None, None, None, None),
            Err(RatingError::Punctuality)
        );
        assert_eq!(
            validate_review(5, None, Some(6), None, None, None),
            Err(RatingError::Professionalism)
        );
        assert_eq!(
            validate_review(5, None, None, Some(9), None, None),
            Err(RatingError::Communication)
        );
        assert_eq!(
            validate_review(5, None, None, None, Some(-1), None),
            Err(RatingError::Appearance)
        );
    }

    #[test]
    fn accepts_review_text_at_limit_rejects_over() {
        let at_limit = "ก".repeat(MAX_REVIEW_TEXT_LEN); // multibyte → count by chars, not bytes
        assert!(
            validate_review(5, None, None, None, None, Some(&at_limit)).is_ok(),
            "exactly the limit (in chars) is fine"
        );
        let over = "a".repeat(MAX_REVIEW_TEXT_LEN + 1);
        assert_eq!(
            validate_review(5, None, None, None, None, Some(&over)),
            Err(RatingError::ReviewTextTooLong)
        );
    }

    #[test]
    fn messages_name_the_field_and_range() {
        assert_eq!(
            RatingError::Overall.message(),
            "overall_rating must be between 1 and 5"
        );
        assert_eq!(
            RatingError::Appearance.message(),
            "appearance must be between 1 and 5"
        );
        assert_eq!(
            RatingError::ReviewTextTooLong.message(),
            "review_text must be at most 2000 characters"
        );
    }

    #[test]
    fn summary_of_empty_is_zero_count_none_average() {
        let s = compute_summary(&[]);
        assert_eq!(s.count, 0);
        assert_eq!(s.average, None);
    }

    #[test]
    fn summary_counts_and_averages() {
        // [5,4,3] → count 3, avg 4.00
        let s = compute_summary(&[5, 4, 3]);
        assert_eq!(s.count, 3);
        assert_eq!(s.average, Some(dec("4.00")));
    }

    #[test]
    fn summary_average_rounds_to_two_dp() {
        // [5,4] → 4.5 → 4.50 ; [5,4,4] → 13/3 = 4.333.. → 4.33
        assert_eq!(compute_summary(&[5, 4]).average, Some(dec("4.50")));
        assert_eq!(compute_summary(&[5, 4, 4]).average, Some(dec("4.33")));
    }

    #[test]
    fn summary_single_review() {
        let s = compute_summary(&[5]);
        assert_eq!(s.count, 1);
        assert_eq!(s.average, Some(dec("5.00")));
    }

    #[test]
    fn only_completed_is_reviewable() {
        assert!(is_reviewable_status("completed"));
        for s in [
            "requested",
            "accepted",
            "en_route",
            "arrived",
            "cancelled",
            "",
            "COMPLETED",
        ] {
            assert!(!is_reviewable_status(s), "{s} must not be reviewable");
        }
    }
}
