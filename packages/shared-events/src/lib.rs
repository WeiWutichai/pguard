//! pguard event bus types — the NATS JetStream envelope + topic constants.
//!
//! Convention: `pguard.events.<bounded_context>.<event_name>` (CLAUDE.md "NATS topics").
//! Every event carries the envelope below; JetStream durable consumers are
//! at-least-once, so consumers must dedupe on [`EventEnvelope::event_id`].
//!
//! The canonical machine-readable contract lives in
//! `contracts/asyncapi/events.yaml`; keep [`topics`] in sync with it.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

mod nats;
mod sig;
pub use nats::connect;
pub use sig::{
    init_signing_key, init_signing_key_from_env, publish_signed, sign_bytes, verify_bytes,
    verify_message, SIGNATURE_HEADER,
};

/// Generated event-payload types — `pguard.events.*` payload structs codegen'd from
/// `contracts/asyncapi/events.yaml` (see `generated/events.rs`). CONTRACT-LOCK only: services
/// still build payloads inline today, and `tests/drift_lock.rs` pins each generated struct to the
/// exact JSON the producers emit, so an un-regenerated contract edit turns the suite red.
/// Adopting these in the services is a documented follow-up (out of scope for the codegen slice).
pub mod generated {
    pub mod events;
}

/// The standard event envelope wrapping a typed `payload`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EventEnvelope<T> {
    /// Unique event id — consumers dedupe on this (at-least-once delivery).
    pub event_id: Uuid,
    /// Fully-qualified topic/type, e.g. `"pguard.events.booking.job_accepted"`.
    pub event_type: String,
    /// When the event occurred (producer clock, UTC).
    pub occurred_at: DateTime<Utc>,
    /// Correlation id threaded across services for distributed tracing.
    pub correlation_id: Uuid,
    /// W3C `traceparent` captured from the producer's request span at construction time
    /// (C5.1). The consumer reparents its span on this so the trace continues across NATS.
    /// `None` when produced outside a sampled trace (e.g. logging-only mode). `default` +
    /// `skip_serializing_if` keep wire-compat with envelopes that predate this field.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub traceparent: Option<String>,
    /// The domain payload.
    pub payload: T,
}

impl<T> EventEnvelope<T> {
    /// Build an envelope for `event_type` with a fresh `event_id` and `occurred_at = now`.
    ///
    /// Captures the current span's `traceparent` so the event carries the producer's trace
    /// through the outbox → NATS → consumer. Call this *inside the request span* (the repo
    /// tx that writes the outbox row) — which is exactly where producers build envelopes.
    pub fn new(event_type: impl Into<String>, correlation_id: Uuid, payload: T) -> Self {
        Self {
            event_id: Uuid::new_v4(),
            event_type: event_type.into(),
            occurred_at: Utc::now(),
            correlation_id,
            traceparent: observability::current_traceparent(),
            payload,
        }
    }
}

/// Canonical topic strings. Mirror of `contracts/asyncapi/events.yaml`.
pub mod topics {
    // booking context
    /// Customer created a booking request (no guard yet). Producer = booking (transactional
    /// outbox, atomic with the bookings insert); consumer = notification → data-push every
    /// ONLINE guard "งานใหม่ใกล้คุณ" (new job nearby) so they can accept it. NOT a lifecycle
    /// status change — the gateway's booking-status WS ignores it (`status_from_topic` → None).
    pub const BOOKING_REQUESTED: &str = "pguard.events.booking.requested";
    pub const BOOKING_JOB_ACCEPTED: &str = "pguard.events.booking.job_accepted";
    pub const BOOKING_DECLINED: &str = "pguard.events.booking.declined";
    pub const BOOKING_CANCELLED: &str = "pguard.events.booking.cancelled";
    pub const BOOKING_COMPLETED: &str = "pguard.events.booking.completed";
    pub const BOOKING_GUARD_EN_ROUTE: &str = "pguard.events.booking.guard_en_route";
    pub const BOOKING_ARRIVED: &str = "pguard.events.booking.arrived";
    /// Guard REQUESTED completion (`arrived → pending_completion`): the customer must now review
    /// and approve/reject. A customer-facing lifecycle status change — the gateway's booking
    /// status WS maps it to the `pending_completion` wire status so the customer's live screen
    /// updates WITHOUT a manual refresh; notification also pushes the customer "โปรดตรวจสอบ".
    /// Same booking-ref payload (booking_id/customer_id/guard_id) as the other lifecycle events.
    pub const BOOKING_COMPLETION_REQUESTED: &str = "pguard.events.booking.completion_requested";
    /// Guard hourly check-in persisted (photo key + GPS). NOT a lifecycle status change —
    /// the gateway's booking-status WS ignores it (`status_from_topic` → None). Future
    /// consumer: notification ("your guard checked in").
    pub const BOOKING_PROGRESS_REPORTED: &str = "pguard.events.booking.progress_reported";

