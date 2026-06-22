//! Drift-lock for the generated `pguard.events.*` payload types.
//!
//! Each test pins a generated struct (codegen'd from `contracts/asyncapi/events.yaml`) to the
//! EXACT JSON its producing service emits today — the JSON values below are transcribed from the
//! real `serde_json::json!` payloads in the services (see each test's source ref). The check is
//! deliberately NOT a self-roundtrip (which would prove nothing): it
//!   1. deserializes the real producer JSON into `EventEnvelope<generated::X>` — fails if the
//!      contract dropped/renamed a field the producer still sends, or added a new required one;
//!   2. reads each field BY NAME (`payload.booking_id`, …) — a renamed field in events.yaml
//!      regenerates a different Rust field name and this test stops COMPILING (compile-time lock);
//!   3. re-serializes and asserts byte-for-byte equality with the producer JSON — fails if the
//!      generated struct grew/lost a field vs. what the service actually puts on the wire.
//!
//! So: edit events.yaml and forget to regenerate ⇒ generated structs diverge from these fixtures
//! ⇒ the suite goes red (and the CI stale-check also catches the un-regenerated file). This is the
//! contract↔code binding the codegen slice adds; services are NOT switched to these types here.

use serde_json::{json, Value};
use shared_events::generated::events::*;
use shared_events::{topics, EventEnvelope};

/// Wrap a payload in a well-formed envelope (the envelope itself is hand-written + generic).
fn envelope(event_type: &str, payload: Value) -> Value {
    json!({
        "event_id": "11111111-1111-4111-8111-111111111111",
        "event_type": event_type,
        "occurred_at": "2026-06-10T12:00:00Z",
        "correlation_id": "22222222-2222-4222-8222-222222222222",
        "payload": payload,
    })
}

const B: &str = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"; // booking_id
const G: &str = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"; // guard_id
const C: &str = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"; // customer_id

/// Deserialize an envelope JSON into a typed `EventEnvelope<T>`, asserting it parses.
fn parse<T: serde::de::DeserializeOwned>(env: &Value) -> EventEnvelope<T> {
    serde_json::from_value(env.clone()).expect("producer JSON must parse into the generated type")
}

// ── booking ──────────────────────────────────────────────────────────────────
// Ref: services/booking/src/domain/events.rs — payload()/event_for_status()/event_for_progress_report().

#[test]
fn booking_requested_with_coords_locks_to_producer_shape() {
    // Producer = booking's event_for_booking_requested(): new-job signal carrying the full job
    // card (ids, address, scheduled_at, hours, guard_count) + the site coordinates. lat/lng are
    // present numbers here, so the generated Option<f64> round-trips byte-for-byte.
    let payload = json!({
        "booking_id": B, "customer_id": C, "address": "1 Sukhumvit Rd",
        "lat": 13.7563, "lng": 100.5018,
        "scheduled_at": "2026-06-22T10:00:00Z", "hours": 4, "guard_count": 2
    });
    let env: EventEnvelope<BookingRequested> =
        parse(&envelope(topics::BOOKING_REQUESTED, payload.clone()));
    assert_eq!(env.payload.booking_id.to_string(), B);
    assert_eq!(env.payload.customer_id.to_string(), C);
    assert_eq!(env.payload.address, "1 Sukhumvit Rd");
    assert_eq!(env.payload.lat, Some(13.7563));
    assert_eq!(env.payload.lng, Some(100.5018));
    assert_eq!(env.payload.hours, 4);
    assert_eq!(env.payload.guard_count, 2);
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}

#[test]
fn booking_requested_with_null_coords_accepts_present_null() {
    // Producer CARRIES lat/lng EVEN WHEN ABSENT → emits them as JSON null (key present), the
    // actual_seconds precedent. The generated type must accept present-null → None. Re-serialize
    // omits them (skip None), semantically equivalent, so we lock the DESERIALIZE behavior here.
    let payload = json!({
        "booking_id": B, "customer_id": C, "address": "no-coords site",
        "lat": null, "lng": null,
        "scheduled_at": "2026-06-22T10:00:00Z", "hours": 3, "guard_count": 1
    });
    let env: EventEnvelope<BookingRequested> = parse(&envelope(topics::BOOKING_REQUESTED, payload));
    assert!(env.payload.lat.is_none());
    assert!(env.payload.lng.is_none());
    assert_eq!(env.payload.guard_count, 1);
}

