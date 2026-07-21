//! Event CONSUMER — the REFUND half: subscribe to `pguard.events.booking.declined` +
//! `pguard.events.booking.cancelled` and FULL-REFUND the customer's pre-pay when a PAID booking is
//! cancelled before it ran (a guard withdrawing en_route, or a customer cancelling after paying).
//!
//! Kept SEPARATE from the completion-settle consumer (its own durable) so the money-critical
//! reconcile path is untouched. v2 policy: no work was done → the ENTIRE pre-pay is returned
//! (`repo::refund_on_cancellation` flips the row to `refunded`, queues the refund). An UNPAID cancel
//! (e.g. cancelled at `accepted`, before the pre-pay) has no payment row → NoOp.
//!
//! Resilience + correctness:
//!  - A durable pull consumer filtered to the two cancellation terminals (JetStream at-least-once).
//!  - The refund is **idempotent via the `processed_events` ledger** (the event_id is claimed in the
//!    same tx): a redelivery is a NoOp, so a refund is never applied twice.
//!  - HMAC-verified BEFORE any refund (a forged cancellation would issue money) — fail-closed.
//!  - A message is acked only after a successful refund; a failure leaves it for redelivery.

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
/// Intent-scoped durable name (this consumer only ever refunds cancellations/declines).
const DURABLE: &str = "payment-booking-cancelled";
/// Backoff between reconnect attempts when NATS is down or the stream ends.
const RECONNECT_INTERVAL: Duration = Duration::from_secs(2);

/// The minimal payload the refund needs — just the `booking_id` to look the pre-pay up by. Both
/// `booking.declined` and `booking.cancelled` carry `customer_id` (+ `guard_id` once assigned);
/// they are parsed for contract validation but the refund reads the payment row off `booking_id`.
#[derive(Debug, Deserialize)]
#[allow(dead_code)] // customer_id/guard_id validate the contract; the refund keys off booking_id.
struct CancelPayload {
    booking_id: Uuid,
    customer_id: Uuid,
    #[serde(default)]
    guard_id: Option<Uuid>,
}

/// Run the cancellation-refund consumer FOREVER: (re)connect to NATS, drain, and on any
/// connect/stream error log + back off + reconnect. Never returns under normal operation — a
/// transient NATS outage must not silently kill the refund half of the money path. Spawned as a
/// background task by `main`.
pub async fn run_consumer(db: sqlx::PgPool, nats_url: &str) {
    loop {
        match connect_and_consume(&db, nats_url).await {
            Ok(()) => tracing::warn!("cancellation-refund consumer stream ended; reconnecting"),
            Err(e) => tracing::warn!("cancellation-refund consumer error: {e}; reconnecting"),
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
                // Only the two cancellation terminals reach the refund path.
                filter_subjects: vec![
                    topics::BOOKING_DECLINED.to_string(),
                    topics::BOOKING_CANCELLED.to_string(),
                ],
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
        "payment cancellation-refund consumer started"
    );

    while let Some(item) = messages.next().await {
        let message = match item {
            Ok(m) => m,
            Err(e) => {
                tracing::warn!("NATS message error: {e}");
                continue;
            }
        };

        if let Ok(info) = message.info() {
            observability::record_consumer_lag(DURABLE, info.pending);
        }

        // Verify the HMAC signature BEFORE refunding — a forged cancellation (which would issue a
        // refund) is dropped, counted, and never applied. Fail-closed.
        if !shared_events::verify_message(message.headers.as_ref(), message.payload.as_ref()) {
            observability::record_rejected_event(DURABLE);
            tracing::warn!("dropping cancellation event with missing/invalid signature (forged?)");
            let _ = message.ack().await;
            continue;
        }

        // A malformed envelope is POISON — it can never become valid, so ACK (drop) rather than
        // let it redeliver forever and wedge the consumer.
        let envelope: EventEnvelope<CancelPayload> =
            match serde_json::from_slice(message.payload.as_ref()) {
                Ok(e) => e,
                Err(e) => {
                    observability::record_rejected_event(DURABLE);
                    tracing::error!("dropping malformed cancellation envelope (poison): {e}");
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
                // Transient (e.g. DB) error → do NOT ack; JetStream redelivers and the event-id
                // claim absorbs the replay (no double refund).
                tracing::error!("cancellation refund failed (will redeliver): {e}");
            }
        }
    }

    Ok(())
}

/// Dispatch one parsed cancellation inside a span carrying the event identity + `correlation_id`
/// so booking→NATS→payment stitches into one trace. Returns `Err` only on transient failures.
async fn process(
    db: &sqlx::PgPool,
    envelope: EventEnvelope<CancelPayload>,
) -> Result<(), AppError> {
    // Defensive: the filter restricts the subjects, but never refund off an unexpected type.
    if envelope.event_type != topics::BOOKING_DECLINED
        && envelope.event_type != topics::BOOKING_CANCELLED
    {
        tracing::warn!(event_type = %envelope.event_type, "ignoring unexpected event type");
        return Ok(());
    }

    let span = tracing::info_span!(
        "payment.refund_on_cancellation",
        event_type = %envelope.event_type,
        event_id = %envelope.event_id,
        correlation_id = %envelope.correlation_id,
    );
    if let Some(tp) = envelope.traceparent.as_deref() {
        observability::set_parent_from_traceparent(&span, tp);
    }
    refund(db, envelope).instrument(span).await
}

/// FULL-REFUND the pre-pay for a cancelled/declined booking (idempotent), logging the outcome.
async fn refund(db: &sqlx::PgPool, envelope: EventEnvelope<CancelPayload>) -> Result<(), AppError> {
    let booking_id = envelope.payload.booking_id;
    let outcome = repo::refund_on_cancellation(
        db,
        envelope.event_id,
        &envelope.event_type,
        booking_id,
        envelope.correlation_id,
    )
    .await?;
    tracing::info!(booking_id = %booking_id, ?outcome, "processed cancellation refund");
    Ok(())
}
