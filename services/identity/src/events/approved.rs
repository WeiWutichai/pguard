//! Event CONSUMER — `pguard.events.user.approved` (profile → identity).
//!
//! Closes the approval→login loop the registration slice deferred: admin approves a guard in
//! profile's schema, profile emits `user.approved` (transactional outbox), and identity reacts
//! here by flipping ITS OWN `users.approval_status` to `approved` — so `verify_credentials`
//! (login) now passes. No cross-schema write: profile never touches `identity.*`, identity never
//! touches `profile.*`; the event is the only coupling.
//!
//! Resilience + correctness (mirrors payment's `booking.completed` consumer):
//!  - A durable pull consumer filtered to `user.approved` (JetStream at-least-once).
//!  - Each event is applied **idempotently by `event_id`** (`repo::approve_user_on_event`
//!    claims the id + flips the column in ONE tx), so a redelivery is a safe no-op.
//!  - A message is acked only after a successful apply; a transient failure leaves it for
//!    redelivery (the idempotency ledger absorbs the replay). A malformed envelope is poison —
//!    acked (dropped) so it can't wedge the consumer.

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
/// Intent-scoped durable name (this consumer only ever processes approvals).
const DURABLE: &str = "identity-user-approved";
/// Backoff between reconnect attempts when NATS is down or the stream ends.
const RECONNECT_INTERVAL: Duration = Duration::from_secs(2);

/// The `user.approved` payload identity needs. Only `user_id` drives the flip; `role` is
/// informational metadata (profile sets it from the route). A missing `user_id` fails the
/// parse → the message is treated as poison (dropped + logged), never silently ignored.
#[derive(Debug, Deserialize)]
struct ApprovedPayload {
    user_id: Uuid,
}

/// Run the `user.approved` consumer FOREVER: (re)connect to NATS, drain, and on any
/// connect/stream error log + back off + reconnect. Never returns under normal operation
/// (mirrors the compromise consumer's resilience). Spawned as a background task by `main`.
pub async fn run_consumer(state: AppState, nats_url: &str) {
    loop {
        match connect_and_consume(&state, nats_url).await {
            Ok(()) => tracing::warn!("user.approved consumer stream ended; reconnecting"),
            Err(e) => tracing::warn!("user.approved consumer error: {e}; reconnecting"),
        }
        tokio::time::sleep(RECONNECT_INTERVAL).await;
    }
}

/// One connect+consume session: bind the durable consumer and drain until the stream ends or
/// a fatal error. Returns to [`run_consumer`], which reconnects.
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
                // Only approvals reach this consumer.
                filter_subject: topics::USER_APPROVED.to_string(),
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
        subject = topics::USER_APPROVED,
        "identity user.approved consumer started"
    );

    while let Some(item) = messages.next().await {
        let message = match item {
            Ok(m) => m,
            Err(e) => {
                tracing::warn!("NATS message error: {e}");
                continue;
            }
        };

        // Report this durable consumer's backlog (lag) to Prometheus.
        if let Ok(info) = message.info() {
            observability::record_consumer_lag(DURABLE, info.pending);
        }

        // Verify the HMAC signature BEFORE parse/dedupe/flip — a FORGED `user.approved` (the
        // headline threat: approving an arbitrary account over the open bus) is dropped, counted,
        // and never applied. Fail-closed: missing/invalid signature → drop.
        if !shared_events::verify_message(message.headers.as_ref(), message.payload.as_ref()) {
            observability::record_rejected_event(DURABLE);
            tracing::warn!("dropping user.approved event with missing/invalid signature (forged?)");
            let _ = message.ack().await;
            continue;
        }

        // Parse first. A malformed envelope is POISON — ACK it (drop) instead of letting it
        // redeliver forever and wedge the consumer.
        let envelope: EventEnvelope<ApprovedPayload> =
            match serde_json::from_slice(message.payload.as_ref()) {
                Ok(e) => e,
                Err(e) => {
                    tracing::error!("dropping malformed user.approved envelope (poison): {e}");
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
                // Transient (e.g. DB) error → do NOT ack; JetStream redelivers and the
                // idempotency ledger makes the reprocess safe.
                tracing::error!("user.approved apply failed (will redeliver): {e}");
            }
        }
    }

    Ok(())
}

