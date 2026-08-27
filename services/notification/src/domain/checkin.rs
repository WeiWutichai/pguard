//! PURE domain logic for the hourly check-in reminder (N3a). No DB/HTTP imports.
//!
//! Two concerns live here, both 100% unit-testable:
//!   1. [`ledger_op_for_event`] — turn a booking lifecycle event into the mutation the consumer
//!      applies to `notification.checkin_reminders` (open / record-checkin / close).
//!   2. [`is_due`] — the DUE rule the scheduler evaluates (mirrored by the SQL in
//!      `repo::due_checkins`), plus [`checkin_hour`] + [`reminder_plan`] for the push copy.
//!
//! notification owns NO booking state; this ledger is a tiny projection built purely from the
//! `pguard.events.booking.*` stream that already flows for the customer-facing notifications.

use chrono::{DateTime, Duration, Utc};
use serde_json::Value;
use uuid::Uuid;

use shared_events::topics;

use crate::domain::NotificationPlan;
use crate::models::NotificationType;

/// One hour — the check-in cadence and the reminder cooldown.
const CHECKIN_INTERVAL: Duration = Duration::hours(1);

/// The mutation a booking lifecycle event applies to the check-in ledger. Pure data — the repo
/// applies it in the SAME transaction that claims the event_id, so it is atomic + idempotent.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CheckinLedgerOp {
    /// `booking.arrived`: the guard (re)arrived and is working. Open/refresh the row and RESET the
    /// clock (in_progress_since = now, clear last_checkin/last_reminded/closed) — a fresh arrival
    /// starts a clean hour, and the completion-REJECT bounce (pending_completion → arrived, which
    /// re-emits `booking.arrived`) likewise restarts the guard's work session.
    Open { booking_id: Uuid, guard_id: Uuid },
    /// `booking.progress_reported`: an hourly check-in landed → push last_checkin_at forward so the
    /// next reminder is an hour from THIS check-in (not from arrival).
    RecordCheckin { booking_id: Uuid, guard_id: Uuid },
    /// `booking.completed` / `booking.cancelled` / `booking.completion_requested`: the job ended
    /// (or the guard requested completion and is now waiting on the customer) → close the row, stop
    /// reminding. Closing on completion-REQUEST (not just the customer's final confirm) is what
    /// stops the "keep nagging the guard to check in while the job sits in pending_completion, even
    /// past its scheduled end" bug: the guard has finished and is done checking in. If the customer
    /// REJECTS the completion the booking bounces back to `arrived`, which re-emits
    /// `booking.arrived` → [`Open`] restarts a clean work session, so reminders correctly resume.
    Close { booking_id: Uuid },
}

/// Parse a UUID string field out of an event payload (mirrors `mapping::uuid_field`).
fn uuid_field(payload: &Value, key: &str) -> Option<Uuid> {
    payload
        .get(key)?
        .as_str()
        .and_then(|s| Uuid::parse_str(s).ok())
}

/// Map a booking lifecycle event to the ledger mutation it drives, or `None` for any event that
/// does not touch the check-in ledger (and `None` when a required id is missing → tolerant: the
/// consumer simply applies no ledger op). PURE so the routing is unit-testable.
pub fn ledger_op_for_event(event_type: &str, payload: &Value) -> Option<CheckinLedgerOp> {
    match event_type {
        topics::BOOKING_ARRIVED => Some(CheckinLedgerOp::Open {
            booking_id: uuid_field(payload, "booking_id")?,
            guard_id: uuid_field(payload, "guard_id")?,
        }),
        topics::BOOKING_PROGRESS_REPORTED => Some(CheckinLedgerOp::RecordCheckin {
            booking_id: uuid_field(payload, "booking_id")?,
            guard_id: uuid_field(payload, "guard_id")?,
        }),
        topics::BOOKING_COMPLETED
        | topics::BOOKING_CANCELLED
        | topics::BOOKING_COMPLETION_REQUESTED => Some(CheckinLedgerOp::Close {
            booking_id: uuid_field(payload, "booking_id")?,
        }),
        _ => None,
    }
}

