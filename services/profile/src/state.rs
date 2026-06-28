//! Shared application state + the trait impls the extractors require.

use jsonwebtoken::DecodingKey;
use sqlx::PgPool;
use uuid::Uuid;

use shared::auth::HasJwtSecret;
use shared::config::{JwtConfig, ServiceJwtConfig};
use shared::error::AppError;
use shared::service_jwt::HasServiceJwt;

use crate::identity_client::{HttpIdentityResolver, IdentityResolver};
use crate::repo;
use crate::s3::S3Client;

/// The IDOR authorization read: does `customer_id` have an ACTIVE booking with `guard_id`?
/// Decoupled from the DB so the customer-gate on the public guard-profile read is hermetically
/// testable (mirrors presence's `BookingAuthz`). Backed by the event-derived
/// `profile.guard_assignments` read-model.
#[allow(async_fn_in_trait)] // internal trait, never `dyn`.
pub trait BookingAuthz: Send + Sync {
    async fn has_active_booking(&self, customer_id: Uuid, guard_id: Uuid)
        -> Result<bool, AppError>;
}

/// DB-backed authz — reads the event-derived `profile.guard_assignments` read-model.
#[derive(Clone)]
pub struct DbBookingAuthz {
    pub db: PgPool,
}

impl BookingAuthz for DbBookingAuthz {
    async fn has_active_booking(
        &self,
        customer_id: Uuid,
        guard_id: Uuid,
    ) -> Result<bool, AppError> {
        repo::has_active_booking(&self.db, customer_id, guard_id).await
    }
}

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
    /// IDOR authz for the customer-readable guard mini-profile read — backed by the
    /// event-derived `profile.guard_assignments` read-model.
    pub booking_authz: DbBookingAuthz,
    /// S3/MinIO presigner for guard-document images (upload + presigned download).
    pub s3: S3Client,
    /// Service-JWT'd client to identity's `/internal/users/names` — the admin name-resolver merges
    /// admin names (which live ONLY in identity) for ids it can't resolve from its own profiles.
    pub identity_resolver: HttpIdentityResolver,
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
    /// The IDOR authz reader (associated type → static dispatch; the public guard-profile
    /// handler's customer gate calls it). A test stub makes the gate hermetic.
    type Authz: BookingAuthz;
    /// The identity name-resolver (associated type → static dispatch; the admin name-resolver
    /// merges admin names from identity). A test stub makes the merge hermetic.
    type Resolver: IdentityResolver;

    fn db(&self) -> &PgPool;
    /// Read-replica pool for admin list reads (C5.3). Defaults to primary (test doubles +
    /// single-node need no change); `AppState` overrides it with the replica pool.
    fn db_read(&self) -> &PgPool {
        self.db()
    }
    fn booking_authz(&self) -> &Self::Authz;
    /// S3 presigner for guard-document upload/download (mirrors booking's `BookingDeps::s3()`).
    fn s3(&self) -> &S3Client;
    /// The identity resolver — used by `admin_resolve_names` to fill in admin names.
    fn identity_resolver(&self) -> &Self::Resolver;
}

impl ProfileDeps for AppState {
    type Authz = DbBookingAuthz;
    type Resolver = HttpIdentityResolver;

    fn db(&self) -> &PgPool {
        &self.db
    }
    fn db_read(&self) -> &PgPool {
        &self.db_read
    }
    fn booking_authz(&self) -> &Self::Authz {
        &self.booking_authz
    }
    fn s3(&self) -> &S3Client {
        &self.s3
    }
    fn identity_resolver(&self) -> &Self::Resolver {
        &self.identity_resolver
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
    /// S3 presigner — the internal catalog presigns each guard's `avatar_key` into a
    /// short-lived `avatar_url` (the raw key never leaves profile), reusing the same
    /// `download_url` the owner/admin avatar path uses.
    fn s3(&self) -> &S3Client;
}

impl ProfileInternalDeps for AppState {
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
