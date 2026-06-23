//! Event CONSUMER — booking's inbound half of the PRE-PAY gate: subscribe to
//! `pguard.events.payment.completed` and stamp the booking's `paid_at` so the
//! `accepted → en_route` transition un-gates (the guard may then go en route).
//!
//! Booking was a PURE PRODUCER until now (only the outbox relay). This is its FIRST inbound
//! consumer, modelled on payment's `booking.completed` consumer:
//!  - A durable PULL consumer filtered to `payment.completed` (JetStream at-least-once).
//!  - The stamp is IDEMPOTENT via `booking.processed_events` (claim the envelope's `event_id`
//!    in the same tx that sets `paid_at`): a redelivery re-stamps nothing.
//!  - HMAC-verified before any write — a forged `payment.completed` (which would un-gate an
//!    unpaid booking) is dropped, counted, never applied. Fail-closed.
//!  - A message is acked only after a successful stamp; a transient (DB) failure leaves it for
//!    redelivery (safe — the ledger absorbs the replay). A malformed envelope is POISON: acked
//!    (dropped) so it can't wedge the consumer redelivering forever.

use std::time::Duration;

use futures::StreamExt;
use serde::Deserialize;
use tracing::Instrument;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::{topics, EventEnvelope};

use crate::repo;

const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";
/// Intent-scoped durable name (this consumer only ever un-gates on payment completions).
const DURABLE: &str = "booking-payment-completed";
/// Backoff between reconnect attempts when NATS is down or the stream ends.
const RECONNECT_INTERVAL: Duration = Duration::from_secs(2);

/// The single `payment.completed` field booking needs: WHICH booking was paid. payment emits
/// `{ payment_id, booking_id, guard_id, amount }` (AsyncAPI `EnvelopeOf_PaymentRef`); booking
/// reads only `booking_id`. A missing `booking_id` fails the parse → the event is poison
/// (dropped + logged), never silently un-gating the wrong booking.
#[derive(Debug, Deserialize)]
struct PaymentCompletedPayload {
    booking_id: Uuid,
}

/// Run the payment.completed consumer FOREVER: (re)connect to NATS, drain, and on any
/// connect/stream error log + back off + reconnect. Never returns under normal operation — a
/// transient NATS outage must not silently kill the gate's un-gating half (mirrors `run_relay`'s
/// resilience). Spawned as a background task by `main`.
pub async fn run_consumer(db: sqlx::PgPool, nats_url: String) {
    loop {
        match connect_and_consume(&db, &nats_url).await {
            // The message stream ended (NATS dropped the connection) — reconnect.
            Ok(()) => tracing::warn!("payment.completed consumer stream ended; reconnecting"),
            Err(e) => tracing::warn!("payment.completed consumer error: {e}; reconnecting"),
        }
        tokio::time::sleep(RECONNECT_INTERVAL).await;
    }
}

/// One connect+consume session: bind the durable consumer and drain until the stream ends or a
/// fatal error. Returns to [`run_consumer`], which reconnects.
async fn connect_and_consume(db: &sqlx::PgPool, nats_url: &str) -> Result<(), AppError> {
    let client = shared_events::connect(nats_url)
        .await
        .map_err(|e| AppError::Internal(format!("NATS connect failed: {e}")))?;
    let jetstream = async_nats::jetstream::new(client);

    let stream = jetstream
        .get_or_create_stream(async_nats::jetstream::stream::Config {
            name: STREAM.to_string(),
            subjects: vec![SUBJECTS.to_string()],
            ..Default::default()
        })
        .await
        .map_err(|e| AppError::Internal(format!("ensure stream failed: {e}")))?;

    let consumer = stream
        .get_or_create_consumer(
            DURABLE,
            async_nats::jetstream::consumer::pull::Config {
                durable_name: Some(DURABLE.to_string()),
                // Only payment completions reach the gate.
                filter_subject: topics::PAYMENT_COMPLETED.to_string(),
                ..Default::default()
            },
        )
        .await
        .map_err(|e| AppError::Internal(format!("ensure consumer failed: {e}")))?;

    let mut messages = consumer
        .messages()
        .await
        .map_err(|e| AppError::Internal(format!("consume failed: {e}")))?;

    tracing::info!(
        stream = STREAM,
        subject = topics::PAYMENT_COMPLETED,
        "booking payment.completed consumer started"
    );

    while let Some(item) = messages.next().await {
        let message = match item {
            Ok(m) => m,
            Err(e) => {
                tracing::warn!("NATS message error: {e}");
                continue;
            }
        };

        // Report this durable consumer's backlog (lag) to Prometheus.
        if let Ok(info) = message.info() {
            observability::record_consumer_lag(DURABLE, info.pending);
        }

        // Verify the HMAC signature BEFORE stamping — a forged `payment.completed` (which would
        // un-gate an UNPAID booking) is dropped, counted, and never applied. Fail-closed.
        if !shared_events::verify_message(message.headers.as_ref(), message.payload.as_ref()) {
            observability::record_rejected_event(DURABLE);
            tracing::warn!(
                "dropping payment.completed event with missing/invalid signature (forged?)"
            );
            let _ = message.ack().await;
            continue;
        }

        // Parse first. A malformed envelope is POISON — it can never become valid, so ACK it
        // (drop) instead of redelivering forever and wedging the consumer.
        let envelope: EventEnvelope<PaymentCompletedPayload> =
            match serde_json::from_slice(message.payload.as_ref()) {
                Ok(e) => e,
                Err(e) => {
                    observability::record_rejected_event(DURABLE);
                    tracing::error!("dropping malformed payment.completed envelope (poison): {e}");
                    let _ = message.ack().await;
                    continue;
                }
            };

        match process(db, envelope).await {
            Ok(()) => {
                if let Err(e) = message.ack().await {
                    tracing::warn!("ack failed: {e}");
                }
            }
            Err(e) => {
                // Transient (e.g. DB) error → do NOT ack; JetStream redelivers and the
                // processed_events ledger makes the reprocess safe (no re-stamp).
                tracing::error!("payment.completed stamp failed (will redeliver): {e}");
            }
        }
    }

    Ok(())
}

