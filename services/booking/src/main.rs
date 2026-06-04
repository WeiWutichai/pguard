//! pguard booking service — requests, assignments, state transitions (split from v1
//! booking). Phase 1 producer side: status changes emit `pguard.events.booking.*` via a
//! TRANSACTIONAL OUTBOX so the notification consumer receives them — no cross-schema
//! writes (v1 Issue C1).
//!
//! This file is wiring only — router, state, the outbox relay spawn, telemetry. Logic
//! lives in `domain/` (pure state machine + event mapping), `repo/` (DB + atomic
//! status+outbox tx), `events/` (the relay → NATS), `api/` (transport).

mod api;
mod domain;
mod events;
mod models;
mod repo;
mod state;

use anyhow::Context;
use axum::routing::{get, post};
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig};
use shared::db::create_pool;
use shared::redis_client::create_redis_client;

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

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;
    let redis_client = create_redis_client(&redis_config.cache_url)?;
    let redis_conn = redis_client
        .get_multiplexed_tokio_connection()
        .await
        .context("Redis cache connection")?;

    let state = AppState {
        db: db.clone(),
        redis_conn,
        jwt_config,
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
