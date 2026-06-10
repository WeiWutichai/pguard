//! NATS connection bootstrap — the single place every service dials the broker.
//!
//! v2's NATS originally ran with NO server-side auth (only network isolation + the signed
//! envelope in [`crate::publish_signed`]). This helper adds per-service credentials: a service
//! connects as ITS OWN NATS user (`NATS_USER` / `NATS_PASSWORD`), and the broker enforces
//! least-privilege subject permissions (see `infra/docker/nats.conf`) so a compromised
//! container can only publish its own context's subjects — it can't forge a `payment.completed`
//! from booking, and a consumer-only service (notification/presence/gateway) can't publish at
//! all.
//!
//! Backward-compatible: when `NATS_USER`/`NATS_PASSWORD` are unset (local dev, CI's auth-less
//! broker), it connects anonymously exactly like `async_nats::connect` did before — so the
//! existing gated tests and `docker compose up` keep working without credentials.
//!
//! Drop-in: same signature + return type as `async_nats::connect`, so call sites swap
//! `async_nats::connect(url)` → `shared_events::connect(url)` with no other change.

/// Connect to NATS at `url`, authenticating with `NATS_USER`/`NATS_PASSWORD` when BOTH are set
/// (per-service least-privilege creds), else anonymously (dev/CI). The password is read from the
/// environment and passed to the auth handshake — it is never placed in the URL or logged.
pub async fn connect(url: &str) -> Result<async_nats::Client, async_nats::ConnectError> {
    match (env_nonempty("NATS_USER"), env_nonempty("NATS_PASSWORD")) {
        (Some(user), Some(pass)) => {
            async_nats::ConnectOptions::new()
                .user_and_password(user, pass)
                .connect(url)
                .await
        }
        // Either unset → anonymous (dev/CI broker has no auth). Half-set is treated as
        // anonymous too (a partial config shouldn't silently send a bare username); the broker
        // rejects it if auth is actually required, surfacing a loud connect error.
        _ => async_nats::connect(url).await,
    }
}

/// `Some(value)` only for a present, non-blank env var (an empty `NATS_PASSWORD=` from an
/// unfilled compose default must not be treated as a real credential).
fn env_nonempty(key: &str) -> Option<String> {
    std::env::var(key)
        .ok()
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
}
