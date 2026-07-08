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
mod s3;
mod state;

use anyhow::Context;
use axum::extract::DefaultBodyLimit;
use axum::routing::{get, post, put};
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig, S3Config, ServiceJwtConfig};
use shared::db::{create_pool, create_read_pool};
use shared::redis_client::create_connection_manager;

use crate::discovery_client::HttpDiscoveryClient;
use crate::s3::S3Client;
use crate::state::AppState;

const SERVICE_NAME: &str = "booking";
const PORT: u16 = 3005;

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
    // Guards the `/internal/*` read the payment/rating services call, and signs the
    // discovery reads booking MINTS to profile + rating (separate secret).
    let service_jwt_config = ServiceJwtConfig::from_env()?;
    // Discovery upstreams (service-JWT'd internal reads).
    let profile_url =
        std::env::var("PROFILE_URL").unwrap_or_else(|_| "http://localhost:3002".to_string());
    let rating_url =
        std::env::var("RATING_URL").unwrap_or_else(|_| "http://localhost:3007".to_string());
    let presence_url =
        std::env::var("PRESENCE_URL").unwrap_or_else(|_| "http://localhost:3009".to_string());
    // S3/MinIO for check-in photos (fail-fast: S3_ENDPOINT/S3_ACCESS_KEY/S3_SECRET_KEY/
    // S3_BUCKET required). Region + public URL are read ad-hoc exactly like chat's main.rs:
    // an empty `${S3_PUBLIC_URL:-}` from compose is treated as absent (single-host dev
    // falls back to the internal endpoint).
    let s3_config = S3Config::from_env()?;
    let s3_region = std::env::var("S3_REGION").unwrap_or_else(|_| "us-east-1".to_string());
    let s3_public_url = std::env::var("S3_PUBLIC_URL")
        .ok()
        .filter(|s| !s.trim().is_empty());

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;
    // Read-replica pool (C5.3) for list/discovery reads; falls back to primary if unset.
    let db_read = create_read_pool(&db_config).await?;
    // Reconnecting manager (not a one-shot MultiplexedConnection) so a Redis restart self-heals
    // in the background instead of wedging the AuthUser revocation check forever (chaos case 3).
    let redis_conn = create_connection_manager(&redis_config.cache_url)
        .await
        .context("Redis cache connection (reconnecting)")?;

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
        presence_url,
        service_jwt_config.encoding_key.clone(),
        service_jwt_config.ttl_secs,
    );

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
        db: db.clone(),
        db_read,
        redis_conn,
        jwt_config,
        service_jwt_config,
        discovery,
        s3,
    };

    // --- background outbox relay (the producer half of Phase 1) ---
    // This is the service's event publisher, not fire-and-forget side-effect work: each
    // event was already durably committed to the outbox in the same tx as the status
    // change. The relay owns its own retry; a NATS outage never crashes booking.
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());
    {
        let relay_db = db.clone();
        let relay_nats = nats_url.clone();
        tokio::spawn(async move {
            events::run_relay(relay_db, relay_nats).await;
        });
    }
    // --- background inbound consumer (PRE-PAY gate): payment.completed → stamp paid_at ---
    // booking's FIRST inbound consumer. It un-gates the `accepted → en_route` transition when the
    // customer has paid (it stamps `bookings.paid_at` idempotently via the processed_events
    // ledger). Owns its own reconnect/retry; a NATS outage never crashes booking.
    {
        let consumer_db = db.clone();
        tokio::spawn(async move {
            events::consumer::run_consumer(consumer_db, nats_url).await;
        });
    }

    // --- HTTP router (resource paths; gateway adds the /v1 prefix) ---
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route(
            "/bookings",
            post(api::create_booking::<AppState>).get(api::list_bookings::<AppState>),
        )
        // Open-job discovery — a LITERAL segment beside `/bookings/{id}`: the router gives
        // static segments priority over captures (house precedent: calling's `/calls/ice`),
        // and the gateway's `/bookings` prefix rule already routes it (no gateway change).
        .route("/bookings/open", get(api::list_open_bookings::<AppState>))
        .route("/bookings/{id}", get(api::get_booking::<AppState>))
        // Guard hourly check-in (multipart photo ≤ 10MB; the explicit body cap replaces
        // Axum's ~2MB default) + the participant-readable report list. NOTE: routing needs
        // no gateway change (the /bookings prefix rule covers it), but the gateway's 1 MiB
        // proxy body buffer + staging nginx's 2 MB cap currently 413 real photos at the
        // edge — a per-route body-cap carve-out is a TRACKED HARD DEPENDENCY for the
        // mobile wiring slice (see PROGRESS.md + the OpenAPI operation note).
        .route(
            "/bookings/{id}/progress-reports",
            post(api::create_progress_report::<AppState>)
                .get(api::list_progress_reports::<AppState>)
                .layer(DefaultBodyLimit::max(api::MAX_CHECK_IN_BODY_BYTES)),
        )
        // Admin cross-user surfaces (admin-role gated in the handler). The gateway needs a
        // NEW `/admin/bookings` prefix rule → Booking (no generic /admin/* catch-all); the
        // single prefix rule also routes the `/{id}/assign` subpath.
        .route("/admin/bookings", get(api::admin_list_bookings::<AppState>))
        .route(
            "/admin/bookings/{id}/assign",
            post(api::admin_assign_guard::<AppState>),
        )
        // Admin booking analytics (volume + utilization + retention). Gateway needs a NEW
        // `/admin/reports/bookings` prefix rule → Booking (payment owns `/admin/reports/revenue`).
        .route(
            "/admin/reports/bookings",
            get(api::admin_bookings_report::<AppState>),
        )
        // Per-customer booking aggregates for the web-admin customers page. Routed by the same
        // NEW `/admin/reports` prefix rule → Booking (no gateway change beyond that prefix).
        .route(
            "/admin/reports/customer-bookings",
            get(api::admin_customer_bookings_report::<AppState>),
        )
        // Admin missed/overdue hourly check-ins (dashboard alert card). Gateway needs a NEW
        // `/admin/checkins` prefix rule → Booking (no /admin/* catch-all exists).
        .route(
            "/admin/checkins/overdue",
            get(api::admin_overdue_checkins::<AppState>),
        )
        // Admin service catalog (pricing) CRUD — standalone, not wired to the charge path.
        // Gateway needs a NEW `/admin/pricing` prefix rule → Booking (covers /{id} too).
        .route(
            "/admin/pricing/services",
            get(api::admin_list_services::<AppState>).post(api::admin_create_service::<AppState>),
        )
        .route(
            "/admin/pricing/services/{id}",
            put(api::admin_update_service::<AppState>)
                .delete(api::admin_delete_service::<AppState>),
        )
        // Discovery: approved guard catalog (profile) + rating summaries (rating).
        .route("/available-guards", get(api::available_guards::<AppState>))
        // Customer-facing service picker — ACTIVE catalog services only (any authenticated
        // user; NOT admin-gated, unlike `/admin/pricing/services`). The gateway needs a NEW
        // `/services` prefix rule → Booking.
        .route("/services", get(api::list_services::<AppState>))
        .route(
            "/bookings/{id}/accept",
            post(api::accept_booking::<AppState>),
        )
        // Guard passes on an open offer → server-tracked skip (discovery stops re-offering it to them).
        .route("/bookings/{id}/skip", post(api::skip_booking::<AppState>))
        // Lifecycle state changes (PUT). Guard: decline/en-route/arrived/start/complete;
        // customer: review-completion/cancel. The gateway's `/bookings` prefix already routes
        // every subpath, so these are edge-reachable under /v1.
        .route(
            "/bookings/{id}/decline",
            put(api::decline_booking::<AppState>),
        )
        .route(
            "/bookings/{id}/en-route",
            put(api::en_route_booking::<AppState>),
        )
        .route(
            "/bookings/{id}/arrived",
            put(api::arrived_booking::<AppState>),
        )
        .route("/bookings/{id}/start", put(api::start_booking::<AppState>))
        .route(
            "/bookings/{id}/complete",
            put(api::complete_booking::<AppState>),
        )
        .route(
            "/bookings/{id}/review-completion",
            put(api::review_completion::<AppState>),
        )
        .route(
            "/bookings/{id}/cancel",
            put(api::cancel_booking::<AppState>),
        )
        // Service-to-service read (service-JWT'd) — the payment service verifies a charge
        // against the authoritative booking here. Not exposed through the public gateway.
        .route(
            "/internal/bookings/{id}",
            get(api::get_internal_booking::<AppState>),
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
