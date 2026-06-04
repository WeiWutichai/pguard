//! Shared application state + the trait impls the extractors require.

use jsonwebtoken::DecodingKey;
use sqlx::PgPool;

use shared::auth::HasJwtSecret;
use shared::config::{JwtConfig, ServiceJwtConfig};
use shared::service_jwt::HasServiceJwt;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    /// Multiplexed Redis connection for the jti revocation blocklist (user auth).
    pub redis_conn: redis::aio::MultiplexedConnection,
    pub jwt_config: JwtConfig,
    /// Separate secret for service-to-service JWTs — guards the `/internal/*` read that
    /// the payment service calls (CLAUDE.md "Service auth (internal)").
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

/// Capability seam for the booking endpoints. Mounting the handlers over a trait (rather
/// than the concrete [`AppState`]) lets tests exercise the `AuthUser` guard with a
/// lightweight state — no live NATS needed, and the rejection path short-circuits before
/// the DB is touched (mirrors notification's `InternalPushDeps`).
pub trait BookingDeps: HasJwtSecret + Clone + Send + Sync + 'static {
    fn db(&self) -> &PgPool;
}

impl BookingDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
}

/// Capability seam for the service-JWT'd internal read (`GET /internal/bookings/{id}`).
/// Generic over [`HasServiceJwt`] so the `ServiceCaller` guard is unit-testable with a
/// lightweight state — the rejection path short-circuits before the DB is touched (mirrors
/// identity's `RevokeAllDeps`).
pub trait BookingInternalDeps: HasServiceJwt + Clone + Send + Sync + 'static {
    fn db(&self) -> &PgPool;
}

impl BookingInternalDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
}
