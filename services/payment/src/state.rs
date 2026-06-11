//! Shared application state + the trait impls the extractors require.

use jsonwebtoken::DecodingKey;
use sqlx::PgPool;

use shared::auth::HasJwtSecret;
use shared::config::JwtConfig;
use shared::service_jwt::HasServiceJwt;

use crate::booking_client::{BookingReader, HttpBookingReader};

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    /// Read-replica pool (C5.3) for the payment list + data-export reads; primary fallback.
    /// Writes + read-after-write (charge, proration, single get_payment) use `db`.
    pub db_read: PgPool,
    /// Multiplexed Redis connection for the jti revocation blocklist (user auth).
    pub redis_conn: redis::aio::ConnectionManager,
    pub jwt_config: JwtConfig,
    /// Verifies inbound service-JWTs on the internal data-export read.
    pub service_decoding_key: DecodingKey,
    /// The booking-reader (mints a service-JWT + GETs booking's internal read).
    pub booking_reader: HttpBookingReader,
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
        &self.service_decoding_key
    }
}

/// Capability seam for the service-JWT'd internal data-export read (mirrors rating/booking).
pub trait PaymentInternalDeps: HasServiceJwt + Clone + Send + Sync + 'static {
    fn db(&self) -> &PgPool;
    /// Read-replica pool for the read-only data export (C5.3). Defaults to primary.
    fn db_read(&self) -> &PgPool {
        self.db()
    }
}

impl PaymentInternalDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
    fn db_read(&self) -> &PgPool {
        &self.db_read
    }
}

/// Capability seam for the payment endpoints. Mounting the handlers over a trait (rather
/// than the concrete [`AppState`]) lets tests exercise the `AuthUser` guard + role/
/// idempotency gates with a lightweight state — no live booking service needed, and the
/// auth-rejection path short-circuits before the DB/booking is touched (mirrors booking's
/// `BookingDeps`).
///
/// The booking reader is an associated type (not a `dyn` object) so the port can use native
/// `async fn` in the trait — static dispatch keeps the slice free of `async-trait`.
pub trait PaymentDeps: HasJwtSecret + Clone + Send + Sync + 'static {
    type Reader: BookingReader;

    fn db(&self) -> &PgPool;
    /// Read-replica pool for the payment list read (C5.3). Defaults to primary; single
    /// `get_payment` + charge/proration stay on `db` (money read-after-write).
    fn db_read(&self) -> &PgPool {
        self.db()
    }
    fn booking_reader(&self) -> &Self::Reader;
}

impl PaymentDeps for AppState {
    type Reader = HttpBookingReader;

    fn db(&self) -> &PgPool {
        &self.db
    }
    fn db_read(&self) -> &PgPool {
        &self.db_read
    }
    fn booking_reader(&self) -> &Self::Reader {
        &self.booking_reader
    }
}
