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
mod profile_client;
mod repo;
mod state;

use std::sync::Arc;
use std::time::Duration;

use anyhow::Context;
use axum::routing::{get, post, put};
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig, ServiceJwtConfig};
use shared::db::create_pool;
use shared::redis_client::create_connection_manager;

use crate::fcm::{FcmConfig, FcmPusher, NoopPusher, Pusher};
use crate::state::AppState;

const PORT: u16 = 3004;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _telemetry = observability::init_telemetry("notification");
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
    let http_client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .connect_timeout(Duration::from_secs(5))
        .build()
        .context("build HTTP client")?;

    // --- push backend (fail-fast unless explicitly disabled for dev) ---
    // Value-aware gate (mirrors otp's SMS_DISABLED): only a TRUTHY FCM_DISABLED disables push;
    // `false`/`0`/empty/unset keep it ENABLED → FcmConfig::from_env fail-fasts without creds, so a
    // misconfig is loud at boot (never the old silent NoopPusher on `FCM_DISABLED=false`).
    let pusher: Arc<dyn Pusher> =
        if crate::fcm::fcm_disabled(std::env::var("FCM_DISABLED").ok().as_deref()) {
            tracing::warn!(
                "FCM_DISABLED is truthy — using NoopPusher (no real pushes will be sent)"
            );
            Arc::new(NoopPusher)
        } else {
            Arc::new(FcmPusher::new(FcmConfig::from_env()?, http_client.clone()))
        };

    // Service-JWT'd client for profile's broadcast-recipient roster (admin bulk-send). Mints
    // a token from the SAME service secret profile verifies with; PROFILE_INTERNAL_URL points
    // at profile DIRECTLY (service-to-service, never through the public gateway).
    let profile_internal_url =
        std::env::var("PROFILE_INTERNAL_URL").unwrap_or_else(|_| "http://profile:3002".to_string());
    let profile_client = crate::profile_client::ProfileClient::new(
        http_client.clone(),
        profile_internal_url,
        service_jwt_config.encoding_key.clone(),
        service_jwt_config.ttl_secs,
    );

    let state = AppState {
        db,
        redis_conn,
        jwt_config,
        service_jwt_config,
        pusher,
        profile_client,
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

    // --- background scheduler: fires due scheduled broadcasts every 30s ---
    // State-changing work that owns its retry via the broadcast `status` ledger (a row stays
    // `scheduled` until a fan-out succeeds + flips it to `sent`) — not fire-and-forget.
    {
        let sched_state = state.clone();
        tokio::spawn(async move {
            let mut tick = tokio::time::interval(Duration::from_secs(30));
            loop {
                tick.tick().await;
                if let Err(e) = api::dispatch_due_broadcasts(&sched_state).await {
                    tracing::error!("broadcast scheduler tick failed: {e}");
                }
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
        // Admin broadcast (bulk-send) — composer + draft + schedule + history + counts.
        .route(
            "/admin/broadcasts",
            post(api::create_broadcast).get(api::list_broadcasts),
        )
        .route(
            "/admin/broadcasts/{id}",
            get(api::get_broadcast).put(api::update_broadcast),
        )
        .route("/admin/broadcasts/{id}/send", post(api::send_broadcast))
        .route("/admin/audience-counts", get(api::audience_counts))
        // Admin automation rules (authoring/list/toggle/delete — live execution is a follow-up).
        .route(
            "/admin/automation/rules",
            get(api::list_rules).post(api::create_rule),
        )
        .route(
            "/admin/automation/rules/{id}",
            put(api::update_rule).delete(api::delete_rule),
        )
        .route(
            "/internal/notifications/push",
            post(api::internal_push::<AppState>),
        )
        .route("/metrics", get(observability::metrics_handler))
        .layer(shared::config::build_cors_layer())
        .layer(axum::middleware::from_fn(
            observability::telemetry_middleware,
        ))
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