/// The DUE rule (pure — the scheduler's decision, mirrored by `repo::due_checkins`'s SQL):
/// a work session is due for a reminder when it is OPEN and it has been ≥ 1h since the later of
/// {last check-in, work start} AND ≥ 1h since the later of {last reminder, work start}. The first
/// clause paces to the guard's OWN check-ins (a fresh check-in defers the next nudge an hour); the
/// second is the cooldown so a not-yet-checked-in guard is nudged at most once an hour.
pub fn is_due(
    now: DateTime<Utc>,
    in_progress_since: DateTime<Utc>,
    last_checkin_at: Option<DateTime<Utc>>,
    last_reminded_at: Option<DateTime<Utc>>,
    closed_at: Option<DateTime<Utc>>,
) -> bool {
    if closed_at.is_some() {
        return false; // job ended → never remind
    }
    let since_checkin = now - last_checkin_at.unwrap_or(in_progress_since);
    let since_reminded = now - last_reminded_at.unwrap_or(in_progress_since);
    since_checkin >= CHECKIN_INTERVAL && since_reminded >= CHECKIN_INTERVAL
}

/// Which check-in hour this reminder names: whole hours since work began, floored, at least 1
/// (the first reminder fires at the 1-hour mark → "hour 1"). PURE.
pub fn checkin_hour(now: DateTime<Utc>, in_progress_since: DateTime<Utc>) -> i64 {
    let secs = (now - in_progress_since).num_seconds().max(0);
    (secs / 3600).max(1)
}

