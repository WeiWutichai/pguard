//! PURE scheduling-time rules. No DB/HTTP imports — 100% unit-testable (the only shared
//! import is the error TYPE, mirroring [`crate::domain::progress`] and [`crate::domain::geo`]).
//!
//! Two server-authoritative time gates keyed off a booking's `scheduled_at`:
//!   * [`validate_scheduled_at`] (C4) — a booking may not be CREATED for a time already in the
//!     past. The customer's device clock is never trusted; the server compares against its own
//!     `now`. Code `SCHEDULED_IN_PAST` (400).
//!   * [`validate_start_time`] (G3) — the assigned guard may not START the job long before the
//!     customer booked it (a 15-min early grace covers a guard who arrives a touch early). Code
//!     `START_TOO_EARLY` (409).
//!
//! Both take `now` as a parameter (never read the clock here) so the rules stay pure and the
//! boundaries are exercised deterministically in unit tests.

use chrono::{DateTime, Duration, Utc};

use shared::error::AppError;

/// Machine-readable `error.code` for a start pressed before the booking's scheduled window
/// opens. Clients branch on this sub-code (see `AppError::ConflictCode`) to render a localized
/// "ยังไม่ถึงเวลาเริ่มงาน" hint instead of the English message.
pub const START_TOO_EARLY_CODE: &str = "START_TOO_EARLY";

/// Machine-readable `error.code` for creating a booking whose `scheduled_at` is already in the
/// past. Clients branch on this (`AppError::BadRequestCode`) and localize the copy themselves.
pub const SCHEDULED_IN_PAST_CODE: &str = "SCHEDULED_IN_PAST";

/// Early grace before `scheduled_at` within which a start is allowed: a guard who is on-site a
/// little ahead of schedule can begin, but not arbitrarily early.
pub const START_EARLY_GRACE_MINUTES: i64 = 15;

/// C4 — validate that a booking may be created for `scheduled_at` given the server's `now`.
///
/// A booking may only be scheduled STRICTLY in the future: `scheduled_at <= now` is rejected
/// (a booking "for now-or-earlier" is a client clock error, not a bookable job). The `<=`
/// boundary means `scheduled_at == now` is refused — an at-this-instant booking is not a
/// scheduled request.
pub fn validate_scheduled_at(
    scheduled_at: DateTime<Utc>,
    now: DateTime<Utc>,
) -> Result<(), AppError> {
    if scheduled_at <= now {
        return Err(AppError::BadRequestCode {
            code: SCHEDULED_IN_PAST_CODE,
            message: "Scheduled time must be in the future".to_string(),
        });
    }
    Ok(())
}

/// G3 — validate that the assigned guard may START a job scheduled for `scheduled_at` given the
/// server's `now`.
///
/// The start window opens at `scheduled_at - `[`START_EARLY_GRACE_MINUTES`]; a start before
/// that is [`START_TOO_EARLY_CODE`] (409). At or after the boundary it passes. There is no
/// upper bound here — a late start is legitimate (the guard may have been held up en route).
pub fn validate_start_time(
    scheduled_at: DateTime<Utc>,
    now: DateTime<Utc>,
) -> Result<(), AppError> {
    let opens_at = scheduled_at - Duration::minutes(START_EARLY_GRACE_MINUTES);
    if now < opens_at {
        return Err(AppError::ConflictCode {
            code: START_TOO_EARLY_CODE,
            message: "Too early to start this job".to_string(),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn t0() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 6, 10, 8, 0, 0).unwrap()
    }

    fn code_of(err: &AppError) -> &'static str {
        match err {
            AppError::ConflictCode { code, .. } | AppError::BadRequestCode { code, .. } => code,
            other => panic!("expected coded error, got {other:?}"),
        }
    }

    // ----- validate_scheduled_at (C4) -----

    #[test]
    fn scheduled_future_is_ok() {
        // One second into the future is fine.
        let now = t0();
        assert!(validate_scheduled_at(now + Duration::seconds(1), now).is_ok());
        assert!(validate_scheduled_at(now + Duration::hours(3), now).is_ok());
    }

    #[test]
    fn scheduled_now_or_past_is_rejected() {
        let now = t0();
        // Exactly now → rejected (the boundary is `<=`).
        let err = validate_scheduled_at(now, now).unwrap_err();
        assert_eq!(code_of(&err), SCHEDULED_IN_PAST_CODE);
        assert!(matches!(err, AppError::BadRequestCode { .. }));
        // A second in the past → rejected.
        let err = validate_scheduled_at(now - Duration::seconds(1), now).unwrap_err();
        assert_eq!(code_of(&err), SCHEDULED_IN_PAST_CODE);
    }

    // ----- validate_start_time (G3) -----

    #[test]
    fn start_within_grace_before_scheduled_is_ok() {
        let scheduled = t0();
        // Exactly at the grace boundary (scheduled − 15m) → open.
        let boundary = scheduled - Duration::minutes(START_EARLY_GRACE_MINUTES);
        assert!(validate_start_time(scheduled, boundary).is_ok());
        // At the scheduled time itself → open.
        assert!(validate_start_time(scheduled, scheduled).is_ok());
        // Well after the scheduled time (late start) → open (no upper bound).
        assert!(validate_start_time(scheduled, scheduled + Duration::hours(2)).is_ok());
    }

    #[test]
    fn start_before_grace_window_is_too_early() {
        let scheduled = t0();
        // One second before the grace boundary → too early.
        let before =
            scheduled - Duration::minutes(START_EARLY_GRACE_MINUTES) - Duration::seconds(1);
        let err = validate_start_time(scheduled, before).unwrap_err();
        assert_eq!(code_of(&err), START_TOO_EARLY_CODE);
        assert!(matches!(err, AppError::ConflictCode { .. }));
        // An hour early → too early.
        let err = validate_start_time(scheduled, scheduled - Duration::hours(1)).unwrap_err();
        assert_eq!(code_of(&err), START_TOO_EARLY_CODE);
    }
}
