//! pguard payment service — payments + receipts (split from v1 booking). THE MONEY PATH.
//!
//! v2 design (CLAUDE.md) — POST-PAY:
//!  - The customer is NOT charged up front. The bill is RAISED on completion by the
//!    `booking.completed` consumer for the hours actually worked (`domain::post_pay_charge`:
//!    base prorated + flat tip) — computed entirely from booking's server-owned pricing carried
//!    on the (signed) event, never a client. There is no up-front charge endpoint and no refund.
//!  - At most ONE completed payment per booking (DB UNIQUE partial index + ON CONFLICT) — a
//!    redelivered completion event cannot double-charge; it returns the existing payment.
//!  - All money is `rust_decimal::Decimal` — never f64.
//!
//! This file is wiring only — configs, db pool, redis, the outbox relay spawn, the
//! booking.completed consumer, telemetry, CORS. Logic lives in `domain/` (pure pricing —
//! `post_pay_charge` + proration), `repo/` (atomic charge + outbox), `events/` (relay → NATS +
//! consumer), `api/` (transport: the read endpoints + admin ledger/reports + data export).

mod api;
mod domain;
mod events;
mod models;
mod repo;
mod state;

use anyhow::Context;
use axum::routing::get;
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig, ServiceJwtConfig};
use shared::db::{create_pool, create_read_pool};
use shared::redis_client::create_connection_manager;

use crate::state::AppState;

const SERVICE_NAME: &str = "payment";
const PORT: u16 = 3006;

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
    // The payment service verifies inbound service-JWTs on its internal data-export read; it no
    // longer MINTS service-JWTs (the post-pay bill is raised from the completion event, not a
    // cross-service booking read), so only the decoding key is used.
    let service_jwt_config = ServiceJwtConfig::from_env()?;

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;
    // Read-replica pool (C5.3) for the payment list + export reads; primary fallback.
    let db_read = create_read_pool(&db_config).await?;
    // Reconnecting manager (not a one-shot MultiplexedConnection) so a Redis restart self-heals
    // in the background instead of wedging the AuthUser revocation check forever (chaos case 3).
    let redis_conn = create_connection_manager(&redis_config.cache_url)
        .await
        .context("Redis cache connection (reconnecting)")?;

    let state = AppState {
        db: db.clone(),
        db_read,
        redis_conn,
        jwt_config,
        service_decoding_key: service_jwt_config.decoding_key.clone(),
    };

    // --- background outbox relay (publishes payment.* events) ---
    // Not fire-and-forget side-effect work: each event was already durably committed to the
    // outbox in the same tx as the payment change. The relay owns its own retry; a NATS
    // outage never crashes payment.
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());
    {
        let relay_db = db.clone();
        let relay_nats = nats_url.clone();
        tokio::spawn(async move {
            events::run_relay(relay_db, relay_nats).await;
        });
    }

    // --- background booking.completed consumer (raises the post-pay charge idempotently) ---
    // The reactive half of the money path: a completed job raises the bill for actual hours.
    // Like the relay, it owns its retry and a NATS outage never crashes payment.
    {
        let consumer_db = db.clone();
        let consumer_nats = nats_url.clone();
        tokio::spawn(async move {
            // Loops forever (reconnects internally); only returns if the task is aborted.
            events::consumer::run_consumer(consumer_db, &consumer_nats).await;
        });
    }

    // --- HTTP router (resource paths; gateway adds the /v1 prefix) ---
    // POST-PAY: no customer-initiated charge endpoint — only reads (the bill is raised by the
    // consumer). `GET /payments` (own ledger) + `GET /payments/{id}`.
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/payments", get(api::list_payments::<AppState>))
        .route("/payments/{id}", get(api::get_payment::<AppState>))
        // Admin cross-user payment ledger (admin-role gated in the handler). Needs a NEW
        // gateway `/admin/payments` prefix rule → Payment.
        .route("/admin/payments", get(api::admin_list_payments::<AppState>))
        // Admin revenue-trend report (analytics). Needs a NEW gateway `/admin/reports/revenue`
        // prefix rule → Payment (booking owns `/admin/reports/bookings`).
        .route(
            "/admin/reports/revenue",
            get(api::admin_revenue_report::<AppState>),
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
    tracing::info!(service = SERVICE_NAME, %addr, "payment-service listening");
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
