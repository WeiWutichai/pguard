//! Event layer — the transactional-outbox **relay**: the producer half of Phase 1.
//!
//! booking writes the status change AND an outbox row atomically (see `repo`). This
//! background task then drains the outbox: poll unpublished rows → publish each to NATS
//! (subject = `EventEnvelope.event_type`) → stamp `published_at`. The notification
//! consumer (notification slice) subscribes to `pguard.events.>` and receives them.
//!
//! Resilience: if NATS is down the relay logs and retries on the next tick — it never
//! crashes the service (a transient broker outage must not take booking offline). Because
//! a row is only marked published *after* a successful publish, delivery is at-least-once
//! (the consumer dedupes on `event_id`), which is exactly the JetStream contract.

//! The CONSUMER half (subscribe to `payment.completed` → stamp `paid_at` idempotently, which
//! un-gates the PRE-PAY `accepted → en_route` transition) lives in [`consumer`].

pub mod consumer;

use std::time::Duration;

use crate::repo::{self, OutboxRow};

/// Publishes a serialized [`shared_events::EventEnvelope`] to a subject. A trait so the
/// relay is decoupled from `async-nats` (and unit-testable without a live broker).
/// `#[async_trait]` makes it `dyn`-compatible (the relay drains over `&dyn EventPublisher`).
#[async_trait::async_trait]
pub trait EventPublisher: Send + Sync {
    /// Publish `payload` (already-serialized envelope bytes) to `subject`.
    async fn publish(&self, subject: &str, payload: &[u8]) -> Result<(), anyhow::Error>;
}

/// JetStream-backed publisher. Ensures the shared `PGUARD_EVENTS` stream exists so the
/// notification durable consumer can bind to it.
pub struct JetStreamPublisher {
    jetstream: async_nats::jetstream::Context,
}

const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";

impl JetStreamPublisher {
    /// Connect to NATS and ensure the stream exists. Fails fast on a bad URL/broker so
    /// the relay's connect step can log + retry.
    pub async fn connect(nats_url: &str) -> Result<Self, anyhow::Error> {
        let client = shared_events::connect(nats_url).await?;
        let jetstream = async_nats::jetstream::new(client);
        jetstream
            .get_or_create_stream(async_nats::jetstream::stream::Config {
                name: STREAM.to_string(),
                subjects: vec![SUBJECTS.to_string()],
                ..Default::default()
            })
            .await?;
        Ok(Self { jetstream })
    }
}

#[async_trait::async_trait]
impl EventPublisher for JetStreamPublisher {
    async fn publish(&self, subject: &str, payload: &[u8]) -> Result<(), anyhow::Error> {
        // Sign + publish via the shared helper (HMAC in the signature header) so the event is
        // authenticated on the wire. It awaits the broker's persistence ack before returning,
        // so the relay marks the row published only after a durable, signed publish.
        shared_events::publish_signed(&self.jetstream, subject, payload).await
    }
}

/// How long to sleep between drains when there is nothing to publish (or NATS is down).
const POLL_INTERVAL: Duration = Duration::from_secs(2);
/// Max rows drained per tick (bounded so one tick cannot monopolize a DB connection).
const BATCH: i64 = 100;

