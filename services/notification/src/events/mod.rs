//! Event layer — the NATS JetStream consumer that turns `pguard.events.*` into
//! notifications. This is the heart of Phase 1: booking et al. no longer write the
//! notification schema; they emit events and this subscribes.

use futures::StreamExt;
use serde_json::Value;

use shared::error::AppError;
use shared_events::EventEnvelope;

use crate::domain;
use crate::fcm::PushMessage;
use crate::repo::{self, Processed};
use crate::state::AppState;

/// JetStream stream + durable consumer names.
const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";
const DURABLE: &str = "notification";

/// Connect to NATS JetStream and run the consume loop until the stream ends or errors.
/// Spawned as a background task by `main`; resilient (logs and returns on fatal error).
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
        subjects = SUBJECTS,
        "notification consumer started"
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
                // Do not ack → JetStream will redeliver; the idempotency ledger makes
                // reprocessing safe.
                tracing::error!("event handling failed (will redeliver): {e}");
            }
        }
    }

    Ok(())
}

/// Parse one envelope, dedupe + persist atomically, then push (best-effort).
async fn handle_event(state: &AppState, payload: &[u8]) -> Result<(), AppError> {
    let envelope: EventEnvelope<Value> = serde_json::from_slice(payload)
        .map_err(|e| AppError::BadRequest(format!("invalid event envelope: {e}")))?;

    let plan = domain::plan_for_event(&envelope.event_type, &envelope.payload);

    match repo::process_event(
        &state.db,
        envelope.event_id,
        &envelope.event_type,
        plan.as_ref(),
    )
    .await?
    {
        Processed::Created(recipient) => {
            if let Some(plan) = plan {
                let tokens = repo::user_tokens(&state.db, recipient).await?;
                state
                    .pusher
                    .push(&PushMessage {
                        tokens,
                        title: plan.title,
                        body: plan.body,
                        data: plan.data,
                    })
                    .await?;
            }
        }
        Processed::Ignored => {
            tracing::debug!(event = %envelope.event_type, "no notification mapping; marked processed")
        }
        Processed::Duplicate => {
            tracing::debug!(event_id = %envelope.event_id, "duplicate event; skipped")
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use crate::domain::idempotency::SeenSet;
    use crate::domain::plan_for_event;
    use serde_json::{json, Value};
    use shared_events::topics;
    use uuid::Uuid;

    /// Models the consumer's per-event decision (claim THEN map) — the same two steps
    /// `repo::process_event` performs atomically against `processed_events` +
    /// `notification_logs`. Returns the notification title, or `None` for a duplicate or
    /// an unmapped event.
    fn consume(
        seen: &mut SeenSet,
        event_type: &str,
        event_id: Uuid,
        payload: &Value,
    ) -> Option<String> {
        if !seen.claim(event_id) {
            return None; // duplicate (at-least-once redelivery) → skip
        }
        plan_for_event(event_type, payload).map(|p| p.title)
    }

    /// Integration-style consumer dedupe test, using the in-memory claim as a test
    /// double for the DB/NATS at-least-once path.
    #[test]
    fn redelivery_of_same_event_is_deduped() {
        let mut seen = SeenSet::new();
        let event_id = Uuid::new_v4();
        let payload = json!({ "customer_id": Uuid::new_v4(), "booking_id": Uuid::new_v4() });

        assert!(
            consume(&mut seen, topics::BOOKING_JOB_ACCEPTED, event_id, &payload).is_some(),
            "first delivery notifies"
        );
        assert!(
            consume(&mut seen, topics::BOOKING_JOB_ACCEPTED, event_id, &payload).is_none(),
            "redelivery of the same event_id is deduped"
        );
    }

    #[test]
    fn distinct_events_each_notify() {
        let mut seen = SeenSet::new();
        let payload = json!({ "customer_id": Uuid::new_v4(), "guard_id": Uuid::new_v4(), "booking_id": Uuid::new_v4() });
        assert!(consume(
            &mut seen,
            topics::BOOKING_JOB_ACCEPTED,
            Uuid::new_v4(),
            &payload
        )
        .is_some());
        assert!(consume(&mut seen, topics::BOOKING_ARRIVED, Uuid::new_v4(), &payload).is_some());
    }
}
