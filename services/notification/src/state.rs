//! Shared application state + the trait impls the extractors require.

use std::sync::Arc;

use jsonwebtoken::DecodingKey;
use sqlx::PgPool;

use shared::auth::HasJwtSecret;
use shared::config::{JwtConfig, ServiceJwtConfig};
use shared::service_jwt::HasServiceJwt;

use crate::fcm::Pusher;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    /// Multiplexed Redis connection for the jti revocation blocklist (user auth).
    pub redis_conn: redis::aio::MultiplexedConnection,
    pub jwt_config: JwtConfig,
    pub service_jwt_config: ServiceJwtConfig,
    pub pusher: Arc<dyn Pusher>,
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

/// Capability seam for the internal push route. Mounting `internal_push` over a trait
/// (rather than the concrete [`AppState`]) lets tests exercise the service-JWT guard
/// with a lightweight state — no live Redis/DB needed to prove rejection.
pub trait InternalPushDeps: HasServiceJwt + Clone + Send + Sync + 'static {
    fn db(&self) -> &PgPool;
    fn pusher(&self) -> Arc<dyn Pusher>;
}

impl InternalPushDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
    fn pusher(&self) -> Arc<dyn Pusher> {
        self.pusher.clone()
    }
}
