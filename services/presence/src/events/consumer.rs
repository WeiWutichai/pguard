//! Event CONSUMER — projects `pguard.events.booking.*` into the `guard_assignments` IDOR
//! read-model so presence can answer "does customer X have an active booking with guard Y?"
//! WITHOUT a cross-service FK or a synchronous cross-schema read (CLAUDE.md Data rules; the v1
//! `has_active_booking` query joined `booking.assignments` directly — forbidden in v2).
//!
//! Resilience + correctness:
//!  - A durable pull consumer filtered to `pguard.events.booking.>` (JetStream at-least-once),
//!    durable name `presence-booking-links` (distinct from notification/payment consumers).
//!  - `job_accepted` → link active; `declined`/`cancelled`/`completed` → link inactive. The
//!    projection is idempotent + last-writer-wins by the envelope's `occurred_at`
//!    (`repo::upsert_assignment`), so a redelivery/reorder never reactivates a finished booking.
//!  - A malformed envelope is POISON → acked (dropped). A transient (DB) error is NOT acked →
//!    JetStream redelivers; the idempotent projection makes the replay safe.

use std::time::Duration;

use futures::StreamExt;
use serde::Deserialize;
use tracing::Instrument;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::{topics, EventEnvelope};

const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";
/// Only booking events feed the read-model (en_route/arrived are ignored — see [`active_for`]).
const FILTER: &str = "pguard.events.booking.>";
const DURABLE: &str = "presence-booking-links";
/// Backoff between reconnect attempts when NATS is down or the stream ends.
const RECONNECT_INTERVAL: Duration = Duration::from_secs(2);

/// The booking-event fields the projection needs. `customer_id`/`guard_id` are optional: a
/// terminal event may omit them — the read-model already has them from the accept (COALESCE in
/// `repo::upsert_assignment` keeps the known ids).
#[derive(Debug, Deserialize)]
struct BookingPayload {
    booking_id: Uuid,
    #[serde(default)]
    customer_id: Option<Uuid>,
    #[serde(default)]
    guard_id: Option<Uuid>,
}

/// The read-model effect of a booking event: `Some(true)` = link active (a guard was assigned),
/// `Some(false)` = link inactive (booking ended), `None` = irrelevant to authz (en_route /
/// arrived / a non-booking subject that slipped past the filter — projected as a no-op). Pure.
fn active_for(event_type: &str) -> Option<bool> {
    match event_type {
        topics::BOOKING_JOB_ACCEPTED => Some(true),
        topics::BOOKING_DECLINED | topics::BOOKING_CANCELLED | topics::BOOKING_COMPLETED => {
            Some(false)
        }
        _ => None,
    }
}

