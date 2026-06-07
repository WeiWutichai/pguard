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

/// STUN/TURN config for the served ICE list (`GET /calls/ice`). `secret` is the coturn
/// `static-auth-secret` — held SERVER-SIDE ONLY (used to mint short-lived per-caller credentials;
/// never sent to clients). When no TURN is configured the service serves STUN-only (local dev /
/// same-LAN); a TURN URL with no secret is a fail-fast misconfig (can't authenticate the relay).
///
/// MUST NOT derive `Debug`: it holds the coturn static-auth-secret, and a `Debug` impl would risk
/// logging it via any `{:?}` on `AppState`/`TurnConfig`. The `ice_config` handler also `skip`s
/// `state` in its span for the same reason.
#[derive(Clone)]
pub struct TurnConfig {
    /// coturn shared secret (`TURN_SECRET`). `None` ⇒ STUN-only.
    pub secret: Option<String>,
    /// Public STUN URLs (`STUN_URLS`, comma-separated). Defaults to a public STUN.
    pub stun_urls: Vec<String>,
    /// CLIENT-reachable TURN URLs (`TURN_URLS`, comma-separated; e.g. the public relay FQDN with
    /// `?transport=udp`/`tcp`). Empty ⇒ STUN-only.
    pub turn_urls: Vec<String>,
    /// TURN credential lifetime (`TURN_CRED_TTL_SECS`, default 3600).
    pub ttl_secs: i64,
}

impl TurnConfig {
    pub fn from_env() -> anyhow::Result<Self> {
        fn split(v: String) -> Vec<String> {
            v.split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect()
        }
        let stun_urls = std::env::var("STUN_URLS")
            .map(split)
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| vec!["stun:stun.l.google.com:19302".to_string()]);
        let turn_urls = std::env::var("TURN_URLS").map(split).unwrap_or_default();
        let secret = std::env::var("TURN_SECRET")
            .ok()
            .filter(|s| !s.trim().is_empty());
        if !turn_urls.is_empty() && secret.is_none() {
            anyhow::bail!(
                "TURN_URLS is set but TURN_SECRET is missing — cannot mint TURN credentials"
            );
        }
        // Clamp to (0, 24h]: bounds the served credential's lifetime so an env typo (e.g. ms vs s)
        // can't mint a credential valid for days/weeks — keeping the leaked-credential window small.
        let ttl_secs = std::env::var("TURN_CRED_TTL_SECS")
            .ok()
            .and_then(|s| s.parse::<i64>().ok())
            .filter(|&n| n > 0 && n <= 86_400)
            .unwrap_or(3600);
        Ok(Self {
            secret,
            stun_urls,
            turn_urls,
            ttl_secs,
        })
    }
}

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
    /// STUN/TURN config served to clients via `GET /calls/ice`.
    pub turn: TurnConfig,
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
    fn turn(&self) -> &TurnConfig;
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
    fn turn(&self) -> &TurnConfig {
        &self.turn
    }
}