/// Build the guard's check-in reminder push. PURE (no DB/HTTP) so the copy + `data` shape is
/// unit-testable, mirroring [`crate::domain::dispatch_plan_for_guard`]. `data` carries
/// `type: "checkin_due"` + the `booking_id` so the mobile can deep-link to the check-in screen;
/// `target_role: "guard"` so the read API filters it to guards.
pub fn reminder_plan(guard_id: Uuid, booking_id: Uuid, hour: i64) -> NotificationPlan {
    let mut data = serde_json::Map::new();
    data.insert("type".to_string(), Value::String("checkin_due".to_string()));
    data.insert(
        "target_role".to_string(),
        Value::String("guard".to_string()),
    );
    data.insert(
        "booking_id".to_string(),
        Value::String(booking_id.to_string()),
    );
    data.insert("hour".to_string(), Value::String(hour.to_string()));
    NotificationPlan {
        recipient_id: guard_id,
        notification_type: NotificationType::System,
        title: "ถึงเวลาเช็คอิน".to_string(),
        body: format!("ถึงเวลาเช็คอินชั่วโมงที่ {hour} — แตะเพื่อถ่ายรูปและส่งพิกัด"),
        data: Value::Object(data),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn t(offset_secs: i64) -> DateTime<Utc> {
        DateTime::<Utc>::from_timestamp(1_700_000_000 + offset_secs, 0).unwrap()
    }

    // ----- ledger_op_for_event routing -----

    #[test]
    fn arrived_opens_the_ledger() {
        let booking = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let payload =
            json!({ "booking_id": booking, "customer_id": Uuid::new_v4(), "guard_id": guard });
        assert_eq!(
            ledger_op_for_event(topics::BOOKING_ARRIVED, &payload),
            Some(CheckinLedgerOp::Open {
                booking_id: booking,
                guard_id: guard
            })
        );
    }

    #[test]
    fn progress_reported_records_a_checkin() {
        let booking = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let payload = json!({
            "booking_id": booking, "customer_id": Uuid::new_v4(), "guard_id": guard,
            "report_id": Uuid::new_v4(), "hour_number": 1
        });
        assert_eq!(
            ledger_op_for_event(topics::BOOKING_PROGRESS_REPORTED, &payload),
            Some(CheckinLedgerOp::RecordCheckin {
                booking_id: booking,
                guard_id: guard
            })
        );
    }

    #[test]
    fn completed_and_cancelled_close_the_ledger() {
        let booking = Uuid::new_v4();
        let payload = json!({ "booking_id": booking, "customer_id": Uuid::new_v4(), "guard_id": Uuid::new_v4() });
        assert_eq!(
            ledger_op_for_event(topics::BOOKING_COMPLETED, &payload),
            Some(CheckinLedgerOp::Close {
                booking_id: booking
            })
        );
        assert_eq!(
            ledger_op_for_event(topics::BOOKING_CANCELLED, &payload),
            Some(CheckinLedgerOp::Close {
                booking_id: booking
            })
        );
    }

    #[test]
    fn completion_request_closes_the_ledger_so_pending_completion_stops_nagging() {
        // The guard tapped "จบงาน" → arrived → pending_completion (booking.completion_requested).
        // The job is over from the guard's side; reminders must stop even though the customer has
        // not yet confirmed (else the guard is nagged hourly past the scheduled end). A later
        // customer REJECT re-emits booking.arrived → Open restarts the session (covered above).
        let booking = Uuid::new_v4();
        let payload = json!({ "booking_id": booking, "customer_id": Uuid::new_v4(), "guard_id": Uuid::new_v4() });
        assert_eq!(
            ledger_op_for_event(topics::BOOKING_COMPLETION_REQUESTED, &payload),
            Some(CheckinLedgerOp::Close {
                booking_id: booking
            })
        );
    }

    #[test]
    fn unrelated_events_touch_no_ledger() {
        let payload = json!({ "booking_id": Uuid::new_v4(), "customer_id": Uuid::new_v4() });
        assert_eq!(
            ledger_op_for_event(topics::BOOKING_JOB_ACCEPTED, &payload),
            None
        );
        assert_eq!(
            ledger_op_for_event(topics::PAYMENT_COMPLETED, &payload),
            None
        );
        assert_eq!(ledger_op_for_event("pguard.events.bogus", &payload), None);
    }

    #[test]
    fn arrived_without_guard_is_ignored() {
        // Defensive: no guard_id → no ledger op (tolerant), never a panic.
        let payload = json!({ "booking_id": Uuid::new_v4(), "customer_id": Uuid::new_v4() });
        assert_eq!(ledger_op_for_event(topics::BOOKING_ARRIVED, &payload), None);
    }

    // ----- the DUE rule -----

    #[test]
    fn not_due_before_an_hour_has_passed() {
        // Arrived 59m ago, never checked in / reminded → NOT due yet.
        let start = t(0);
        let now = t(59 * 60);
        assert!(!is_due(now, start, None, None, None));
    }

    #[test]
    fn due_exactly_at_the_one_hour_mark() {
        let start = t(0);
        let now = t(3600);
        assert!(is_due(now, start, None, None, None));
    }

    #[test]
    fn not_due_when_just_checked_in() {
        // Working 90m, but checked in 10m ago → next reminder is an hour from that check-in.
        let start = t(0);
        let now = t(90 * 60);
        let last_checkin = Some(t(80 * 60));
        assert!(!is_due(now, start, last_checkin, None, None));
    }

    #[test]
    fn not_due_within_the_reminder_cooldown() {
        // 2h in, no check-in, but reminded 30m ago → cooldown blocks a re-fire until the hour.
        let start = t(0);
        let now = t(2 * 3600);
        let last_reminded = Some(t(90 * 60));
        assert!(!is_due(now, start, None, last_reminded, None));
    }

    #[test]
    fn due_again_an_hour_after_the_last_reminder() {
        // 2h in, no check-in, last reminder exactly 1h ago → due for the hour-2 nudge.
        let start = t(0);
        let now = t(2 * 3600);
        let last_reminded = Some(t(3600));
        assert!(is_due(now, start, None, last_reminded, None));
    }

    #[test]
    fn never_due_once_closed() {
        // Even hours overdue, a closed (completed/cancelled) row is never reminded.
        let start = t(0);
        let now = t(5 * 3600);
        assert!(!is_due(now, start, None, None, Some(t(2 * 3600))));
    }

    // ----- hour naming + copy -----

    #[test]
    fn checkin_hour_floors_to_at_least_one() {
        let start = t(0);
        assert_eq!(checkin_hour(t(3600), start), 1); // exactly 1h → hour 1
        assert_eq!(checkin_hour(t(3600 + 59 * 60), start), 1); // 1h59m → still hour 1
        assert_eq!(checkin_hour(t(2 * 3600), start), 2); // 2h → hour 2
        assert_eq!(checkin_hour(t(0), start), 1); // clamp: never 0/negative
    }

    #[test]
    fn reminder_plan_targets_the_guard_and_names_the_hour() {
        let guard = Uuid::new_v4();
        let booking = Uuid::new_v4();
        let plan = reminder_plan(guard, booking, 2);
        assert_eq!(plan.recipient_id, guard);
        assert_eq!(plan.notification_type, NotificationType::System);
        assert_eq!(plan.title, "ถึงเวลาเช็คอิน");
        assert!(
            plan.body.contains('2'),
            "body names the hour, got: {}",
            plan.body
        );
        assert_eq!(plan.data["type"], "checkin_due");
        assert_eq!(plan.data["target_role"], "guard");
        assert_eq!(plan.data["booking_id"], json!(booking.to_string()));
    }
}
