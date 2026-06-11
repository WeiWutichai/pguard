//! pguard rating service — guard reviews, admin visibility moderation, rating summary
//! (split from v1 booking god-service).
//!
//! v2 design (CLAUDE.md):
//!  - A review NEVER trusts client-supplied guard/customer/status. It MINTS a service-JWT and
//!    verifies against booking's `/internal/bookings/{id}` (caller must be the booking's
//!    customer; booking must be `completed`; guard_id comes from the booking).
//!  - One review per assignment (DB UNIQUE) — a duplicate submit → 409.
//!  - `rating.submitted` is emitted in the SAME tx as the INSERT (transactional outbox);
//!    notification consumes it. rating NEVER writes the notification schema.
//!  - Public discovery filters `is_visible = true`; admin-hidden reviews never surface.
//!
//! This file is wiring only — configs, db pool, redis, the booking reqwest client, the outbox
//! relay spawn, telemetry, CORS. Logic lives in `domain/` (pure validation + aggregation),
//! `repo/` (atomic submit + outbox + reads), `events/` (relay → NATS), `booking_client/`
//! (the service-JWT'd cross-service read), `api/` (transport).

mod api;
mod booking_client;
mod domain;
mod events;
mod models;
mod repo;
mod state;

use anyhow::Context;
use axum::routing::{get, post, put};
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig, ServiceJwtConfig};
use shared::db::{create_pool, create_read_pool};
use shared::redis_client::create_connection_manager;

use crate::booking_client::HttpBookingReader;
use crate::state::AppState;

const SERVICE_NAME: &str = "rating";
const PORT: u16 = 3007;

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
    // rating MINTS service-JWTs (to read booking) AND VERIFIES them (its own internal read),
    // so it needs both halves of the shared SERVICE_JWT_SECRET.
    let service_jwt_config = ServiceJwtConfig::from_env()?;
    let booking_url =
        std::env::var("BOOKING_URL").unwrap_or_else(|_| "http://localhost:3005".to_string());

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;
    // Read-replica pool (C5.3) for the review-list + summary reads; primary fallback.
    let db_read = create_read_pool(&db_config).await?;
    // Reconnecting manager (not a one-shot MultiplexedConnection) so a Redis restart self-heals
    // in the background instead of wedging the AuthUser revocation check forever (chaos case 3).
    let redis_conn = create_connection_manager(&redis_config.cache_url)
        .await
        .context("Redis cache connection (reconnecting)")?;

    let booking_reader = HttpBookingReader::new(
        reqwest::Client::new(),
        booking_url,
        service_jwt_config.encoding_key.clone(),
        service_jwt_config.ttl_secs,
    );

    let state = AppState {
        db: db.clone(),
        db_read,
        redis_conn,
        jwt_config,
        service_decoding_key: service_jwt_config.decoding_key.clone(),
        booking_reader,
    };

    // --- background outbox relay (publishes rating.submitted) ---
    // Each event was already durably committed to the outbox in the same tx as the review;
    // the relay owns its retry, so a NATS outage never crashes rating.
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());
    {
        let relay_db = db.clone();
        tokio::spawn(async move {
            events::run_relay(relay_db, nats_url).await;
        });
    }

    // --- HTTP router (resource paths; gateway adds the /v1 prefix) ---
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route(
            "/assignments/{id}/review",
            post(api::submit_review::<AppState>),
        )
        .route("/guards/{id}/ratings", get(api::guard_ratings::<AppState>))
        .route("/admin/reviews", get(api::list_admin_reviews::<AppState>))
        .route(
            "/admin/reviews/{id}/visibility",
            put(api::set_review_visibility::<AppState>),
        )
        .route(
            "/internal/guards/{id}/rating-summary",
            get(api::internal_rating_summary::<AppState>),
        )
        .route(
            "/internal/users/{user_id}/export",
            get(api::internal_export_user::<AppState>),
        )
        .route("/metrics", get(observability::metrics_handler))
        .layer(shared::config::build_cors_layer())
        .layer(axum::middleware::from_fn(
            observability::telemetry_middleware,
        ))
        .with_state(state);

    let addr = format!("0.0.0.0:{PORT}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(service = SERVICE_NAME, %addr, "rating-service listening");
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
