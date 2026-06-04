//! pguard notification service — first v2 vertical slice (Phase 1 / KICKOFF §2.4).
//!
//! Decouples notifications: other services emit `pguard.events.*` instead of writing the
//! notification schema (v1 Issue C1), and the direct push path is service-JWT'd. This
//! file is wiring only — router, state, NATS consumer spawn, telemetry. Logic lives in
//! `domain/` (pure), `repo/` (DB), `events/` (consumer), `api/` (transport).

mod api;
mod domain;
mod events;
mod fcm;
mod models;
mod repo;
mod state;

use std::sync::Arc;
use std::time::Duration;

use anyhow::Context;
use axum::routing::{get, post, put};
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig, ServiceJwtConfig};
use shared::db::create_pool;
use shared::redis_client::create_redis_client;

use crate::fcm::{FcmConfig, FcmPusher, NoopPusher, Pusher};
use crate::state::AppState;

const PORT: u16 = 3004;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    observability::init_telemetry("notification");

    // --- config (fail-fast at startup) ---
    let db_config = DatabaseConfig::from_env()?;
    let redis_config = RedisConfig::from_env()?;
    let jwt_config = JwtConfig::from_env()?;
    let service_jwt_config = ServiceJwtConfig::from_env()?;

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;
    let redis_client = create_redis_client(&redis_config.cache_url)?;
    let redis_conn = redis_client
        .get_multiplexed_tokio_connection()
        .await
        .context("Redis cache connection")?;
    let http_client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .connect_timeout(Duration::from_secs(5))
        .build()
        .context("build HTTP client")?;

    // --- push backend (fail-fast unless explicitly disabled for dev) ---
    let pusher: Arc<dyn Pusher> = if std::env::var("FCM_DISABLED").is_ok() {
        tracing::warn!("FCM_DISABLED set — using NoopPusher (no real pushes will be sent)");
        Arc::new(NoopPusher)
    } else {
        Arc::new(FcmPusher::new(FcmConfig::from_env()?, http_client.clone()))
    };

    let state = AppState {
        db,
        redis_conn,
        jwt_config,
        service_jwt_config,
        pusher,
    };

    // --- background JetStream consumer (the event → notification path) ---
    // This is the service's event processor, not fire-and-forget side-effect work; it
    // owns its retry via JetStream redelivery + the idempotency ledger.
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());
    {
        let consumer_state = state.clone();
        tokio::spawn(async move {
            if let Err(e) = events::run_consumer(consumer_state, &nats_url).await {
                tracing::error!("notification consumer stopped: {e}");
            }
        });
    }

    // --- HTTP router ---
    // Route order: register `unread-count` and `read-all` before `{id}/read`.
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route(
            "/tokens",
            post(api::register_token).delete(api::unregister_token),
        )
        .route("/notifications", get(api::list_notifications))
        .route("/notifications/unread-count", get(api::unread_count))
        .route("/notifications/read-all", put(api::mark_all_as_read))
        .route("/notifications/{id}/read", put(api::mark_as_read))
        .route("/notifications/send", post(api::send_notification))
        .route(
            "/internal/notifications/push",
            post(api::internal_push::<AppState>),
        )
        .layer(shared::config::build_cors_layer())
        .with_state(state);

    let addr = format!("0.0.0.0:{PORT}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(%addr, "notification-service listening");
    axum::serve(listener, app).await?;
    Ok(())
}

async fn healthz() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "service": "notification",
        "version": env!("CARGO_PKG_VERSION"),
    }))
}
