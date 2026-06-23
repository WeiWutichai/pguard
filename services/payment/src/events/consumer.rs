//! Event CONSUMER — the money path's reactive half: subscribe to
//! `pguard.events.booking.completed` and RECONCILE the actual-hours bill against the PRE-PAID
//! amount when a job completes.
//!
//! v2 is PRE-PAY then SETTLE: the customer already paid the ESTIMATE up front (see the
//! `createPayment` endpoint), which gated the booking's en_route. On completion we recompute the
//! bill for the hours ACTUALLY worked (base prorated + flat tip) and diff it against the pre-paid
//! amount — refund the overpay (`payment.refund_processed`) or record the shortfall. The base is
//! NEVER double-charged. booking emits the completion event carrying its server-owned pricing;
//! payment reacts and settles — no cross-service write, no god-service.
//!
//! Resilience + correctness:
//!  - A durable pull consumer filtered to `booking.completed` (JetStream at-least-once).
//!  - The settle is **idempotent via the `processed_events` ledger** (`repo::reconcile_on_completion`
//!    claims the event_id in the same tx): a redelivery is a NoOp, so a refund is never applied twice.
//!  - A message is acked only after a successful settle; a failure leaves it for redelivery
//!    (safe — the event-id claim absorbs the replay).

use std::time::Duration;

use futures::StreamExt;
use rust_decimal::Decimal;
use serde::Deserialize;
use tracing::Instrument;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::{topics, EventEnvelope};

use crate::repo;

const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";
/// Intent-scoped durable name (this consumer only ever processes booking completions).
const DURABLE: &str = "payment-booking-completed";
/// Backoff between reconnect attempts when NATS is down or the stream ends.
const RECONNECT_INTERVAL: Duration = Duration::from_secs(2);

/// The `booking.completed` payload fields the RECONCILE settle needs (booking emits these; see
/// booking `domain::events::CompletionInfo`). `booked_hours` + the pricing inputs
/// (`base_fee`/`guard_count`/`tip`) are REQUIRED (AsyncAPI contract): a missing field fails the
/// parse → the message is treated as poison (dropped + logged), never silently settled at zero.
/// `actual_seconds` is genuinely optional: `None` when the guard never started (defensive — a
/// completion requires a start; the full booked base is the settle target). Money fields
/// deserialize from a JSON string (rust_decimal serde-str, workspace-wide).
///
/// `customer_id`/`guard_id` are parsed (contract validation + future use) but the SETTLE reads
/// the customer/guard off the PRE-PAID payment row, not the event — the reconcile diffs against
/// what was actually paid, so the event only supplies the pricing inputs to recompute the bill.
///
/// A local type (not the codegen'd `shared_events::BookingCompleted`, which models money as
/// `String`) — deliberately, so the bill math gets `Decimal` directly. This matches the project
/// convention that services build/parse payloads inline today; the contract is drift-locked by
/// the generated type + `shared-events` tests.
#[derive(Debug, Deserialize)]
#[allow(dead_code)] // customer_id/guard_id validate the contract; the settle reads them off the row.
struct CompletedPayload {
    booking_id: Uuid,
    customer_id: Uuid,
    #[serde(default)]
    guard_id: Option<Uuid>,
    booked_hours: i32,
    #[serde(default)]
    actual_seconds: Option<i64>,
    base_fee: Decimal,
    guard_count: i32,
    tip: Decimal,
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

        // Verify the HMAC signature BEFORE charging — a forged `booking.completed` (which would
        // bill a customer) is dropped, counted, and never applied. Fail-closed.
        if !shared_events::verify_message(message.headers.as_ref(), message.payload.as_ref()) {
            observability::record_rejected_event(DURABLE);
            tracing::warn!(
                "dropping booking.completed event with missing/invalid signature (forged?)"
            );
            let _ = message.ack().await;
            continue;
        }

