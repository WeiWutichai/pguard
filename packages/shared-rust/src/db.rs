//! Postgres connection pool. Ported from v1.

use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;

use crate::config::DatabaseConfig;
use crate::error::AppError;

pub async fn create_pool(config: &DatabaseConfig) -> Result<PgPool, AppError> {
    let pool = PgPoolOptions::new()
        .max_connections(config.max_connections)
        .acquire_timeout(std::time::Duration::from_secs(5))
        .connect(&config.url)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to connect to database: {e}")))?;

    tracing::info!(
        "Database pool created (max_connections={})",
        config.max_connections
    );

    Ok(pool)
}