/// Stamp one parsed completion inside a span carrying the event identity + `correlation_id` so
/// the payment→NATS→booking trace stitches together. Returns `Err` only on transient
/// (retryable) failures.
async fn process(
    db: &sqlx::PgPool,
    envelope: EventEnvelope<PaymentCompletedPayload>,
) -> Result<(), AppError> {
    // Defensive: the filter restricts the subject, but never act off an unexpected type.
    if envelope.event_type != topics::PAYMENT_COMPLETED {
        tracing::warn!(event_type = %envelope.event_type, "ignoring unexpected event type");
        return Ok(());
    }

    let span = tracing::info_span!(
        "booking.mark_paid_on_payment",
        event_type = %envelope.event_type,
        event_id = %envelope.event_id,
        correlation_id = %envelope.correlation_id,
    );
    // Reparent on the producer's trace (carried in the envelope) so payment→NATS→booking is one
    // distributed trace in Tempo (C5.1).
    if let Some(tp) = envelope.traceparent.as_deref() {
        observability::set_parent_from_traceparent(&span, tp);
    }
    mark_paid(db, envelope).instrument(span).await
}

/// Stamp the paid booking's `paid_at` idempotently (un-gates en_route), logging the outcome.
async fn mark_paid(
    db: &sqlx::PgPool,
    envelope: EventEnvelope<PaymentCompletedPayload>,
) -> Result<(), AppError> {
    let booking_id = envelope.payload.booking_id;
    let claimed =
        repo::mark_paid_idempotent(db, envelope.event_id, &envelope.event_type, booking_id).await?;
    if claimed {
        tracing::info!(%booking_id, "booking marked paid on payment.completed (en_route un-gated)");
    } else {
        tracing::debug!(%booking_id, "duplicate payment.completed; skipped");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// The envelope/payload parse the consumer relies on: a well-formed payment.completed event
    /// yields the booking_id (the only field booking needs). Pure (no DB/NATS).
    #[test]
    fn parses_payment_completed_envelope() {
        let booking_id = Uuid::new_v4();
        let raw = json!({
            "event_id": Uuid::new_v4(),
            "event_type": topics::PAYMENT_COMPLETED,
            "occurred_at": "2026-06-23T10:00:00Z",
            "correlation_id": Uuid::new_v4(),
            "payload": {
                "payment_id": Uuid::new_v4(),
                "booking_id": booking_id,
                "guard_id": Uuid::new_v4(),
                "amount": "1000.00"
            }
        });
        let env: EventEnvelope<PaymentCompletedPayload> =
            serde_json::from_value(raw).expect("parse");
        assert_eq!(env.event_type, topics::PAYMENT_COMPLETED);
        assert_eq!(env.payload.booking_id, booking_id);
    }

    /// A payment.completed payload missing `booking_id` is POISON — the parse fails (the consumer
    /// drops it rather than stamping the wrong/no booking).
    #[test]
    fn payload_without_booking_id_fails_to_parse() {
        let raw = json!({
            "event_id": Uuid::new_v4(),
            "event_type": topics::PAYMENT_COMPLETED,
            "occurred_at": "2026-06-23T10:00:00Z",
            "correlation_id": Uuid::new_v4(),
            "payload": { "payment_id": Uuid::new_v4(), "amount": "1000.00" }
        });
        let parsed: Result<EventEnvelope<PaymentCompletedPayload>, _> = serde_json::from_value(raw);
        assert!(parsed.is_err(), "missing booking_id must fail the parse");
    }
}