        // Parse first. A malformed envelope is POISON — it can never become valid, so ACK it
        // (drop) instead of letting it redeliver forever and wedge the consumer. NB: an old-shape
        // completion from a pre-deploy booking (missing the required pricing fields) lands here —
        // it is dropped, never billed; count it so a deploy-window gap is observable (an operator
        // reconciles via the booking). See the deploy-ordering note in PROGRESS.
        let envelope: EventEnvelope<CompletedPayload> =
            match serde_json::from_slice(message.payload.as_ref()) {
                Ok(e) => e,
                Err(e) => {
                    observability::record_rejected_event(DURABLE);
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
                // one-completed-per-booking index makes the reprocess safe (no double charge).
                tracing::error!("booking.completed charge failed (will redeliver): {e}");
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

/// RECONCILE the actual-hours bill against the PRE-PAID amount for a completed booking, logging
/// the outcome. Runs inside the event span. The settle target is the base prorated to the hours
/// actually worked + the flat tip, diffed against what the customer pre-paid
/// ([`repo::reconcile_on_completion`] → [`crate::domain::reconcile`]) — computed entirely from
/// the booking's server-owned pricing carried on the event (never a client). The base is never
/// double-charged: an overpay is REFUNDED (emits `payment.refund_processed`) and an under-payment
/// records the shortfall. Idempotent via the `processed_events` event-id claim: a redelivery is a
/// NoOp (no second refund).
async fn finalize(
    db: &sqlx::PgPool,
    envelope: EventEnvelope<CompletedPayload>,
) -> Result<(), AppError> {
    let p = &envelope.payload;
    let outcome = repo::reconcile_on_completion(
        db,
        envelope.event_id,
        &envelope.event_type,
        p.booking_id,
        p.base_fee,
        p.booked_hours,
        p.guard_count,
        p.tip,
        p.actual_seconds,
        envelope.correlation_id,
    )
    .await?;
    tracing::info!(booking_id = %p.booking_id, ?outcome, "reconciled pre-pay on booking completion");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// The envelope/payload parse the consumer relies on: a well-formed booking.completed event
    /// yields the booking_id + duration + the pricing inputs. Money fields are JSON STRINGS
    /// (rust_decimal serde-str). Pure (no DB/NATS).
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
                "actual_seconds": 7200,
                "base_fee": "500.00",
                "guard_count": 2,
                "tip": "100.00"
            }
        });
        let env: EventEnvelope<CompletedPayload> = serde_json::from_value(raw).expect("parse");
        assert_eq!(env.event_type, topics::BOOKING_COMPLETED);
        assert_eq!(env.payload.booking_id, booking_id);
        assert_eq!(env.payload.booked_hours, 4);
        assert_eq!(env.payload.actual_seconds, Some(7200));
        assert_eq!(env.payload.base_fee, "500.00".parse::<Decimal>().unwrap());
        assert_eq!(env.payload.guard_count, 2);
        assert_eq!(env.payload.tip, "100.00".parse::<Decimal>().unwrap());
    }

    /// A completion without a work-start carries null actual_seconds → `None` (the full booked
    /// base is billed).
    #[test]
    fn parses_completed_envelope_with_null_actual_seconds() {
        let raw = json!({
            "event_id": Uuid::new_v4(),
            "event_type": topics::BOOKING_COMPLETED,
            "occurred_at": "2026-06-05T10:00:00Z",
            "correlation_id": Uuid::new_v4(),
            "payload": {
                "booking_id": Uuid::new_v4(),
                "customer_id": Uuid::new_v4(),
                "booked_hours": 3,
                "actual_seconds": null,
                "base_fee": "300.00",
                "guard_count": 1,
                "tip": "0"
            }
        });
        let env: EventEnvelope<CompletedPayload> = serde_json::from_value(raw).expect("parse");
        assert_eq!(env.payload.actual_seconds, None);
        assert_eq!(env.payload.booked_hours, 3);
        assert_eq!(env.payload.guard_count, 1);
    }
}

