//! pguard chat service — messaging (N+1 fixed).
//!
//! v2 scaffold stub: exposes only /healthz. Real handlers adopt the per-service
//! domain layering (api / domain / repo / events) and shared::{config, auth, error,
//! service_jwt} per CLAUDE.md. No Provider-style globals; no cross-schema writes —
//! cross-service state changes go through the NATS event bus (shared-events).

use axum::routing::get;
use axum::{Json, Router};
use serde_json::{json, Value};

const SERVICE_NAME: &str = "chat";
const VERSION: &str = env!("CARGO_PKG_VERSION");
const PORT: u16 = 3010;

#[tokio::main]
async fn main() {
    let _telemetry = observability::init_telemetry(SERVICE_NAME);

    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/metrics", get(observability::metrics_handler))
        .layer(axum::middleware::from_fn(
            observability::telemetry_middleware,
        ));

    let addr = format!("0.0.0.0:{PORT}");
    // startup-only expect — CLAUDE.md forbids unwrap/expect only in the request path.
    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .expect("failed to bind health listener");
    tracing::info!(service = SERVICE_NAME, %addr, "listening");
    axum::serve(listener, app).await.expect("server error");
}

/// Liveness/readiness probe.
async fn healthz() -> Json<Value> {
    Json(json!({ "status": "ok", "service": SERVICE_NAME, "version": VERSION }))
}
