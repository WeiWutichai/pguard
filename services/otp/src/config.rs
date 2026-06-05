//! OTP service config (env-driven). Ported from v1
//! `../guard-dispatch/services/shared/src/otp.rs::OtpConfig`. Service-local (not in the
//! shared crate) because only this service owns the OTP lifecycle in v2.

use shared::error::AppError;

/// OTP configuration loaded from environment.
#[derive(Debug, Clone)]
pub struct OtpConfig {
    pub expiry_minutes: i64,
    pub max_attempts: i32,
    pub length: usize,
    pub rate_limit_seconds: u64,
    /// TTL for the phone-verified token (separate from OTP expiry to give users more
    /// time to fill the registration form). Default: 10 minutes.
    pub phone_verify_ttl_minutes: i64,
    /// Maximum OTP requests per phone per 24-hour window. Default: 10.
    pub daily_otp_limit: u32,
}

impl OtpConfig {
    pub fn from_env() -> Result<Self, AppError> {
        Ok(Self {
            expiry_minutes: std::env::var("OTP_EXPIRY_MINUTES")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(5),
            max_attempts: std::env::var("OTP_MAX_ATTEMPTS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(3),
            length: std::env::var("OTP_LENGTH")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(6),
            rate_limit_seconds: std::env::var("OTP_RATE_LIMIT_SECONDS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(60),
            phone_verify_ttl_minutes: std::env::var("PHONE_VERIFY_TTL_MINUTES")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(10),
            daily_otp_limit: std::env::var("DAILY_OTP_LIMIT")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(10),
        })
    }
}
