//! Shared application state + the trait impls the extractors require.

use jsonwebtoken::DecodingKey;
use sqlx::PgPool;

use shared::auth::HasJwtSecret;
use shared::config::JwtConfig;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    /// Multiplexed Redis connection for the jti + force-revoke-all blocklist (user auth).
    /// The `AuthUser` extractor reads it on every request — this slice never writes it.
    pub redis_conn: redis::aio::MultiplexedConnection,
    pub jwt_config: JwtConfig,
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

/// Capability seam for the profile endpoints. Mounting the handlers over a trait (rather
/// than the concrete [`AppState`]) lets tests exercise the `AuthUser` guard + the role
/// gate with a lightweight state — the rejection paths short-circuit before the DB is
/// touched (mirrors booking's `BookingDeps`).
pub trait ProfileDeps: HasJwtSecret + Clone + Send + Sync + 'static {
    fn db(&self) -> &PgPool;
}

impl ProfileDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
}
