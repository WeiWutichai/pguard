//! pguard calling service — WebRTC voice/video SIGNALING (split from v1 booking).
//!
//! v2 design (CLAUDE.md):
//!  - WS `/ws/call` signaling with **Bearer-on-upgrade** auth (never a token in the URL).
//!  - A call may only be placed between the two participants of a booking — verified via
//!    booking's `/internal/bookings/{id}` over a service-JWT; the callee is DERIVED, never
//!    client-supplied (IDOR protection).
//!  - State changes emit `pguard.events.calling.*` in the SAME tx (transactional outbox);
//!    notification consumes them. No cross-schema writes.
//!  - The MEDIA plane is the Node mediasoup SFU (brokered by calling over a service-JWT).
//!
//! Wiring only — config, db pool, redis, the booking reqwest client, the WS registry, the
//! outbox relay spawn, telemetry, CORS. Logic lives in `domain/` (pure state machine),
//! `repo/` (atomic state writes + outbox), `events/` (relay → NATS), `booking_client/`
//! (service-JWT'd authz read), `api/` (REST + WS transport).

mod api;
mod booking_client;
mod domain;
mod events;
mod models;
mod repo;
mod state;

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Context;
use axum::routing::{get, put};
use axum::{Json, Router};
use tokio::sync::Mutex;

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig, ServiceJwtConfig};
use shared::db::create_pool;
use shared::redis_client::create_redis_client;

use crate::booking_client::HttpBookingReader;
use crate::state::AppState;

const SERVICE_NAME: &str = "calling";
const PORT: u16 = 3008;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    observability::init_telemetry(SERVICE_NAME);

    // --- config (fail-fast at startup) ---
    let db_config = DatabaseConfig::from_env()?;
    let redis_config = RedisConfig::from_env()?;
    let jwt_config = JwtConfig::from_env()?;
    // calling MINTS service-JWTs (to authorize a call against booking); it exposes no
    // /internal endpoint, so it needs only the encoding side of the shared secret.
    let service_jwt_config = ServiceJwtConfig::from_env()?;
    let booking_url =
        std::env::var("BOOKING_URL").unwrap_or_else(|_| "http://localhost:3005".to_string());

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;
    let redis_client = create_redis_client(&redis_config.cache_url)?;
    let redis_conn = redis_client
        .get_multiplexed_tokio_connection()
        .await
        .context("Redis cache connection")?;

    // Bounded timeouts so a hung booking read can't stall a call initiate.
    let booking_http = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_millis(500))
        .timeout(std::time::Duration::from_secs(5))
        .build()
        .context("build booking HTTP client")?;
    let booking_reader = HttpBookingReader::new(
        booking_http,
        booking_url,
        service_jwt_config.encoding_key.clone(),
        service_jwt_config.ttl_secs,
    );

    let state = AppState {
        db: db.clone(),
        redis_conn,
        jwt_config,
        booking_reader,
        registry: Arc::new(Mutex::new(HashMap::new())),
    };

    // --- background outbox relay (publishes calling.* events) ---
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());
    {
        let relay_db = db.clone();
        tokio::spawn(async move {
            events::run_relay(relay_db, nats_url).await;
        });
    }

    // --- HTTP/WS router (resource paths; gateway adds the /v1 prefix) ---
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route(
            "/calls/initiate",
            axum::routing::post(api::initiate_call::<AppState>),
        )
        .route("/calls/{id}", get(api::get_call::<AppState>))
        .route("/calls/{id}/accept", put(api::accept_call::<AppState>))
        .route("/calls/{id}/reject", put(api::reject_call::<AppState>))
        .route(
            "/calls/{id}/connected",
            put(api::connected_call::<AppState>),
        )
        .route("/calls/{id}/end", put(api::end_call::<AppState>))
        .route("/ws/call", get(api::ws::ws_call::<AppState>))
        .layer(shared::config::build_cors_layer())
        .with_state(state);

    let addr = format!("0.0.0.0:{PORT}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(service = SERVICE_NAME, %addr, "calling-service listening");
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
