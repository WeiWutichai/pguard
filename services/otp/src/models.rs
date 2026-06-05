//! DTOs for the otp service (transport shapes). Pure data — no I/O.
//! Request/response shapes ported from v1
//! `../guard-dispatch/services/auth/src/{models.rs,handlers.rs}`.

use serde::{Deserialize, Serialize};

// ----- Requests -----

/// `POST /otp/request` body. The captcha must be solved first (`GET /otp/challenge`).
#[derive(Debug, Deserialize)]
pub struct RequestOtpRequest {
    pub phone: String,
    pub challenge_id: String,
    pub answer: String,
}

/// `POST /otp/verify` body.
#[derive(Debug, Deserialize)]
pub struct VerifyOtpRequest {
    pub phone: String,
    pub code: String,
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
