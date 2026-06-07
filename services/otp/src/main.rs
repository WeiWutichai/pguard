//! pguard otp service — OTP, SMS, phone verification (split from v1 auth).
//!
//! Owns the OTP lifecycle: a math-captcha gate (`GET /otp/challenge`), abuse-controlled
//! request (`POST /otp/request` — captcha + cooldown + daily cap + tiered lockout, then a
//! SHA-256-hashed code sent via the INET SMS gateway), and verify
//! (`POST /otp/verify` — atomic attempts increment + constant-time compare → a single-use
//! phone-verified JWT that profile/identity later exchange to finish registration).
//!
//! This file is wiring only — router, state, telemetry. Logic lives in `domain/` (PURE),
//! `repo/` (the only sqlx), `api/` (thin transport). The SMS gateway sits behind the
//! `sms::SmsSender` port (real `InetSender`, or `NoopSender` when `SMS_DISABLED`).

mod api;
mod config;
mod domain;
mod models;
mod repo;
mod sms;
mod state;
mod token;

use std::sync::Arc;
use std::time::Duration;

use anyhow::Context;
use axum::routing::{get, post};
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig};
use shared::db::create_pool;
use shared::redis_client::create_redis_client;

use crate::config::OtpConfig;
use crate::sms::{InetConfig, InetSender, NoopSender, SmsSender};
use crate::state::AppState;

const SERVICE_NAME: &str = "otp";
const VERSION: &str = env!("CARGO_PKG_VERSION");
const PORT: u16 = 3003;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _telemetry = observability::init_telemetry(SERVICE_NAME);

    // --- config (fail-fast at startup) ---
    let db_config = DatabaseConfig::from_env()?;
    let redis_config = RedisConfig::from_env()?;
    let jwt_config = JwtConfig::from_env()?;
    let otp_config = OtpConfig::from_env()?;

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;
    let redis_client = create_redis_client(&redis_config.cache_url)?;
    let redis_conn = redis_client
        .get_multiplexed_tokio_connection()
        .await
        .context("Redis cache connection")?;
    // --- SMS backend (fail-fast unless explicitly disabled for dev). The HTTP client is
    // built only when a real sender is used; InetSender owns it (no copy on state). ---
    let sms: Arc<dyn SmsSender> = if sms::sms_disabled(std::env::var("SMS_DISABLED").ok().as_deref())
    {
        tracing::warn!("SMS_DISABLED is truthy — using NoopSender (no real SMS will be sent)");
        Arc::new(NoopSender)
    } else {
        let http_client = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .connect_timeout(Duration::from_secs(5))
            .build()
            .context("build HTTP client")?;
        Arc::new(InetSender::new(InetConfig::from_env()?, http_client))
    };

    let state = AppState {
        db,
        redis_conn,
        otp_config,
        jwt_config,
        sms,
    };

    // --- HTTP router (all OTP routes are PUBLIC / pre-auth) ---
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/otp/challenge", get(api::challenge))
        .route("/otp/request", post(api::request))
        .route("/otp/verify", post(api::verify))
        .route("/metrics", get(observability::metrics_handler))
        .layer(shared::config::build_cors_layer())
        .layer(axum::middleware::from_fn(
            observability::telemetry_middleware,
        ))
        .with_state(state);

    let addr = format!("0.0.0.0:{PORT}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(service = SERVICE_NAME, %addr, "otp-service listening");
    axum::serve(listener, app).await?;
    Ok(())
}

/// Liveness/readiness probe.
async fn healthz() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "service": SERVICE_NAME,
        "version": VERSION,
    }))
}
