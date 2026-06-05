//! pguard identity service — auth-core foundation (split from v1 auth).
//!
//! ISSUES + manages user JWTs that every other service validates: login, refresh
//! (RFC 6749 §6 rotation + reuse detection), logout, /me, and a service-JWT'd
//! force-revoke-all. Also the consumer of `pguard.events.user.compromised`.
//!
//! This file is wiring only — router, state, NATS consumer spawn, telemetry. Logic lives
//! in `domain/` (pure), `repo/` (DB), `events/` (consumer), `api/` (transport).

mod api;
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

use crate::state::AppState;

const SERVICE_NAME: &str = "identity";
const PORT: u16 = 3001;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _telemetry = observability::init_telemetry(SERVICE_NAME);

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

    let state = AppState {
        db,
        redis_conn,
        jwt_config,
        service_jwt_config,
    };

    // --- background JetStream consumer (user.compromised → force-revoke-all) ---
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());
    {
        let consumer_state = state.clone();
        tokio::spawn(async move {
            if let Err(e) = events::run_consumer(consumer_state, &nats_url).await {
                tracing::error!("identity compromise consumer stopped: {e}");
            }
        });
    }

    // --- HTTP router ---
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/auth/login", post(api::login))
        .route("/auth/refresh", post(api::refresh))
        .route("/auth/logout", post(api::logout))
        .route("/auth/me", get(api::me).delete(api::delete_me))
        .route(
            "/internal/users/{id}/revoke-all",
            post(api::internal_revoke_all::<AppState>),
        )
        .route("/metrics", get(observability::metrics_handler))
        .layer(shared::config::build_cors_layer())
        .layer(axum::middleware::from_fn(
            observability::telemetry_middleware,
        ))
        .with_state(state);

    let addr = format!("0.0.0.0:{PORT}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(service = SERVICE_NAME, %addr, "identity-service listening");
    axum::serve(listener, app).await?;
    Ok(())
}

async fn healthz() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "service": SERVICE_NAME,
        "version": env!("CARGO_PKG_VERSION"),
    }))
}
