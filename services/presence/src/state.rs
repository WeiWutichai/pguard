//! Shared application state + the capability seams the handlers are generic over.
//!
//! presence holds NO service-JWT (it exposes no `/internal` endpoint and makes no synchronous
//! cross-service HTTP read); it consumes `pguard.events.booking.*` to derive its IDOR
//! read-model instead. It needs the user-JWT decoding key + the cache Redis (for the `AuthUser`
//! revocation check + the WS re-auth tick) and a Redis pub/sub connection (to republish raw
//! GPS to the admin live map).
//!
//! Handlers are generic over [`PresenceDeps`] (mirroring calling's `CallDeps`) so the role
//! gate + IDOR authz are unit-testable with a lightweight state — the [`BookingAuthz`] seam
//! (mirroring calling's `BookingReader`) lets a test stub `has_active_booking` without a DB.

use jsonwebtoken::DecodingKey;
use sqlx::PgPool;
use uuid::Uuid;

use shared::auth::HasJwtSecret;
use shared::config::JwtConfig;
use shared::error::AppError;

use crate::repo;

/// The IDOR authorization read: does `customer_id` have an ACTIVE booking with `guard_id`?
/// Decoupled from the DB so handler authz tests are hermetic (mirrors calling's `BookingReader`).
#[allow(async_fn_in_trait)] // internal trait, never `dyn`.
pub trait BookingAuthz: Send + Sync {
    async fn has_active_booking(&self, customer_id: Uuid, guard_id: Uuid)
        -> Result<bool, AppError>;
}

/// DB-backed authz — reads the event-derived `presence.guard_assignments` read-model.
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
    /// Read-replica pool (C5.3) for the heavy admin/bulk reads (`/locations`, `/guards/{id}/
    /// history`); falls back to the primary URL when `DATABASE_READ_URL` is unset. The WS
    /// ingress writes (upsert/insert/set_offline) + the IDOR authz read stay on `db`.
    pub db_read: PgPool,
    /// Cache Redis — the `AuthUser` jti/force-revoke blocklist + the WS re-auth tick.
    pub redis_cache: redis::aio::ConnectionManager,
    /// Pub/sub Redis — republish raw GPS to the admin live map (channel `presence:gps`).
    pub redis_pub: redis::aio::ConnectionManager,
    pub jwt_config: JwtConfig,
    pub booking_authz: DbBookingAuthz,
}

impl HasJwtSecret for AppState {
    fn jwt_secret(&self) -> &str {
        &self.jwt_config.secret
    }
    fn decoding_key(&self) -> &DecodingKey {
        &self.jwt_config.decoding_key
    }
    fn redis_conn(&self) -> &redis::aio::ConnectionManager {
        &self.redis_cache
    }
}

/// Capability seam for the presence endpoints (REST reads + WS ingress). Mounting handlers over
/// a trait (not the concrete [`AppState`]) keeps the role gate + IDOR authz hermetically
/// testable. The authz reader is an associated type (static dispatch) so the port uses native
/// `async fn` (no `async-trait`).
pub trait PresenceDeps: HasJwtSecret + Clone + Send + Sync + 'static {
    type Authz: BookingAuthz;

    fn db(&self) -> &PgPool;
    /// Read-replica pool for the heavy admin/bulk reads (`/locations`, `/guards/{id}/history`)
    /// — C5.3. Defaults to the primary; the WS writes + the IDOR authz read stay on `db`.
    fn db_read(&self) -> &PgPool {
        self.db()
    }
    fn booking_authz(&self) -> &Self::Authz;
    /// Redis connection raw GPS is published on (WS path).
    fn redis_pub(&self) -> &redis::aio::ConnectionManager;
}

impl PresenceDeps for AppState {
    type Authz = DbBookingAuthz;

    fn db(&self) -> &PgPool {
        &self.db
    }
    fn db_read(&self) -> &PgPool {
        &self.db_read
    }
    fn booking_authz(&self) -> &Self::Authz {
        &self.booking_authz
    }
    fn redis_pub(&self) -> &redis::aio::ConnectionManager {
        &self.redis_pub
    }
}
