//! pguard chat service — booking-scoped messaging (REST + WebSocket, N+1 fixed).
//!
//! v2 design (CLAUDE.md + docs/PHASE-chat-spec.md):
//!  - REST: create/list (N+1-free, no cross-schema JOIN) + messages + per-role read receipts +
//!    magic-byte-validated attachments (own SigV4 presigning).
//!  - WS `/ws/chat`: **Bearer-on-upgrade** (never a token in the URL); `conversation_id` sent
//!    AFTER open; participant gate on the wire; alignment by `sender_role`; Redis pub/sub
//!    (`chat:{id}`) for cross-instance fan-out.
//!  - A sent message enqueues `pguard.events.chat.message_sent` in the SAME tx (transactional
//!    outbox); a background relay publishes it; notification consumes. No cross-schema writes.
//!  - Booking pushes lifecycle status onto `/internal/conversations/by-request/{id}/status`
//!    (service-JWT) so the read-only gate stays current.
//!
//! Wiring only — config, primary + read pools, redis (cache + pub/sub), the S3 client, the
//! outbox relay spawn, telemetry, CORS. Logic lives in `domain/` (pure), `repo/` (DB + outbox),
//! `s3/` (upload + presign), `events/` (relay + pub/sub), `api/` (REST + WS).

mod api;
mod booking_client;
mod domain;
mod events;
mod models;
mod repo;
mod s3;
mod state;

use anyhow::Context;
use axum::extract::DefaultBodyLimit;
use axum::routing::{get, post, put};
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig, S3Config, ServiceJwtConfig};
use shared::db::{create_pool, create_read_pool};
use shared::redis_client::{create_connection_manager, create_redis_client};

use crate::booking_client::HttpBookingReader;
use crate::s3::S3Client;
use crate::state::AppState;

const SERVICE_NAME: &str = "chat";
const PORT: u16 = 3010;

