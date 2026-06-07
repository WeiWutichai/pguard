//! Event layer.
//!
//! Two directions, deliberately asymmetric (the presence boundary):
//!  - **OUT (raw GPS):** every accepted fix is republished to **Redis pub/sub** (channel
//!    `presence:gps`) for the admin live map — high-frequency, ephemeral, NOT NATS. presence
//!    emits ZERO `pguard.events.*` topics (booking already owns en_route/arrived; duplicating
//!    them here would be wrong).
//!  - **IN (booking facts):** a durable JetStream consumer projects `pguard.events.booking.*`
//!    into the `guard_assignments` IDOR read-model (see [`consumer`]).

pub mod consumer;

use redis::AsyncCommands;

use shared::error::AppError;

use crate::models::GpsEvent;

/// Redis pub/sub channel the admin live map subscribes to. A single fan-out channel (guard_id
/// is in the payload) keeps the map a one-subscription consumer.
pub const GPS_CHANNEL: &str = "presence:gps";

/// Republish a raw fix to Redis pub/sub for the live map. Best-effort by contract: the caller
/// treats a failure as log-and-continue — the DB write already succeeded and the next fix
/// re-publishes, so a transient Redis blip never blocks GPS ingestion.
pub async fn publish_gps(
    redis: &redis::aio::MultiplexedConnection,
    event: &GpsEvent,
) -> Result<(), AppError> {
    let payload = serde_json::to_string(event)
        .map_err(|e| AppError::Internal(format!("serialize gps event: {e}")))?;
    let mut conn = redis.clone();
    conn.publish::<_, _, ()>(GPS_CHANNEL, payload)
        .await
        .map_err(AppError::Redis)?;
    Ok(())
}