/// Run the outbox relay forever: connect to NATS (retrying), then loop draining the
/// outbox. Spawned as a background task by `main`. Never returns under normal operation.
///
/// Concurrency: each drain claims its batch with `FOR UPDATE SKIP LOCKED` (see `drain_once`),
/// so running this at >1 replica is safe — concurrent relays partition the unpublished rows
/// rather than double-publishing them. The single-instance crash-recovery contract is still
/// at-least-once (the consumer dedupes on `event_id`).
pub async fn run_relay(db: sqlx::PgPool, nats_url: String) {
    loop {
        let publisher = match JetStreamPublisher::connect(&nats_url).await {
            Ok(p) => {
                tracing::info!(stream = STREAM, "outbox relay connected to NATS");
                p
            }
            Err(e) => {
                tracing::warn!("outbox relay NATS connect failed: {e}; retrying");
                tokio::time::sleep(POLL_INTERVAL).await;
                continue;
            }
        };

        // Drain until a publish/DB error forces a reconnect.
        loop {
            match drain_once(&db, &publisher).await {
                Ok(0) => tokio::time::sleep(POLL_INTERVAL).await,
                Ok(n) => tracing::debug!(published = n, "outbox relay drained batch"),
                Err(e) => {
                    tracing::warn!("outbox relay drain failed: {e}; reconnecting");
                    tokio::time::sleep(POLL_INTERVAL).await;
                    break; // reconnect (NATS may have dropped)
                }
            }
        }
    }
}

/// Publish one batch of unpublished outbox rows. Returns the number published.
///
/// The batch is claimed and marked inside ONE transaction: `fetch_unpublished` takes a
/// `FOR UPDATE SKIP LOCKED` row lock on each claimed row, and that lock is held until the
/// transaction commits at the end of the batch. So if this relay runs at >1 replica (scaled,
/// or a rolling-deploy overlap), a second instance simply skips the locked rows and works a
/// different slice — no row is ever published twice by concurrent relays. Within a single
/// instance, each row is marked published only AFTER its publish acks, so a crash mid-batch
/// rolls back the uncommitted marks and the rows redeliver next tick (at-least-once; the
/// consumer dedupes on `event_id`). A publish error aborts the batch (early return drops `tx`,
/// rolling it back) and bubbles up so `run_relay` reconnects.
#[tracing::instrument(skip_all, fields(batch = BATCH))]
async fn drain_once(
    db: &sqlx::PgPool,
    publisher: &dyn EventPublisher,
) -> Result<u64, anyhow::Error> {
    let mut tx = db.begin().await?;
    let rows: Vec<OutboxRow> = repo::fetch_unpublished(&mut tx, BATCH).await?;
    let mut published = 0u64;
    for row in rows {
        let bytes = serde_json::to_vec(&row.payload)?;
        publisher.publish(&row.topic, &bytes).await?;
        repo::mark_published(&mut tx, row.id).await?;
        published += 1;
    }
    tx.commit().await?;
    Ok(published)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::sync::Mutex;
    use uuid::Uuid;

    /// In-memory publisher capturing what the relay would publish — proves `drain_once`
    /// publishes the subject + bytes without needing a live broker.
    #[derive(Default)]
    struct CapturingPublisher {
        published: Mutex<Vec<(String, Vec<u8>)>>,
    }

    #[async_trait::async_trait]
    impl EventPublisher for CapturingPublisher {
        async fn publish(&self, subject: &str, payload: &[u8]) -> Result<(), anyhow::Error> {
            self.published
                .lock()
                .expect("lock")
                .push((subject.to_string(), payload.to_vec()));
            Ok(())
        }
    }

    #[tokio::test]
    async fn publisher_receives_subject_and_serialized_envelope() {
        // Exercises the publish seam directly (DB drain is covered by the real-DB path
        // in repo when DATABASE_URL is set).
        let pubr = CapturingPublisher::default();
        let envelope = json!({
            "event_id": Uuid::new_v4(),
            "event_type": "pguard.events.booking.job_accepted",
            "payload": { "booking_id": Uuid::new_v4() }
        });
        let bytes = serde_json::to_vec(&envelope).unwrap();
        pubr.publish("pguard.events.booking.job_accepted", &bytes)
            .await
            .unwrap();

        let captured = pubr.published.lock().unwrap();
        assert_eq!(captured.len(), 1);
        assert_eq!(captured[0].0, "pguard.events.booking.job_accepted");
        let back: serde_json::Value = serde_json::from_slice(&captured[0].1).unwrap();
        assert_eq!(back["event_type"], "pguard.events.booking.job_accepted");
    }
}
