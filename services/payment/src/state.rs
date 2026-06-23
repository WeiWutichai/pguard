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
    /// Writes + read-after-write (the single get_payment) use `db`.
    pub db_read: PgPool,
    /// Multiplexed Redis connection for the jti revocation blocklist (user auth).
    pub redis_conn: redis::aio::ConnectionManager,
    pub jwt_config: JwtConfig,
    /// Verifies inbound service-JWTs on the internal data-export read.
    pub service_decoding_key: DecodingKey,
    /// The booking-reader (MINTS a service-JWT + GETs booking's `/internal/bookings/{id}`) —
    /// the authoritative source for the PRE-PAY estimate + ownership/payability authz.
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

/// Capability seam for the customer-facing payment endpoints (createPayment + get/list/
/// admin-ledger/reports). Mounting the handlers over a trait (rather than the concrete
/// [`AppState`]) lets tests exercise the `AuthUser` guard + role/authz gates with a lightweight
/// state — the auth/role rejection paths short-circuit before the DB is touched (mirrors
/// rating's `RatingDeps`).
///
/// v2 is PRE-PAY: `createPayment` reads the authoritative booking through the booking reader (an
/// associated type → static dispatch, native `async fn`, no `async-trait`) to compute the estimate
/// + verify ownership/payability, so this seam carries a `BookingReader`.
pub trait PaymentDeps: HasJwtSecret + Clone + Send + Sync + 'static {
    type Reader: BookingReader;

    fn db(&self) -> &PgPool;
    /// Read-replica pool for the payment list read (C5.3). Defaults to primary; the single
    /// `get_payment` stays on `db` (money read-after-write).
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
