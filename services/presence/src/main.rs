//! pguard presence service — GPS location history + retention (renamed tracking).
//!
//! Phase 5 C5.2 establishes the SENSITIVE `presence.location_history` store and the 90-day
//! retention purge that v1 never implemented (the headline PDPA §7.3 gap — unbounded GPS
//! history). WS GPS ingestion + live-position reads land in a later presence build; this
//! slice owns the table, its purge job, and the index the purge needs.
//!
//! Wiring only — config, db pool, the retention task spawn, telemetry. The purge SQL lives
//! in `repo`, the scheduled loop in `retention`.

mod repo;
mod retention;

use std::time::Duration;

use axum::routing::get;
use axum::{Json, Router};
use serde_json::{json, Value};

use shared::config::DatabaseConfig;
use shared::db::create_pool;

const SERVICE_NAME: &str = "presence";
const VERSION: &str = env!("CARGO_PKG_VERSION");
const PORT: u16 = 3009;
/// GPS-history retention window — PDPA §7.3 recommends 90 days for this sensitive store.
const RETENTION_DAYS: i64 = 90;
/// How often the purge runs (hourly by default).
const PURGE_INTERVAL_SECS: u64 = 3600;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _telemetry = observability::init_telemetry(SERVICE_NAME);

    // --- config + db (fail-fast at startup) ---
    let db_config = DatabaseConfig::from_env()?;
    let db = create_pool(&db_config).await?;

    // --- scheduled GPS-history retention purge (PDPA §7.3) ---
    let retention_days = env_i64("LOCATION_RETENTION_DAYS", RETENTION_DAYS);
    let purge_interval =
        Duration::from_secs(env_u64("LOCATION_PURGE_INTERVAL_SECS", PURGE_INTERVAL_SECS));
    {
        let pool = db.clone();
        tokio::spawn(async move {
            retention::run_retention(pool, retention_days, purge_interval).await;
        });
    }

    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/metrics", get(observability::metrics_handler))
        .layer(axum::middleware::from_fn(
            observability::telemetry_middleware,
        ));

    let addr = format!("0.0.0.0:{PORT}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(service = SERVICE_NAME, %addr, "presence-service listening");
    axum::serve(listener, app).await?;
    Ok(())
}

/// Positive integer from env, else `default`.
fn env_i64(key: &str, default: i64) -> i64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .filter(|&n| n > 0)
        .unwrap_or(default)
}

fn env_u64(key: &str, default: u64) -> u64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .filter(|&n| n > 0)
        .unwrap_or(default)
}

/// Liveness/readiness probe.
async fn healthz() -> Json<Value> {
    Json(json!({ "status": "ok", "service": SERVICE_NAME, "version": VERSION }))
}
