//! Event layer — two halves:
//!
//!   * **Outbox relay** (producer): chat writes the message AND a `chat.outbox` row atomically
//!     (see `repo::send_message`); this background task drains the outbox → publishes each to
//!     NATS (subject = `EventEnvelope.event_type`) → stamps `published_at`. notification consumes
//!     `pguard.events.chat.message_sent`. A NATS outage only delays delivery (at-least-once;
//!     consumers dedupe on `event_id`). Mirrors calling/payment/rating.
//!
//!   * **Redis pub/sub fan-out** (real-time): a persisted message is published to
//!     `chat:{conversation_id}` so EVERY chat replica's WS sessions can deliver it — cross-
//!     instance broadcast (the spec's requirement; unlike calling's in-process registry).

use std::time::Duration;

use redis::AsyncCommands;
use uuid::Uuid;

use crate::models::OutgoingChatMessage;
use crate::repo::{self, OutboxRow};

const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";
const POLL_INTERVAL: Duration = Duration::from_secs(2);
const BATCH: i64 = 100;

/// Redis pub/sub channel for a conversation's live broadcast. WS subscribers `psubscribe`
/// `chat:*` and filter by their authorized-rooms set.
pub fn channel_for(conversation_id: Uuid) -> String {
    format!("chat:{conversation_id}")
}

/// Publish a persisted message to its conversation channel (best-effort; the durable record is
/// the DB row + the outbox event — pub/sub is the real-time accelerator). Never fails the send.
pub async fn publish_chat_message(
    conn: &redis::aio::MultiplexedConnection,
    message: &OutgoingChatMessage,
) {
    let channel = channel_for(message.conversation_id);
    match serde_json::to_string(message) {
        Ok(payload) => {
            let mut conn = conn.clone();
            if let Err(e) = conn.publish::<_, _, ()>(&channel, payload).await {
                tracing::warn!(%channel, "chat pub/sub publish failed: {e}");
            }
        }
        Err(e) => tracing::warn!("chat message serialize for pub/sub failed: {e}"),
    }
}

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
                tracing::info!(stream = STREAM, "chat outbox relay connected to NATS");
                p
            }
            Err(e) => {
                tracing::warn!("chat outbox relay NATS connect failed: {e}; retrying");
                tokio::time::sleep(POLL_INTERVAL).await;
                continue;
            }
        };

        loop {
            match drain_once(&db, &publisher).await {
                Ok(0) => tokio::time::sleep(POLL_INTERVAL).await,
                Ok(n) => tracing::debug!(published = n, "chat outbox relay drained batch"),
                Err(e) => {
                    tracing::warn!("chat outbox relay drain failed: {e}; reconnecting");
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn channel_is_per_conversation() {
        let id = Uuid::nil();
        assert_eq!(channel_for(id), "chat:00000000-0000-0000-0000-000000000000");
    }
}
