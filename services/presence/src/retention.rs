//! Scheduled GPS-history retention purge (PDPA §7.3). Runs forever on a fixed cadence,
//! deleting `location_history` rows older than the retention window. A transient DB error
//! never crashes presence — it logs and retries on the next tick.

use std::time::Duration;

use chrono::Utc;
use sqlx::PgPool;

use crate::repo;

/// Loop forever: every `interval`, delete history older than `retention_days`.
pub async fn run_retention(pool: PgPool, retention_days: i64, interval: Duration) {
    tracing::info!(
        retention_days,
        interval_secs = interval.as_secs(),
        "location_history retention task started"
    );
    loop {
        let cutoff = Utc::now() - chrono::Duration::days(retention_days);
        match repo::purge_older_than(&pool, cutoff).await {
            Ok(0) => tracing::debug!(%cutoff, "retention purge: nothing older than cutoff"),
            Ok(n) => tracing::info!(purged = n, %cutoff, "location_history retention purge"),
            Err(e) => tracing::error!("location_history retention purge failed: {e}"),
        }
        tokio::time::sleep(interval).await;
    }
}
