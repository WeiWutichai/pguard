//! pguard presence service — real-time guard GPS (renamed tracking).
//!
//! Owns schema `presence`:
//!  - **GPS-over-WebSocket ingress** (`/ws/track`, Bearer-on-upgrade, guard-only): validated +
//!    rate-limited fixes upsert the live position, append history, and republish to Redis
//!    pub/sub for the admin map (`api::ws`).
//!  - **IDOR-safe reads** (`/locations` admin-only bulk; `/guards/{id}/location|history`
//!    own/active-booking-customer/admin) — `api`.
//!  - **Event-derived authz read-model**: a durable consumer projects `pguard.events.booking.*`
//!    into `guard_assignments` so the customer IDOR check needs no cross-schema read
//!    (`events::consumer`).
//!  - **PDPA retention** (90-day purge of the SENSITIVE `location_history`) — `retention`.
//!
//! Wiring only — config, db pool, Redis (cache + pub/sub), the retention + consumer task spawns,
//! telemetry, CORS. Logic lives in `domain` (pure), `repo` (sqlx), `api` (transport), `events`.

mod api;
mod domain;
mod events;
mod models;
mod repo;
mod retention;
mod state;

use std::time::Duration;

use anyhow::Context;
use axum::routing::get;
use axum::{Json, Router};
use serde_json::{json, Value};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig};
use shared::db::create_pool;
use shared::redis_client::create_redis_client;

use crate::state::{AppState, DbBookingAuthz};

const SERVICE_NAME: &str = "presence";
const VERSION: &str = env!("CARGO_PKG_VERSION");
const PORT: u16 = 3009;
/// GPS-history retention window — PDPA §7.3 recommends 90 days for this sensitive store.
const RETENTION_DAYS: i64 = 90;
/// How often the purge runs (hourly by default).
const PURGE_INTERVAL_SECS: u64 = 3600;

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
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;

    // Cache connection: the AuthUser revocation blocklist + the WS re-auth tick.
    let redis_cache = create_redis_client(&redis_config.cache_url)?
        .get_multiplexed_tokio_connection()
        .await
        .context("Redis cache connection")?;
    // Pub/sub connection: republish raw GPS to the admin live map. Falls back to the cache URL
    // when REDIS_PUBSUB_URL is unset (single-node dev).
    let pubsub_url = redis_config
        .pubsub_url
        .clone()
        .unwrap_or_else(|| redis_config.cache_url.clone());
    let redis_pub = create_redis_client(&pubsub_url)?
        .get_multiplexed_tokio_connection()
        .await
        .context("Redis pub/sub connection")?;

    let state = AppState {
        db: db.clone(),
        redis_cache,
        redis_pub,
        jwt_config,
        booking_authz: DbBookingAuthz { db: db.clone() },
    };

    // --- scheduled GPS-history retention purge (PDPA §7.3) ---
    let retention_days = env_i64("LOCATION_RETENTION_DAYS", RETENTION_DAYS);
    let purge_interval =
        Duration::from_secs(env_u64("LOCATION_PURGE_INTERVAL_SECS", PURGE_INTERVAL_SECS));
    {
        let pool = db.clone();
        tokio::spawn(async move {
            retention::run_retention(pool, retention_days, purge_interval).await;
        });
    }

    // --- booking-events consumer → IDOR read-model projection ---
    {
        let consumer_db = db.clone();
        tokio::spawn(async move {
            events::consumer::run_consumer(consumer_db, &nats_url).await;
        });
    }

    // --- HTTP/WS router (resource paths; the gateway adds the /v1 prefix) ---
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/metrics", get(observability::metrics_handler))
        .route("/ws/track", get(api::ws::ws_track::<AppState>))
        .route("/locations", get(api::list_locations::<AppState>))
        .route(
            "/guards/{id}/location",
            get(api::guard_location::<AppState>),
        )
        .route("/guards/{id}/history", get(api::guard_history::<AppState>))
        .layer(shared::config::build_cors_layer())
        .layer(axum::middleware::from_fn(
            observability::telemetry_middleware,
        ))
        .with_state(state);

    let addr = format!("0.0.0.0:{PORT}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(service = SERVICE_NAME, %addr, "presence-service listening");
    axum::serve(listener, app).await?;
    Ok(())
}

/// Positive integer from env, else `default`.
fn env_i64(key: &str, default: i64) -> i64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .filter(|&n| n > 0)
        .unwrap_or(default)
}

fn env_u64(key: &str, default: u64) -> u64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .filter(|&n| n > 0)
        .unwrap_or(default)
}

/// Liveness/readiness probe.
async fn healthz() -> Json<Value> {
    Json(json!({ "status": "ok", "service": SERVICE_NAME, "version": VERSION }))
}
