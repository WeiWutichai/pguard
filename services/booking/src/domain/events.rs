//! PURE event mapping. No DB/HTTP/NATS imports — 100% unit-testable.
//!
//! Decides which `pguard.events.booking.*` topic a status change emits, and builds the
//! event payload object (the inner `payload` of an [`EventEnvelope`]). This is the
//! producer counterpart to notification's `domain::mapping::plan_for_event`: booking
//! emits, notification maps the emission to a user notification.
//!
//! Not every status change emits — e.g. `declined`/`cancelled` do, `requested` does not
//! (no cross-service consumer cares about a bare request yet).

use serde_json::{json, Value};
use uuid::Uuid;

use shared_events::topics;

use crate::domain::state::BookingStatus;

/// The decision for one status change: which NATS topic to publish + the payload object.
#[derive(Debug, Clone, PartialEq)]
pub struct EventMapping {
    /// Fully-qualified topic / `EventEnvelope.event_type`, e.g.
    /// `"pguard.events.booking.job_accepted"`.
    pub topic: &'static str,
    /// The inner event payload (becomes `EventEnvelope.payload`).
    pub payload: Value,
}

/// Proration inputs the completion event carries so the payment consumer can finalize
/// without a round-trip back to booking. `actual_seconds` is `now − work_started_at`
/// (the worked duration), or `None` if the guard never started (no factual basis to
/// prorate → payment keeps the full charge). Mirrors v1's `started_at`/`completed_at`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CompletionInfo {
    /// The hours the customer booked (= `bookings.hours`), the proration denominator.
    pub booked_hours: i32,
    /// Seconds actually worked (`now − work_started_at`), clamped/used by payment.
    pub actual_seconds: Option<i64>,
}

/// Build the standard booking event payload. Always carries `booking_id` and
/// `customer_id`; includes `guard_id` once a guard is assigned. notification's mapper
/// reads exactly these fields to route the notification.
fn payload(booking_id: Uuid, customer_id: Uuid, guard_id: Option<Uuid>) -> Value {
    match guard_id {
        Some(g) => json!({
            "booking_id": booking_id,
            "customer_id": customer_id,
            "guard_id": g,
        }),
        None => json!({
            "booking_id": booking_id,
            "customer_id": customer_id,
        }),
    }
}