/// Multipart upload body cap — a little above the 200MB video limit for multipart overhead; the
/// per-kind size + magic-byte gate (`domain::validate_upload`) is the precise check.
const MAX_UPLOAD_BYTES: usize = 210 * 1024 * 1024;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _telemetry = observability::init_telemetry(SERVICE_NAME);
    // Load the event-signing key (EVENT_SIGNING_SECRET, ≥64 chars) once at startup — fail-fast
    // so this service never publishes/consumes unsigned NATS events.
    shared_events::init_signing_key_from_env().map_err(|e| anyhow::anyhow!(e))?;

    // --- config (fail-fast at startup) ---
    let db_config = DatabaseConfig::from_env()?;
    let redis_config = RedisConfig::from_env()?;
    let jwt_config = JwtConfig::from_env()?;
    // chat exposes a service-JWT'd `/internal` endpoint (booking → request-status push) AND mints
    // its own service-JWT to read booking's `/internal/bookings/{id}` (authoritative conversation
    // identity at create time) — so it needs BOTH sides of the shared service secret.
    let service_jwt_config = ServiceJwtConfig::from_env()?;
    // Booking internal-read upstream (service-JWT'd; makes conversation identity authoritative at
    // create time). Same env var the other booking-internal consumers use (calling/rating).
    let booking_url =
        std::env::var("BOOKING_URL").unwrap_or_else(|_| "http://localhost:3005".to_string());
    let s3_config = S3Config::from_env()?;
    let s3_region = std::env::var("S3_REGION").unwrap_or_else(|_| "us-east-1".to_string());
    // Client-facing GET URLs are signed for the PUBLIC host (falls back to the internal endpoint
    // for single-host dev). NOT a post-hoc host rewrite — that would break the SigV4 signature.
    // An empty value (e.g. an unset `${S3_PUBLIC_URL:-}` in compose) is treated as absent.
    let s3_public_url = std::env::var("S3_PUBLIC_URL")
        .ok()
        .filter(|s| !s.trim().is_empty());

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;
    let db_read = create_read_pool(&db_config).await?;

    // Reconnecting manager (not a one-shot MultiplexedConnection) so a Redis restart self-heals
    // instead of wedging the AuthUser revocation check + WS re-auth tick forever (chaos case 3).
    let redis_conn = create_connection_manager(&redis_config.cache_url)
        .await
        .context("Redis cache connection (reconnecting)")?;

    // The pub/sub plane (separate URL/db when provided) — a reconnecting manager for PUBLISH + the
    // client each WS session opens a dedicated SUBSCRIBE connection on (the subscriber stays a raw
    // Client: a new session reconnects on its own; an in-flight subscriber that drops is replaced
    // when the client reconnects after its re-auth tick fails closed).
    let pubsub_url = redis_config
        .pubsub_url
        .clone()
        .unwrap_or_else(|| redis_config.cache_url.clone());
    let pubsub_client = create_redis_client(&pubsub_url)?;
    let pubsub_conn = create_connection_manager(&pubsub_url)
        .await
        .context("Redis pub/sub connection (reconnecting)")?;

    let s3_http = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_secs(2))
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .context("build S3 HTTP client")?;
    let s3 = S3Client::new(
        s3_http,
        s3_config.endpoint,
        s3_public_url,
        s3_config.bucket,
        s3_region,
        s3_config.access_key,
        s3_config.secret_key,
    );

    // Bounded timeouts so a stalled booking can't hang a create-conversation request.
    let booking_http = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_millis(500))
        .timeout(std::time::Duration::from_secs(2))
        .build()
        .context("build booking HTTP client")?;
    let booking = HttpBookingReader::new(
        booking_http,
        booking_url,
        service_jwt_config.encoding_key,
        service_jwt_config.ttl_secs,
    );

    // Clone the booking reader for the call-summary consumer BEFORE `booking` moves into state
    // (it find-or-creates the conversation from the authoritative booking when neither party ever
    // opened the chat). Cheap clone — reqwest::Client is ref-counted, the key/url are small.
    let consumer_booking = booking.clone();

    let state = AppState {
        db: db.clone(),
        db_read,
        redis_conn,
        pubsub_conn,
        pubsub_client,
        jwt_config,
        service_decoding_key: service_jwt_config.decoding_key,
        s3,
        booking,
    };

    // --- background outbox relay (publishes chat.message_sent events) ---
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());
    {
        let relay_db = db.clone();
        let relay_nats = nats_url.clone();
        tokio::spawn(async move {
            events::run_relay(relay_db, relay_nats).await;
        });
    }

    // --- background call-summary consumer (subscribes to terminal calling.* → posts a
    // server-generated `system` summary message; the SECURITY FIX: clients can no longer forge a
    // `system` message to silence the victim's push, and the summary is emitted server-side). ---
    {
        let consumer_db = db.clone();
        tokio::spawn(async move {
            events::consumer::run_consumer(consumer_db, nats_url, consumer_booking).await;
        });
    }

    // --- HTTP/WS router (resource paths; gateway adds the /v1 prefix) ---
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/conversations", post(api::create_conversation::<AppState>))
        .route("/conversations", get(api::list_conversations::<AppState>))
        // Admin cross-user conversation list + the ENRICHED message audit (both admin-role gated).
        // Distinct /admin/conversations prefix; the gateway routes both via the /admin/conversations
        // rule (prefix match covers the /{id}/messages subpath). The audit endpoint returns
        // RENDERABLE data (parsed kind, presigned media URL, structured call event) — distinct from
        // the participant /conversations/{id}/messages which returns raw `content` for the mobile app.
        .route(
            "/admin/conversations",
            get(api::admin_list_conversations::<AppState>),
        )
        .route(
            "/admin/conversations/{id}/messages",
            get(api::admin_list_messages::<AppState>),
        )
        .route(
            "/conversations/{id}/messages",
            get(api::list_messages::<AppState>),
        )
        .route("/conversations/{id}/read", put(api::mark_read::<AppState>))
        .route(
            "/attachments",
            post(api::upload_attachment::<AppState>).layer(DefaultBodyLimit::max(MAX_UPLOAD_BYTES)),
        )
        .route("/attachments/{id}", get(api::get_attachment::<AppState>))
        .route(
            "/internal/conversations/by-request/{request_id}/status",
            put(api::internal_set_request_status::<AppState>),
        )
        .route("/ws/chat", get(api::ws::ws_chat::<AppState>))
        .route("/metrics", get(observability::metrics_handler))
        .layer(shared::config::build_cors_layer())
        .layer(axum::middleware::from_fn(
            observability::telemetry_middleware,
        ))
        .with_state(state);

    let addr = format!("0.0.0.0:{PORT}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(service = SERVICE_NAME, %addr, "chat-service listening");
    axum::serve(listener, app).await?;
    Ok(())
}

/// Liveness/readiness probe.
async fn healthz() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "service": SERVICE_NAME,
        "version": env!("CARGO_PKG_VERSION"),
    }))
}
