//! Shared gateway state + the env-resolved upstream URL table.
//!
//! The pure layer (`domain::routing`) deals in [`Upstream`] keys; this map binds each
//! key to a concrete base URL read from env at startup. Keeping the resolution here
//! (not in `domain`) keeps `domain` free of env/IO.

use std::collections::HashMap;
use std::sync::Arc;

use jsonwebtoken::DecodingKey;

use shared::auth::HasJwtSecret;
use shared::config::JwtConfig;

use tokio::sync::broadcast;

use crate::domain::ratelimit::Limits;
use crate::domain::routing::Upstream;
use crate::domain::ws::StatusUpdate;

/// Resolved base URLs for every upstream, keyed by [`Upstream`].
#[derive(Debug, Clone)]
pub struct UpstreamTable {
    urls: HashMap<Upstream, String>,
}

impl UpstreamTable {
    /// Build the table from env, falling back to the documented dev defaults
    /// (CLAUDE.md gateway route map). Trailing slashes are trimmed so joins are clean.
    pub fn from_env() -> Self {
        let mut urls = HashMap::new();
        urls.insert(
            Upstream::Identity,
            env_url("IDENTITY_URL", "http://localhost:3001"),
        );
        urls.insert(Upstream::Otp, env_url("OTP_URL", "http://localhost:3003"));
        urls.insert(
            Upstream::Profile,
            env_url("PROFILE_URL", "http://localhost:3002"),
        );
        urls.insert(
            Upstream::Booking,
            env_url("BOOKING_URL", "http://localhost:3005"),
        );
        urls.insert(
            Upstream::Payment,
            env_url("PAYMENT_URL", "http://localhost:3006"),
        );
        urls.insert(
            Upstream::Notification,
            env_url("NOTIFICATION_URL", "http://localhost:3004"),
        );
        Self { urls }
    }

    /// Base URL for an upstream (no trailing slash). Present for every variant because
    /// [`from_env`](Self::from_env) inserts all of them.
    pub fn base_url(&self, upstream: Upstream) -> Option<&str> {
        self.urls.get(&upstream).map(String::as_str)
    }

    /// Override a single upstream's base URL (trailing slash trimmed). Used by tests to
    /// point a route at an ephemeral in-process upstream without mutating process env.
    #[cfg(test)]
    pub fn with_override(mut self, upstream: Upstream, url: &str) -> Self {
        self.urls
            .insert(upstream, url.trim_end_matches('/').to_string());
        self
    }
}

fn env_url(key: &str, default: &str) -> String {
    std::env::var(key)
        .unwrap_or_else(|_| default.to_string())
        .trim_end_matches('/')
        .to_string()
}

/// Gateway application state, shared (cheaply cloned) across handlers.
#[derive(Clone)]
pub struct AppState {
    /// Outbound HTTP client (connection-pooled) used to forward to upstreams.
    pub http: reqwest::Client,
    /// Multiplexed Redis connection for jti/trv checks + the rate-limit counters.
    pub redis_conn: redis::aio::MultiplexedConnection,
    /// User-JWT validation config (decoding key + secret) for edge auth.
    pub jwt_config: JwtConfig,
    /// Env-resolved upstream base URLs.
    pub routes: UpstreamTable,
    /// Per-tier rate limits.
    pub limits: Limits,
    /// Fan-out of live booking-status updates (fed by the NATS hub) to the per-connection
    /// WebSocket receivers. Each `/v1/ws/bookings/{id}` connection subscribes and filters
    /// to its own booking id.
    pub status_tx: broadcast::Sender<StatusUpdate>,
    /// Allowed browser origins (same allowlist as CORS) — the WS upgrade checks `Origin`
    /// against this because CORS does not cover WebSocket handshakes.
    pub allowed_origins: Arc<[String]>,
}

/// Lets the gateway reuse shared auth helpers/typing that key off [`HasJwtSecret`].
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn upstream_table_has_all_upstreams_with_defaults() {
        // No env set in test → documented dev defaults; trailing slash trimmed.
        let t = UpstreamTable::from_env();
        for up in [
            Upstream::Identity,
            Upstream::Otp,
            Upstream::Profile,
            Upstream::Booking,
            Upstream::Payment,
            Upstream::Notification,
        ] {
            let url = t.base_url(up).expect("every upstream resolves");
            assert!(url.starts_with("http://"), "{up:?} -> {url}");
            assert!(!url.ends_with('/'), "trailing slash trimmed: {url}");
        }
    }
}