/// Run the booking-links consumer FOREVER: (re)connect to NATS, drain, and on any
/// connect/stream error log + back off + reconnect. Never returns under normal operation — a
/// transient NATS outage must not silently kill the IDOR read-model's updates (mirrors
/// payment's consumer). Spawned as a background task by `main`.
pub async fn run_consumer(db: sqlx::PgPool, nats_url: &str) {
    loop {
        match connect_and_consume(&db, nats_url).await {
            Ok(()) => tracing::warn!("presence booking-links consumer stream ended; reconnecting"),
            Err(e) => tracing::warn!("presence booking-links consumer error: {e}; reconnecting"),
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
                filter_subject: FILTER.to_string(),
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
        filter = FILTER,
        "presence booking-links consumer started"
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

        // Verify the HMAC signature BEFORE dedupe/business — a forged booking event (which would
        // poison the presence assignment read-model) is dropped, counted, and never applied.
        if !shared_events::verify_message(message.headers.as_ref(), message.payload.as_ref()) {
            observability::record_rejected_event(DURABLE);
            tracing::warn!("dropping booking event with missing/invalid signature (forged?)");
            let _ = message.ack().await;
            continue;
        }

        // Parse first. A malformed envelope is POISON — ack (drop) so it can't wedge the
        // consumer by redelivering forever.
        let envelope: EventEnvelope<BookingPayload> =
            match serde_json::from_slice(message.payload.as_ref()) {
                Ok(e) => e,
                Err(e) => {
                    tracing::error!("dropping malformed booking envelope (poison): {e}");
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
                // idempotent projection makes the reprocess safe.
                tracing::error!("booking projection failed (will redeliver): {e}");
            }
        }
    }

    Ok(())
}

/// Project one parsed booking event onto the read-model, inside a span reparented on the
/// producer's trace (booking→NATS→presence is one trace in Tempo, C5.1).
async fn process(
    db: &sqlx::PgPool,
    envelope: EventEnvelope<BookingPayload>,
) -> Result<(), AppError> {
    let Some(active) = active_for(&envelope.event_type) else {
        // en_route/arrived (or a non-booking subject) — irrelevant to authz; ack as processed.
        return Ok(());
    };

    let span = tracing::info_span!(
        "presence.project_booking_event",
        event_type = %envelope.event_type,
        event_id = %envelope.event_id,
        correlation_id = %envelope.correlation_id,
    );
    if let Some(tp) = envelope.traceparent.as_deref() {
        observability::set_parent_from_traceparent(&span, tp);
    }
    project(db, envelope, active).instrument(span).await
}

async fn project(
    db: &sqlx::PgPool,
    envelope: EventEnvelope<BookingPayload>,
    active: bool,
) -> Result<(), AppError> {
    let p = &envelope.payload;
    crate::repo::upsert_assignment(
        db,
        p.booking_id,
        p.customer_id,
        p.guard_id,
        active,
        envelope.occurred_at,
    )
    .await?;
    tracing::debug!(booking_id = %p.booking_id, active, "booking link projected");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn active_mapping_is_correct() {
        assert_eq!(active_for(topics::BOOKING_JOB_ACCEPTED), Some(true));
        assert_eq!(active_for(topics::BOOKING_DECLINED), Some(false));
        assert_eq!(active_for(topics::BOOKING_CANCELLED), Some(false));
        assert_eq!(active_for(topics::BOOKING_COMPLETED), Some(false));
        // not relevant to authz → no projection
        assert_eq!(active_for(topics::BOOKING_GUARD_EN_ROUTE), None);
        assert_eq!(active_for(topics::BOOKING_ARRIVED), None);
        assert_eq!(active_for(topics::PAYMENT_COMPLETED), None);
    }

    #[test]
    fn parses_job_accepted_envelope() {
        let booking = Uuid::new_v4();
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let raw = json!({
            "event_id": Uuid::new_v4(),
            "event_type": topics::BOOKING_JOB_ACCEPTED,
            "occurred_at": "2026-06-05T10:00:00Z",
            "correlation_id": Uuid::new_v4(),
            "payload": { "booking_id": booking, "customer_id": customer, "guard_id": guard }
        });
        let env: EventEnvelope<BookingPayload> = serde_json::from_value(raw).expect("parse");
        assert_eq!(env.payload.booking_id, booking);
        assert_eq!(env.payload.customer_id, Some(customer));
        assert_eq!(env.payload.guard_id, Some(guard));
    }

    #[test]
    fn parses_terminal_envelope_without_ids() {
        let booking = Uuid::new_v4();
        let raw = json!({
            "event_id": Uuid::new_v4(),
            "event_type": topics::BOOKING_COMPLETED,
            "occurred_at": "2026-06-05T11:00:00Z",
            "correlation_id": Uuid::new_v4(),
            "payload": { "booking_id": booking, "booked_hours": 4 }
        });
        let env: EventEnvelope<BookingPayload> = serde_json::from_value(raw).expect("parse");
        assert_eq!(env.payload.booking_id, booking);
        assert_eq!(env.payload.customer_id, None);
        assert_eq!(env.payload.guard_id, None);
    }
}
