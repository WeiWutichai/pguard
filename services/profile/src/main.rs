//! pguard profile service — guard/customer profiles + approval (split from v1 auth).
//!
//! AuthUser-gated CRUD: a registered, logged-in user upserts/reads their own profile; an
//! admin reviews + approves/rejects guard onboarding. Bank account numbers are masked on
//! owner reads (PDPA §7); admin endpoints return the full value.
//!
//! This file is wiring only — config, db pool, redis conn, router, CORS, telemetry. Logic
//! lives in `domain/` (pure mask + approval transition + validators), `repo/` (DB), and
//! `api/` (transport). No /internal/* and no event bus in this slice (Postgres-only).

mod api;
mod domain;
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

const SERVICE_NAME: &str = "profile";
const PORT: u16 = 3002;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _telemetry = observability::init_telemetry(SERVICE_NAME);

    // --- config (fail-fast at startup) ---
    let db_config = DatabaseConfig::from_env()?;
    let redis_config = RedisConfig::from_env()?;
    let jwt_config = JwtConfig::from_env()?;
    // Verifies inbound service-JWTs on the internal guard-catalog read.
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

    // --- HTTP router (resource paths; gateway adds the /v1 prefix) ---
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route(
            "/profile/guard",
            post(api::upsert_guard_profile::<AppState>).put(api::update_guard_profile::<AppState>),
        )
        .route(
            "/profile/customer",
            post(api::upsert_customer_profile::<AppState>),
        )
        .route("/profile/me", get(api::get_my_profile::<AppState>))
        .route(
            "/admin/guard-profiles",
            get(api::admin_list_guard_profiles::<AppState>),
        )
        .route(
            "/admin/guard-profiles/{user_id}/approve",
            post(api::admin_approve_guard::<AppState>),
        )
        .route(
            "/admin/guard-profiles/{user_id}/reject",
            post(api::admin_reject_guard::<AppState>),
        )
        .route(
            "/internal/guards",
            get(api::internal_list_guards::<AppState>),
        )
        .route("/metrics", get(observability::metrics_handler))
        .layer(shared::config::build_cors_layer())
        .layer(axum::middleware::from_fn(
            observability::telemetry_middleware,
        ))
        .with_state(state);

    let addr = format!("0.0.0.0:{PORT}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(service = SERVICE_NAME, %addr, "profile-service listening");
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
