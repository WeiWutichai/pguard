//! DTOs for the otp service (transport shapes). Pure data — no I/O.
//! Request/response shapes ported from v1
//! `../guard-dispatch/services/auth/src/{models.rs,handlers.rs}`.

use serde::{Deserialize, Serialize};

// ----- Requests -----

/// `POST /otp/request` body. The captcha must be solved first (`GET /otp/challenge`).
/// `purpose` BINDS the flow at request time: omitted / `"phone_verify"` → registration
/// (default keeps older clients working), `"pin_reset"` → forgot-PIN reset. The stored
/// code carries it, the SMS wording names it, and `/otp/verify` mints the token FROM it —
/// the code recipient can see what the code is for, and a verifier can never upgrade a
/// registration code into a credential-reset token.
#[derive(Debug, Deserialize)]
pub struct RequestOtpRequest {
    pub phone: String,
    pub challenge_id: String,
    pub answer: String,
    #[serde(default)]
    pub purpose: Option<String>,
}

/// `POST /otp/verify` body. `purpose` is a CROSS-CHECK only — the issued token's purpose
/// comes from the value bound at `/otp/request`. Omitted / `"phone_verify"` → expects a
/// registration code, `"pin_reset"` → expects a reset code; a mismatch with the stored
/// code burns it and fails generically. Unknown values are rejected before the code is
/// checked (never burn an OTP attempt on a malformed request).
#[derive(Debug, Deserialize)]
pub struct VerifyOtpRequest {
    pub phone: String,
    pub code: String,
    #[serde(default)]
    pub purpose: Option<String>,
}

// ----- Responses -----

/// `GET /otp/challenge` response — a math captcha the client must answer.
#[derive(Debug, Serialize)]
pub struct OtpChallengeResponse {
    pub challenge_id: String,
    pub question: String,
    pub expires_in: i64,
}

/// `POST /otp/request` response — deliberately generic (never reveals whether the phone
/// exists / is registered; v1 audit + security-reviewer §9 user-enumeration).
#[derive(Debug, Serialize)]
pub struct RequestOtpResponse {
    pub message: String,
    pub expires_in: i64,
}

/// `POST /otp/verify` response — carries the single-use phone-verified token that
/// profile/identity exchange (via Redis GETDEL of its jti) to complete registration.
#[derive(Debug, Serialize)]
pub struct VerifyOtpResponse {
    pub phone_verified_token: String,
    pub expires_in: i64,
}
