//! Redis client factory. Ported from v1.

use crate::error::AppError;

/// Create a Redis client from a connection URL. Used for the cache connection and,
/// separately, for the pub/sub connection (callers obtain async connections from it).
pub fn create_redis_client(url: &str) -> Result<redis::Client, AppError> {
    redis::Client::open(url)
        .map_err(|e| AppError::Internal(format!("Failed to create Redis client: {e}")))
}
