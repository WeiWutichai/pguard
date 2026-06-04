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
pub fn event_for_status(
    new_status: BookingStatus,
    booking_id: Uuid,
    customer_id: Uuid,
    guard_id: Option<Uuid>,
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
    Some(EventMapping {
        topic,
        payload: payload(booking_id, customer_id, guard_id),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepted_emits_job_accepted_with_all_ids() {
        let booking = Uuid::new_v4();
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let m = event_for_status(BookingStatus::Accepted, booking, customer, Some(guard))
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
            event_for_status(BookingStatus::EnRoute, b, c, g)
                .unwrap()
                .topic,
            topics::BOOKING_GUARD_EN_ROUTE
        );
        assert_eq!(
            event_for_status(BookingStatus::Arrived, b, c, g)
                .unwrap()
                .topic,
            topics::BOOKING_ARRIVED
        );
        assert_eq!(
            event_for_status(BookingStatus::Completed, b, c, g)
                .unwrap()
                .topic,
            topics::BOOKING_COMPLETED
        );
    }

    #[test]
    fn cancelled_emits_cancelled_and_carries_guard_when_assigned() {
        let g = Uuid::new_v4();
        let m = event_for_status(
            BookingStatus::Cancelled,
            Uuid::new_v4(),
            Uuid::new_v4(),
            Some(g),
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
            None
        )
        .is_none());
    }
}