/// END-TO-END smoke against REAL infra (Postgres + NATS JetStream): the PRE-PAY → SETTLE money
/// path's full vertical — PRE-PAY the estimate (500×4×1 = 2000.00) up front, then publish a
/// SIGNED `booking.completed` (booked 4h, worked 2h, base 500, 1 guard, no tip → actual 1000.00)
/// to NATS → the payment consumer drains it → RECONCILES: refunds the 1000.00 overpay (the base
/// is NOT re-charged) → emits `payment.refund_processed` to the outbox — AND a replay of the same
/// event is idempotent (no second refund, one event). The payment-events → notification leg is
/// proven separately by the notification slice's e2e.
///
/// Gated on BOTH `DATABASE_URL` (a migrated DB: payment 0001/0002) and `NATS_URL`; hermetic
/// (SKIP) when either is absent, so `cargo test` stays offline-safe. Run:
///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
///   NATS_URL=nats://localhost:4222 \
///     cargo test -p pguard-payment -- e2e_reconcile --nocapture
#[cfg(test)]
mod e2e_tests {
    use super::*;
    use rust_decimal::Decimal;
    use serde_json::json;
    use shared_events::EventEnvelope;
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;

    fn dec(s: &str) -> Decimal {
        s.parse().unwrap()
    }

    #[tokio::test]
    async fn e2e_reconcile_refunds_overpay_on_completion_and_is_idempotent() {
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
        let event_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        // 0) PRE-PAY the estimate up front (500×4×1 + 0 = 2000.00) — the settle basis.
        let _ = crate::repo::prepay_idempotent(
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
        .expect("pre-pay");

        // 1) ensure the stream, then start the consumer.
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
        // — the consumer verifies HMAC signatures, and we publish SIGNED with this same key.
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

        // 2) publish booking.completed with a FIXED event_id (so the replay dedupes): 500/hr × 4h
        //    × 1, worked 2h (7200s), no tip → actual 1000.00, refund 1000.00 of the 2000.00 paid.
        //    Money fields are JSON STRINGS (rust_decimal serde-str, matching booking's emission).
        let mut envelope = EventEnvelope::new(
            topics::BOOKING_COMPLETED,
            correlation,
            json!({
                "booking_id": booking_id,
                "customer_id": customer_id,
                "guard_id": guard_id,
                "booked_hours": 4,
                "actual_seconds": 7200,
                "base_fee": "500.00",
                "guard_count": 1,
                "tip": "0",
            }),
        );
        envelope.event_id = event_id;
        let bytes = serde_json::to_vec(&envelope).expect("serialize envelope");
        shared_events::publish_signed(&js, topics::BOOKING_COMPLETED, &bytes)
            .await
            .expect("signed publish");

        // 3) poll until the consumer records the refund (bounded; ~10s).
        let mut settled: Option<(Decimal, Option<Decimal>, Option<Decimal>)> = None;
        for _ in 0..50 {
            let row: Option<(Decimal, Option<Decimal>, Option<Decimal>)> = sqlx::query_as(
                "SELECT amount, final_amount, refund_amount FROM payment.payments WHERE booking_id = $1",
            )
            .bind(booking_id)
            .fetch_optional(&pool)
            .await
            .expect("read payment");
            if let Some(r) = row {
                if r.2.is_some() {
                    settled = Some(r);
                    break;
                }
            }
            tokio::time::sleep(Duration::from_millis(200)).await;
        }
        let (amount, final_amount, refund_amount) =
            settled.expect("reconcile refund recorded via NATS within timeout");
        assert_eq!(
            amount,
            dec("2000.00"),
            "pre-paid base unchanged (never re-charged)"
        );
        assert_eq!(final_amount, Some(dec("1000.00")), "final = 2h of 4h × 500");
        assert_eq!(refund_amount, Some(dec("1000.00")), "overpay refunded");

        // 4) replay the SAME event → idempotent: still ONE refund_processed event.
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
            "exactly one payment.refund_processed despite the replay (idempotent)"
        );

        // teardown
        consumer.abort();
        let _ = sqlx::query("DELETE FROM payment.processed_events WHERE event_id = $1")
            .bind(event_id)
            .execute(&pool)
            .await;
        let _ =
            sqlx::query("DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(booking_id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = $1")
            .bind(booking_id)
            .execute(&pool)
            .await;
    }
}
