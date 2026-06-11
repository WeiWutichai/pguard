//! Shared application state + the trait impls the extractors require.

use jsonwebtoken::DecodingKey;
use sqlx::PgPool;

use shared::auth::HasJwtSecret;
use shared::config::{JwtConfig, ServiceJwtConfig};
use shared::service_jwt::HasServiceJwt;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    /// Read-replica pool (C5.3) for admin list + discovery-catalog reads; falls back to the
    /// primary when `DATABASE_READ_URL` is unset. Writes + read-after-write use `db`.
    pub db_read: PgPool,
    /// Multiplexed Redis connection for the jti + force-revoke-all blocklist (user auth).
    /// The `AuthUser` extractor reads it on every request — this slice never writes it.
    pub redis_conn: redis::aio::ConnectionManager,
    pub jwt_config: JwtConfig,
    /// Separate secret for service-to-service JWTs — guards the `/internal/guards` catalog
    /// read that booking's discovery calls (CLAUDE.md "Service auth (internal)").
    pub service_jwt_config: ServiceJwtConfig,
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

/// Capability seam for the profile endpoints. Mounting the handlers over a trait (rather
/// than the concrete [`AppState`]) lets tests exercise the `AuthUser` guard + the role
/// gate with a lightweight state — the rejection paths short-circuit before the DB is
/// touched (mirrors booking's `BookingDeps`).
pub trait ProfileDeps: HasJwtSecret + Clone + Send + Sync + 'static {
    fn db(&self) -> &PgPool;
    /// Read-replica pool for admin list reads (C5.3). Defaults to primary (test doubles +
    /// single-node need no change); `AppState` overrides it with the replica pool.
    fn db_read(&self) -> &PgPool {
        self.db()
    }
}

impl ProfileDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
    fn db_read(&self) -> &PgPool {
        &self.db_read
    }
}

/// Capability seam for the service-JWT'd internal guard-catalog read (`GET /internal/guards`).
/// Generic over [`HasServiceJwt`] so the `ServiceCaller` guard is unit-testable with a
/// lightweight state — the rejection path short-circuits before the DB is touched (mirrors
/// booking's `BookingInternalDeps`).
pub trait ProfileInternalDeps: HasServiceJwt + Clone + Send + Sync + 'static {
    fn db(&self) -> &PgPool;
    /// Read-replica pool for the internal catalog + data-export reads (C5.3). Defaults to primary.
    fn db_read(&self) -> &PgPool {
        self.db()
    }
}

impl ProfileInternalDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
    fn db_read(&self) -> &PgPool {
        &self.db_read
    }
}
