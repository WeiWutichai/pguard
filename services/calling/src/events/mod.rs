//! Event layer — the transactional-outbox **relay** (producer half). calling writes the call
//! state change AND an outbox row atomically (see `repo`); this background task drains the
//! outbox: poll unpublished rows → publish each to NATS (subject = `EventEnvelope.event_type`)
//! → stamp `published_at`. notification consumes `pguard.events.calling.*`.
//!
//! Resilience: a NATS outage only delays delivery — the relay logs + retries and never
//! crashes the service; a row is marked published only AFTER a successful publish
//! (at-least-once; consumers dedupe on `event_id`). Mirrors payment/rating's relay.

use std::time::Duration;

use crate::repo::{self, OutboxRow};

const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";
const POLL_INTERVAL: Duration = Duration::from_secs(2);
const BATCH: i64 = 100;

pub struct JetStreamPublisher {
    jetstream: async_nats::jetstream::Context,
}

impl JetStreamPublisher {
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
                tracing::info!(stream = STREAM, "calling outbox relay connected to NATS");
                p
            }
            Err(e) => {
                tracing::warn!("calling outbox relay NATS connect failed: {e}; retrying");
                tokio::time::sleep(POLL_INTERVAL).await;
                continue;
            }
        };

        loop {
            match drain_once(&db, &publisher).await {
                Ok(0) => tokio::time::sleep(POLL_INTERVAL).await,
                Ok(n) => tracing::debug!(published = n, "calling outbox relay drained batch"),
                Err(e) => {
                    tracing::warn!("calling outbox relay drain failed: {e}; reconnecting");
                    tokio::time::sleep(POLL_INTERVAL).await;
                    break;
                }
            }
        }
    }
}

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
