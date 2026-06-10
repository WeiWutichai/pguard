//! Shared application state + the trait impls the extractors require.

use jsonwebtoken::DecodingKey;
use sqlx::PgPool;

use shared::auth::HasJwtSecret;
use shared::config::{JwtConfig, ServiceJwtConfig};
use shared::service_jwt::HasServiceJwt;

use crate::discovery_client::{GuardCatalog, HttpDiscoveryClient, RatingReader};
use crate::s3::S3Client;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    /// Read-replica pool (C5.3) for list/discovery reads. Falls back to the primary when
    /// `DATABASE_READ_URL` is unset. Writes + read-after-write use `db`.
    pub db_read: PgPool,
    /// Multiplexed Redis connection for the jti revocation blocklist (user auth).
    pub redis_conn: redis::aio::MultiplexedConnection,
    pub jwt_config: JwtConfig,
    /// Separate secret for service-to-service JWTs — guards the `/internal/*` read that
    /// the payment/rating services call, and signs the discovery reads booking MINTS
    /// (CLAUDE.md "Service auth (internal)").
    pub service_jwt_config: ServiceJwtConfig,
    /// Discovery reads: the service-JWT'd profile catalog + rating summary clients.
    pub discovery: HttpDiscoveryClient,
    /// S3/MinIO presigner for check-in photos (upload + fresh signed download URLs).
    pub s3: S3Client,
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
    /// Read-replica pool for list reads (C5.3). Defaults to the primary, so test doubles +
    /// single-node deployments need no change; `AppState` overrides it with the replica pool.
    fn db_read(&self) -> &PgPool {
        self.db()
    }
    /// S3 presigner for check-in photos (mirrors chat's `ChatDeps::s3()` seam — presigning
    /// is pure, so test doubles use a stub client with dummy credentials).
    fn s3(&self) -> &S3Client;
}

impl BookingDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
    fn db_read(&self) -> &PgPool {
        &self.db_read
    }
    fn s3(&self) -> &S3Client {
        &self.s3
    }
}

/// Capability seam for the service-JWT'd internal read (`GET /internal/bookings/{id}`).
/// Generic over [`HasServiceJwt`] so the `ServiceCaller` guard is unit-testable with a
/// lightweight state — the rejection path short-circuits before the DB is touched (mirrors
/// identity's `RevokeAllDeps`).
pub trait BookingInternalDeps: HasServiceJwt + Clone + Send + Sync + 'static {
    fn db(&self) -> &PgPool;
    /// Read-replica pool for the read-only data export (C5.3). Defaults to primary.
    fn db_read(&self) -> &PgPool {
        self.db()
    }
}

impl BookingInternalDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
    fn db_read(&self) -> &PgPool {
        &self.db_read
    }
}

/// Capability seam for the discovery aggregator (`GET /available-guards`). The two readers
/// are associated types (static dispatch, native `async fn` ports) so the handler's
/// aggregation is unit-testable with stubs — no live profile/rating needed.
pub trait DiscoveryDeps: HasJwtSecret + Clone + Send + Sync + 'static {
    type Catalog: GuardCatalog;
    type Rating: RatingReader;

    fn guard_catalog(&self) -> &Self::Catalog;
    fn rating_reader(&self) -> &Self::Rating;
}

impl DiscoveryDeps for AppState {
    type Catalog = HttpDiscoveryClient;
    type Rating = HttpDiscoveryClient;

    fn guard_catalog(&self) -> &HttpDiscoveryClient {
        &self.discovery
    }
    fn rating_reader(&self) -> &HttpDiscoveryClient {
        &self.discovery
    }
}
