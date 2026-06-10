//! Event CONSUMER — the money path's reactive half: subscribe to
//! `pguard.events.booking.completed` and finalize proration when a job completes.
//!
//! This replaces v1's `review_completion()` doing proration inline inside booking's
//! completion handler (`../guard-dispatch/services/booking/src/service.rs`, migrations
//! 036/042). In v2 booking emits a completion event and payment reacts — no cross-service
//! write, no god-service.
//!
//! Resilience + correctness:
//!  - A durable pull consumer filtered to `booking.completed` (JetStream at-least-once).
//!  - Each event is finalized **idempotently by `event_id`** (`repo::finalize_on_booking_
//!    completed` claims the id + applies proration + enqueues any refund in ONE tx), so a
//!    redelivery never double-refunds.
//!  - A message is acked only after a successful finalize; a failure leaves it for redelivery
//!    (safe — the idempotency ledger absorbs the replay).

use std::time::Duration;

use futures::StreamExt;
use serde::Deserialize;
use tracing::Instrument;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::{topics, EventEnvelope};

use crate::repo::{self, Finalized};

const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";
/// Intent-scoped durable name (this consumer only ever processes booking completions).
const DURABLE: &str = "payment-booking-completed";
/// Backoff between reconnect attempts when NATS is down or the stream ends.
const RECONNECT_INTERVAL: Duration = Duration::from_secs(2);

/// The `booking.completed` payload fields the proration needs (booking emits these; see
/// booking `domain::events::CompletionInfo`). `booked_hours` is REQUIRED (AsyncAPI contract);
/// a missing field fails the parse → the message is treated as poison (dropped + logged),
/// never silently defaulted to a full charge. `actual_seconds` is genuinely optional: `None`
/// when the guard never started (no factual basis to prorate → the full charge stands).
#[derive(Debug, Deserialize)]
struct CompletedPayload {
    booking_id: Uuid,
    booked_hours: i32,
    #[serde(default)]
    actual_seconds: Option<i64>,
}

/// Run the booking.completed consumer FOREVER: (re)connect to NATS, drain, and on any
/// connect/stream error log + back off + reconnect. Never returns under normal operation —
/// a transient NATS outage must not silently kill the reactive half of the money path
/// (mirrors `run_relay`'s resilience). Spawned as a background task by `main`.
pub async fn run_consumer(db: sqlx::PgPool, nats_url: &str) {
    loop {
        match connect_and_consume(&db, nats_url).await {
            // The message stream ended (NATS dropped the connection) — reconnect.
            Ok(()) => tracing::warn!("booking.completed consumer stream ended; reconnecting"),
            Err(e) => tracing::warn!("booking.completed consumer error: {e}; reconnecting"),
        }
        tokio::time::sleep(RECONNECT_INTERVAL).await;
    }
}

/// One connect+consume session: bind the durable consumer and drain until the stream ends
/// or a fatal error. Returns to [`run_consumer`], which reconnects.
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
                // Only booking completions reach the money path.
                filter_subject: topics::BOOKING_COMPLETED.to_string(),
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
        subject = topics::BOOKING_COMPLETED,
        "payment booking.completed consumer started"
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

        // Verify the HMAC signature BEFORE dedupe/finalize — a forged `booking.completed` (which
        // would drive proration/refunds) is dropped, counted, and never applied. Fail-closed.
        if !shared_events::verify_message(message.headers.as_ref(), message.payload.as_ref()) {
            observability::record_rejected_event(DURABLE);
            tracing::warn!(
                "dropping booking.completed event with missing/invalid signature (forged?)"
            );
            let _ = message.ack().await;
            continue;
        }

        // Parse first. A malformed envelope is POISON — it can never become valid, so ACK it
        // (drop) instead of letting it redeliver forever and wedge the consumer.
        let envelope: EventEnvelope<CompletedPayload> =
            match serde_json::from_slice(message.payload.as_ref()) {
                Ok(e) => e,
                Err(e) => {
                    tracing::error!("dropping malformed booking.completed envelope (poison): {e}");
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
                // idempotency ledger makes the reprocess safe (no double refund).
                tracing::error!("booking.completed finalize failed (will redeliver): {e}");
            }
        }
    }

    Ok(())
}

