//! Postgres connection pools. Ported from v1; C5.3 adds a read-replica pool.
//!
//! Two pools per service (CLAUDE.md "DB scaling"): the **primary** ([`create_pool`], writes +
//! read-after-write — in prod fronted by pgbouncer) and the **read replica**
//! ([`create_read_pool`], list/report/discovery reads). The replica pool falls back to the
//! primary URL when `DATABASE_READ_URL` is unset, so single-node dev/test is unchanged.

use std::time::Duration;

use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;

use crate::config::DatabaseConfig;
use crate::error::AppError;

pub async fn create_pool(config: &DatabaseConfig) -> Result<PgPool, AppError> {
    let pool = PgPoolOptions::new()
        .max_connections(config.max_connections)
        .acquire_timeout(Duration::from_secs(5))
        .connect(&config.url)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to connect to database: {e}")))?;

    tracing::info!(
        "Primary database pool created (max_connections={})",
        config.max_connections
    );

    Ok(pool)
}

/// Create the READ-replica pool for list/report/discovery reads. Connects to
/// `DATABASE_READ_URL` (the replica) when set, else falls back to the PRIMARY url so a
/// single-node deployment works unchanged. Writes + read-after-write must use [`create_pool`].
pub async fn create_read_pool(config: &DatabaseConfig) -> Result<PgPool, AppError> {
    let (url, target) = config.read_target();
    let pool = PgPoolOptions::new()
        .max_connections(config.read_max_connections)
        .acquire_timeout(Duration::from_secs(5))
        .connect(url)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to connect to read database: {e}")))?;

    tracing::info!(
        target,
        max_connections = config.read_max_connections,
        "Read database pool created"
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
