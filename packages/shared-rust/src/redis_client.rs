//! Redis client factory. Ported from v1.

use std::time::Duration;

use crate::error::AppError;

/// Create a Redis client from a connection URL. Used for the pub/sub connection (callers
/// obtain a fresh async connection from it) and as the base for [`create_connection_manager`].
pub fn create_redis_client(url: &str) -> Result<redis::Client, AppError> {
    redis::Client::open(url)
        .map_err(|e| AppError::Internal(format!("Failed to create Redis client: {e}")))
}

/// Each reconnect attempt / command waits at most this long before erroring. WITHOUT these
/// the manager defaults to `None` (no timeout) — a network partition (no TCP RST) could then
/// hang a request indefinitely, defeating timely fail-closed. 2s keeps a down-Redis request
/// erroring quickly (→ 401/500 at the auth layers, 503 at `/readyz`) instead of blocking.
const REDIS_OP_TIMEOUT: Duration = Duration::from_secs(2);
/// Cap the exponential reconnect backoff. The manager backs off (base 2 × 100ms factor) so a
/// recovering Redis is NOT hammered by a busy retry loop, but the cap bounds recovery latency:
/// once Redis is back, the next reconnect fires within ≤2s rather than waiting out a long delay.
const REDIS_RECONNECT_MAX_DELAY_MS: u64 = 2_000;

/// Create a **reconnecting** Redis connection for a long-lived hot path (edge auth, rate-limit,
/// jti/trv revocation). Unlike a raw [`redis::aio::MultiplexedConnection`] — which is opened once
/// and **never re-established** if the socket breaks (a single Redis restart wedges it forever,
/// the chaos case-3 HIGH finding) — a [`redis::aio::ConnectionManager`] reconnects in the
/// background with bounded exponential backoff:
///
/// - while Redis is down, in-flight commands ERROR (passed straight to the caller → the auth
///   layers **fail closed**), so the posture during an outage is unchanged;
/// - a "connection dropped" error triggers a background reconnect; if it fails (Redis still
///   down) the next I/O error triggers another attempt — so it **self-heals within seconds**
///   once Redis returns, with **no service restart** and no busy loop (the backoff + cap).
///
/// The initial connect is awaited (a connect error is returned here), matching the prior
/// startup behaviour. Clone is cheap and shares the one underlying socket.
pub async fn create_connection_manager(
    url: &str,
) -> Result<redis::aio::ConnectionManager, AppError> {
    let client = create_redis_client(url)?;
    let config = redis::aio::ConnectionManagerConfig::new()
        .set_connection_timeout(REDIS_OP_TIMEOUT)
        .set_response_timeout(REDIS_OP_TIMEOUT)
        .set_max_delay(REDIS_RECONNECT_MAX_DELAY_MS);
    redis::aio::ConnectionManager::new_with_config(client, config)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to create Redis connection manager: {e}")))
}
