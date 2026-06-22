//! PURE event mapping. No DB/HTTP/NATS imports — 100% unit-testable.
//!
//! Decides which `pguard.events.booking.*` topic a status change emits, and builds the
//! event payload object (the inner `payload` of an [`EventEnvelope`]). This is the
//! producer counterpart to notification's `domain::mapping::plan_for_event`: booking
//! emits, notification maps the emission to a user notification.
//!
//! Not every status change emits — e.g. `declined`/`cancelled` do, `requested` does not
//! (no cross-service consumer cares about a bare request yet).

use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
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

/// Pricing + duration inputs the completion event carries so the payment consumer can raise the
/// POST-PAY bill self-contained (no round-trip back to booking). `actual_seconds` is
/// `now − work_started_at` (the worked duration), or `None` if the guard never started (no
/// factual basis to prorate → payment bills the full booked base). The `base_fee`/`guard_count`/
/// `tip` are booking's server-owned pricing columns, carried so payment never recomputes the
/// price from a client. Mirrors v1's `started_at`/`completed_at`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CompletionInfo {
    /// The hours the customer booked (= `bookings.hours`), the proration denominator.
    pub booked_hours: i32,
    /// Seconds actually worked (`now − work_started_at`), clamped/used by payment.
    pub actual_seconds: Option<i64>,
    /// Server-owned per-guard-hour fee (`bookings.base_fee`).
    pub base_fee: Decimal,
    /// Number of guards booked (`bookings.guard_count`).
    pub guard_count: i32,
    /// The customer's flat tip (`bookings.tip`) — billed in full, never prorated.
    pub tip: Decimal,
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

/// Map a *transition* (`from → new_status`) to the event it should emit, or `None` if it
/// produces no cross-service event. Pure: the caller (repo) enqueues the returned mapping
/// into the outbox in the same transaction as the status write.
///
/// The decision depends on BOTH ends of the transition, not just the target: e.g. a fresh
/// arrival (`en_route → arrived`) notifies the customer, but the customer's completion
/// REJECT (`pending_completion → arrived`) lands on the same `arrived` status and must NOT
/// re-fire a "guard arrived" push.
///
/// `completion` is only meaningful for [`BookingStatus::Completed`]: it adds
/// `booked_hours` + `actual_seconds` to the payload so the payment consumer can prorate.
/// Other statuses ignore it.
pub fn event_for_status(
    from: BookingStatus,
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
        BookingStatus::Arrived => {
            // Only a FRESH arrival (en_route → arrived) emits. The completion-reject bounce
            // (pending_completion → arrived) reuses `arrived` but is NOT a new arrival, so it
            // emits nothing (a re-fired "guard arrived" push would be wrong + duplicate).
            if from == BookingStatus::PendingCompletion {
                return None;
            }
            topics::BOOKING_ARRIVED
        }
        BookingStatus::Completed => topics::BOOKING_COMPLETED,
        BookingStatus::Cancelled => topics::BOOKING_CANCELLED,
        // A bare request, and the guard's completion REQUEST (pending_completion is an
        // internal milestone awaiting customer review), have no cross-service event.
        BookingStatus::Requested | BookingStatus::PendingCompletion => return None,
    };
    let mut payload = payload(booking_id, customer_id, guard_id);
    // Completion carries the proration + pricing inputs the post-pay money path consumes.
    if new_status == BookingStatus::Completed {
        if let Some(info) = completion {
            payload["booked_hours"] = json!(info.booked_hours);
            payload["actual_seconds"] = json!(info.actual_seconds);
            payload["base_fee"] = json!(info.base_fee);
            payload["guard_count"] = json!(info.guard_count);
            payload["tip"] = json!(info.tip);
        }
    }
    Some(EventMapping { topic, payload })
}

