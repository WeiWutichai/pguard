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
mod export_client;
mod models;
mod repo;
mod state;

use anyhow::Context;
use axum::routing::{get, post, put};
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig, ServiceJwtConfig};
use shared::db::create_pool;
use shared::redis_client::create_connection_manager;

use crate::export_client::{ExportClient, ExportUpstream};
use crate::state::AppState;

const SERVICE_NAME: &str = "identity";
const PORT: u16 = 3001;

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
    let service_jwt_config = ServiceJwtConfig::from_env()?;

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;
    // Reconnecting manager (not a one-shot MultiplexedConnection) so a Redis restart self-heals
    // in the background instead of wedging the AuthUser revocation check forever (chaos case 3).
    let redis_conn = create_connection_manager(&redis_config.cache_url)
        .await
        .context("Redis cache connection (reconnecting)")?;

    // --- data-export aggregator (PDPA §19/§32): fan out to data owners' internal reads ---
    let export_http = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_millis(500))
        .timeout(std::time::Duration::from_secs(3))
        .build()
        .context("build export HTTP client")?;
    let export_client = ExportClient::new(
        export_http,
        service_jwt_config.encoding_key.clone(),
        service_jwt_config.ttl_secs,
        vec![
            ExportUpstream {
                section: "profile",
                base_url: svc_url("PROFILE_URL", "http://localhost:3002"),
            },
            ExportUpstream {
                section: "bookings",
                base_url: svc_url("BOOKING_URL", "http://localhost:3005"),
            },
            ExportUpstream {
                section: "payments",
                base_url: svc_url("PAYMENT_URL", "http://localhost:3006"),
            },
            ExportUpstream {
                section: "reviews",
                base_url: svc_url("RATING_URL", "http://localhost:3007"),
            },
        ],
    );

    let state = AppState {
        db,
        redis_conn,
        jwt_config,
        service_jwt_config,
        export_client,
    };

    // --- background JetStream consumers ---
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());
    // (1) user.compromised → force-revoke-all.
    {
        let consumer_state = state.clone();
        let nats = nats_url.clone();
        tokio::spawn(async move {
            if let Err(e) = events::run_consumer(consumer_state, &nats).await {
                tracing::error!("identity compromise consumer stopped: {e}");
            }
        });
    }
    // (2) user.approved → flip our own approval_status (closes the approval→login loop).
    {
        let consumer_state = state.clone();
        let nats = nats_url.clone();
        tokio::spawn(async move {
            events::approved::run_consumer(consumer_state, &nats).await;
        });
    }

    // --- HTTP router ---
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/auth/register", post(api::register::<AppState>))
        .route(
            "/auth/register/reissue",
            post(api::reissue_profile_token::<AppState>),
        )
        .route("/auth/login", post(api::login))
        .route("/auth/refresh", post(api::refresh))
        .route("/auth/logout", post(api::logout))
        .route(
            "/auth/me",
            get(api::me).put(api::update_me).delete(api::delete_me),
        )
        .route("/auth/password", put(api::change_password))
        .route("/auth/revoke-all", post(api::revoke_all_sessions))
        .route("/me/data-export", get(api::data_export))
        // Admin user search (#138 per-user notify) — admin-gated in the handler. The gateway routes
        // `/admin/users/search` → identity (a more-specific rule than `/admin/users` → profile).
        .route("/admin/users/search", get(api::admin_search_users))
        .route(
            "/internal/users/{id}/revoke-all",
            post(api::internal_revoke_all::<AppState>),
        )
        // Internal batch id → {role, display_name} resolver (service-JWT only; blocked at the edge).
        // The profile resolver merges admin names from here (#142 Activity Log).
        .route(
            "/internal/users/names",
            post(api::internal_resolve_users::<AppState>),
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

/// A data-owner base URL from env, falling back to the dev default.
fn svc_url(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

async fn healthz() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "service": SERVICE_NAME,
        "version": env!("CARGO_PKG_VERSION"),
    }))
}
