//! Shared application state + the trait impls the extractors require.

use jsonwebtoken::DecodingKey;
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
    pub redis_conn: redis::aio::MultiplexedConnection,
    pub jwt_config: JwtConfig,
    pub service_jwt_config: ServiceJwtConfig,
}

impl HasJwtSecret for AppState {
    fn jwt_secret(&self) -> &str {
        &self.jwt_config.secret
    }
    fn decoding_key(&self) -> &DecodingKey {
        &self.jwt_config.decoding_key
    }
    fn redis_conn(&self) -> &redis::aio::MultiplexedConnection {
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
    fn revocation_redis(&self) -> Option<redis::aio::MultiplexedConnection>;
}

impl RevokeAllDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
    fn revocation_redis(&self) -> Option<redis::aio::MultiplexedConnection> {
        Some(self.redis_conn.clone())
    }
}

/// Publish the user's new revocation version so the [`shared::auth::AuthUser`] extractor
/// rejects access tokens stamped with an older version immediately (writes
/// `user_trv:{user_id}`). Best-effort: a Redis hiccup must not fail the revoke — the DB is
/// the source of truth and refresh families are already revoked. No TTL: this marker is the
/// authoritative cache the decode path reads for force-revoke-all.
pub async fn mark_user_revoked(
    redis: &mut redis::aio::MultiplexedConnection,
    user_id: Uuid,
    version: i32,
) {
    let key = format!("user_trv:{user_id}");
    if let Err(e) = redis.set::<_, _, ()>(&key, version).await {
        tracing::warn!("failed to publish revocation marker for {user_id}: {e}");
    }
}
