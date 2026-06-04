//! Shared application state + the trait impls the extractors require.

use jsonwebtoken::DecodingKey;
use sqlx::PgPool;

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
}

impl RevokeAllDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
}
