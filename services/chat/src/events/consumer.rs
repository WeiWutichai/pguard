//! Event CONSUMER — chat's FIRST inbound half: post a SERVER-GENERATED call-summary `system`
//! message into a booking's conversation when a call terminates.
//!
//! This is the second half of the security fix. Clients can no longer mark a message `system`
//! (the user send path rejects it — `repo::send_message`), because notification SUPPRESSES the
//! "new message" push for `system` rows; a participant could otherwise silence the victim's push.
//! So the ONLY producer of a `system` row is the server: this consumer.
//!
//! Modelled on booking's `payment.completed` consumer:
//!  - A durable PULL consumer over the shared `PGUARD_EVENTS` stream, FILTERED to the calling
//!    context (`pguard.events.calling.>`); it acts ONLY on the TERMINAL topics (`calling.ended`,
//!    `calling.rejected`) and skips the rest (initiated/accepted) — no new NATS ACL.
//!  - IDEMPOTENT via `chat.processed_events` (claim the envelope's `event_id` in the SAME tx that
//!    inserts the summary message + its outbox row): a redelivery double-posts nothing.
//!  - HMAC-verified before any write — a forged `calling.*` is dropped, counted, never applied.
//!  - A malformed envelope is POISON: acked (dropped) so it can't wedge the consumer. A transient
//!    (DB / booking-read) failure is NOT acked → JetStream redelivers; the ledger makes it safe.
//!  - The summary insert goes through the SAME transactional-outbox path as a normal message, so
//!    notification still (correctly) SKIPS the push for the `system` row — suppression is structural.

use std::time::Duration;

use futures::StreamExt;
use serde::Deserialize;
use tracing::Instrument;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::{topics, EventEnvelope};

use crate::booking_client::BookingReader;
use crate::domain::CallSummary;
use crate::models::{CreateConversationRequest, ParticipantInput};
use crate::repo;

const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";
/// Intent-scoped durable name (this consumer only ever posts call summaries).
const DURABLE: &str = "chat-call-summary";
/// Filter to the calling context; we dispatch only on the terminal topics below.
const FILTER_SUBJECT: &str = "pguard.events.calling.>";
/// Backoff between reconnect attempts when NATS is down or the stream ends.
const RECONNECT_INTERVAL: Duration = Duration::from_secs(2);

const ROLE_CUSTOMER: &str = "customer";
const ROLE_GUARD: &str = "guard";

/// The terminal-call fields chat reads to build a summary. calling's `enqueue_event` emits
/// `{ call_id, booking_id, caller_id, callee_id, call_type, status, duration_seconds, answered_at,
/// end_reason }`. chat reads the subset it needs; missing `call_id`/`booking_id`/`caller_id`/
/// `callee_id` fail the parse → the event is poison (dropped). `answered_at`/`duration_seconds`/
/// `end_reason` are optional (null on non-terminal events, which we never act on anyway).
#[derive(Debug, Deserialize)]
struct CallEndedPayload {
    #[allow(dead_code)] // part of the contract; the dedupe key is the envelope event_id
    call_id: Uuid,
    booking_id: Uuid,
    caller_id: Uuid,
    // Part of the contract (notification routes pushes on it); chat derives the summary's
    // recipient from the conversation's OTHER participant, so it isn't read here.
    #[allow(dead_code)]
    callee_id: Uuid,
    call_type: String,
    status: String,
    #[serde(default)]
    duration_seconds: Option<i32>,
    #[serde(default)]
    answered_at: Option<serde_json::Value>,
    #[serde(default)]
    end_reason: Option<String>,
}

/// Run the call-summary consumer FOREVER: (re)connect to NATS, drain, and on any connect/stream
/// error log + back off + reconnect. Never returns under normal operation (mirrors the relay's
/// resilience). Spawned as a background task by `main`. `booking` is used to find-or-CREATE the
/// conversation (deriving authoritative roles) when the parties never opened the chat thread.
pub async fn run_consumer<B: BookingReader>(db: sqlx::PgPool, nats_url: String, booking: B) {
    loop {
        match connect_and_consume(&db, &nats_url, &booking).await {
            Ok(()) => tracing::warn!("calling-terminal consumer stream ended; reconnecting"),
            Err(e) => tracing::warn!("calling-terminal consumer error: {e}; reconnecting"),
        }
        tokio::time::sleep(RECONNECT_INTERVAL).await;
    }
}

