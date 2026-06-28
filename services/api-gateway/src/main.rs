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
#[cfg(test)]
mod test_support;
mod ws;
mod wsproxy;

use std::net::SocketAddr;
use std::time::Duration;

use anyhow::Context;
use axum::routing::{any, get};
use axum::{Json, Router};

use shared::config::{JwtConfig, RedisConfig};
use shared::redis_client::create_connection_manager;

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
    // The status-WS hub verifies signed booking events before fan-out — load the key (fail-fast).
    shared_events::init_signing_key_from_env().map_err(|e| anyhow::anyhow!(e))?;

    // --- config (fail-fast at startup) ---
    let redis_config = RedisConfig::from_env()?;
    let jwt_config = JwtConfig::from_env()?;
    let limits = limits_from_env();
    let routes = UpstreamTable::from_env();

    // --- infrastructure ---
    // Reconnecting Redis (ConnectionManager): a Redis restart no longer wedges the edge — it
    // re-establishes in the background (chaos case 3). The initial connect is awaited here, so a
    // Redis that's down at startup still fails fast (unchanged startup posture).
    let redis_conn = create_connection_manager(&redis_config.cache_url)
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
    // (bespoke NATS hub) + the generic WS proxies (chat/track/call) — all specific routes
    // that match before the catch-all — + the catch-all edge handler. The EDGE telemetry
    // middleware starts a fresh root trace — an untrusted client must not be able to
    // supply the trace context (forge trace_id / force sampling). `/metrics` is NOT here;
    // it lives on the admin listener above. ---
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/readyz", get(readyz))
        .route("/v1/ws/bookings/{id}", get(ws::ws_bookings))
        .route("/v1/ws/chat", get(wsproxy::ws_chat))
        .route("/v1/ws/track", get(wsproxy::ws_track))
        .route("/v1/ws/call", get(wsproxy::ws_call))
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
/// `RATE_OTP_PER_MIN` (10), `RATE_OTP_VERIFY_PER_MIN` (30), `RATE_OTP_CHALLENGE_PER_MIN` (30),
/// `RATE_AUTH_PER_SEC` (5), `RATE_API_PER_SEC` (30).
fn limits_from_env() -> Limits {
    let d = Limits::default();
    Limits {
        otp_per_min: parse_env("RATE_OTP_PER_MIN", d.otp_per_min),
        otp_verify_per_min: parse_env("RATE_OTP_VERIFY_PER_MIN", d.otp_verify_per_min),
        otp_challenge_per_min: parse_env("RATE_OTP_CHALLENGE_PER_MIN", d.otp_challenge_per_min),
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

/// **Liveness** probe — the gateway's own endpoint (not proxied). Deliberately does NOT touch
/// Redis: liveness must reflect only "is the process running". Tying it to Redis would make a
/// transient Redis outage trigger a k8s **restart loop** (kill a perfectly-alive gateway), which
/// is exactly the wrong response — the gateway self-heals its Redis connection on its own.
/// Redis reachability is reported by [`readyz`] instead.
async fn healthz() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "service": SERVICE_NAME,
        "version": env!("CARGO_PKG_VERSION"),
    }))
}

/// **Readiness** probe — reflects whether the gateway can actually serve authed traffic, i.e.
/// whether Redis (the jti/trv revocation store + rate-limiter) is reachable. `PING`s through the
/// held reconnecting connection: `200 ready` on PONG, `503 degraded` on error/timeout. The PING
/// is bounded by an explicit 2s `tokio::time::timeout`; this is belt-and-suspenders over the
/// `ConnectionManager`'s own 2s response timeout (`REDIS_OP_TIMEOUT`) — the outer bound also covers
/// any path that resolves before a command is dispatched, so the probe can never hang. The k8s
/// `readinessProbe.timeoutSeconds` (3s) is set to exceed both.
///
/// k8s wires this to the **readiness** probe (pull a Redis-blind pod from the Service so it stops
/// receiving traffic) while keeping **liveness** on [`healthz`] (never restart for a Redis blip).
/// Because the connection self-heals, readiness flips back to `200` on its own once Redis returns.
async fn readyz(
    axum::extract::State(state): axum::extract::State<AppState>,
) -> (axum::http::StatusCode, Json<serde_json::Value>) {
    use axum::http::StatusCode;
    let mut conn = state.redis_conn.clone();
    let ping = tokio::time::timeout(Duration::from_secs(2), async {
        redis::cmd("PING").query_async::<String>(&mut conn).await
    })
    .await;
    match ping {
        Ok(Ok(_)) => (
            StatusCode::OK,
            Json(serde_json::json!({ "status": "ready", "service": SERVICE_NAME, "redis": "up" })),
        ),
        Ok(Err(e)) => {
            tracing::warn!(error = %e, "readyz: redis PING failed");
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(
                    serde_json::json!({ "status": "degraded", "service": SERVICE_NAME, "redis": "down" }),
                ),
            )
        }
        Err(_) => {
            tracing::warn!("readyz: redis PING timed out");
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(
                    serde_json::json!({ "status": "degraded", "service": SERVICE_NAME, "redis": "timeout" }),
                ),
            )
        }
    }
}
