//! Event layer — the transactional-outbox **relay** (producer).
//!
//! profile writes the approval flip AND a `user.approved`/`user.rejected` outbox row
//! atomically (see `repo::set_approval_status`). This background task drains the outbox:
//! poll unpublished rows → publish each to NATS (subject = `EventEnvelope.event_type`) →
//! stamp `published_at`. identity's durable consumer subscribes to `pguard.events.user.approved`
//! and flips its own `users.approval_status` (no cross-schema write — the event is the only
//! coupling).
//!
//! Resilience: if NATS is down the relay logs and retries on the next tick — it never crashes
//! the service. A row is marked published only AFTER a successful publish, so delivery is
//! at-least-once (the consumer dedupes on `event_id`). Mirrors booking/chat's relay.

use std::time::Duration;

use crate::repo::{self, OutboxRow};

/// Publishes a serialized [`shared_events::EventEnvelope`] to a subject. A trait so the relay
/// is decoupled from `async-nats` (and unit-testable without a live broker).
#[async_trait::async_trait]
pub trait EventPublisher: Send + Sync {
    async fn publish(&self, subject: &str, payload: &[u8]) -> Result<(), anyhow::Error>;
}

const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";

/// JetStream-backed publisher. Ensures the shared `PGUARD_EVENTS` stream exists so identity's
/// durable consumer can bind to it.
pub struct JetStreamPublisher {
    jetstream: async_nats::jetstream::Context,
}

impl JetStreamPublisher {
    /// Connect to NATS and ensure the stream exists. Fails fast on a bad URL/broker so the
    /// relay's connect step can log + retry.
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
        // Sign + publish via the shared helper (HMAC signature header); awaits the broker
        // persistence ack so a row is marked published only after a durable, signed publish.
        shared_events::publish_signed(&self.jetstream, subject, payload).await
    }
}

/// How long to sleep between drains when there is nothing to publish (or NATS is down).
const POLL_INTERVAL: Duration = Duration::from_secs(2);
/// Max rows drained per tick (bounded so one tick cannot monopolize a DB connection).
const BATCH: i64 = 100;

/// Run the outbox relay forever: connect to NATS (retrying), then loop draining the outbox.
/// Spawned as a background task by `main`. Never returns under normal operation.
pub async fn run_relay(db: sqlx::PgPool, nats_url: String) {
    loop {
        let publisher = match JetStreamPublisher::connect(&nats_url).await {
            Ok(p) => {
                tracing::info!(stream = STREAM, "profile outbox relay connected to NATS");
                p
            }
            Err(e) => {
                tracing::warn!("profile outbox relay NATS connect failed: {e}; retrying");
                tokio::time::sleep(POLL_INTERVAL).await;
                continue;
            }
        };

        // Drain until a publish/DB error forces a reconnect.
        loop {
            match drain_once(&db, &publisher).await {
                Ok(0) => tokio::time::sleep(POLL_INTERVAL).await,
                Ok(n) => tracing::debug!(published = n, "profile outbox relay drained batch"),
                Err(e) => {
                    tracing::warn!("profile outbox relay drain failed: {e}; reconnecting");
                    tokio::time::sleep(POLL_INTERVAL).await;
                    break; // reconnect (NATS may have dropped)
                }
            }
        }
    }
}

/// Publish one batch of unpublished outbox rows. Returns the number published. Each row is
/// marked published only AFTER its publish acks, so a crash mid-batch simply redelivers
/// (at-least-once; the consumer dedupes on `event_id`).
#[tracing::instrument(skip_all, fields(batch = BATCH))]
async fn drain_once(
    db: &sqlx::PgPool,
    publisher: &dyn EventPublisher,
) -> Result<u64, anyhow::Error> {
    let rows: Vec<OutboxRow> = repo::fetch_unpublished(db, BATCH).await?;
    let mut published = 0u64;
    for row in rows {
        let bytes = serde_json::to_vec(&row.payload)?;
        publisher.publish(&row.topic, &bytes).await?;
        repo::mark_published(db, row.id).await?;
        published += 1;
    }
    Ok(published)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::sync::Mutex;
    use uuid::Uuid;

    /// In-memory publisher capturing what the relay would publish — proves the publish seam
    /// without a live broker.
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
        let pubr = CapturingPublisher::default();
        let envelope = json!({
            "event_id": Uuid::new_v4(),
            "event_type": "pguard.events.user.approved",
            "payload": { "user_id": Uuid::new_v4(), "role": "guard" }
        });
        let bytes = serde_json::to_vec(&envelope).unwrap();
        pubr.publish("pguard.events.user.approved", &bytes)
            .await
            .unwrap();

        let captured = pubr.published.lock().unwrap();
        assert_eq!(captured.len(), 1);
        assert_eq!(captured[0].0, "pguard.events.user.approved");
        let back: serde_json::Value = serde_json::from_slice(&captured[0].1).unwrap();
        assert_eq!(back["event_type"], "pguard.events.user.approved");
    }
}