/// One connect+consume session: bind the durable consumer and drain until the stream ends or a
/// fatal error. Returns to [`run_consumer`], which reconnects.
async fn connect_and_consume<B: BookingReader>(
    db: &sqlx::PgPool,
    nats_url: &str,
    booking: &B,
) -> Result<(), AppError> {
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
                filter_subject: FILTER_SUBJECT.to_string(),
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
        filter = FILTER_SUBJECT,
        "chat call-summary consumer started"
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

        // Verify the HMAC signature BEFORE any write — a forged calling event is dropped, counted,
        // never applied. Fail-closed.
        if !shared_events::verify_message(message.headers.as_ref(), message.payload.as_ref()) {
            observability::record_rejected_event(DURABLE);
            tracing::warn!("dropping calling event with missing/invalid signature (forged?)");
            let _ = message.ack().await;
            continue;
        }

        // Parse first. A malformed envelope is POISON — ACK it (drop) instead of redelivering
        // forever and wedging the consumer.
        let envelope: EventEnvelope<CallEndedPayload> =
            match serde_json::from_slice(message.payload.as_ref()) {
                Ok(e) => e,
                Err(e) => {
                    observability::record_rejected_event(DURABLE);
                    tracing::error!("dropping malformed calling envelope (poison): {e}");
                    let _ = message.ack().await;
                    continue;
                }
            };

        match process(db, booking, envelope).await {
            Ok(()) => {
                if let Err(e) = message.ack().await {
                    tracing::warn!("ack failed: {e}");
                }
            }
            Err(e) => {
                // Transient (DB / booking-read) error → do NOT ack; JetStream redelivers and the
                // processed_events ledger makes the reprocess safe (no double-post).
                tracing::error!("call-summary post failed (will redeliver): {e}");
            }
        }
    }

    Ok(())
}

/// Dispatch one parsed envelope: act ONLY on the terminal topics (`calling.ended` / `.rejected`);
/// every other calling topic (initiated/accepted) is a no-op (acked). Runs inside a span carrying
/// the event identity + `correlation_id` so calling→NATS→chat stitches into one distributed trace.
async fn process<B: BookingReader>(
    db: &sqlx::PgPool,
    booking: &B,
    envelope: EventEnvelope<CallEndedPayload>,
) -> Result<(), AppError> {
    // Only terminal calls produce a summary line. Skip (ack) initiated/accepted + anything else.
    if envelope.event_type != topics::CALLING_ENDED
        && envelope.event_type != topics::CALLING_REJECTED
    {
        tracing::debug!(event_type = %envelope.event_type, "non-terminal calling event; skipped");
        return Ok(());
    }

    let span = tracing::info_span!(
        "chat.post_call_summary",
        event_type = %envelope.event_type,
        event_id = %envelope.event_id,
        correlation_id = %envelope.correlation_id,
    );
    if let Some(tp) = envelope.traceparent.as_deref() {
        observability::set_parent_from_traceparent(&span, tp);
    }
    post_summary(db, booking, envelope).instrument(span).await
}

/// Build + post the summary for one terminal call: find-or-create the booking's conversation, then
/// insert the `system` message idempotently. Returns `Err` only on transient (retryable) failures.
async fn post_summary<B: BookingReader>(
    db: &sqlx::PgPool,
    booking: &B,
    envelope: EventEnvelope<CallEndedPayload>,
) -> Result<(), AppError> {
    let p = &envelope.payload;

    let summary = CallSummary::from_call(
        &p.call_type,
        &p.status,
        p.end_reason.as_deref(),
        p.answered_at.is_some(),
        p.duration_seconds,
    );
    let content = summary.to_content();

    // FIND the booking's conversation (request_id == booking_id, UNIQUE). If the parties never
    // opened the chat thread, CREATE it from the AUTHORITATIVE booking (server-derived roles) so
    // the summary still lands — mirrors create_conversation's identity derivation.
    let conversation_id = match repo::find_conversation_id_by_request(db, p.booking_id).await? {
        Some(id) => id,
        None => create_conversation_for_booking(db, booking, p.booking_id).await?,
    };

    let posted = repo::insert_call_summary_idempotent(
        db,
        envelope.event_id,
        &envelope.event_type,
        conversation_id,
        p.caller_id,
        &content,
    )
    .await?;
    if posted {
        tracing::info!(conversation_id = %conversation_id, outcome = summary.oc, "call summary posted");
    } else {
        tracing::debug!(%conversation_id, "duplicate calling-terminal event; summary skipped");
    }
    Ok(())
}