/// Build the `pguard.events.booking.requested` event for a freshly-created booking (status
/// `requested`, no guard yet). Pure: the repo enqueues this into the outbox in the SAME
/// transaction as the `bookings` insert, so a committed request always has its event durably
/// queued. The notification consumer fans this out as a data-push to every ONLINE guard
/// ("งานใหม่ใกล้คุณ" / "New job nearby") so a guard can open the job and accept it.
///
/// `lat`/`lng` are CARRIED EVEN WHEN ABSENT (emitted as JSON `null`, key present — the
/// `actual_seconds` precedent) so a radius-ranking consumer reads the site coordinates without
/// a round-trip back into booking. NOT a customer-facing lifecycle status change: the gateway's
/// booking-status WS ignores this topic (`status_from_topic` → None).
#[allow(clippy::too_many_arguments)]
pub fn event_for_booking_requested(
    booking_id: Uuid,
    customer_id: Uuid,
    address: &str,
    lat: Option<f64>,
    lng: Option<f64>,
    scheduled_at: DateTime<Utc>,
    hours: i32,
    guard_count: i32,
) -> EventMapping {
    EventMapping {
        topic: topics::BOOKING_REQUESTED,
        payload: json!({
            "booking_id": booking_id,
            "customer_id": customer_id,
            "address": address,
            // Carried even when None → JSON null (key present), like completion's actual_seconds.
            "lat": lat,
            "lng": lng,
            "scheduled_at": scheduled_at,
            "hours": hours,
            "guard_count": guard_count,
        }),
    }
}