#[test]
fn job_accepted_locks_to_producer_shape() {
    let payload = json!({ "booking_id": B, "guard_id": G, "customer_id": C });
    let env: EventEnvelope<JobAccepted> =
        parse(&envelope(topics::BOOKING_JOB_ACCEPTED, payload.clone()));
    assert_eq!(env.payload.booking_id.to_string(), B);
    assert_eq!(env.payload.guard_id.to_string(), G);
    assert_eq!(env.payload.customer_id.to_string(), C);
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}

#[test]
fn booking_ref_with_guard_roundtrips() {
    // cancelled/arrived/en_route once a guard is assigned: payload carries guard_id.
    let payload = json!({ "booking_id": B, "customer_id": C, "guard_id": G });
    let env: EventEnvelope<BookingRef> =
        parse(&envelope(topics::BOOKING_CANCELLED, payload.clone()));
    assert_eq!(env.payload.booking_id.to_string(), B);
    assert_eq!(env.payload.customer_id.unwrap().to_string(), C);
    assert_eq!(env.payload.guard_id.unwrap().to_string(), G);
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}

#[test]
fn booking_ref_without_guard_omits_the_field() {
    // declined before assignment: producer OMITS guard_id (json! without the key). The generated
    // Option<Uuid> + skip_serializing_if must re-emit it ABSENT (not null) to match.
    let payload = json!({ "booking_id": B, "customer_id": C });
    let env: EventEnvelope<BookingRef> =
        parse(&envelope(topics::BOOKING_DECLINED, payload.clone()));
    assert!(env.payload.guard_id.is_none());
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}

#[test]
fn booking_completed_with_work_locks_proration_fields() {
    // Pricing fields (base_fee/guard_count/tip) ride the event so the post-pay consumer bills
    // self-contained; money is a decimal STRING (rust_decimal serde-str on the producer side).
    let payload = json!({
        "booking_id": B, "customer_id": C, "guard_id": G,
        "booked_hours": 4, "actual_seconds": 7200,
        "base_fee": "500.00", "guard_count": 2, "tip": "0"
    });
    let env: EventEnvelope<BookingCompleted> =
        parse(&envelope(topics::BOOKING_COMPLETED, payload.clone()));
    assert_eq!(env.payload.booked_hours, 4);
    assert_eq!(env.payload.actual_seconds, Some(7200));
    assert_eq!(env.payload.base_fee, "500.00");
    assert_eq!(env.payload.guard_count, 2);
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}

#[test]
fn booking_completed_without_start_accepts_null_actual_seconds() {
    // "guard never started" → producer emits actual_seconds: null (explicit). The generated type
    // must accept null → None (proration basis absent). Re-serialize omits it (skip None), which is
    // semantically equivalent, so we lock the DESERIALIZE behavior here, not byte-equality.
    let payload = json!({
        "booking_id": B, "customer_id": C, "booked_hours": 3, "actual_seconds": null,
        "base_fee": "300.00", "guard_count": 1, "tip": "0"
    });
    let env: EventEnvelope<BookingCompleted> = parse(&envelope(topics::BOOKING_COMPLETED, payload));
    assert_eq!(env.payload.booked_hours, 3);
    assert!(env.payload.actual_seconds.is_none());
    assert_eq!(env.payload.guard_count, 1);
}

#[test]
fn progress_reported_locks_routing_ids() {
    let report = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
    let payload = json!({
        "booking_id": B, "customer_id": C, "guard_id": G,
        "report_id": report, "hour_number": 3
    });
    let env: EventEnvelope<ProgressReported> = parse(&envelope(
        topics::BOOKING_PROGRESS_REPORTED,
        payload.clone(),
    ));
    assert_eq!(env.payload.report_id.to_string(), report);
    assert_eq!(env.payload.hour_number, 3);
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}

// ── payment ──────────────────────────────────────────────────────────────────
// Ref: services/payment/src/repo/mod.rs — completed + refund_processed json! payloads.

#[test]
fn payment_completed_locks_decimal_amount_as_string() {
    let pid = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
    let payload = json!({ "payment_id": pid, "booking_id": B, "guard_id": G, "amount": "500.00" });
    let env: EventEnvelope<PaymentRef> =
        parse(&envelope(topics::PAYMENT_COMPLETED, payload.clone()));
    assert_eq!(env.payload.amount, "500.00"); // money is a decimal STRING, never a float
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}

#[test]
fn payment_refund_processed_locks_amounts() {
    let pid = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
    let payload = json!({
        "payment_id": pid, "booking_id": B, "refund_amount": "150.00", "final_amount": "350.00"
    });
    let env: EventEnvelope<RefundRef> =
        parse(&envelope(topics::PAYMENT_REFUND_PROCESSED, payload.clone()));
    assert_eq!(env.payload.refund_amount, "150.00");
    assert_eq!(env.payload.final_amount, "350.00");
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}