/// Create the booking's conversation from the AUTHORITATIVE booking (service-JWT read) so a summary
/// can be posted even when neither party opened the chat. Roles are server-derived (customer +
/// assigned guard) — never from the call event. GET-OR-CREATE (idempotent on `request_id`), so a
/// concurrent create + this one converge on a single conversation. Returns its id.
async fn create_conversation_for_booking<B: BookingReader>(
    db: &sqlx::PgPool,
    booking: &B,
    booking_id: Uuid,
) -> Result<Uuid, AppError> {
    let b = booking.get_booking(booking_id).await?;
    let mut participants = vec![ParticipantInput {
        user_id: b.customer_id,
        role: ROLE_CUSTOMER.to_string(),
        display_name: None,
        avatar_url: None,
    }];
    if let Some(guard_id) = b.guard_id {
        participants.push(ParticipantInput {
            user_id: guard_id,
            role: ROLE_GUARD.to_string(),
            display_name: None,
            avatar_url: None,
        });
    }
    let req = CreateConversationRequest {
        request_id: booking_id,
        request_status: Some(b.status),
        participants,
    };
    let conv = repo::create_conversation(db, &req).await?;
    Ok(conv.id)
}

// ---------------------------------------------------------------------------------------------
// Booking-status consumer — keeps `chat.conversations.request_status` current from booking's
// lifecycle so a completed/cancelled job's thread becomes READ-ONLY. Both gates already read that
// column (server: `repo::send_message` → `domain::is_writable`; mobile: `ChatReadOnly.fromStatus`)
// — they just never learned the booking closed because `request_status` was frozen at create time.
// Own durable + offset (independent of the call-summary consumer); terminal-topics only.
// ---------------------------------------------------------------------------------------------

const BOOKING_STATUS_DURABLE: &str = "chat-booking-status";
const BOOKING_STATUS_FILTER: &str = "pguard.events.booking.>";

/// Only `booking_id` is needed to locate the conversation (completed also carries proration fields,
/// which serde ignores here).
#[derive(Deserialize)]
struct BookingStatusPayload {
    booking_id: Uuid,
}

pub async fn run_booking_status_consumer(db: sqlx::PgPool, nats_url: String) {
    loop {
        match connect_and_consume_booking_status(&db, &nats_url).await {
            Ok(()) => tracing::warn!("chat booking-status consumer stream ended; reconnecting"),
            Err(e) => tracing::warn!("chat booking-status consumer error: {e}; reconnecting"),
        }
        tokio::time::sleep(RECONNECT_INTERVAL).await;
    }
}

