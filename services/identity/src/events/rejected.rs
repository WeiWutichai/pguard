//! Event CONSUMER — `pguard.events.user.rejected` (profile → identity).
//!
//! Mirror of the [`super::approved`] consumer, for the OTHER admin decision. When an admin rejects
//! an application, profile emits `user.rejected` (transactional outbox); identity reacts here by
//! flipping ITS OWN `users.approval_status` to `rejected`. This gives the applicant a distinct
//! rejected state (instead of "pending forever") and — with the re-registerable-rejected upsert —
//! lets them re-apply. Login stays blocked either way (only `approved` passes `verify_credentials`).
//!
//! SEPARATE durable (`identity-user-rejected`) from the approvals consumer so this addition never
//! touches the working approve path's consumer config. Same resilience contract: HMAC-verify →
//! parse → idempotent flip (by `event_id`) → ack-on-success; poison/forged are dropped.

use std::time::Duration;

use futures::StreamExt;
use serde::Deserialize;
use tracing::Instrument;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::{topics, EventEnvelope};

use crate::repo::{self, ApprovedOutcome};
use crate::state::AppState;

const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";
/// Intent-scoped durable name (this consumer only ever processes rejections).
const DURABLE: &str = "identity-user-rejected";
const RECONNECT_INTERVAL: Duration = Duration::from_secs(2);

/// The `user.rejected` payload identity needs — just the `user_id` to flip. `role` is irrelevant
/// (a rejection enrols nothing), so it is not required by the parse.
#[derive(Debug, Deserialize)]
struct RejectedPayload {
    user_id: Uuid,
}

/// Run the `user.rejected` consumer FOREVER: (re)connect, drain, back off + reconnect on error.
pub async fn run_consumer(state: AppState, nats_url: &str) {
    loop {
        match connect_and_consume(&state, nats_url).await {
            Ok(()) => tracing::warn!("user.rejected consumer stream ended; reconnecting"),
            Err(e) => tracing::warn!("user.rejected consumer error: {e}; reconnecting"),
        }
        tokio::time::sleep(RECONNECT_INTERVAL).await;
    }
}

async fn connect_and_consume(state: &AppState, nats_url: &str) -> Result<(), AppError> {
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
                filter_subject: topics::USER_REJECTED.to_string(),
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
        subject = topics::USER_REJECTED,
        "identity user.rejected consumer started"
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

        // Fail-closed HMAC check — a forged rejection (griefing a rival's account) is dropped.
        if !shared_events::verify_message(message.headers.as_ref(), message.payload.as_ref()) {
            observability::record_rejected_event(DURABLE);
            tracing::warn!("dropping user.rejected event with missing/invalid signature (forged?)");
            let _ = message.ack().await;
            continue;
        }

        let envelope: EventEnvelope<RejectedPayload> =
            match serde_json::from_slice(message.payload.as_ref()) {
                Ok(e) => e,
                Err(e) => {
                    tracing::error!("dropping malformed user.rejected envelope (poison): {e}");
                    let _ = message.ack().await;
                    continue;
                }
            };

        match process(state, envelope).await {
            Ok(()) => {
                if let Err(e) = message.ack().await {
                    tracing::warn!("ack failed: {e}");
                }
            }
            Err(e) => {
                tracing::error!("user.rejected apply failed (will redeliver): {e}");
            }
        }
    }

    Ok(())
}

async fn process(
    state: &AppState,
    envelope: EventEnvelope<RejectedPayload>,
) -> Result<(), AppError> {
    if envelope.event_type != topics::USER_REJECTED {
        tracing::warn!(event_type = %envelope.event_type, "ignoring unexpected event type");
        return Ok(());
    }

    let span = tracing::info_span!(
        "identity.user_rejected",
        event_type = %envelope.event_type,
        event_id = %envelope.event_id,
        correlation_id = %envelope.correlation_id,
    );
    if let Some(tp) = envelope.traceparent.as_deref() {
        observability::set_parent_from_traceparent(&span, tp);
    }
    apply(state, envelope).instrument(span).await
}

async fn apply(state: &AppState, envelope: EventEnvelope<RejectedPayload>) -> Result<(), AppError> {
    let outcome = repo::reject_user_on_event(
        &state.db,
        envelope.event_id,
        &envelope.event_type,
        envelope.payload.user_id,
    )
    .await?;

    match outcome {
        ApprovedOutcome::Applied => {
            tracing::info!(user_id = %envelope.payload.user_id, "account rejected → applicant can re-apply")
        }
        ApprovedOutcome::Duplicate => tracing::debug!("duplicate user.rejected event; skipped"),
        ApprovedOutcome::UserNotFound => {
            tracing::warn!(user_id = %envelope.payload.user_id, "user.rejected for unknown/approved user; recorded")
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parses_rejected_envelope() {
        let user_id = Uuid::new_v4();
        let raw = json!({
            "event_id": Uuid::new_v4(),
            "event_type": topics::USER_REJECTED,
            "occurred_at": "2026-07-22T10:00:00Z",
            "correlation_id": Uuid::new_v4(),
            "payload": { "user_id": user_id, "role": "guard", "approved_at": "2026-07-22T10:00:00Z" }
        });
        let env: EventEnvelope<RejectedPayload> = serde_json::from_value(raw).expect("parse");
        assert_eq!(env.event_type, topics::USER_REJECTED);
        assert_eq!(env.payload.user_id, user_id);
    }
}
