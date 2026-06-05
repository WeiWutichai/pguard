//! pguard booking service — requests, assignments, state transitions (split from v1
//! booking). Phase 1 producer side: status changes emit `pguard.events.booking.*` via a
//! TRANSACTIONAL OUTBOX so the notification consumer receives them — no cross-schema
//! writes (v1 Issue C1).
//!
//! This file is wiring only — router, state, the outbox relay spawn, telemetry. Logic
//! lives in `domain/` (pure state machine + event mapping), `repo/` (DB + atomic
//! status+outbox tx), `events/` (the relay → NATS), `api/` (transport).

mod api;
mod discovery_client;
mod domain;
mod events;
mod models;
mod repo;
mod state;

use anyhow::Context;
use axum::routing::{get, post};
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig, ServiceJwtConfig};
use shared::db::create_pool;
use shared::redis_client::create_redis_client;

use crate::discovery_client::HttpDiscoveryClient;
use crate::state::AppState;

const SERVICE_NAME: &str = "booking";
const PORT: u16 = 3005;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    observability::init_telemetry(SERVICE_NAME);

    // --- config (fail-fast at startup) ---
    let db_config = DatabaseConfig::from_env()?;
    let redis_config = RedisConfig::from_env()?;
    let jwt_config = JwtConfig::from_env()?;
    // Guards the `/internal/*` read the payment/rating services call, and signs the
    // discovery reads booking MINTS to profile + rating (separate secret).
    let service_jwt_config = ServiceJwtConfig::from_env()?;
    // Discovery upstreams (service-JWT'd internal reads).
    let profile_url =
        std::env::var("PROFILE_URL").unwrap_or_else(|_| "http://localhost:3002".to_string());
    let rating_url =
        std::env::var("RATING_URL").unwrap_or_else(|_| "http://localhost:3007".to_string());

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;
    let redis_client = create_redis_client(&redis_config.cache_url)?;
    let redis_conn = redis_client
        .get_multiplexed_tokio_connection()
        .await
        .context("Redis cache connection")?;

    // Bounded timeouts so one stalled upstream can't hang a discovery fan-out (each lookup
    // then surfaces as a generic error → best-effort default for that guard).
    let discovery_http = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_millis(500))
        .timeout(std::time::Duration::from_secs(2))
        .build()
        .context("build discovery HTTP client")?;
    let discovery = HttpDiscoveryClient::new(
        discovery_http,
        profile_url,
        rating_url,
        service_jwt_config.encoding_key.clone(),
        service_jwt_config.ttl_secs,
    );

    let state = AppState {
        db: db.clone(),
        redis_conn,
        jwt_config,
        service_jwt_config,
        discovery,
    };

    // --- background outbox relay (the producer half of Phase 1) ---
    // This is the service's event publisher, not fire-and-forget side-effect work: each
    // event was already durably committed to the outbox in the same tx as the status
    // change. The relay owns its own retry; a NATS outage never crashes booking.
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
            "/bookings",
            post(api::create_booking::<AppState>).get(api::list_bookings::<AppState>),
        )
        .route("/bookings/{id}", get(api::get_booking::<AppState>))
        // Discovery: approved guard catalog (profile) + rating summaries (rating).
        .route("/available-guards", get(api::available_guards::<AppState>))
        .route(
            "/bookings/{id}/accept",
            post(api::accept_booking::<AppState>),
        )
        .route(
            "/bookings/{id}/decline",
            post(api::decline_booking::<AppState>),
        )
        .route(
            "/bookings/{id}/en-route",
            post(api::en_route_booking::<AppState>),
        )
        .route(
            "/bookings/{id}/arrived",
            post(api::arrived_booking::<AppState>),
        )
        .route(
            "/bookings/{id}/complete",
            post(api::complete_booking::<AppState>),
        )
        // Service-to-service read (service-JWT'd) — the payment service verifies a charge
        // against the authoritative booking here. Not exposed through the public gateway.
        .route(
            "/internal/bookings/{id}",
            get(api::get_internal_booking::<AppState>),
        )
        .layer(shared::config::build_cors_layer())
        .with_state(state);

    let addr = format!("0.0.0.0:{PORT}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(service = SERVICE_NAME, %addr, "booking-service listening");
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
