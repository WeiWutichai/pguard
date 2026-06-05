//! Shared application state + the trait impls the extractors require.
//!
//! rating both MINTS a service-JWT (to read booking's `/internal/bookings/{id}`) and VERIFIES
//! a service-JWT (its own `/internal/guards/{id}/rating-summary`), so `AppState` carries the
//! booking reader (encoding key) AND the service decoding key.

use jsonwebtoken::DecodingKey;
use sqlx::PgPool;

use shared::auth::HasJwtSecret;
use shared::config::JwtConfig;
use shared::service_jwt::HasServiceJwt;

use crate::booking_client::{BookingReader, HttpBookingReader};

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    /// Multiplexed Redis connection for the jti revocation blocklist (user auth).
    pub redis_conn: redis::aio::MultiplexedConnection,
    pub jwt_config: JwtConfig,
    /// Verifies inbound service-JWTs on the internal rating-summary endpoint.
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
    fn redis_conn(&self) -> &redis::aio::MultiplexedConnection {
        &self.redis_conn
    }
}

impl HasServiceJwt for AppState {
    fn service_decoding_key(&self) -> &DecodingKey {
        &self.service_decoding_key
    }
}

/// Capability seam for the AuthUser-gated rating endpoints (submit + admin). Mounting the
/// handlers over a trait (rather than the concrete [`AppState`]) lets tests exercise the
/// guards with a lightweight state — no live booking service needed. The booking reader is
/// an associated type (static dispatch) so the port can use native `async fn` (no `async-trait`).
pub trait RatingDeps: HasJwtSecret + Clone + Send + Sync + 'static {
    type Reader: BookingReader;

    fn db(&self) -> &PgPool;
    fn booking_reader(&self) -> &Self::Reader;
}

impl RatingDeps for AppState {
    type Reader = HttpBookingReader;

    fn db(&self) -> &PgPool {
        &self.db
    }
    fn booking_reader(&self) -> &Self::Reader {
        &self.booking_reader
    }
}

/// Capability seam for the service-JWT'd internal endpoint (`/internal/guards/{id}/rating-summary`).
/// Only needs the service decoding key + the DB, so it is testable without Redis/booking
/// (mirrors booking's `BookingInternalDeps`).
pub trait RatingInternalDeps: HasServiceJwt + Clone + Send + Sync + 'static {
    fn db(&self) -> &PgPool;
}

impl RatingInternalDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
}
