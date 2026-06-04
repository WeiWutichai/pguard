//! pguard api-gateway — the edge reverse proxy (CLAUDE.md: "JWT validation at edge,
//! rate limit, route").
//!
//! It (1) resolves `/v1/...` paths to an upstream service (longest-prefix, `/internal`
//! blocked, `/v1` stripped before forwarding), (2) enforces per-IP rate limits
//! (Redis fixed-window, fail-open), (3) validates the access token at the edge for
//! protected routes (jti blocklist + per-user `trv` force-revoke-all + CSRF parity) and
//! injects trusted `X-User-*` headers, then (4) forwards via reqwest and returns the
//! upstream response. Backends KEEP their own `AuthUser` validation (defense in depth).
//!
//! This file is wiring only — config from env, Redis/HTTP clients, the env-resolved
//! route table, and the router (one catch-all + `/healthz`). Logic lives in `domain/`
//! (pure), `auth`, `ratelimit`, `proxy`, `handler` (the I/O).

mod auth;
mod domain;
mod handler;
mod proxy;
mod ratelimit;
mod state;

use std::net::SocketAddr;
use std::time::Duration;

use anyhow::Context;
use axum::routing::{any, get};
use axum::{Json, Router};

use shared::config::{JwtConfig, RedisConfig};
use shared::redis_client::create_redis_client;

use crate::domain::ratelimit::Limits;
use crate::state::{AppState, UpstreamTable};

const SERVICE_NAME: &str = "api-gateway";
const PORT: u16 = 3000;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    observability::init_telemetry(SERVICE_NAME);

    // --- config (fail-fast at startup) ---
    let redis_config = RedisConfig::from_env()?;
    let jwt_config = JwtConfig::from_env()?;
    let limits = limits_from_env();
    let routes = UpstreamTable::from_env();

    // --- infrastructure ---
    let redis_client = create_redis_client(&redis_config.cache_url)?;
    let redis_conn = redis_client
        .get_multiplexed_tokio_connection()
        .await
        .context("Redis cache connection")?;
    let http = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .connect_timeout(Duration::from_secs(5))
        .build()
        .context("build HTTP client")?;

    let state = AppState {
        http,
        redis_conn,
        jwt_config,
        routes,
        limits,
    };

    // --- router: gateway's own /healthz (never proxied) + the catch-all edge handler ---
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/{*path}", any(handler::gateway))
        .layer(shared::config::build_cors_layer())
        .with_state(state);

    let addr = format!("0.0.0.0:{PORT}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(service = SERVICE_NAME, %addr, "api-gateway listening");
    // ConnectInfo gives the handler the socket peer for the rate-limit fallback IP.
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await?;
    Ok(())
}

/// Build [`Limits`] from env, falling back to v1's zone defaults.
/// `RATE_OTP_PER_MIN` (10), `RATE_AUTH_PER_SEC` (5), `RATE_API_PER_SEC` (30).
fn limits_from_env() -> Limits {
    let d = Limits::default();
    Limits {
        otp_per_min: parse_env("RATE_OTP_PER_MIN", d.otp_per_min),
        auth_per_sec: parse_env("RATE_AUTH_PER_SEC", d.auth_per_sec),
        api_per_sec: parse_env("RATE_API_PER_SEC", d.api_per_sec),
    }
}

fn parse_env(key: &str, default: u32) -> u32 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .filter(|&n| n > 0)
        .unwrap_or(default)
}

/// Liveness/readiness probe — the gateway's own endpoint (not proxied).
async fn healthz() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "service": SERVICE_NAME,
        "version": env!("CARGO_PKG_VERSION"),
    }))
}
