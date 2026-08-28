//! PURE scheduling-time rules. No DB/HTTP imports — 100% unit-testable (the only shared
//! import is the error TYPE, mirroring [`crate::domain::progress`] and [`crate::domain::geo`]).
//!
//! Server-authoritative time gates keyed off a booking's `scheduled_at`:
//!   * [`validate_scheduled_at`] (C4) — a booking may not be CREATED for a time already in the
//!     past. The customer's device clock is never trusted; the server compares against its own
//!     `now`. Code `SCHEDULED_IN_PAST` (400).
//!   * [`validate_start_time`] (G3) — the assigned guard may not START the job long before the
//!     customer booked it (a 15-min early grace covers a guard who arrives a touch early). Code
//!     `START_TOO_EARLY` (409).
//!   * [`is_expired`] — a booking whose scheduled WINDOW has ended (`now > scheduled_at + hours`,
//!     no grace). An expired OPEN request must not surface in discovery, must be un-acceptable
//!     (`BOOKING_EXPIRED` 409), and is swept to `cancelled` by the background scheduler.
//!   * [`auto_complete_due`] — a `pending_completion` booking whose customer-confirm window has
//!     elapsed ([`AUTO_COMPLETE_GRACE_MINUTES`] past the LATER of the scheduled end and the guard's
//!     completion request); the scheduler auto-completes it.
//!
//! Every rule takes `now` as a parameter (never reads the clock here) so the rules stay pure and
//! the boundaries are exercised deterministically in unit tests.

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

/// Machine-readable `error.code` for an `accept` attempted on a booking whose scheduled window has
/// already ENDED (`now > scheduled_at + hours`). Clients branch on this (`AppError::ConflictCode`)
/// to localize "งานนี้หมดเวลาแล้ว" instead of surfacing the English message.
pub const BOOKING_EXPIRED_CODE: &str = "BOOKING_EXPIRED";

/// Grace after a `pending_completion` becomes due within which the CUSTOMER may still confirm the
/// guard's completion; once it elapses the scheduler auto-completes the job so it never lingers
/// unconfirmed (ISSUE 2). 30 minutes.
pub const AUTO_COMPLETE_GRACE_MINUTES: i64 = 30;

/// A booking's scheduled window END: `scheduled_at + hours`. The single place the expiry and
/// auto-complete rules agree on where a booking's window closes.
fn scheduled_end(scheduled_at: DateTime<Utc>, hours: i32) -> DateTime<Utc> {
    scheduled_at + Duration::hours(i64::from(hours))
}

/// ISSUE 1 — a booking is EXPIRED once its scheduled window has ended: `now > scheduled_at + hours`
/// (NO grace). An expired OPEN request (`requested`, no guard) must not appear in discovery, must
/// be un-acceptable (the accept gate returns [`BOOKING_EXPIRED_CODE`] 409), and is swept to
/// `cancelled` by the scheduler. The boundary is strict `>`: exactly at the window end it is not
/// yet expired.
pub fn is_expired(scheduled_at: DateTime<Utc>, hours: i32, now: DateTime<Utc>) -> bool {
    now > scheduled_end(scheduled_at, hours)
}

