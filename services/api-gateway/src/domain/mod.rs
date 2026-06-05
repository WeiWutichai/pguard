//! PURE gateway logic — no axum / reqwest / redis / tokio imports here.
//!
//! Everything in this module is deterministic and unit-testable in isolation:
//!   - [`routing`]  — `/v1` path → upstream resolution (longest-prefix, /internal block,
//!     public allowlist, tier classification).
//!   - [`ratelimit`] — the fixed-window allow/deny *decision* (given a count + limit),
//!     decoupled from the Redis I/O that produces the count.
//!   - [`headers`]  — hop-by-hop / spoofable-header filtering rules.
//!
//! The I/O that *applies* these decisions lives in `auth`, `ratelimit` (middleware),
//! and `proxy` — per CLAUDE.md's per-service domain layering.

pub mod headers;
pub mod ratelimit;
pub mod routing;