async fn connect_and_consume_booking_status(
    db: &sqlx::PgPool,
    nats_url: &str,
) -> Result<(), AppError> {
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
            BOOKING_STATUS_DURABLE,
            async_nats::jetstream::consumer::pull::Config {
                durable_name: Some(BOOKING_STATUS_DURABLE.to_string()),
                filter_subject: BOOKING_STATUS_FILTER.to_string(),
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
        filter = BOOKING_STATUS_FILTER,
        "chat booking-status consumer started"
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
            observability::record_consumer_lag(BOOKING_STATUS_DURABLE, info.pending);
        }
        // Fail-closed on a forged/unsigned event.
        if !shared_events::verify_message(message.headers.as_ref(), message.payload.as_ref()) {
            observability::record_rejected_event(BOOKING_STATUS_DURABLE);
            tracing::warn!("dropping booking event with missing/invalid signature (forged?)");
            let _ = message.ack().await;
            continue;
        }
        let envelope: EventEnvelope<BookingStatusPayload> =
            match serde_json::from_slice(message.payload.as_ref()) {
                Ok(e) => e,
                Err(e) => {
                    // Poison → ACK (drop) rather than redeliver forever.
                    tracing::warn!("poison booking event (drop): {e}");
                    let _ = message.ack().await;
                    continue;
                }
            };
        // Only the TERMINAL topics change writability; ack-skip every other booking event.
        let status = match envelope.event_type.as_str() {
            topics::BOOKING_COMPLETED => "completed",
            topics::BOOKING_CANCELLED => "cancelled",
            _ => {
                let _ = message.ack().await;
                continue;
            }
        };
        match repo::set_request_status(db, envelope.payload.booking_id, status).await {
            Ok(_) => {
                let _ = message.ack().await;
            }
            Err(e) => {
                // Transient DB error → NAK for redelivery (don't lose the read-only flip).
                tracing::warn!("set_request_status failed: {e}; will redeliver");
                let _ = message
                    .ack_with(async_nats::jetstream::AckKind::Nak(None))
                    .await;
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// A well-formed `calling.ended` envelope parses to the fields chat needs (the summary is built
    /// from the payload; the dedupe key is the envelope `event_id`). Pure (no DB/NATS).
    #[test]
    fn parses_calling_ended_envelope() {
        let booking_id = Uuid::new_v4();
        let caller = Uuid::new_v4();
        let callee = Uuid::new_v4();
        let raw = json!({
            "event_id": Uuid::new_v4(),
            "event_type": topics::CALLING_ENDED,
            "occurred_at": "2026-06-24T10:00:00Z",
            "correlation_id": Uuid::new_v4(),
            "payload": {
                "call_id": Uuid::new_v4(),
                "booking_id": booking_id,
                "caller_id": caller,
                "callee_id": callee,
                "call_type": "video",
                "status": "ended",
                "duration_seconds": 125,
                "answered_at": "2026-06-24T09:58:00Z",
                "end_reason": "hangup"
            }
        });
        let env: EventEnvelope<CallEndedPayload> = serde_json::from_value(raw).expect("parse");
        assert_eq!(env.event_type, topics::CALLING_ENDED);
        assert_eq!(env.payload.booking_id, booking_id);
        assert_eq!(env.payload.caller_id, caller);
        // The summary derived from this answered call is "completed" with its duration.
        let s = CallSummary::from_call(
            &env.payload.call_type,
            &env.payload.status,
            env.payload.end_reason.as_deref(),
            env.payload.answered_at.is_some(),
            env.payload.duration_seconds,
        );
        assert_eq!(s.oc, "completed");
        assert_eq!(s.ds, Some(125));
    }

    /// A rejected call's event (no answer) → a "rejected" summary with null duration.
    #[test]
    fn rejected_event_yields_rejected_summary() {
        let raw = json!({
            "event_id": Uuid::new_v4(),
            "event_type": topics::CALLING_REJECTED,
            "occurred_at": "2026-06-24T10:00:00Z",
            "correlation_id": Uuid::new_v4(),
            "payload": {
                "call_id": Uuid::new_v4(),
                "booking_id": Uuid::new_v4(),
                "caller_id": Uuid::new_v4(),
                "callee_id": Uuid::new_v4(),
                "call_type": "audio",
                "status": "rejected",
                "duration_seconds": null,
                "answered_at": null,
                "end_reason": "rejected_by_callee"
            }
        });
        let env: EventEnvelope<CallEndedPayload> = serde_json::from_value(raw).expect("parse");
        let s = CallSummary::from_call(
            &env.payload.call_type,
            &env.payload.status,
            env.payload.end_reason.as_deref(),
            env.payload.answered_at.is_some(),
            env.payload.duration_seconds,
        );
        assert_eq!(s.oc, "rejected");
        assert_eq!(s.ds, None);
    }

    /// A payload missing a required identity field (caller_id) is POISON — the parse fails so the
    /// consumer drops it rather than posting a summary it can't attribute.
    #[test]
    fn payload_missing_caller_fails_to_parse() {
        let raw = json!({
            "event_id": Uuid::new_v4(),
            "event_type": topics::CALLING_ENDED,
            "occurred_at": "2026-06-24T10:00:00Z",
            "correlation_id": Uuid::new_v4(),
            "payload": {
                "call_id": Uuid::new_v4(),
                "booking_id": Uuid::new_v4(),
                "callee_id": Uuid::new_v4(),
                "call_type": "audio",
                "status": "missed"
            }
        });
        let parsed: Result<EventEnvelope<CallEndedPayload>, _> = serde_json::from_value(raw);
        assert!(parsed.is_err(), "missing caller_id must fail the parse");
    }
}