/// Map a *new* booking status to the event it should emit, or `None` if that status
/// produces no cross-service event. Pure: the caller (repo) enqueues the returned
/// mapping into the outbox in the same transaction as the status write.
///
/// `completion` is only meaningful for [`BookingStatus::Completed`]: it adds
/// `booked_hours` + `actual_seconds` to the payload so the payment consumer can prorate.
/// Other statuses ignore it.
pub fn event_for_status(
    new_status: BookingStatus,
    booking_id: Uuid,
    customer_id: Uuid,
    guard_id: Option<Uuid>,
    completion: Option<CompletionInfo>,
) -> Option<EventMapping> {
    let topic = match new_status {
        BookingStatus::Accepted => topics::BOOKING_JOB_ACCEPTED,
        BookingStatus::Declined => topics::BOOKING_DECLINED,
        BookingStatus::EnRoute => topics::BOOKING_GUARD_EN_ROUTE,
        BookingStatus::Arrived => topics::BOOKING_ARRIVED,
        BookingStatus::Completed => topics::BOOKING_COMPLETED,
        BookingStatus::Cancelled => topics::BOOKING_CANCELLED,
        // A bare request has no cross-service consumer yet → no event.
        BookingStatus::Requested => return None,
    };
    let mut payload = payload(booking_id, customer_id, guard_id);
    // Completion carries the proration inputs the money path consumes.
    if new_status == BookingStatus::Completed {
        if let Some(info) = completion {
            payload["booked_hours"] = json!(info.booked_hours);
            payload["actual_seconds"] = json!(info.actual_seconds);
        }
    }
    Some(EventMapping { topic, payload })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepted_emits_job_accepted_with_all_ids() {
        let booking = Uuid::new_v4();
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let m = event_for_status(
            BookingStatus::Accepted,
            booking,
            customer,
            Some(guard),
            None,
        )
        .expect("accepted must emit");
        assert_eq!(m.topic, topics::BOOKING_JOB_ACCEPTED);
        assert_eq!(m.payload["booking_id"], json!(booking));
        assert_eq!(m.payload["customer_id"], json!(customer));
        assert_eq!(m.payload["guard_id"], json!(guard));
    }

    #[test]
    fn declined_emits_declined() {
        let m = event_for_status(
            BookingStatus::Declined,
            Uuid::new_v4(),
            Uuid::new_v4(),
            None,
            None,
        )
        .expect("declined must emit");
        assert_eq!(m.topic, topics::BOOKING_DECLINED);
        // declined before any guard assignment → no guard_id in payload
        assert!(m.payload.get("guard_id").is_none());
    }

    #[test]
    fn en_route_and_arrived_and_completed_map_to_their_topics() {
        let b = Uuid::new_v4();
        let c = Uuid::new_v4();
        let g = Some(Uuid::new_v4());
        assert_eq!(
            event_for_status(BookingStatus::EnRoute, b, c, g, None)
                .unwrap()
                .topic,
            topics::BOOKING_GUARD_EN_ROUTE
        );
        assert_eq!(
            event_for_status(BookingStatus::Arrived, b, c, g, None)
                .unwrap()
                .topic,
            topics::BOOKING_ARRIVED
        );
        assert_eq!(
            event_for_status(BookingStatus::Completed, b, c, g, None)
                .unwrap()
                .topic,
            topics::BOOKING_COMPLETED
        );
    }

    #[test]
    fn completed_carries_proration_inputs() {
        let b = Uuid::new_v4();
        let c = Uuid::new_v4();
        let g = Some(Uuid::new_v4());
        let m = event_for_status(
            BookingStatus::Completed,
            b,
            c,
            g,
            Some(CompletionInfo {
                booked_hours: 4,
                actual_seconds: Some(7200),
            }),
        )
        .expect("completed must emit");
        assert_eq!(m.topic, topics::BOOKING_COMPLETED);
        assert_eq!(m.payload["booked_hours"], json!(4));
        assert_eq!(m.payload["actual_seconds"], json!(7200));
    }

    #[test]
    fn completed_without_start_carries_null_actual_seconds() {
        let m = event_for_status(
            BookingStatus::Completed,
            Uuid::new_v4(),
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            Some(CompletionInfo {
                booked_hours: 3,
                actual_seconds: None,
            }),
        )
        .expect("completed must emit");
        assert_eq!(m.payload["booked_hours"], json!(3));
        assert!(
            m.payload["actual_seconds"].is_null(),
            "no work_started_at → null actual_seconds (payment keeps full charge)"
        );
    }

    #[test]
    fn non_completed_ignores_completion_info() {
        // Passing completion info to a non-completed status must not leak proration fields.
        let m = event_for_status(
            BookingStatus::Accepted,
            Uuid::new_v4(),
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            Some(CompletionInfo {
                booked_hours: 4,
                actual_seconds: Some(7200),
            }),
        )
        .expect("accepted must emit");
        assert!(m.payload.get("booked_hours").is_none());
        assert!(m.payload.get("actual_seconds").is_none());
    }

    #[test]
    fn cancelled_emits_cancelled_and_carries_guard_when_assigned() {
        let g = Uuid::new_v4();
        let m = event_for_status(
            BookingStatus::Cancelled,
            Uuid::new_v4(),
            Uuid::new_v4(),
            Some(g),
            None,
        )
        .expect("cancelled must emit");
        assert_eq!(m.topic, topics::BOOKING_CANCELLED);
        assert_eq!(m.payload["guard_id"], json!(g));
    }

    #[test]
    fn requested_emits_nothing() {
        assert!(event_for_status(
            BookingStatus::Requested,
            Uuid::new_v4(),
            Uuid::new_v4(),
            None,
            None
        )
        .is_none());
    }
}
