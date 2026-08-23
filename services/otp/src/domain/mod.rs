//! PURE domain logic — no DB, no HTTP, no Redis, no Axum. 100% unit-testable.
//!
//! Ported from v1 `../guard-dispatch/services/shared/src/otp.rs` (the pure helpers)
//! plus the v1 OTP-hashing/constant-time-compare and the tiered-lockout decision
//! (`../guard-dispatch/services/auth/src/service.rs::request_otp`). This module imports
//! NOTHING from `sqlx`/`reqwest`/`axum`/`redis`/`tokio` — that is the whole point of the
//! `domain/` layer (CLAUDE.md "Domain logic in `domain/`").

mod captcha;
mod lockout;
mod otp;

pub use captcha::generate_captcha;
pub use lockout::{
    existing_lock_decision, lockout_decision, ActiveLock, LockoutDecision, BURST_WINDOW_SECS,
};
pub use otp::{
    format_otp_message, format_phone_change_otp_message, format_pin_reset_otp_message,
    generate_otp, hashes_match, sha256_hex, to_international_format, validate_thai_phone,
};