/// Map a persisted hourly check-in to its `pguard.events.booking.progress_reported` event.
/// Pure: the repo enqueues this into the outbox in the SAME transaction as the
/// `progress_reports` insert. Carries `customer_id` so the (future) notification consumer
/// can route "your guard checked in" without a read back into booking. NOT a lifecycle
/// status change — the gateway's booking-status WS ignores this topic.
pub fn event_for_progress_report(
    booking_id: Uuid,
    customer_id: Uuid,
    guard_id: Uuid,
    report_id: Uuid,
    hour_number: i32,
) -> EventMapping {
    EventMapping {
        topic: topics::BOOKING_PROGRESS_REPORTED,
        payload: json!({
            "booking_id": booking_id,
            "customer_id": customer_id,
            "guard_id": guard_id,
            "report_id": report_id,
            "hour_number": hour_number,
        }),
    }
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
            BookingStatus::Requested,
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
            BookingStatus::Accepted,
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
            event_for_status(
                BookingStatus::Accepted,
                BookingStatus::EnRoute,
                b,
                c,
                g,
                None
            )
            .unwrap()
            .topic,
            topics::BOOKING_GUARD_EN_ROUTE
        );
        // FRESH arrival (en_route → arrived) emits.
        assert_eq!(
            event_for_status(
                BookingStatus::EnRoute,
                BookingStatus::Arrived,
                b,
                c,
                g,
                None
            )
            .unwrap()
            .topic,
            topics::BOOKING_ARRIVED
        );
        assert_eq!(
            event_for_status(
                BookingStatus::PendingCompletion,
                BookingStatus::Completed,
                b,
                c,
                g,
                None
            )
            .unwrap()
            .topic,
            topics::BOOKING_COMPLETED
        );
    }

    #[test]
    fn completion_reject_bounce_to_arrived_emits_nothing() {
        // pending_completion → arrived is the customer REJECTING completion, not a new
        // arrival; it must NOT re-fire booking.arrived (which would push "guard arrived").
        let m = event_for_status(
            BookingStatus::PendingCompletion,
            BookingStatus::Arrived,
            Uuid::new_v4(),
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            None,
        );
        assert!(
            m.is_none(),
            "completion-reject bounce to arrived must emit no event"
        );
    }

    #[test]
    fn completed_carries_proration_and_pricing_inputs() {
        let b = Uuid::new_v4();
        let c = Uuid::new_v4();
        let g = Some(Uuid::new_v4());
        let base_fee: Decimal = "500.00".parse().unwrap();
        let tip: Decimal = "100.00".parse().unwrap();
        let m = event_for_status(
            BookingStatus::PendingCompletion,
            BookingStatus::Completed,
            b,
            c,
            g,
            Some(CompletionInfo {
                booked_hours: 4,
                actual_seconds: Some(7200),
                base_fee,
                guard_count: 2,
                tip,
            }),
        )
        .expect("completed must emit");
        assert_eq!(m.topic, topics::BOOKING_COMPLETED);
        assert_eq!(m.payload["booked_hours"], json!(4));
        assert_eq!(m.payload["actual_seconds"], json!(7200));
        // Pricing inputs ride the event so the post-pay consumer is self-contained (money
        // serializes as a JSON string workspace-wide via rust_decimal serde-str).
        assert_eq!(m.payload["base_fee"], json!(base_fee));
        assert_eq!(m.payload["guard_count"], json!(2));
        assert_eq!(m.payload["tip"], json!(tip));
    }

    #[test]
    fn completed_without_start_carries_null_actual_seconds() {
        let m = event_for_status(
            BookingStatus::PendingCompletion,
            BookingStatus::Completed,
            Uuid::new_v4(),
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            Some(CompletionInfo {
                booked_hours: 3,
                actual_seconds: None,
                base_fee: "300.00".parse().unwrap(),
                guard_count: 1,
                tip: Decimal::ZERO,
            }),
        )
        .expect("completed must emit");
        assert_eq!(m.payload["booked_hours"], json!(3));
        assert!(
            m.payload["actual_seconds"].is_null(),
            "no work_started_at → null actual_seconds (payment bills the full booked base)"
        );
    }

    #[test]
    fn non_completed_ignores_completion_info() {
        // Passing completion info to a non-completed status must not leak proration fields.
        let m = event_for_status(
            BookingStatus::Requested,
            BookingStatus::Accepted,
            Uuid::new_v4(),
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            Some(CompletionInfo {
                booked_hours: 4,
                actual_seconds: Some(7200),
                base_fee: "500.00".parse().unwrap(),
                guard_count: 1,
                tip: Decimal::ZERO,
            }),
        )
        .expect("accepted must emit");
        assert!(m.payload.get("booked_hours").is_none());
        assert!(m.payload.get("actual_seconds").is_none());
        assert!(m.payload.get("base_fee").is_none());
        assert!(m.payload.get("tip").is_none());
    }

    #[test]
    fn cancelled_emits_cancelled_and_carries_guard_when_assigned() {
        let g = Uuid::new_v4();
        let m = event_for_status(
            BookingStatus::Accepted,
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
    fn booking_requested_carries_full_job_payload() {
        let booking = Uuid::new_v4();
        let customer = Uuid::new_v4();
        let scheduled_at: DateTime<Utc> = "2026-06-22T10:00:00Z".parse().unwrap();
        let m = event_for_booking_requested(
            booking,
            customer,
            "1 Sukhumvit Rd",
            Some(13.7563),
            Some(100.5018),
            scheduled_at,
            4,
            2,
        );
        assert_eq!(m.topic, topics::BOOKING_REQUESTED);
        assert_eq!(m.topic, "pguard.events.booking.requested");
        assert_eq!(m.payload["booking_id"], json!(booking));
        assert_eq!(m.payload["customer_id"], json!(customer));
        assert_eq!(m.payload["address"], json!("1 Sukhumvit Rd"));
        assert_eq!(m.payload["lat"], json!(13.7563));
        assert_eq!(m.payload["lng"], json!(100.5018));
        assert_eq!(m.payload["scheduled_at"], json!(scheduled_at));
        assert_eq!(m.payload["hours"], json!(4));
        assert_eq!(m.payload["guard_count"], json!(2));
    }

    #[test]
    fn booking_requested_carries_null_coords_as_present_keys() {
        // "carry lat/lng even when null": the keys are PRESENT with a JSON null (not omitted),
        // so a consumer can distinguish "no coordinates" from a truncated payload.
        let m = event_for_booking_requested(
            Uuid::new_v4(),
            Uuid::new_v4(),
            "no-coords site",
            None,
            None,
            Utc::now(),
            3,
            1,
        );
        assert!(m.payload.get("lat").is_some(), "lat key must be present");
        assert!(m.payload.get("lng").is_some(), "lng key must be present");
        assert!(m.payload["lat"].is_null(), "absent lat → JSON null");
        assert!(m.payload["lng"].is_null(), "absent lng → JSON null");
    }

    #[test]
    fn progress_report_event_carries_all_routing_ids_and_hour() {
        let booking = Uuid::new_v4();
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let report = Uuid::new_v4();
        let m = event_for_progress_report(booking, customer, guard, report, 3);
        assert_eq!(m.topic, topics::BOOKING_PROGRESS_REPORTED);
        assert_eq!(m.payload["booking_id"], json!(booking));
        assert_eq!(m.payload["customer_id"], json!(customer));
        assert_eq!(m.payload["guard_id"], json!(guard));
        assert_eq!(m.payload["report_id"], json!(report));
        assert_eq!(m.payload["hour_number"], json!(3));
    }

    #[test]
    fn requested_emits_nothing() {
        assert!(event_for_status(
            BookingStatus::Requested,
            BookingStatus::Requested,
            Uuid::new_v4(),
            Uuid::new_v4(),
            None,
            None
        )
        .is_none());
    }
}
