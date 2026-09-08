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
//!   * [`validate_keep_working`] (QA #25) — the customer may send a guard BACK to work
//!     (`pending_completion → arrived`, the "ให้ทำต่อ" reject) only while the booked window is
//!     still open. Past it that reject is an EXTENSION of the original job, which the product
//!     forbids. Code `JOB_WINDOW_CLOSED` (409).
//!   * [`close_arrived`] + [`worked_seconds_within_window`] (QA #25) — the scheduler's safety net
//!     for a booking left sitting in `arrived` past its window, and the deterministic worked
//!     duration such a system close is billed on.
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
///
/// QA #25 re-uses the SAME constant for the `arrived` safety net ([`close_arrived`]): "how long
/// past the booked window may a job stay open before the system closes it" is ONE product number,
/// and two different graces would put the two closure paths on different clocks.
pub const AUTO_COMPLETE_GRACE_MINUTES: i64 = 30;

/// Machine-readable `error.code` for the NO-EXTENSION gate 409 (QA #25): the customer tried to
/// send the guard back to work (`pending_completion → arrived`) after the booked window had
/// already ENDED. Clients branch on this sub-code (`AppError::ConflictCode`) to render the Thai
/// "งานนี้สิ้นสุดเวลาแล้ว — หากต้องการใช้บริการต่อ กรุณาสร้างงานใหม่" instead of the English message.
pub const JOB_WINDOW_CLOSED_CODE: &str = "JOB_WINDOW_CLOSED";

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

/// QA #25 — the NO-EXTENSION gate. May the customer send the guard BACK to work
/// (`pending_completion → arrived`, the "ให้ทำต่อ / Keep working" reject) at `now`?
///
/// Only while the booked window is still open. Past `scheduled_at + hours` that reject is the ONE
/// mechanism in the whole system that prolongs a job beyond what the customer bought — the guard
/// keeps working, the booking leaves `pending_completion`, and with it leaves the reach of
/// [`auto_complete_due`]'s sweep, so it can be repeated without limit. The product rule is
/// explicit: the original job may not be extended; more service means a NEW booking through the
/// normal flow. So the reject is refused with [`JOB_WINDOW_CLOSED_CODE`] (409) once the window has
/// closed, and the customer's only remaining review action is `approve`.
///
/// There is deliberately NO admin bypass. The money basis for a job closed after its window is
/// capped at the scheduled end ([`worked_seconds_within_window`]) — so re-opening a job past that
/// point cannot produce a larger bill, only unpaid guard work. An override here would have nothing
/// to buy with it.
///
/// The boundary is [`is_expired`]'s: strict `>`, so EXACTLY at the window end the reject is still
/// allowed (one rule for "has this booking's time passed", never two that can drift apart).
pub fn validate_keep_working(
    scheduled_at: DateTime<Utc>,
    hours: i32,
    now: DateTime<Utc>,
) -> Result<(), AppError> {
    if is_expired(scheduled_at, hours, now) {
        return Err(AppError::ConflictCode {
            code: JOB_WINDOW_CLOSED_CODE,
            message: "This job's scheduled window has ended; book a new job to continue"
                .to_string(),
        });
    }
    Ok(())
}

/// What the scheduler must do with a booking still sitting in `arrived` (QA #25).
///
/// `arrived` is the ONE active status nothing time-driven used to reach: [`is_expired`]'s sweep
/// only touches OPEN `requested` rows and [`auto_complete_due`]'s only `pending_completion`, so a
/// job whose guard never pressed จบงาน (app backgrounded, or bounced back by a completion reject)
/// stayed `arrived` forever — the customer's PRE-PAY held with no completion event to reconcile
/// it and no refund, the guard never entering the payout backlog. This decides its fate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ArrivedClosure {
    /// The booked window (+ grace) has not elapsed — leave it alone, the job is live.
    NotDue,
    /// Close it as DONE. There is evidence of work (`work_started_at` plus at least one filed
    /// check-in), so it is billed on [`worked_seconds_within_window`] and paid out.
    Complete,
    /// Close it as DID-NOT-HAPPEN. The guard marked themselves on-site but never started, so
    /// there is no worked time to bill at all — completing it would hand payment a `None`
    /// `actual_seconds`, which it reads as "keep the FULL charge" for a job with zero work.
    /// Cancelling instead makes payment's cancellation consumer full-refund the customer.
    Cancel,
    /// AMBIGUOUS — the guard started but filed no check-in, so there is no on-site attestation.
    /// Deliberately neither: completing it would bill the customer (and pay the guard) for work
    /// the platform's own `CHECK_IN_REQUIRED` rule says is unproven — and would hand a guard a
    /// way to get paid while never checking in, which is exactly what that rule prevents;
    /// cancelling it would silently write off the pay of a guard whose photo uploads may simply
    /// have failed. Both directions move real money on a guess, so the sweep leaves the row for a
    /// human and reports the count.
    Review,
}

