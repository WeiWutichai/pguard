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
mod config;
mod domain;
mod events;
mod models;
mod repo;
mod s3;
mod slip2go_client;
mod state;

use anyhow::Context;
use axum::extract::DefaultBodyLimit;
use axum::routing::{get, post};
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig, S3Config, ServiceJwtConfig};
use shared::db::{create_pool, create_read_pool};
use shared::redis_client::create_connection_manager;

use crate::booking_client::HttpBookingReader;
use crate::config::SlipPaymentConfig;
use crate::s3::S3Client;
use crate::slip2go_client::HttpSlipVerifier;
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

    // --- REAL money path (Slip2Go) config + clients. The feature flag (PAYMENT_PROVIDER) defaults
    //     to `simulated`, so the service starts WITHOUT the Slip2Go secret / S3 / receiving account
    //     — the slip path simply fails gracefully if hit. Under `slip2go` the receiving account is
    //     required (fail-fast in SlipPaymentConfig::from_env); S3 + the secret are required to
    //     actually settle a slip (S3Config::from_env fails fast when slip2go is on).
    let slip_config = SlipPaymentConfig::from_env()?;

    let slip2go_base_url = std::env::var("SLIP2GO_BASE_URL")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| "https://connect.slip2go.com/api".to_string());
    let slip2go_secret = std::env::var("SLIP2GO_API_SECRET").ok();
    let slip_http = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_secs(3))
        .timeout(std::time::Duration::from_secs(20))
        .build()
        .context("build Slip2Go HTTP client")?;
    let slip_verifier = HttpSlipVerifier::new(slip_http, slip2go_base_url, slip2go_secret);

    // S3 for the private slip-image store (PDPA — like guard documents). Required only under
    // slip2go; under the simulated default, an absent S3 config is tolerated (the slip path is off)
    // so dev/CI run with the simulated gateway need no MinIO env.
    let s3 = build_s3_client(slip_config.provider.is_slip2go())?;

    let state = AppState {
        db: db.clone(),
        db_read,
        redis_conn,
        jwt_config,
        service_decoding_key: service_jwt_config.decoding_key.clone(),
        booking_reader,
        slip_verifier,
        s3,
        slip_config,
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

    // --- background cancellation-refund consumer (FULL-REFUNDS a paid pre-pay idempotently) ---
    // The refund half of the money path: a guard withdrawing en_route or a customer cancelling
    // after paying returns the whole pre-pay. Its OWN durable, kept separate from the completion
    // settle so the reconcile path is untouched; owns its retry (a NATS outage never crashes payment).
    {
        let cancel_db = db.clone();
        let cancel_nats = nats_url.clone();
        tokio::spawn(async move {
            events::cancel_consumer::run_consumer(cancel_db, &cancel_nats).await;
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
        // Guard earnings ledger (their completed jobs + actual worked hours). Registered before the
        // `/payments/{id}` capture; axum 0.8 matches the static `earnings` segment first regardless.
        .route("/payments/earnings", get(api::guard_earnings::<AppState>))
        .route("/payments/{id}", get(api::get_payment::<AppState>))
        // PromptPay transfer instructions for a booking (the customer's "where do I pay?" read):
        // the server estimate + our receiving account + the authoritative EMVCo QR payload. Own-only
        // (the booking's customer); only meaningful under PAYMENT_PROVIDER=slip2go. Served under the
        // existing gateway `/payments/` prefix → Payment.
        .route(
            "/payments/{id}/promptpay",
            get(api::get_promptpay::<AppState>),
        )
        // REAL money path: pay a booking with a Slip2Go-verified transfer slip. Own-only (the
        // booking's customer); multipart `file` (the slip image). 12 MiB body cap on THIS route
        // only (images); the gateway carves a matching Large cap for /payments/{id}/slip.
        .route(
            "/payments/{id}/slip",
            post(api::pay_with_slip::<AppState>)
                .layer(DefaultBodyLimit::max(api::MAX_SLIP_BODY_BYTES)),
        )
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

/// Build the S3 client for the private slip-image store. Under `slip2go` the S3 env
/// (`S3_ENDPOINT`/`S3_ACCESS_KEY`/`S3_SECRET_KEY`/`S3_BUCKET`) is REQUIRED (fail-fast). Under the
/// simulated default the slip path is off, so an absent S3 config is tolerated — we build a client
/// from empty defaults that is never invoked (mirrors the Slip2Go secret being optional). Region +
/// public URL are read ad-hoc, exactly like profile/booking.
fn build_s3_client(required: bool) -> anyhow::Result<S3Client> {
    let s3_config = match S3Config::from_env() {
        Ok(c) => c,
        Err(e) if !required => {
            tracing::info!(
                "S3 not configured ({e}); slip path off under PAYMENT_PROVIDER=simulated"
            );
            S3Config {
                endpoint: String::new(),
                access_key: String::new(),
                secret_key: String::new(),
                bucket: String::new(),
            }
        }
        Err(e) => return Err(anyhow::anyhow!(e)),
    };
    let s3_region = std::env::var("S3_REGION").unwrap_or_else(|_| "us-east-1".to_string());
    let s3_public_url = std::env::var("S3_PUBLIC_URL")
        .ok()
        .filter(|s| !s.trim().is_empty());
    let s3_http = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_secs(2))
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .context("build S3 HTTP client")?;
    Ok(S3Client::new(
        s3_http,
        s3_config.endpoint,
        s3_public_url,
        s3_config.bucket,
        s3_region,
        s3_config.access_key,
        s3_config.secret_key,
    ))
}