/// ISSUE 2 — a `pending_completion` booking is DUE for auto-completion once `grace` has elapsed
/// past the LATER of its scheduled end (`scheduled_at + hours`) and the guard's completion request
/// (`completion_requested_at`).
///
/// Taking the LATER of the two is what keeps the customer's confirm window honest at both edges: a
/// guard who requested completion EARLY (before the booked window ends) does not shrink the wait,
/// and a booking whose window ended is not auto-completed until `grace` past the request. This
/// counts only the confirm wait — the WORKED duration is still measured at `completion_requested_at`
/// by the completion path, so the auto-complete delay is never billed. `completion_requested_at` is
/// `None` only for a legacy row (it is stamped on `arrived → pending_completion`); then the
/// scheduled end alone drives the window. Strict `>` boundary.
pub fn auto_complete_due(
    scheduled_at: DateTime<Utc>,
    hours: i32,
    completion_requested_at: Option<DateTime<Utc>>,
    now: DateTime<Utc>,
    grace: Duration,
) -> bool {
    let end = scheduled_end(scheduled_at, hours);
    let later = match completion_requested_at {
        Some(requested) => end.max(requested),
        None => end,
    };
    now > later + grace
}

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

    // ----- is_expired (ISSUE 1) -----

    #[test]
    fn not_expired_before_or_at_window_end() {
        let scheduled = t0();
        let hours = 4;
        let end = scheduled + Duration::hours(hours as i64);
        // Well inside the window.
        assert!(!is_expired(
            scheduled,
            hours,
            scheduled + Duration::hours(1)
        ));
        // Exactly AT the window end → not yet expired (strict `>`).
        assert!(!is_expired(scheduled, hours, end));
    }

    #[test]
    fn expired_strictly_after_window_end() {
        let scheduled = t0();
        let hours = 4;
        let end = scheduled + Duration::hours(hours as i64);
        // One second past the end → expired (no grace).
        assert!(is_expired(scheduled, hours, end + Duration::seconds(1)));
        // Long past → expired.
        assert!(is_expired(scheduled, hours, end + Duration::days(1)));
    }

    // ----- auto_complete_due (ISSUE 2) -----

    fn grace() -> Duration {
        Duration::minutes(AUTO_COMPLETE_GRACE_MINUTES)
    }

    #[test]
    fn auto_complete_waits_for_grace_past_the_later_of_end_and_request() {
        let scheduled = t0();
        let hours = 2;
        // Window ends at t0 + 2h; the guard requested completion just AFTER it (worked a touch over).
        let end = scheduled + Duration::hours(hours as i64);
        let requested = end + Duration::minutes(10);
        // Before the request + grace → not due.
        assert!(!auto_complete_due(
            scheduled,
            hours,
            Some(requested),
            requested + grace() - Duration::seconds(1),
            grace()
        ));
        // Exactly at request + grace → not yet (strict `>`).
        assert!(!auto_complete_due(
            scheduled,
            hours,
            Some(requested),
            requested + grace(),
            grace()
        ));
        // One second past request + grace → due.
        assert!(auto_complete_due(
            scheduled,
            hours,
            Some(requested),
            requested + grace() + Duration::seconds(1),
            grace()
        ));
    }

    #[test]
    fn early_completion_request_still_waits_grace_past_the_scheduled_end() {
        // The guard requested completion BEFORE the booked window ended (finished early). The
        // confirm window is measured from the LATER value — the scheduled end — not the earlier
        // request, so the customer still gets the full grace after the window they paid for.
        let scheduled = t0();
        let hours = 4;
        let end = scheduled + Duration::hours(hours as i64);
        let requested = scheduled + Duration::hours(1); // long before the end
                                                        // grace past the REQUEST but still before the end → not due.
        assert!(!auto_complete_due(
            scheduled,
            hours,
            Some(requested),
            requested + grace() + Duration::minutes(5),
            grace()
        ));
        // grace past the scheduled END → due.
        assert!(auto_complete_due(
            scheduled,
            hours,
            Some(requested),
            end + grace() + Duration::seconds(1),
            grace()
        ));
    }

    #[test]
    fn auto_complete_falls_back_to_scheduled_end_when_request_unstamped() {
        // A legacy pending_completion row with no completion_requested_at: the scheduled end alone
        // drives the window.
        let scheduled = t0();
        let hours = 3;
        let end = scheduled + Duration::hours(hours as i64);
        assert!(!auto_complete_due(
            scheduled,
            hours,
            None,
            end + grace(),
            grace()
        ));
        assert!(auto_complete_due(
            scheduled,
            hours,
            None,
            end + grace() + Duration::seconds(1),
            grace()
        ));
    }
}
