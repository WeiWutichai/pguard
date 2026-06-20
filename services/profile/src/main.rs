//! pguard profile service — guard/customer profiles + approval (split from v1 auth).
//!
//! AuthUser-gated CRUD: a registered, logged-in user upserts/reads their own profile; an
//! admin reviews + approves/rejects guard onboarding. Bank account numbers are masked on
//! owner reads (PDPA §7); admin endpoints return the full value.
//!
//! This file is wiring only — config, db pool, redis conn, router, CORS, telemetry, and the
//! transactional-outbox relay. Logic lives in `domain/` (pure mask + approval transition +
//! validators), `repo/` (DB), `events/` (outbox relay), and `api/` (transport).

mod api;
mod domain;
mod events;
mod models;
mod repo;
mod s3;
mod state;

use anyhow::Context;
use axum::extract::DefaultBodyLimit;
use axum::routing::{get, post};
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig, S3Config, ServiceJwtConfig};
use shared::db::{create_pool, create_read_pool};
use shared::redis_client::create_connection_manager;

use crate::s3::S3Client;
use crate::state::AppState;

const SERVICE_NAME: &str = "profile";
const PORT: u16 = 3002;

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
    // Verifies inbound service-JWTs on the internal guard-catalog read.
    let service_jwt_config = ServiceJwtConfig::from_env()?;

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;
    // Read-replica pool (C5.3) for admin list + discovery-catalog reads; primary fallback.
    let db_read = create_read_pool(&db_config).await?;
    // Reconnecting manager (not a one-shot MultiplexedConnection) so a Redis restart self-heals
    // in the background instead of wedging the AuthUser revocation check forever (chaos case 3).
    let redis_conn = create_connection_manager(&redis_config.cache_url)
        .await
        .context("Redis cache connection (reconnecting)")?;

    // IDOR authz reader for the customer-readable guard mini-profile — reads the event-derived
    // `profile.guard_assignments` read-model (projected by the booking-events consumer below).
    let booking_authz = state::DbBookingAuthz { db: db.clone() };

    // --- S3/MinIO for guard-document images (fail-fast: S3_ENDPOINT/S3_ACCESS_KEY/S3_SECRET_KEY/
    //     S3_BUCKET required). Region + public URL read ad-hoc like booking's main.rs: an empty
    //     S3_PUBLIC_URL (single-host dev) is treated as absent → falls back to the internal endpoint.
    let s3_config = S3Config::from_env()?;
    let s3_region = std::env::var("S3_REGION").unwrap_or_else(|_| "us-east-1".to_string());
    let s3_public_url = std::env::var("S3_PUBLIC_URL")
        .ok()
        .filter(|s| !s.trim().is_empty());
    let s3_http = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_secs(2))
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .context("build S3 HTTP client")?;
    let s3 = S3Client::new(
        s3_http,
        s3_config.endpoint,
        s3_public_url,
        s3_config.bucket,
        s3_region,
        s3_config.access_key,
        s3_config.secret_key,
    );

    let state = AppState {
        db,
        db_read,
        redis_conn,
        jwt_config,
        service_jwt_config,
        booking_authz,
        s3,
    };

    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());
    // --- background outbox relay: drains profile.outbox → NATS (user.approved/rejected) ---
    {
        let relay_db = state.db.clone();
        let relay_nats = nats_url.clone();
        tokio::spawn(async move {
            events::run_relay(relay_db, relay_nats).await;
        });
    }
    // --- background booking-events consumer: projects pguard.events.booking.* into the
    //     profile.guard_assignments IDOR read-model (gates the customer guard-profile read) ---
    {
        let consumer_db = state.db.clone();
        let consumer_nats = nats_url.clone();
        tokio::spawn(async move {
            events::consumer::run_consumer(consumer_db, &consumer_nats).await;
        });
    }

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
        // Customer-readable guard mini-profile (name + experience) for the live-tracking map.
        // IDOR-gated: a customer reads it only for a guard on their ACTIVE booking; the guard's
        // own read + admin allowed. Approval-gated (un-approved guards → 404).
        .route(
            "/guards/{id}/public",
            get(api::get_public_guard_profile::<AppState>),
        )
        // Guard document image upload/read. Own-docs-only write (logged-in guard); owner-or-admin
        // read (presigned). 12 MiB body cap on THIS route only (images); gateway carves the same.
        .route(
            "/profile/guard/{user_id}/documents",
            post(api::upload_guard_document::<AppState>)
                .get(api::get_guard_document::<AppState>)
                .layer(DefaultBodyLimit::max(api::MAX_DOCUMENT_BODY_BYTES)),
        )
        .route(
            "/profile/guard/{user_id}/avatar",
            post(api::upload_guard_avatar::<AppState>)
                .get(api::get_guard_avatar::<AppState>)
                .layer(DefaultBodyLimit::max(api::MAX_DOCUMENT_BODY_BYTES)),
        )
        .route(
            "/profile/guard/{user_id}/document-expiries",
            get(api::list_guard_document_expiries::<AppState>),
        )
        .route(
            "/profile/guard/{user_id}/document-expiry",
            axum::routing::put(api::set_guard_document_expiry::<AppState>),
        )
        .route(
            "/admin/guard-profiles",
            get(api::admin_list_guard_profiles::<AppState>),
        )
        .route(
            "/admin/customer-profiles",
            get(api::admin_list_customer_profiles::<AppState>),
        )
        .route(
            "/admin/access-audit",
            get(api::admin_list_access_audit::<AppState>),
        )
        .route(
            "/admin/documents/expiring",
            get(api::admin_list_expiring_documents::<AppState>),
        )
        .route(
            "/admin/recruitment/candidates",
            get(api::admin_list_candidates::<AppState>),
        )
        .route(
            "/admin/recruitment/candidates/{user_id}/stage",
            axum::routing::put(api::admin_set_candidate_stage::<AppState>),
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
        .route(
            "/internal/profiles/recipients",
            get(api::internal_list_recipients::<AppState>),
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