// ── rating ───────────────────────────────────────────────────────────────────
// Ref: services/rating/src/repo/mod.rs — rating.submitted json! payload.

#[test]
fn rating_submitted_locks_score() {
    let rid = "ffffffff-ffff-4fff-8fff-ffffffffffff";
    let payload = json!({ "rating_id": rid, "booking_id": B, "guard_id": G, "score": 5 });
    let env: EventEnvelope<RatingRef> = parse(&envelope(topics::RATING_SUBMITTED, payload.clone()));
    assert_eq!(env.payload.score, 5);
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}

// ── calling ──────────────────────────────────────────────────────────────────
// Ref: services/calling/src/repo/mod.rs. NOTE the contract (EnvelopeOf_CallRef) defines only
// [call_id, booking_id]; the calling service currently ALSO emits caller_id/callee_id/status —
// a pre-existing producer-vs-contract drift (the open object schema allows extra fields). The
// generated type locks the CONTRACT subset; the second test proves it still parses the richer
// producer payload (extras ignored), so it is forward-compatible. Reconciling the two is a
// follow-up (either tighten the producer or add the fields to events.yaml).

#[test]
fn call_ref_locks_to_contract_subset() {
    let call = "99999999-9999-4999-8999-999999999999";
    let payload = json!({ "call_id": call, "booking_id": B });
    let env: EventEnvelope<CallRef> = parse(&envelope(topics::CALLING_INITIATED, payload.clone()));
    assert_eq!(env.payload.call_id.to_string(), call);
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}

#[test]
fn call_ref_ignores_extra_producer_fields() {
    let call = "99999999-9999-4999-8999-999999999999";
    let producer = json!({
        "call_id": call, "booking_id": B,
        "caller_id": C, "callee_id": G, "status": "initiated"
    });
    let env: EventEnvelope<CallRef> = parse(&envelope(topics::CALLING_INITIATED, producer));
    assert_eq!(env.payload.call_id.to_string(), call);
    assert_eq!(env.payload.booking_id.to_string(), B);
}

// ── chat ─────────────────────────────────────────────────────────────────────
// Ref: services/chat/src/repo/mod.rs — chat.message_sent json! payload.

#[test]
fn chat_message_sent_locks_participants() {
    let msg = "12121212-1212-4121-8121-121212121212";
    let conv = "34343434-3434-4343-8343-343434343434";
    let payload = json!({
        "message_id": msg, "conversation_id": conv, "sender_id": C, "recipient_id": G
    });
    let env: EventEnvelope<ChatRef> = parse(&envelope(topics::CHAT_MESSAGE_SENT, payload.clone()));
    assert_eq!(env.payload.message_id.to_string(), msg);
    assert_eq!(env.payload.recipient_id.to_string(), G);
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}

// ── user / security ────────────────────────────────────────────────────────────
// Ref: user.approved PRODUCER = services/profile/src/repo/mod.rs (emits {user_id, role,
// approved_at}); identity's consumer reads only {user_id}, so we lock the richer PRODUCER shape.
// user.compromised has NO in-repo producer yet (reserved topic) — locked to the CONTRACT
// (events.yaml required:[user_id, reason]); identity's consumer reads only {user_id}.

#[test]
fn user_compromised_locks_reason() {
    let uid = "56565656-5656-4565-8565-565656565656";
    let payload = json!({ "user_id": uid, "reason": "refresh_token_reuse_detected" });
    let env: EventEnvelope<UserRef> = parse(&envelope(topics::USER_COMPROMISED, payload.clone()));
    assert_eq!(env.payload.reason, "refresh_token_reuse_detected");
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}

#[test]
fn user_approved_with_timestamp_roundtrips() {
    let uid = "56565656-5656-4565-8565-565656565656";
    let payload = json!({ "user_id": uid, "role": "guard", "approved_at": "2026-06-10T12:00:00Z" });
    let env: EventEnvelope<UserApproved> = parse(&envelope(topics::USER_APPROVED, payload.clone()));
    assert_eq!(env.payload.role, "guard");
    assert!(env.payload.approved_at.is_some());
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}

#[test]
fn user_approved_without_timestamp_omits_it() {
    // identity's consumer (ApprovedPayload) only needs user_id; approved_at is optional metadata.
    let uid = "56565656-5656-4565-8565-565656565656";
    let payload = json!({ "user_id": uid, "role": "customer" });
    let env: EventEnvelope<UserApproved> = parse(&envelope(topics::USER_APPROVED, payload.clone()));
    assert!(env.payload.approved_at.is_none());
    assert_eq!(serde_json::to_value(&env.payload).unwrap(), payload);
}
