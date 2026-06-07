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
mod ws;

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
/// Default admin port — serves `/metrics` (+ `/healthz`) OFF the public edge port so the
/// metrics registry (route inventory, traffic, latency) is not scrapable from the internet.
/// Override with `METRICS_ADDR`; restrict it to the monitoring network in prod.
const METRICS_PORT: u16 = 9100;
/// Buffer of in-flight booking-status updates the broadcast hub holds for slow receivers; a
/// receiver that lags past this gets a `Lagged` signal (the client then REST-refreshes).
const STATUS_FANOUT_CAPACITY: usize = 1024;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _telemetry = observability::init_telemetry(SERVICE_NAME);

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

    // --- booking-status WS fan-out: one NATS subscription → broadcast → per-connection ---
    // The hub owns the single subscription to pguard.events.booking.* and pushes updates to
    // every connected /v1/ws/bookings/{id} session (which filters to its own booking).
    let (status_tx, _) = tokio::sync::broadcast::channel(STATUS_FANOUT_CAPACITY);
    {
        let nats_url =
            std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());
        let tx = status_tx.clone();
        tokio::spawn(async move { ws::run_status_hub(nats_url, tx).await });
    }

    let state = AppState {
        http,
        redis_conn,
        jwt_config,
        routes,
        limits,
        status_tx,
        allowed_origins: shared::config::cors_allowed_origins().into(),
    };

    // --- admin listener: /metrics (+ /healthz) on a SEPARATE port, never on the public
    // edge. Prometheus scrapes this; the public 3000 port serves only the proxied API. ---
    {
        let metrics_addr =
            std::env::var("METRICS_ADDR").unwrap_or_else(|_| format!("0.0.0.0:{METRICS_PORT}"));
        let metrics_app = Router::new()
            .route("/metrics", get(observability::metrics_handler))
            .route("/healthz", get(healthz));
        tokio::spawn(async move {
            match tokio::net::TcpListener::bind(&metrics_addr).await {
                Ok(l) => {
                    tracing::info!(addr = %metrics_addr, "api-gateway metrics listener");
                    if let Err(e) = axum::serve(l, metrics_app).await {
                        tracing::error!("metrics listener error: {e}");
                    }
                }
                Err(e) => {
                    tracing::error!(addr = %metrics_addr, "metrics listener bind failed: {e}")
                }
            }
        });
    }

    // --- public router: gateway's own /healthz (never proxied) + the booking-status WS
    // (specific route, matches before the catch-all) + the catch-all edge handler. The EDGE
    // telemetry middleware starts a fresh root trace — an untrusted client must not be able to
    // supply the trace context (forge trace_id / force sampling). `/metrics` is NOT here; it
    // lives on the admin listener above. ---
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/v1/ws/bookings/{id}", get(ws::ws_bookings))
        .route("/{*path}", any(handler::gateway))
        .layer(shared::config::build_cors_layer())
        .layer(axum::middleware::from_fn(
            observability::edge_telemetry_middleware,
        ))
        // OUTERMOST: stamp security headers on every response (incl. CORS + errors).
        .layer(axum::middleware::from_fn(handler::security_headers_mw))
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
