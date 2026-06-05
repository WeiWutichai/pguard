//! Shared application state + the trait impls the extractors require.
//!
//! calling MINTS service-JWTs (to authorize a call against booking) but exposes no `/internal`
//! endpoint, so it needs the service ENCODING key (held inside the booking reader) but not a
//! service decoding key. The WS signaling registry (user → live socket sender) lives here so
//! the relay can route a signal from one participant to the other.

use std::collections::HashMap;
use std::sync::Arc;

use jsonwebtoken::DecodingKey;
use sqlx::PgPool;
use tokio::sync::{mpsc, Mutex};
use uuid::Uuid;

use shared::auth::HasJwtSecret;
use shared::config::JwtConfig;

use crate::booking_client::{BookingReader, HttpBookingReader};

/// A live WS session's outbound channel — the relay pushes JSON text frames here. One entry
/// per connected user; replaced if the same user reconnects.
///
/// SCALING CONSTRAINT: this registry is PER-PROCESS (in-memory). WS signaling therefore
/// requires a SINGLE calling replica until cross-instance relay (e.g. a Redis pub/sub or NATS
/// fan-out keyed by user_id) is added — tracked as a Phase 5 follow-up. The REST call-control
/// path is stateless and already scales horizontally.
pub type Registry = Arc<Mutex<HashMap<Uuid, mpsc::UnboundedSender<String>>>>;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    /// Multiplexed Redis connection for the jti revocation blocklist (user auth).
    pub redis_conn: redis::aio::MultiplexedConnection,
    pub jwt_config: JwtConfig,
    /// The booking-reader (mints a service-JWT + GETs booking's internal read for authz).
    pub booking_reader: HttpBookingReader,
    /// Live WS signaling sessions (user_id → outbound sender).
    pub registry: Registry,
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

/// Capability seam for the calling endpoints (REST + WS). Mounting the handlers over a trait
/// (rather than the concrete [`AppState`]) lets tests exercise the `AuthUser` guard + authz
/// with a lightweight state — no live booking service needed. The booking reader is an
/// associated type (static dispatch) so the port uses native `async fn` (no `async-trait`).
pub trait CallDeps: HasJwtSecret + Clone + Send + Sync + 'static {
    type Reader: BookingReader;

    fn db(&self) -> &PgPool;
    fn booking_reader(&self) -> &Self::Reader;
    fn registry(&self) -> &Registry;
}

impl CallDeps for AppState {
    type Reader = HttpBookingReader;

    fn db(&self) -> &PgPool {
        &self.db
    }
    fn booking_reader(&self) -> &Self::Reader {
        &self.booking_reader
    }
    fn registry(&self) -> &Registry {
        &self.registry
    }
}
