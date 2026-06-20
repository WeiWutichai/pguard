//! Shared application state + the trait impls the extractors require.

use jsonwebtoken::{DecodingKey, EncodingKey};
use redis::AsyncCommands;
use sqlx::PgPool;
use uuid::Uuid;

use shared::auth::HasJwtSecret;
use shared::config::{JwtConfig, ServiceJwtConfig};
use shared::service_jwt::HasServiceJwt;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    /// Multiplexed Redis connection for the access-jti revocation blocklist.
    pub redis_conn: redis::aio::ConnectionManager,
    pub jwt_config: JwtConfig,
    pub service_jwt_config: ServiceJwtConfig,
    /// PDPA data-export aggregator: fans out to the data owners' internal export reads.
    pub export_client: crate::export_client::ExportClient,
}

impl HasJwtSecret for AppState {
    fn jwt_secret(&self) -> &str {
        &self.jwt_config.secret
    }
    fn decoding_key(&self) -> &DecodingKey {
        &self.jwt_config.decoding_key
    }
    fn redis_conn(&self) -> &redis::aio::ConnectionManager {
        &self.redis_conn
    }
}

impl HasServiceJwt for AppState {
    fn service_decoding_key(&self) -> &DecodingKey {
        &self.service_jwt_config.decoding_key
    }
}

/// Capability seam for the internal `revoke-all` route. Mounting `internal_revoke_all`
/// over a trait (rather than the concrete [`AppState`]) lets tests exercise the
/// service-JWT guard with a lightweight state — no live Redis/DB needed to prove
/// rejection. Mirrors the notification service's `InternalPushDeps`.
pub trait RevokeAllDeps: HasServiceJwt + Clone + Send + Sync + 'static {
    fn db(&self) -> &PgPool;
    /// A clonable Redis connection for publishing the revocation marker, or `None` in
    /// tests that only exercise the service-JWT guard (which never reaches Redis).
    fn revocation_redis(&self) -> Option<redis::aio::ConnectionManager>;
}

impl RevokeAllDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
    fn revocation_redis(&self) -> Option<redis::aio::ConnectionManager> {
        Some(self.redis_conn.clone())
    }
}

/// Capability seam for `POST /auth/register`. Mounting the handler over a trait (rather
/// than the concrete [`AppState`]) lets an integration test drive it with a lightweight
/// state — a real Redis (for the single-use GETDEL/SET) + the JWT keys + a lazy DB pool —
/// without building the full `AppState` (export client, service-JWT config). Mirrors the
/// `RevokeAllDeps` seam.
pub trait RegisterDeps: Clone + Send + Sync + 'static {
    fn db(&self) -> &PgPool;
    fn redis(&self) -> redis::aio::ConnectionManager;
    fn jwt_encoding_key(&self) -> &EncodingKey;
    fn jwt_decoding_key(&self) -> &DecodingKey;
}

impl RegisterDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
    fn redis(&self) -> redis::aio::ConnectionManager {
        self.redis_conn.clone()
    }
    fn jwt_encoding_key(&self) -> &EncodingKey {
        &self.jwt_config.encoding_key
    }
    fn jwt_decoding_key(&self) -> &DecodingKey {
        &self.jwt_config.decoding_key
    }
}

/// Max attempts (1 initial + retries) for the revocation-marker write before giving up.
const MARK_REVOKED_MAX_ATTEMPTS: u32 = 3;
/// Base backoff between marker-write attempts; doubles each retry (50ms, 100ms).
const MARK_REVOKED_BACKOFF: std::time::Duration = std::time::Duration::from_millis(50);

/// Publish the user's new revocation version so the [`shared::auth::AuthUser`] extractor
/// rejects access tokens stamped with an older version immediately (writes
/// `user_trv:{user_id}`). No TTL: this marker is the authoritative cache the decode path
/// (identity + gateway) reads for force-revoke-all, defaulting to version 0 when absent.
///
/// Durability matters: `authenticate_token` reads the marker SOLELY from Redis, so a dropped
/// write silently re-validates already-revoked ACCESS tokens. The write is therefore retried
/// with a small bounded backoff; on persistent failure it emits a loud `tracing::error!` and
/// returns `Err` so the caller knows revocation is NOT fully effective (the DB version bump +
/// refresh-family revocation still stand — only the in-flight access-token marker is missing).
pub async fn mark_user_revoked(
    redis: &mut redis::aio::ConnectionManager,
    user_id: Uuid,
    version: i32,
) -> Result<(), redis::RedisError> {
    let key = format!("user_trv:{user_id}");
    let mut last_err = None;
    for attempt in 1..=MARK_REVOKED_MAX_ATTEMPTS {
        match redis.set::<_, _, ()>(&key, version).await {
            Ok(()) => return Ok(()),
            Err(e) => {
                tracing::warn!(
                    %user_id,
                    attempt,
                    "failed to publish revocation marker (will retry): {e}"
                );
                last_err = Some(e);
                if attempt < MARK_REVOKED_MAX_ATTEMPTS {
                    tokio::time::sleep(MARK_REVOKED_BACKOFF * (1 << (attempt - 1))).await;
                }
            }
        }
    }
    // Persistent failure: in-flight access tokens for this user will NOT be rejected until they
    // expire naturally. Make it loud and propagate so the revoke path does not falsely succeed.
    let err = last_err.unwrap_or_else(|| {
        redis::RedisError::from((redis::ErrorKind::IoError, "revocation marker write failed"))
    });
    tracing::error!(
        %user_id,
        attempts = MARK_REVOKED_MAX_ATTEMPTS,
        "REVOCATION MARKER WRITE FAILED — in-flight access tokens remain valid until expiry: {err}"
    );
    Err(err)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// On a live Redis, `mark_user_revoked` writes the `user_trv:{id}` marker and returns `Ok`,
    /// and the written version is readable by the decode path. Redis-gated (matches the crate's
    /// SKIP-without-Redis convention); the persistent-failure path can't be exercised hermetically
    /// because `ConnectionManager` awaits a live initial connect.
    #[tokio::test]
    async fn mark_user_revoked_writes_marker_and_returns_ok() {
        let Ok(redis_url) =
            std::env::var("TEST_REDIS_URL").or_else(|_| std::env::var("REDIS_CACHE_URL"))
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let Ok(mut redis) = shared::redis_client::create_connection_manager(&redis_url).await
        else {
            eprintln!("SKIP: could not connect to test Redis");
            return;
        };

        let user_id = Uuid::new_v4();
        let key = format!("user_trv:{user_id}");

        mark_user_revoked(&mut redis, user_id, 7)
            .await
            .expect("marker write should succeed against live Redis");

        let stored: i32 = redis
            .get(&key)
            .await
            .expect("read back the revocation marker");
        assert_eq!(stored, 7, "marker holds the published revocation version");

        let _: () = redis.del(&key).await.expect("cleanup marker");
    }
}