    // payment context
    pub const PAYMENT_COMPLETED: &str = "pguard.events.payment.completed";
    pub const PAYMENT_REFUND_PROCESSED: &str = "pguard.events.payment.refund_processed";

    // rating context
    pub const RATING_SUBMITTED: &str = "pguard.events.rating.submitted";

    // calling context
    pub const CALLING_INITIATED: &str = "pguard.events.calling.initiated";
    pub const CALLING_ACCEPTED: &str = "pguard.events.calling.accepted";
    pub const CALLING_REJECTED: &str = "pguard.events.calling.rejected";
    pub const CALLING_ENDED: &str = "pguard.events.calling.ended";

    // chat context
    pub const CHAT_MESSAGE_SENT: &str = "pguard.events.chat.message_sent";

    // user/security context — triggers force-revoke-all
    pub const USER_COMPROMISED: &str = "pguard.events.user.compromised";
    /// Account approved (profile → identity): identity flips its own `users.approval_status`
    /// to `approved` so the (previously pending) account can log in. Producer = profile,
    /// consumer = identity. Closes the approval→login loop without a cross-schema write.
    pub const USER_APPROVED: &str = "pguard.events.user.approved";
    /// Account rejected — RESERVED topic for a future audit/notify consumer. Not emitted today:
    /// login already blocks every non-`approved` account, so a rejection needs no propagation
    /// (emitting it with no consumer would only accrue orphan messages). Kept for symmetry so a
    /// later "notify the guard they were rejected" slice has a stable name to bind to.
    pub const USER_REJECTED: &str = "pguard.events.user.rejected";
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
    struct JobAccepted {
        booking_id: Uuid,
        guard_id: Uuid,
    }

    #[test]
    fn envelope_new_sets_type_and_payload() {
        let corr = Uuid::new_v4();
        let payload = JobAccepted {
            booking_id: Uuid::new_v4(),
            guard_id: Uuid::new_v4(),
        };
        let env = EventEnvelope::new(topics::BOOKING_JOB_ACCEPTED, corr, payload.clone());
        assert_eq!(env.event_type, "pguard.events.booking.job_accepted");
        assert_eq!(env.correlation_id, corr);
        assert_eq!(env.payload, payload);
    }

    #[test]
    fn envelope_roundtrips_through_json() {
        let env = EventEnvelope::new(
            topics::PAYMENT_COMPLETED,
            Uuid::new_v4(),
            JobAccepted {
                booking_id: Uuid::new_v4(),
                guard_id: Uuid::new_v4(),
            },
        );
        let json = serde_json::to_string(&env).unwrap();
        let back: EventEnvelope<JobAccepted> = serde_json::from_str(&json).unwrap();
        assert_eq!(env, back);
    }

    #[test]
    fn envelope_json_has_all_envelope_fields() {
        let env = EventEnvelope::new(topics::RATING_SUBMITTED, Uuid::new_v4(), 42u32);
        let v: serde_json::Value = serde_json::to_value(&env).unwrap();
        for key in [
            "event_id",
            "event_type",
            "occurred_at",
            "correlation_id",
            "payload",
        ] {
            assert!(v.get(key).is_some(), "missing envelope field: {key}");
        }
    }

    #[test]
    fn each_event_id_is_unique() {
        let a = EventEnvelope::new(topics::CHAT_MESSAGE_SENT, Uuid::new_v4(), 1u8);
        let b = EventEnvelope::new(topics::CHAT_MESSAGE_SENT, Uuid::new_v4(), 1u8);
        assert_ne!(a.event_id, b.event_id);
    }
}
