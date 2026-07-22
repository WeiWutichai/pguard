//! PURE domain logic — no DB, no HTTP, no async I/O. 100% unit-testable.
//!
//! - [`password`] — Argon2 hash/verify (CPU-only; allowed in domain per CLAUDE.md).
//! - [`registration`] — role choice + role→purpose mapping + phone/pin/name/email validation.
//! - [`mask`]     — PII masking for admin reads (phone → last-4).
//! - [`rotation`] — the refresh-token rotation / reuse-detection decision (RFC 6749 §6).
//! - [`revocation`] — the per-user force-revoke-all version helper.
//! - [`token`]    — opaque `{rotation_id}.{secret}` refresh-token format helpers.

/// Per-account failed-login lockout backoff (PURE); the API layer owns the Redis counter/lock.
pub mod login_throttle;
pub mod mask;
pub mod password;
pub mod registration;
pub mod revocation;
pub mod rotation;
pub mod token;
/// 2FA + secret-sealing primitives (TOTP, AES-256-GCM seal, recovery codes, API-token format).
pub mod twofactor;
