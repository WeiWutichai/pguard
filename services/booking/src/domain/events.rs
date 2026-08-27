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

use crate::domain::cancellation::{set_for_target, Cancellation};
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
/// The target status alone determines the topic. Both ends of a transition land on the same
/// topic where they share a status: a fresh arrival (`en_route → arrived`) AND the customer's
/// completion REJECT (`pending_completion → arrived`) both emit `booking.arrived`, so the live
/// WS updates the guard's screen on the reject bounce too (notification's mapper de-dupes copy by
/// type, not by transition). `from` is retained for callers/clarity but no longer gates the topic.
///
/// `completion` is only meaningful for [`BookingStatus::Completed`]: it adds
/// `booked_hours` + `actual_seconds` to the payload so the payment consumer can prorate.
/// Other statuses ignore it.
///
/// `cancellation` is the same idea for the two terminal "did not happen" targets
/// ([`BookingStatus::Cancelled`] / [`BookingStatus::Declined`], per
/// [`set_for_target`]): it adds `cancellation_reason` (the stable code) and, only when the
/// client wrote one, `cancellation_note`. The note key is OMITTED when `None` (the `guard_id`
/// precedent — an absent note is no key at all, not a JSON null), so a consumer can render
/// "reason only" without null-checking. Other statuses ignore it.
///
/// `is_admin` + `from` decide the `charge_cancel_fee` boolean that rides ONLY the
/// `booking.cancelled` event (the booking side of the shared cancellation-fee policy): it is
/// `true` ONLY for a genuine CUSTOMER-initiated cancel of a still-active booking
/// (`requested`/`accepted`/`en_route` → `cancelled`) BEFORE arrival, and `false` for (a) an
/// ADMIN-initiated cancel (`is_admin`), (b) the customer's cancel-after-decline ACK
/// (`from == Declined`), and — by construction — (c) a guard decline/withdraw (that emits
/// `booking.declined`, a different topic that never carries the flag). Payment charges the
/// cancellation fee IFF this boolean is `true`, defaulting to `false` when the field is absent
/// (an old event). This is what keeps "admin cancel charges customer" and the
/// decline-vs-ack fee reordering from ever charging a fee that was not the customer's own choice.
#[allow(clippy::too_many_arguments)]
pub fn event_for_status(
    // The source status. It no longer gates the TOPIC (target status alone decides), but it now
    // decides the `charge_cancel_fee` flag on a `booking.cancelled` (an ACK of a decline comes
    // FROM `declined` and must never carry a fee), so it is a live input again, not decoration.
    from: BookingStatus,
    new_status: BookingStatus,
    booking_id: Uuid,
    customer_id: Uuid,
    guard_id: Option<Uuid>,
    completion: Option<CompletionInfo>,
    cancellation: Option<&Cancellation>,
    is_admin: bool,
) -> Option<EventMapping> {
    let topic = match new_status {
        BookingStatus::Accepted => topics::BOOKING_JOB_ACCEPTED,
        BookingStatus::Declined => topics::BOOKING_DECLINED,
        BookingStatus::EnRoute => topics::BOOKING_GUARD_EN_ROUTE,
        // BOTH a fresh arrival (en_route → arrived) AND the completion-REJECT bounce
        // (pending_completion → arrived) emit `booking.arrived`: the customer's live screen must
        // update on either path. (The earlier behavior of emitting nothing on the reject bounce
        // left the GUARD's live screen stuck on "pending_completion" until a manual refresh.)
        BookingStatus::Arrived => topics::BOOKING_ARRIVED,
        BookingStatus::Completed => topics::BOOKING_COMPLETED,
        BookingStatus::Cancelled => topics::BOOKING_CANCELLED,
        // The guard's completion REQUEST (arrived → pending_completion) is a customer-facing
        // lifecycle change: the customer must review it. Emit so the customer's live WS updates
        // WITHOUT a manual refresh + notification pushes "please review".
        BookingStatus::PendingCompletion => topics::BOOKING_COMPLETION_REQUESTED,
        // A bare request has no cross-service event (create_booking emits booking.requested
        // separately — don't double-emit here).
        BookingStatus::Requested => return None,
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
    // WHY the job did not happen — only on the two terminal cancellation targets (a stray
    // reason can never ride e.g. booking.arrived). The reason is the stable CODE, so the
    // notification consumer localizes it; the note rides only when the client wrote one.
    if set_for_target(new_status).is_some() {
        if let Some(c) = cancellation {
            payload["cancellation_reason"] = json!(c.reason);
            if let Some(note) = &c.note {
                payload["cancellation_note"] = json!(note);
            }
        }
    }
    // Cancellation-fee policy (booking side): `charge_cancel_fee` rides ONLY `booking.cancelled`.
    // It is TRUE exclusively for a genuine CUSTOMER-initiated cancel of a still-active booking
    // BEFORE arrival — i.e. NOT an admin cancel (`is_admin`) and NOT the ack of a guard decline
    // (`from == Declined`, whose fee-free full refund was already issued on `booking.declined`).
    // Payment reads this boolean and charges the fee IFF true (default false when absent).
    if new_status == BookingStatus::Cancelled {
        let charge_cancel_fee = !is_admin
            && matches!(
                from,
                BookingStatus::Requested | BookingStatus::Accepted | BookingStatus::EnRoute
            );
        payload["charge_cancel_fee"] = json!(charge_cancel_fee);
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
///
/// `target_guard_id` (DIRECTED OFFER, C3) rides the SAME even-when-null way: `Some(g)` means the
/// booking was offered to ONE guard, so the notification consumer must push the "new job" to ONLY
/// that guard (a broadcast to every online guard would defeat the directed offer); `null` = OPEN
/// first-come → notification fans out to all online guards, as today. NOTE for notification (out
/// of scope here): branch on this key — target the one guard when present, broadcast when null.
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
    target_guard_id: Option<Uuid>,
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
            // Carried even when None → JSON null: notification routes the "new job" to this one
            // guard when set, or broadcasts to all online guards when null (open first-come).
            "target_guard_id": target_guard_id,
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
            None,
            false,
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
            None,
            false,
        )
        .expect("declined must emit");
        assert_eq!(m.topic, topics::BOOKING_DECLINED);
        // declined before any guard assignment → no guard_id in payload
        assert!(m.payload.get("guard_id").is_none());
        // ...and a pre-0009 decline (no reason recorded) carries neither cancellation key.
        assert!(m.payload.get("cancellation_reason").is_none());
        assert!(m.payload.get("cancellation_note").is_none());
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
                None,
                None,
                false
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
                None,
                None,
                false
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
                None,
                None,
                false
            )
            .unwrap()
            .topic,
            topics::BOOKING_COMPLETED
        );
    }

    #[test]
    fn pending_completion_emits_completion_requested() {
        // The guard's completion REQUEST (arrived → pending_completion) MUST emit so the
        // customer's live WS updates without a manual refresh (this was the dropped-event bug).
        let b = Uuid::new_v4();
        let c = Uuid::new_v4();
        let g = Uuid::new_v4();
        let m = event_for_status(
            BookingStatus::Arrived,
            BookingStatus::PendingCompletion,
            b,
            c,
            Some(g),
            None,
            None,
            false,
        )
        .expect("pending_completion must emit");
        assert_eq!(m.topic, topics::BOOKING_COMPLETION_REQUESTED);
        assert_eq!(m.topic, "pguard.events.booking.completion_requested");
        // Same booking-ref payload as the other lifecycle transitions.
        assert_eq!(m.payload["booking_id"], json!(b));
        assert_eq!(m.payload["customer_id"], json!(c));
        assert_eq!(m.payload["guard_id"], json!(g));
        // Proration/pricing fields ride ONLY booking.completed, never the completion request.
        assert!(m.payload.get("booked_hours").is_none());
    }

    #[test]
    fn completion_reject_bounce_to_arrived_emits_arrived() {
        // pending_completion → arrived is the customer REJECTING completion: the guard goes back
        // to work. It MUST emit booking.arrived so the GUARD's live screen leaves
        // "pending_completion" without a manual refresh (the topic is keyed on the TARGET status).
        let b = Uuid::new_v4();
        let c = Uuid::new_v4();
        let g = Uuid::new_v4();
        let m = event_for_status(
            BookingStatus::PendingCompletion,
            BookingStatus::Arrived,
            b,
            c,
            Some(g),
            None,
            None,
            false,
        )
        .expect("completion-reject bounce must emit");
        assert_eq!(m.topic, topics::BOOKING_ARRIVED);
        assert_eq!(m.payload["booking_id"], json!(b));
        assert_eq!(m.payload["guard_id"], json!(g));
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
            None,
            false,
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
            None,
            false,
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
            None,
            false,
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
            None,
            false,
        )
        .expect("cancelled must emit");
        assert_eq!(m.topic, topics::BOOKING_CANCELLED);
        assert_eq!(m.payload["guard_id"], json!(g));
        // A customer cancel of a still-active (pre-arrival) booking charges the cancellation fee.
        assert_eq!(m.payload["charge_cancel_fee"], json!(true));
    }

    // ----- the cancellation-fee policy flag rides ONLY booking.cancelled -----

    #[test]
    fn customer_active_cancel_charges_the_fee() {
        // A genuine customer-initiated cancel of a still-active pre-arrival booking
        // (requested/accepted/en_route → cancelled) is the ONE case that carries a fee.
        for from in [
            BookingStatus::Requested,
            BookingStatus::Accepted,
            BookingStatus::EnRoute,
        ] {
            let m = event_for_status(
                from,
                BookingStatus::Cancelled,
                Uuid::new_v4(),
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                None,
                Some(&Cancellation {
                    reason: "changed_plan",
                    note: None,
                }),
                false, // is_admin
            )
            .expect("cancelled must emit");
            assert_eq!(
                m.payload["charge_cancel_fee"],
                json!(true),
                "{from} → cancelled by the customer must charge the fee"
            );
        }
    }

    #[test]
    fn admin_cancel_never_charges_the_fee() {
        // An admin cancels on the customer's behalf (support/ops) — the customer did not choose
        // to cancel, so no fee, even from an otherwise fee-bearing active state.
        let m = event_for_status(
            BookingStatus::EnRoute,
            BookingStatus::Cancelled,
            Uuid::new_v4(),
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            None,
            Some(&Cancellation {
                reason: "changed_plan",
                note: None,
            }),
            true, // is_admin
        )
        .expect("cancelled must emit");
        assert_eq!(m.payload["charge_cancel_fee"], json!(false));
    }

    #[test]
    fn cancel_after_decline_ack_never_charges_the_fee() {
        // The customer's ACK of a guard withdrawal (declined → cancelled) full-refunds with no
        // fee: the guard ended the job, not the customer. `from == Declined` is the tell, whoever
        // drives it.
        for is_admin in [false, true] {
            let m = event_for_status(
                BookingStatus::Declined,
                BookingStatus::Cancelled,
                Uuid::new_v4(),
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                None,
                None,
                is_admin,
            )
            .expect("cancelled must emit");
            assert_eq!(
                m.payload["charge_cancel_fee"],
                json!(false),
                "the decline ACK must never charge a fee (is_admin={is_admin})"
            );
        }
    }

    #[test]
    fn declined_event_carries_no_fee_flag() {
        // The guard-withdraw event is a DIFFERENT topic (booking.declined) and never carries the
        // fee flag — payment full-refunds it, and defaults the absent flag to false.
        let m = event_for_status(
            BookingStatus::EnRoute,
            BookingStatus::Declined,
            Uuid::new_v4(),
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            None,
            Some(&Cancellation {
                reason: "sick",
                note: None,
            }),
            false,
        )
        .expect("declined must emit");
        assert_eq!(m.topic, topics::BOOKING_DECLINED);
        assert!(
            m.payload.get("charge_cancel_fee").is_none(),
            "charge_cancel_fee rides only booking.cancelled, not booking.declined"
        );
    }

    // ----- the cancellation reason rides the two terminal "did not happen" events -----

    #[test]
    fn cancelled_carries_reason_and_note() {
        let m = event_for_status(
            BookingStatus::EnRoute,
            BookingStatus::Cancelled,
            Uuid::new_v4(),
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            None,
            Some(&Cancellation {
                reason: "other",
                note: Some("ลูกค้าไม่อยู่บ้าน".to_string()),
            }),
            false,
        )
        .expect("cancelled must emit");
        assert_eq!(m.topic, topics::BOOKING_CANCELLED);
        // The stable CODE rides the wire — notification/the app localize it.
        assert_eq!(m.payload["cancellation_reason"], json!("other"));
        assert_eq!(m.payload["cancellation_note"], json!("ลูกค้าไม่อยู่บ้าน"));
        // A customer en_route cancel carries the fee flag.
        assert_eq!(m.payload["charge_cancel_fee"], json!(true));
    }

    #[test]
    fn declined_carries_reason_and_omits_an_absent_note() {
        let m = event_for_status(
            BookingStatus::EnRoute,
            BookingStatus::Declined,
            Uuid::new_v4(),
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            None,
            Some(&Cancellation {
                reason: "sick",
                note: None,
            }),
            false,
        )
        .expect("declined must emit");
        assert_eq!(m.topic, topics::BOOKING_DECLINED);
        assert_eq!(m.payload["cancellation_reason"], json!("sick"));
        // OMITTED entirely (the guard_id precedent) — not a JSON null.
        assert!(
            m.payload.get("cancellation_note").is_none(),
            "an absent note must not appear as a null key: {}",
            m.payload
        );
    }

    #[test]
    fn non_cancellation_statuses_ignore_the_reason() {
        // A stray reason must never leak onto e.g. booking.arrived (set_for_target gates it).
        let c = Cancellation {
            reason: "sick",
            note: Some("should not appear".to_string()),
        };
        for (from, to) in [
            (BookingStatus::Requested, BookingStatus::Accepted),
            (BookingStatus::EnRoute, BookingStatus::Arrived),
            (BookingStatus::Arrived, BookingStatus::PendingCompletion),
            (BookingStatus::PendingCompletion, BookingStatus::Completed),
        ] {
            let m = event_for_status(
                from,
                to,
                Uuid::new_v4(),
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                None,
                Some(&c),
                false,
            )
            .expect("must emit");
            assert!(
                m.payload.get("cancellation_reason").is_none()
                    && m.payload.get("cancellation_note").is_none(),
                "{from} → {to} must carry no cancellation keys: {}",
                m.payload
            );
        }
    }

    #[test]
    fn booking_requested_carries_full_job_payload() {
        let booking = Uuid::new_v4();
        let customer = Uuid::new_v4();
        let scheduled_at: DateTime<Utc> = "2026-06-22T10:00:00Z".parse().unwrap();
        let target = Uuid::new_v4();
        let m = event_for_booking_requested(
            booking,
            customer,
            "1 Sukhumvit Rd",
            Some(13.7563),
            Some(100.5018),
            scheduled_at,
            4,
            2,
            Some(target),
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
        // DIRECTED OFFER (C3): the targeted guard rides the event so notification routes to only them.
        assert_eq!(m.payload["target_guard_id"], json!(target));
    }

    #[test]
    fn booking_requested_carries_null_target_guard_as_present_key() {
        // An OPEN (un-directed) booking still emits the key with a JSON null — notification reads
        // "null" as "broadcast to all online guards" (vs. a missing key it would have to special-case).
        let m = event_for_booking_requested(
            Uuid::new_v4(),
            Uuid::new_v4(),
            "open job",
            None,
            None,
            Utc::now(),
            3,
            1,
            None,
        );
        assert!(
            m.payload.get("target_guard_id").is_some(),
            "target_guard_id key must be present"
        );
        assert!(
            m.payload["target_guard_id"].is_null(),
            "an open booking → JSON null target_guard_id (broadcast)"
        );
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
            None,
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
            None,
            None,
            false
        )
        .is_none());
    }
}
