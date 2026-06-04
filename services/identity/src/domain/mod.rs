//! PURE domain logic — no DB, no HTTP, no async I/O. 100% unit-testable.
//!
//! - [`password`] — Argon2 hash/verify (CPU-only; allowed in domain per CLAUDE.md).
//! - [`rotation`] — the refresh-token rotation / reuse-detection decision (RFC 6749 §6).
//! - [`revocation`] — the per-user force-revoke-all version helper.
//! - [`token`]    — opaque `{rotation_id}.{secret}` refresh-token format helpers.

pub mod password;
pub mod revocation;
pub mod rotation;
pub mod token;