/// Apply one parsed approval inside a span carrying the event identity + `correlation_id` so
/// the profile→NATS→identity trace stitches together. Returns `Err` only on transient failures.
async fn process(
    state: &AppState,
    envelope: EventEnvelope<ApprovedPayload>,
) -> Result<(), AppError> {
    // Defensive: the filter restricts the subject, but never apply off an unexpected type.
    if envelope.event_type != topics::USER_APPROVED {
        tracing::warn!(event_type = %envelope.event_type, "ignoring unexpected event type");
        return Ok(());
    }

    let span = tracing::info_span!(
        "identity.user_approved",
        event_type = %envelope.event_type,
        event_id = %envelope.event_id,
        correlation_id = %envelope.correlation_id,
    );
    if let Some(tp) = envelope.traceparent.as_deref() {
        observability::set_parent_from_traceparent(&span, tp);
    }
    apply(state, envelope).instrument(span).await
}

/// Drive the idempotent flip, logging the outcome. Runs inside the event span.
async fn apply(state: &AppState, envelope: EventEnvelope<ApprovedPayload>) -> Result<(), AppError> {
    let outcome = repo::approve_user_on_event(
        &state.db,
        envelope.event_id,
        &envelope.event_type,
        envelope.payload.user_id,
    )
    .await?;

    match outcome {
        ApprovedOutcome::Applied => {
            tracing::info!(user_id = %envelope.payload.user_id, "account approved → login enabled")
        }
        ApprovedOutcome::Duplicate => tracing::debug!("duplicate user.approved event; skipped"),
        ApprovedOutcome::UserNotFound => {
            tracing::warn!(user_id = %envelope.payload.user_id, "user.approved for unknown user; recorded")
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// The envelope/payload parse the consumer relies on: a well-formed user.approved event
    /// yields the user_id. Pure (no DB/NATS).
    #[test]
    fn parses_approved_envelope() {
        let user_id = Uuid::new_v4();
        let raw = json!({
            "event_id": Uuid::new_v4(),
            "event_type": topics::USER_APPROVED,
            "occurred_at": "2026-06-07T10:00:00Z",
            "correlation_id": Uuid::new_v4(),
            "payload": { "user_id": user_id, "role": "guard", "approved_at": "2026-06-07T10:00:00Z" }
        });
        let env: EventEnvelope<ApprovedPayload> = serde_json::from_value(raw).expect("parse");
        assert_eq!(env.event_type, topics::USER_APPROVED);
        assert_eq!(env.payload.user_id, user_id);
    }
}

/// END-TO-END against REAL infra (Postgres + NATS JetStream): the approval→login loop's full
/// vertical — register a PENDING guard → login BLOCKED → publish `user.approved` to NATS (what
/// profile's relay emits) → identity's consumer flips `users.approval_status` → login ALLOWED —
/// AND a replay of the same event_id is idempotent (still approved, no error).
///
/// Gated on BOTH `DATABASE_URL` (identity 0001+0003+0004 migrated) and `NATS_URL`; hermetic
/// (SKIP) when either is absent. Run:
///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5440/pguard \
///   NATS_URL=nats://localhost:4222 \
///     cargo test -p pguard-identity -- e2e_register_approve_login --nocapture
#[cfg(test)]
mod e2e_tests {
    use super::*;
    use crate::state::AppState;
    use shared::config::{JwtConfig, ServiceJwtConfig};
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-approval-e2e-test!!!!";

    #[tokio::test]
    async fn e2e_register_approve_login_is_idempotent() {
        let (Ok(db_url), Ok(nats_url)) = (std::env::var("DATABASE_URL"), std::env::var("NATS_URL"))
        else {
            eprintln!(
                "SKIP: DATABASE_URL + NATS_URL required for the approval e2e (hermetic default)"
            );
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&db_url)
            .await
            .expect("connect real Postgres");
        let redis = match std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
        {
            Ok(url) => shared::redis_client::create_connection_manager(&url)
                .await
                .expect("redis conn"),
            Err(_) => {
                eprintln!("SKIP: TEST_REDIS_URL/REDIS_CACHE_URL required (AppState needs Redis)");
                return;
            }
        };

        // The consumer now verifies HMAC signatures, so the test must publish SIGNED with the
        // same key. Set the process signing key (first-write-wins; shared across this binary).
        shared_events::init_signing_key(SECRET.as_bytes());

        // 1) Register a PENDING guard (as /auth/register does).
        let phone: String = format!(
            "0{}",
            uuid::Uuid::new_v4()
                .simple()
                .to_string()
                .chars()
                .filter(|c| c.is_ascii_digit())
                .take(9)
                .collect::<String>()
        );
        let pin_hash = "a".repeat(64);
        let user_id = repo::upsert_pending_user(&pool, &phone, "guard", &pin_hash)
            .await
            .expect("register pending");

        // 2) Login is BLOCKED while pending.
        assert!(
            repo::verify_credentials(&pool, &phone, &pin_hash)
                .await
                .is_err(),
            "pending account cannot log in"
        );

        // 3) Start identity's consumer over a real AppState.
        let state = AppState {
            db: pool.clone(),
            redis_conn: redis,
            jwt_config: JwtConfig {
                secret: SECRET.to_string(),
                expiry_minutes: 15,
                encoding_key: jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes()),
                decoding_key: jsonwebtoken::DecodingKey::from_secret(SECRET.as_bytes()),
            },
            service_jwt_config: ServiceJwtConfig {
                encoding_key: jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes()),
                decoding_key: jsonwebtoken::DecodingKey::from_secret(SECRET.as_bytes()),
                ttl_secs: 60,
            },
            export_client: crate::export_client::ExportClient::new(
                reqwest::Client::new(),
                jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes()),
                60,
                vec![],
            ),
            totp_enc_key: [0u8; 32],
        };

        let client = shared_events::connect(&nats_url)
            .await
            .expect("nats connect");
        let js = async_nats::jetstream::new(client);
        js.get_or_create_stream(async_nats::jetstream::stream::Config {
            name: STREAM.to_string(),
            subjects: vec![SUBJECTS.to_string()],
            ..Default::default()
        })
        .await
        .expect("ensure stream");

        let consumer_state = state.clone();
        let consumer_nats = nats_url.clone();
        let consumer = tokio::spawn(async move {
            run_consumer(consumer_state, &consumer_nats).await;
        });
        tokio::time::sleep(Duration::from_millis(500)).await; // let the durable bind

        // 4) Publish user.approved (exactly what profile's relay emits from its outbox).
        let envelope = EventEnvelope::new(
            topics::USER_APPROVED,
            uuid::Uuid::new_v4(),
            serde_json::json!({ "user_id": user_id, "role": "guard", "approved_at": chrono::Utc::now() }),
        );
        let bytes = serde_json::to_vec(&envelope).expect("serialize");
        shared_events::publish_signed(&js, topics::USER_APPROVED, &bytes)
            .await
            .expect("signed publish");

        // 5) Poll until login succeeds (bounded ~10s).
        let mut ok = false;
        for _ in 0..50 {
            if repo::verify_credentials(&pool, &phone, &pin_hash)
                .await
                .is_ok()
            {
                ok = true;
                break;
            }
            tokio::time::sleep(Duration::from_millis(200)).await;
        }
        assert!(
            ok,
            "login allowed after the approval event flipped approval_status"
        );

        // 6) Replay the SAME event → idempotent (still approved, processed_events dedupes).
        shared_events::publish_signed(&js, topics::USER_APPROVED, &bytes)
            .await
            .expect("signed replay");
        tokio::time::sleep(Duration::from_millis(800)).await;
        assert!(
            repo::verify_credentials(&pool, &phone, &pin_hash)
                .await
                .is_ok(),
            "still approved after replay"
        );

        // teardown
        consumer.abort();
        let _ = sqlx::query("DELETE FROM identity.processed_events WHERE event_id = $1")
            .bind(envelope.event_id)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM identity.users WHERE id = $1")
            .bind(user_id)
            .execute(&pool)
            .await;
    }

    /// THE forgery defense: a FORGED (unsigned) `user.approved` for a pending account is
    /// DROPPED by the consumer — the account is NOT approved and still cannot log in. This is
    /// the exact attack the slice closes (approving an arbitrary account over the open bus).
    /// Gated on DATABASE_URL + NATS_URL + a test Redis.
    #[tokio::test]
    async fn e2e_forged_user_approved_is_dropped() {
        let (Ok(db_url), Ok(nats_url)) = (std::env::var("DATABASE_URL"), std::env::var("NATS_URL"))
        else {
            eprintln!("SKIP: DATABASE_URL + NATS_URL required for the forged-event e2e");
            return;
        };
        let Ok(redis_url) =
            std::env::var("TEST_REDIS_URL").or_else(|_| std::env::var("REDIS_CACHE_URL"))
        else {
            eprintln!("SKIP: TEST_REDIS_URL/REDIS_CACHE_URL required (AppState needs Redis)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&db_url)
            .await
            .expect("connect Postgres");
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .expect("redis conn");

        // The consumer verifies against this key; the attacker does NOT have it.
        shared_events::init_signing_key(SECRET.as_bytes());

        // Seed a PENDING guard.
        let phone: String = format!(
            "0{}",
            uuid::Uuid::new_v4()
                .simple()
                .to_string()
                .chars()
                .filter(|c| c.is_ascii_digit())
                .take(9)
                .collect::<String>()
        );
        let pin_hash = "a".repeat(64);
        let user_id = repo::upsert_pending_user(&pool, &phone, "guard", &pin_hash)
            .await
            .expect("register pending");

        let state = AppState {
            db: pool.clone(),
            redis_conn: redis,
            jwt_config: JwtConfig {
                secret: SECRET.to_string(),
                expiry_minutes: 15,
                encoding_key: jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes()),
                decoding_key: jsonwebtoken::DecodingKey::from_secret(SECRET.as_bytes()),
            },
            service_jwt_config: ServiceJwtConfig {
                encoding_key: jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes()),
                decoding_key: jsonwebtoken::DecodingKey::from_secret(SECRET.as_bytes()),
                ttl_secs: 60,
            },
            export_client: crate::export_client::ExportClient::new(
                reqwest::Client::new(),
                jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes()),
                60,
                vec![],
            ),
            totp_enc_key: [0u8; 32],
        };

        let client = shared_events::connect(&nats_url)
            .await
            .expect("nats connect");
        let js = async_nats::jetstream::new(client);
        js.get_or_create_stream(async_nats::jetstream::stream::Config {
            name: STREAM.to_string(),
            subjects: vec![SUBJECTS.to_string()],
            ..Default::default()
        })
        .await
        .expect("ensure stream");

        let consumer = tokio::spawn({
            let s = state.clone();
            let n = nats_url.clone();
            async move { run_consumer(s, &n).await }
        });
        tokio::time::sleep(Duration::from_millis(500)).await;

        // ATTACK: publish a well-formed but UNSIGNED user.approved (no signature header) —
        // exactly what an attacker with raw bus access (but no signing key) could send.
        let envelope = EventEnvelope::new(
            topics::USER_APPROVED,
            uuid::Uuid::new_v4(),
            serde_json::json!({ "user_id": user_id, "role": "guard" }),
        );
        let bytes = serde_json::to_vec(&envelope).expect("serialize");
        js.publish(topics::USER_APPROVED.to_string(), bytes.into())
            .await
            .expect("publish forged")
            .await
            .expect("publish ack");

        // Give the consumer time to receive + DROP it.
        tokio::time::sleep(Duration::from_millis(1500)).await;

        // The forged event was dropped: the account is STILL pending and cannot log in.
        let (status,): (String,) =
            sqlx::query_as("SELECT approval_status::text FROM identity.users WHERE id = $1")
                .bind(user_id)
                .fetch_one(&pool)
                .await
                .expect("read status");
        assert_eq!(
            status, "pending",
            "a forged (unsigned) user.approved must NOT flip approval"
        );
        assert!(
            repo::verify_credentials(&pool, &phone, &pin_hash)
                .await
                .is_err(),
            "forged approval must not enable login"
        );
        // The forged event_id must NOT have been recorded as processed (it never reached the
        // dedupe/business layer — it was dropped at the signature boundary).
        let (claimed,): (i64,) = sqlx::query_as(
            "SELECT count(*)::bigint FROM identity.processed_events WHERE event_id = $1",
        )
        .bind(envelope.event_id)
        .fetch_one(&pool)
        .await
        .expect("count processed");
        assert_eq!(
            claimed, 0,
            "a dropped forged event never reaches the dedupe ledger"
        );

        // teardown
        consumer.abort();
        let _ = sqlx::query("DELETE FROM identity.users WHERE id = $1")
            .bind(user_id)
            .execute(&pool)
            .await;
    }
}
