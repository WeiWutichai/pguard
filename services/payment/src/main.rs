//! pguard payment service — payments + receipts (split from v1 booking). THE MONEY PATH.
//!
//! v2 design (CLAUDE.md) — PRE-PAY then SETTLE:
//!  - PRE-PAY: after a guard ACCEPTS, the customer pays the ESTIMATE up front via
//!    `POST /payments` (createPayment) — `base_fee × hours × guard_count + tip`, computed
//!    SERVER-SIDE from booking's authoritative `/internal/bookings/{id}` read (never a client
//!    body). This payment GATES the booking's en_route (booking learns it is paid by consuming
//!    `payment.completed`). At most ONE completed payment per booking (DB UNIQUE partial index +
//!    ON CONFLICT) — a repeat POST is a no-op returning the existing payment.
//!  - SETTLE: on `booking.completed` the consumer RECONCILES the actual-hours bill
//!    (`domain::reconcile`: base prorated + flat tip) against the pre-paid amount — refunds the
//!    overpay (`payment.refund_processed`) or records the shortfall. The base is NEVER
//!    double-charged. Idempotent via the `processed_events` event-id claim.
//!  - All money is `rust_decimal::Decimal` — never f64.
//!
//! This file is wiring only — configs, db pool, redis, the booking reader, the outbox relay
//! spawn, the booking.completed consumer, telemetry, CORS. Logic lives in `domain/` (pure pricing
//! — `expected_total`/`reconcile`/`post_pay_charge` + proration), `repo/` (atomic pre-pay/settle +
//! outbox), `events/` (relay → NATS + consumer), `api/` (transport: createPayment + the read
//! endpoints + admin ledger/reports + data export).

mod api;
mod booking_client;
mod domain;
mod events;
mod models;
mod repo;
mod state;

use anyhow::Context;
use axum::routing::{get, post};
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig, ServiceJwtConfig};
use shared::db::{create_pool, create_read_pool};
use shared::redis_client::create_connection_manager;

use crate::booking_client::HttpBookingReader;
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
    // payment MINTS service-JWTs (the PRE-PAY estimate reads booking's `/internal/bookings/{id}`)
    // AND VERIFIES them (its own internal data-export read), so it needs both halves of the shared
    // SERVICE_JWT_SECRET.
    let service_jwt_config = ServiceJwtConfig::from_env()?;
    let booking_url =
        std::env::var("BOOKING_URL").unwrap_or_else(|_| "http://localhost:3005".to_string());

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;
    // Read-replica pool (C5.3) for the payment list + export reads; primary fallback.
    let db_read = create_read_pool(&db_config).await?;
    // Reconnecting manager (not a one-shot MultiplexedConnection) so a Redis restart self-heals
    // in the background instead of wedging the AuthUser revocation check forever (chaos case 3).
    let redis_conn = create_connection_manager(&redis_config.cache_url)
        .await
        .context("Redis cache connection (reconnecting)")?;

    let booking_reader = HttpBookingReader::new(
        reqwest::Client::new(),
        booking_url,
        service_jwt_config.encoding_key.clone(),
        service_jwt_config.ttl_secs,
    );

    let state = AppState {
        db: db.clone(),
        db_read,
        redis_conn,
        jwt_config,
        service_decoding_key: service_jwt_config.decoding_key.clone(),
        booking_reader,
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

    // --- background booking.completed consumer (RECONCILES the pre-pay idempotently) ---
    // The reactive half of the money path: a completed job settles the pre-paid amount against
    // the actual hours (refund the overpay / record the shortfall). Like the relay, it owns its
    // retry and a NATS outage never crashes payment.
    {
        let consumer_db = db.clone();
        let consumer_nats = nats_url.clone();
        tokio::spawn(async move {
            // Loops forever (reconnects internally); only returns if the task is aborted.
            events::consumer::run_consumer(consumer_db, &consumer_nats).await;
        });
    }

    // --- HTTP router (resource paths; gateway adds the /v1 prefix) ---
    // PRE-PAY: `POST /payments` pre-pays the estimate (createPayment); `GET /payments` (own
    // ledger) + `GET /payments/{id}`. The completion-time SETTLE is event-driven (the consumer).
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route(
            "/payments",
            post(api::create_payment::<AppState>).get(api::list_payments::<AppState>),
        )
        .route("/payments/{id}", get(api::get_payment::<AppState>))
        // Admin cross-user payment ledger (admin-role gated in the handler). Needs a NEW
        // gateway `/admin/payments` prefix rule → Payment.
        .route("/admin/payments", get(api::admin_list_payments::<AppState>))
        // Admin refund queue (dashboard "คิวคืนเงิน" signal — refunds awaiting action /
        // in-progress + count). Admin-role gated in the handler. Needs a NEW gateway
        // `/admin/refunds` prefix rule → Payment.
        .route(
            "/admin/refunds/queue",
            get(api::admin_refund_queue::<AppState>),
        )
        // Admin revenue-trend report (analytics). Needs a NEW gateway `/admin/reports/revenue`
        // prefix rule → Payment (booking owns `/admin/reports/bookings`).
        .route(
            "/admin/reports/revenue",
            get(api::admin_revenue_report::<AppState>),
        )
        // Admin per-customer lifetime-spend report (web-admin customers page). Served under the
        // same gateway `/admin/reports/` prefix rule → Payment.
        .route(
            "/admin/reports/customer-spend",
            get(api::admin_customer_spend_report::<AppState>),
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
