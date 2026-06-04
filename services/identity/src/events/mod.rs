//! Event layer — the NATS JetStream consumer for `pguard.events.user.compromised`.
//! Identity is the consumer of record for that topic: on a compromise event it runs the
//! SAME force-revoke-all logic as the internal HTTP route (`repo::revoke_all`), so an
//! incident-response signal from any service instantly invalidates the user's tokens
//! (CLAUDE.md "Token revocation" + NATS topic `pguard.events.user.compromised`).

use futures::StreamExt;
use serde::Deserialize;
use serde_json::Value;
use tracing::Instrument;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::{topics, EventEnvelope};

use crate::repo;
use crate::state::AppState;

/// JetStream stream + durable consumer names. The stream is shared across services
/// (`get_or_create` is idempotent); identity binds its own durable filtered to the
/// compromise subject.
const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";
const DURABLE: &str = "identity-user-compromised";

/// Payload of `pguard.events.user.compromised`.
#[derive(Debug, Deserialize)]
struct UserCompromised {
    user_id: Uuid,
}

/// Connect to NATS JetStream and run the consume loop. Spawned as a background task by
/// `main`; resilient (logs and returns on fatal error).
pub async fn run_consumer(state: AppState, nats_url: &str) -> Result<(), AppError> {
    let client = async_nats::connect(nats_url)
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
                // Only the compromise topic concerns identity.
                filter_subject: topics::USER_COMPROMISED.to_string(),
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
        subject = topics::USER_COMPROMISED,
        "identity compromise consumer started"
    );

    while let Some(item) = messages.next().await {
        let message = match item {
            Ok(m) => m,
            Err(e) => {
                tracing::warn!("NATS message error: {e}");
                continue;
            }
        };

        match handle_event(&state, message.payload.as_ref()).await {
            Ok(()) => {
                if let Err(e) = message.ack().await {
                    tracing::warn!("ack failed: {e}");
                }
            }
            Err(e) => {
                // Do not ack → JetStream redelivers; revoke_all is idempotent enough (each
                // redelivery just bumps the version again — strictly monotonic, safe).
                tracing::error!("compromise handling failed (will redeliver): {e}");
            }
        }
    }

    Ok(())
}

/// Parse one envelope and, if it is a compromise event, run force-revoke-all inside a span
/// carrying the event identity + correlation id for distributed tracing.
async fn handle_event(state: &AppState, payload: &[u8]) -> Result<(), AppError> {
    let envelope: EventEnvelope<Value> = serde_json::from_slice(payload)
        .map_err(|e| AppError::BadRequest(format!("invalid event envelope: {e}")))?;

    if envelope.event_type != topics::USER_COMPROMISED {
        // Filtered server-side, but be defensive: ack-and-ignore anything else.
        return Ok(());
    }

    let span = tracing::info_span!(
        "identity.user_compromised",
        event_type = %envelope.event_type,
        event_id = %envelope.event_id,
        correlation_id = %envelope.correlation_id,
    );
    process(state, envelope).instrument(span).await
}

async fn process(state: &AppState, envelope: EventEnvelope<Value>) -> Result<(), AppError> {
    let payload: UserCompromised = serde_json::from_value(envelope.payload)
        .map_err(|e| AppError::BadRequest(format!("invalid user.compromised payload: {e}")))?;
    let version = repo::revoke_all(&state.db, payload.user_id).await?;
    // Publish the marker so in-flight access tokens are rejected immediately, not just
    // refresh tokens.
    let mut redis = state.redis_conn.clone();
    crate::state::mark_user_revoked(&mut redis, payload.user_id, version).await;
    Ok(())
}
