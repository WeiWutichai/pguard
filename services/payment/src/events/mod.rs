//! Event layer — the transactional-outbox **relay**: the producer half of the money path.
//!
//! payment writes the payment row AND an outbox row atomically (see `repo`). This
//! background task drains the outbox: poll unpublished rows → publish each to NATS
//! (subject = `EventEnvelope.event_type`) → stamp `published_at`. Consumers (notification,
//! and any future ledger) subscribe to `pguard.events.payment.*`.
//!
//! Resilience: if NATS is down the relay logs and retries on the next tick — it never
//! crashes the service. A row is marked published only AFTER a successful publish, so
//! delivery is at-least-once (consumers dedupe on `event_id`), per the JetStream contract.
//!
//! Mirrors booking's relay; uses a concrete [`JetStreamPublisher`] (no `dyn`) so the slice
//! needs no `async-trait`.
//!
//! The CONSUMER half (subscribe to `booking.completed` → finalize proration idempotently)
//! lives in [`consumer`].

pub mod consumer;

use std::time::Duration;

use crate::repo::{self, OutboxRow};

const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";
/// How long to sleep between drains when there is nothing to publish (or NATS is down).
const POLL_INTERVAL: Duration = Duration::from_secs(2);
/// Max rows drained per tick (bounded so one tick cannot monopolize a DB connection).
const BATCH: i64 = 100;

/// JetStream-backed publisher. Ensures the shared `PGUARD_EVENTS` stream exists.
pub struct JetStreamPublisher {
    jetstream: async_nats::jetstream::Context,
}

impl JetStreamPublisher {
    /// Connect to NATS and ensure the stream exists. Fails fast on a bad URL/broker so the
    /// relay's connect step can log + retry.
    pub async fn connect(nats_url: &str) -> Result<Self, anyhow::Error> {
        let client = async_nats::connect(nats_url).await?;
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

    /// Publish `payload` (serialized envelope bytes) to `subject`, awaiting the broker ack.
    async fn publish(&self, subject: &str, payload: Vec<u8>) -> Result<(), anyhow::Error> {
        let ack = self
            .jetstream
            .publish(subject.to_string(), payload.into())
            .await?;
        ack.await?;
        Ok(())
    }
}

/// Run the outbox relay forever: connect to NATS (retrying), then loop draining the outbox.
/// Spawned as a background task by `main`. Never returns under normal operation.
pub async fn run_relay(db: sqlx::PgPool, nats_url: String) {
    loop {
        let publisher = match JetStreamPublisher::connect(&nats_url).await {
            Ok(p) => {
                tracing::info!(stream = STREAM, "payment outbox relay connected to NATS");
                p
            }
            Err(e) => {
                tracing::warn!("payment outbox relay NATS connect failed: {e}; retrying");
                tokio::time::sleep(POLL_INTERVAL).await;
                continue;
            }
        };

        // Drain until a publish/DB error forces a reconnect.
        loop {
            match drain_once(&db, &publisher).await {
                Ok(0) => tokio::time::sleep(POLL_INTERVAL).await,
                Ok(n) => tracing::debug!(published = n, "payment outbox relay drained batch"),
                Err(e) => {
                    tracing::warn!("payment outbox relay drain failed: {e}; reconnecting");
                    tokio::time::sleep(POLL_INTERVAL).await;
                    break; // reconnect (NATS may have dropped)
                }
            }
        }
    }
}

/// Publish one batch of unpublished outbox rows. Returns the number published. Each row is
/// marked published only AFTER its publish acks, so a crash mid-batch simply redelivers
/// (at-least-once; consumers dedupe on `event_id`).
#[tracing::instrument(skip_all, fields(batch = BATCH))]
async fn drain_once(
    db: &sqlx::PgPool,
    publisher: &JetStreamPublisher,
) -> Result<u64, anyhow::Error> {
    let rows: Vec<OutboxRow> = repo::fetch_unpublished(db, BATCH).await?;
    let mut published = 0u64;
    for row in rows {
        let bytes = serde_json::to_vec(&row.payload)?;
        publisher.publish(&row.topic, bytes).await?;
        repo::mark_published(db, row.id).await?;
        published += 1;
    }
    Ok(published)
}