/// Finalize one parsed completion inside a span carrying the event identity +
/// `correlation_id` so the booking→NATS→payment trace stitches together. Returns `Err` only
/// on transient (retryable) failures.
async fn process(
    db: &sqlx::PgPool,
    envelope: EventEnvelope<CompletedPayload>,
) -> Result<(), AppError> {
    // Defensive: the filter restricts the subject, but never finalize off an unexpected type.
    if envelope.event_type != topics::BOOKING_COMPLETED {
        tracing::warn!(event_type = %envelope.event_type, "ignoring unexpected event type");
        return Ok(());
    }

    let span = tracing::info_span!(
        "payment.finalize_on_completion",
        event_type = %envelope.event_type,
        event_id = %envelope.event_id,
        correlation_id = %envelope.correlation_id,
    );
    // Reparent on the producer's trace (carried in the envelope) so booking→NATS→payment
    // is one distributed trace in Tempo (C5.1).
    if let Some(tp) = envelope.traceparent.as_deref() {
        observability::set_parent_from_traceparent(&span, tp);
    }
    finalize(db, envelope).instrument(span).await
}

/// Drive the idempotent finalize, logging the outcome. Runs inside the event span.
async fn finalize(
    db: &sqlx::PgPool,
    envelope: EventEnvelope<CompletedPayload>,
) -> Result<(), AppError> {
    let p = &envelope.payload;
    let outcome = repo::finalize_on_booking_completed(
        db,
        envelope.event_id,
        &envelope.event_type,
        p.booking_id,
        p.booked_hours,
        p.actual_seconds,
        envelope.correlation_id,
    )
    .await?;

    match outcome {
        Finalized::Applied { refunded } => {
            tracing::info!(refunded, "payment finalized on booking completion")
        }
        Finalized::NoPayment => tracing::debug!("no payment for booking; nothing to finalize"),
        Finalized::Duplicate => tracing::debug!("duplicate completion event; skipped"),
        Finalized::AlreadyDone => tracing::debug!("payment already finalized; skipped"),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// The envelope/payload parse the consumer relies on: a well-formed booking.completed
    /// event yields the booking_id + proration inputs. Pure (no DB/NATS).
    #[test]
    fn parses_completed_envelope() {
        let booking_id = Uuid::new_v4();
        let raw = json!({
            "event_id": Uuid::new_v4(),
            "event_type": topics::BOOKING_COMPLETED,
            "occurred_at": "2026-06-05T10:00:00Z",
            "correlation_id": Uuid::new_v4(),
            "payload": {
                "booking_id": booking_id,
                "customer_id": Uuid::new_v4(),
                "guard_id": Uuid::new_v4(),
                "booked_hours": 4,
                "actual_seconds": 7200
            }
        });
        let env: EventEnvelope<CompletedPayload> = serde_json::from_value(raw).expect("parse");
        assert_eq!(env.event_type, topics::BOOKING_COMPLETED);
        assert_eq!(env.payload.booking_id, booking_id);
        assert_eq!(env.payload.booked_hours, 4);
        assert_eq!(env.payload.actual_seconds, Some(7200));
    }

    /// A completion without a work-start carries null actual_seconds → `None` (full charge).
    #[test]
    fn parses_completed_envelope_with_null_actual_seconds() {
        let raw = json!({
            "event_id": Uuid::new_v4(),
            "event_type": topics::BOOKING_COMPLETED,
            "occurred_at": "2026-06-05T10:00:00Z",
            "correlation_id": Uuid::new_v4(),
            "payload": {
                "booking_id": Uuid::new_v4(),
                "booked_hours": 3,
                "actual_seconds": null
            }
        });
        let env: EventEnvelope<CompletedPayload> = serde_json::from_value(raw).expect("parse");
        assert_eq!(env.payload.actual_seconds, None);
        assert_eq!(env.payload.booked_hours, 3);
    }
}

/// END-TO-END smoke against REAL infra (Postgres + NATS JetStream): the money path's full
/// vertical — booking (accepted) → pay → publish `booking.completed` to NATS → the payment
/// consumer drains it → proration finalized → `payment.refund_processed` emitted to the
/// outbox — AND a replay of the same event is idempotent (no double refund). The
/// payment-events → notification leg is proven separately by the notification slice's e2e.
///
/// Gated on BOTH `DATABASE_URL` (a migrated DB: booking 0001/0002 + payment 0001/0002) and
/// `NATS_URL`; hermetic (SKIP) when either is absent, so `cargo test` stays offline-safe. Run:
///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
///   NATS_URL=nats://localhost:4222 \
///     cargo test -p pguard-payment -- e2e_book_pay_complete --nocapture
#[cfg(test)]
mod e2e_tests {
    use super::*;
    use crate::repo;
    use rust_decimal::Decimal;
    use serde_json::json;
    use shared_events::EventEnvelope;
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;

    fn dec(s: &str) -> Decimal {
        s.parse().unwrap()
    }

    #[tokio::test]
    async fn e2e_book_pay_complete_finalizes_and_is_idempotent() {
        let (Ok(db_url), Ok(nats_url)) = (std::env::var("DATABASE_URL"), std::env::var("NATS_URL"))
        else {
            eprintln!(
                "SKIP: DATABASE_URL + NATS_URL required for the e2e smoke (hermetic default)"
            );
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&db_url)
            .await
            .expect("connect real Postgres");

        let booking_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        // 1) booking fixture in `accepted` (payable). 500 ฿/hr × 4h × 1 + 0 = 2000 expected.
        sqlx::query(
            "INSERT INTO booking.bookings \
               (id, customer_id, guard_id, status, address, scheduled_at, hours, base_fee, guard_count, tip) \
             VALUES ($1, $2, $3, 'accepted'::booking.booking_status, '1 E2E Rd', now(), 4, 500.00, 1, 0)",
        )
        .bind(booking_id)
        .bind(customer_id)
        .bind(guard_id)
        .execute(&pool)
        .await
        .expect("insert booking fixture");

        // 2) pay the full expected total (2000.00).
        repo::charge_idempotent(
            &pool,
            booking_id,
            customer_id,
            Some(guard_id),
            dec("2000.00"),
            dec("2000.00"),
            "promptpay",
            correlation,
        )
        .await
        .expect("charge");

        // 3) ensure the stream, then start the consumer.
        let client = shared_events::connect(&nats_url)
            .await
            .expect("nats connect");
        let js = async_nats::jetstream::new(client);
        js.get_or_create_stream(async_nats::jetstream::stream::Config {
            name: STREAM.to_string(),
            subjects: vec![SUBJECTS.to_string()],
            ..Default::default()
        })
        .await
        .expect("ensure stream");

        // Set the process signing key BEFORE spawning the consumer (whose verify path reads it)
        // — the consumer now verifies HMAC signatures, and we publish SIGNED with this same key.
        shared_events::init_signing_key(
            b"payment-e2e-event-signing-secret-at-least-64-characters-long-okok!",
        );

        let consumer_pool = pool.clone();
        let consumer_nats = nats_url.clone();
        let consumer = tokio::spawn(async move {
            run_consumer(consumer_pool, &consumer_nats).await;
        });
        // Let the durable consumer bind before publishing.
        tokio::time::sleep(Duration::from_millis(500)).await;

        // 4) publish booking.completed: booked 4h, worked 2h (7200s) → final 1000, refund 1000.
        let envelope = EventEnvelope::new(
            topics::BOOKING_COMPLETED,
            correlation,
            json!({
                "booking_id": booking_id,
                "customer_id": customer_id,
                "guard_id": guard_id,
                "booked_hours": 4,
                "actual_seconds": 7200,
            }),
        );
        let bytes = serde_json::to_vec(&envelope).expect("serialize envelope");
        shared_events::publish_signed(&js, topics::BOOKING_COMPLETED, &bytes)
            .await
            .expect("signed publish");

        // 5) poll until the consumer finalizes (bounded; ~10s).
        let mut finalized = None;
        for _ in 0..50 {
            let p = repo::get_payment_for_booking_amount(&pool, booking_id)
                .await
                .expect("read payment");
            if p.final_amount.is_some() {
                finalized = Some(p);
                break;
            }
            tokio::time::sleep(Duration::from_millis(200)).await;
        }
        let p = finalized.expect("payment finalized via NATS within timeout");
        assert_eq!(
            p.final_amount,
            Some(dec("1000.00")),
            "2h of 4h → final 1000"
        );
        assert_eq!(p.refund_amount, Some(dec("1000.00")), "refund 1000");
        assert_eq!(p.refund_status.as_deref(), Some("pending"));

        // 6) replay the SAME event (same event_id) → idempotent, no double refund.
        shared_events::publish_signed(&js, topics::BOOKING_COMPLETED, &bytes)
            .await
            .expect("signed replay");
        tokio::time::sleep(Duration::from_millis(1500)).await;

        let refund_events: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::PAYMENT_REFUND_PROCESSED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count refund events");
        assert_eq!(
            refund_events, 1,
            "exactly one refund event despite the replay (idempotent)"
        );

        // teardown
        consumer.abort();
        let _ =
            sqlx::query("DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(booking_id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM payment.processed_events WHERE event_id = $1")
            .bind(envelope.event_id)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = $1")
            .bind(booking_id)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(booking_id)
            .execute(&pool)
            .await;
    }
}
