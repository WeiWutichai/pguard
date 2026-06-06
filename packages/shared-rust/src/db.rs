//! Postgres connection pools. Ported from v1; C5.3 adds a read-replica pool.
//!
//! Two pools per service (CLAUDE.md "DB scaling"): the **primary** ([`create_pool`], writes +
//! read-after-write — in prod fronted by pgbouncer) and the **read replica**
//! ([`create_read_pool`], list/report/discovery reads). The replica pool falls back to the
//! primary URL when `DATABASE_READ_URL` is unset, so single-node dev/test is unchanged.

use std::str::FromStr;
use std::time::Duration;

use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use sqlx::PgPool;

use crate::config::DatabaseConfig;
use crate::error::AppError;

/// The PRIMARY pool (writes + read-after-write). EAGER connect — the primary is essential, so
/// a service that can't reach it at startup should fail fast.
///
/// `statement_cache_capacity(0)`: in prod the primary is fronted by pgbouncer in TRANSACTION
/// pooling mode, which can hand a different backend per transaction — incompatible with sqlx's
/// default named, persistent server-side prepared statements (`prepared statement "sqlx_s_N"
/// does not exist`). Disabling the cache forces one-shot unnamed prepares that are safe across
/// multiplexed backends. (Negligible cost in dev where `DATABASE_URL` is a direct connection.)
pub async fn create_pool(config: &DatabaseConfig) -> Result<PgPool, AppError> {
    let opts = PgConnectOptions::from_str(&config.url)
        .map_err(|e| AppError::Internal(format!("invalid DATABASE_URL: {e}")))?
        .statement_cache_capacity(0);
    let pool = PgPoolOptions::new()
        .max_connections(config.max_connections)
        .acquire_timeout(Duration::from_secs(5))
        .connect_with(opts)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to connect to database: {e}")))?;

    tracing::info!(
        "Primary database pool created (max_connections={}, prepared-statement cache disabled for pgbouncer transaction mode)",
        config.max_connections
    );

    Ok(pool)
}

/// The READ-replica pool for list/report/discovery reads. Targets `DATABASE_READ_URL` (the
/// replica) when set, else falls back to the PRIMARY url so a single-node deployment works
/// unchanged. Writes + read-after-write must use [`create_pool`].
///
/// LAZY connect (`connect_lazy_with`): a temporarily-unavailable replica (e.g. mid
/// `pg_basebackup` on first boot) must DEGRADE reads, not abort service startup — connections
/// open on first query. The prepared-statement cache stays ENABLED: in the prod topology the
/// replica is a DIRECT connection (not pooled), so named prepares are safe + faster. If you
/// front the replica with a transaction-mode pooler, add `.statement_cache_capacity(0)` here.
pub async fn create_read_pool(config: &DatabaseConfig) -> Result<PgPool, AppError> {
    let (url, target) = config.read_target();
    let opts = PgConnectOptions::from_str(url)
        .map_err(|e| AppError::Internal(format!("invalid DATABASE_READ_URL: {e}")))?;
    let pool = PgPoolOptions::new()
        .max_connections(config.read_max_connections)
        .acquire_timeout(Duration::from_secs(5))
        .connect_lazy_with(opts);

    tracing::info!(
        target,
        max_connections = config.read_max_connections,
        "Read database pool created (lazy; a down replica degrades reads, not startup)"
    );

    Ok(pool)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg(read_url: Option<&str>) -> DatabaseConfig {
        DatabaseConfig {
            url: "postgres://primary/db".to_string(),
            read_url: read_url.map(str::to_string),
            max_connections: 20,
            read_max_connections: 10,
        }
    }

    #[test]
    fn read_target_uses_replica_when_set() {
        let c = cfg(Some("postgres://replica/db"));
        assert_eq!(c.read_target(), ("postgres://replica/db", "replica"));
    }

    #[test]
    fn read_target_falls_back_to_primary_when_unset() {
        let c = cfg(None);
        assert_eq!(
            c.read_target(),
            ("postgres://primary/db", "primary-fallback")
        );
    }
}
