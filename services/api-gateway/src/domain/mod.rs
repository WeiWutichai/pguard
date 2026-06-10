//! PURE gateway logic — no axum / reqwest / redis / tokio imports here.
//!
//! Everything in this module is deterministic and unit-testable in isolation:
//!   - [`routing`]  — `/v1` path → upstream resolution (longest-prefix, /internal block,
//!     public allowlist, tier classification).
//!   - [`ratelimit`] — the fixed-window allow/deny *decision* (given a count + limit),
//!     decoupled from the Redis I/O that produces the count.
//!   - [`headers`]  — hop-by-hop / spoofable-header filtering rules.
//!   - [`ws`]       — booking-status event → client frame mapping (topic→status, parse, frame).
//!   - [`wsproxy`]  — edge-WS-path → (upstream, backend WS path) table + http(s)→ws(s)
//!     URL derivation for the generic WebSocket proxy.
//!
//! The I/O that *applies* these decisions lives in `auth`, `ratelimit` (middleware),
//! `proxy`, `ws` (the WebSocket handler + NATS hub), and `wsproxy` (the WS relay) — per
//! CLAUDE.md's domain layering.

pub mod headers;
pub mod ratelimit;
pub mod routing;
pub mod ws;
pub mod wsproxy;