/// QA #25 — decide the fate of an `arrived` booking at `now`. See [`ArrivedClosure`].
///
/// Due on the SCHEDULED end plus `grace` (not on `work_started_at + hours`): the customer bought
/// a window, and that window — not when the guard happened to start — is what bounds the job.
/// Strict `>` boundary, matching both sibling rules.
pub fn close_arrived(
    scheduled_at: DateTime<Utc>,
    hours: i32,
    work_started_at: Option<DateTime<Utc>>,
    has_check_in: bool,
    now: DateTime<Utc>,
    grace: Duration,
) -> ArrivedClosure {
    if now <= scheduled_end(scheduled_at, hours) + grace {
        return ArrivedClosure::NotDue;
    }
    match (work_started_at, has_check_in) {
        (None, _) => ArrivedClosure::Cancel,
        (Some(_), false) => ArrivedClosure::Review,
        (Some(_), true) => ArrivedClosure::Complete,
    }
}

/// QA #25 — the worked duration a SYSTEM-closed job is billed on: the seconds the guard was on
/// the clock INSIDE the window the customer paid for.
///
/// `min(scheduled_at + hours, now) − work_started_at`, floored at zero.
///
/// WHY NOT `now − work_started_at` (what the ordinary completion path falls back to when no
/// completion was requested): `now` here is a SWEEP-TICK instant. It is 0–60s past the deadline on
/// a healthy day, but arbitrarily later after a restart, a failed tick or a backlog — so the
/// customer's refund and the guard's PromptPay transfer (both derive from this one number, via
/// payment's `compute_proration` and the SCB payout file) would depend on scheduler health rather
/// than on facts. Capping at the scheduled end makes the figure deterministic: the same job closed
/// by a tick at +31 min and by one at +6 h bills identically. It also means the 30-minute grace is
/// never billed to the customer — the grace buys the customer time to confirm, not the guard time
/// on the clock.
///
/// WHY NOT `work_started_at + hours` (the full booked duration): that always yields exactly the
/// booked hours, so payment's proration clamp could never produce a refund — a guard who started
/// two hours late would still bill the customer in full. Capping the END INSTANT (not just the
/// duration) is what closes that: a late start is credited only the part of the paid window the
/// guard was actually on site, and the customer is refunded the rest.
///
/// The floor at zero covers the degenerate late start — `work_started_at` past the window end
/// (a start has no upper time bound, see [`validate_start_time`]) — where the guard was never on
/// the clock inside the paid window at all. Payment already floors negatives, but a negative
/// duration must not travel on an event in the first place.
pub fn worked_seconds_within_window(
    scheduled_at: DateTime<Utc>,
    hours: i32,
    work_started_at: DateTime<Utc>,
    now: DateTime<Utc>,
) -> i64 {
    let ended = scheduled_end(scheduled_at, hours).min(now);
    (ended - work_started_at).num_seconds().max(0)
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

    // ----- validate_keep_working (QA #25, the NO-EXTENSION gate) -----

    #[test]
    fn keep_working_allowed_up_to_and_including_the_window_end() {
        let scheduled = t0();
        let hours = 4;
        let end = scheduled + Duration::hours(hours as i64);
        // Mid-job: the guard finished early and the customer wants more of what they paid for.
        assert!(validate_keep_working(scheduled, hours, scheduled + Duration::hours(1)).is_ok());
        // One second before the end → still inside the paid window.
        assert!(validate_keep_working(scheduled, hours, end - Duration::seconds(1)).is_ok());
        // EXACTLY at the end → still allowed (strict `>` boundary, same as `is_expired`).
        assert!(validate_keep_working(scheduled, hours, end).is_ok());
    }

    #[test]
    fn keep_working_refused_once_the_window_has_closed() {
        let scheduled = t0();
        let hours = 4;
        let end = scheduled + Duration::hours(hours as i64);
        // One second past the end → refused; this is the extension the product forbids.
        let err = validate_keep_working(scheduled, hours, end + Duration::seconds(1)).unwrap_err();
        assert_eq!(code_of(&err), JOB_WINDOW_CLOSED_CODE);
        assert!(matches!(err, AppError::ConflictCode { .. }));
        // Well past — including inside the auto-complete grace, which is the customer's window to
        // APPROVE, never to send the guard back out.
        assert_eq!(
            code_of(&validate_keep_working(scheduled, hours, end + grace()).unwrap_err()),
            JOB_WINDOW_CLOSED_CODE
        );
    }

    #[test]
    fn keep_working_gate_is_the_same_boundary_as_is_expired() {
        // One rule, two callers: whatever `is_expired` says at an instant, the reject gate must
        // agree — otherwise a booking could be un-acceptable AND still extendable (or vice versa).
        let scheduled = t0();
        let hours = 3;
        for offset_secs in [-3600, -1, 0, 1, 3600] {
            let now = scheduled + Duration::hours(3) + Duration::seconds(offset_secs);
            assert_eq!(
                is_expired(scheduled, hours, now),
                validate_keep_working(scheduled, hours, now).is_err(),
                "boundary drift at {offset_secs}s from the window end"
            );
        }
    }

    #[test]
    fn a_reject_loop_cannot_outlive_the_booked_window() {
        // The defect shape: guard requests completion → customer rejects → guard requests again →
        // customer rejects again… Each bounce is legal INSIDE the window (the customer is spending
        // time they paid for), and every one of them is refused once the window has closed — so the
        // loop is bounded by the booking's own window no matter how many times it goes round.
        let scheduled = t0();
        let hours = 2;
        let end = scheduled + Duration::hours(hours as i64);
        for minute in [1, 30, 60, 90, 119] {
            assert!(
                validate_keep_working(scheduled, hours, scheduled + Duration::minutes(minute))
                    .is_ok(),
                "reject at +{minute}m is inside the paid window"
            );
        }
        for minute in [1, 5, 30, 120, 1440] {
            assert_eq!(
                code_of(
                    &validate_keep_working(scheduled, hours, end + Duration::minutes(minute))
                        .unwrap_err()
                ),
                JOB_WINDOW_CLOSED_CODE,
                "reject at end+{minute}m must be refused"
            );
        }
    }

    // ----- close_arrived (QA #25, the `arrived` safety net) -----

    #[test]
    fn arrived_is_not_due_until_grace_past_the_scheduled_end() {
        let scheduled = t0();
        let hours = 4;
        let end = scheduled + Duration::hours(hours as i64);
        let started = Some(scheduled);
        // Mid-job.
        assert_eq!(
            close_arrived(
                scheduled,
                hours,
                started,
                true,
                scheduled + Duration::hours(1),
                grace()
            ),
            ArrivedClosure::NotDue
        );
        // Past the window but inside the grace — the guard may still press จบงาน themselves.
        assert_eq!(
            close_arrived(
                scheduled,
                hours,
                started,
                true,
                end + Duration::minutes(29),
                grace()
            ),
            ArrivedClosure::NotDue
        );
        // EXACTLY at end + grace → not yet (strict `>`).
        assert_eq!(
            close_arrived(scheduled, hours, started, true, end + grace(), grace()),
            ArrivedClosure::NotDue
        );
        // One second later → due.
        assert_eq!(
            close_arrived(
                scheduled,
                hours,
                started,
                true,
                end + grace() + Duration::seconds(1),
                grace()
            ),
            ArrivedClosure::Complete
        );
    }

    #[test]
    fn arrived_closure_branches_on_the_evidence_of_work() {
        let scheduled = t0();
        let hours = 4;
        let due = scheduled + Duration::hours(hours as i64) + grace() + Duration::seconds(1);
        // Never started → the job did not happen → cancel (payment full-refunds).
        assert_eq!(
            close_arrived(scheduled, hours, None, false, due, grace()),
            ArrivedClosure::Cancel
        );
        // Never started but somehow holding a report (not reachable — a report requires a start;
        // asserted so the branch order is deliberate, not accidental): still a cancel.
        assert_eq!(
            close_arrived(scheduled, hours, None, true, due, grace()),
            ArrivedClosure::Cancel
        );
        // Started, no attestation → neither bill nor write off; leave it for a human.
        assert_eq!(
            close_arrived(scheduled, hours, Some(scheduled), false, due, grace()),
            ArrivedClosure::Review
        );
        // Started + attested → complete.
        assert_eq!(
            close_arrived(scheduled, hours, Some(scheduled), true, due, grace()),
            ArrivedClosure::Complete
        );
    }

    #[test]
    fn arrived_not_due_wins_over_every_evidence_shape() {
        // The due check comes FIRST: a live job is never cancelled for want of a check-in it has
        // not had time to file yet.
        let scheduled = t0();
        let hours = 4;
        let now = scheduled + Duration::minutes(5);
        for started in [None, Some(scheduled)] {
            for has_check_in in [false, true] {
                assert_eq!(
                    close_arrived(scheduled, hours, started, has_check_in, now, grace()),
                    ArrivedClosure::NotDue
                );
            }
        }
    }

    // ----- worked_seconds_within_window (QA #25, the money basis) -----

    #[test]
    fn worked_seconds_are_capped_at_the_scheduled_end_not_at_now() {
        // 09:00–13:00 booking, guard started on time. The sweep runs late — 6 hours late, say,
        // after a restart. The bill must be the 4 booked hours, NOT 10.
        let scheduled = t0();
        let hours = 4;
        let end = scheduled + Duration::hours(4);
        let four_hours = 4 * 3600;
        assert_eq!(
            worked_seconds_within_window(scheduled, hours, scheduled, end + Duration::minutes(31)),
            four_hours
        );
        assert_eq!(
            worked_seconds_within_window(scheduled, hours, scheduled, end + Duration::hours(6)),
            four_hours,
            "a late sweep tick must not bill the customer for the delay"
        );
        // …and the grace itself is never billed.
        assert_eq!(
            worked_seconds_within_window(scheduled, hours, scheduled, end + grace()),
            four_hours
        );
    }

    #[test]
    fn a_late_start_is_credited_only_the_part_of_the_window_it_covered() {
        // 09:00–13:00, guard started at 11:00 → 2 of the 4 paid hours. The customer is refunded
        // the other half; the guard is paid for 2 hours.
        let scheduled = t0();
        let hours = 4;
        let started = scheduled + Duration::hours(2);
        let due = scheduled + Duration::hours(4) + grace() + Duration::seconds(1);
        assert_eq!(
            worked_seconds_within_window(scheduled, hours, started, due),
            2 * 3600
        );
    }

    #[test]
    fn a_start_after_the_window_closed_credits_nothing() {
        // Degenerate: `validate_start_time` has no upper bound, so a guard CAN start after the
        // window ended. None of that time is inside what the customer paid for → zero, never a
        // negative duration on the wire.
        let scheduled = t0();
        let hours = 2;
        let started = scheduled + Duration::hours(3); // an hour past the end
        let due = scheduled + Duration::hours(2) + grace() + Duration::seconds(1);
        assert_eq!(
            worked_seconds_within_window(scheduled, hours, started, due),
            0
        );
    }

    #[test]
    fn worked_seconds_before_the_window_end_measure_up_to_now() {
        // Not a sweep shape (the sweep only fires past the end), but the cap is `min(end, now)`,
        // so the function never credits time in the FUTURE if it is ever called mid-window.
        let scheduled = t0();
        let hours = 4;
        let now = scheduled + Duration::hours(1);
        assert_eq!(
            worked_seconds_within_window(scheduled, hours, scheduled, now),
            3600
        );
    }
}
