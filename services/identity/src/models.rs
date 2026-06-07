//! DTOs for the identity service (transport shapes). Pure data — no I/O.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ----- Requests -----

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    /// Phone number or email — identity resolves which.
    pub identifier: String,
    pub password: String,
}

#[derive(Debug, Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

/// Account creation (`POST /auth/register`). The phone is taken from the single-use
/// `phone_verified_token` (otp-issued) — NEVER from the body — and `pin_hash` is the
/// client-side SHA-256 hex of the user's PIN, which identity Argon2's as the password.
#[derive(Debug, Deserialize)]
pub struct RegisterRequest {
    pub phone_verified_token: String,
    /// `guard` | `customer` (admin is rejected — no self-assignment).
    pub role: String,
    pub pin_hash: String,
}

// ----- Responses -----

/// Issued token pair. Also mirrored into httpOnly cookies on the response.
#[derive(Debug, Serialize)]
pub struct TokenPair {
    pub access_token: String,
    pub refresh_token: String,
    /// Access-token lifetime in seconds (so clients can schedule a refresh).
    pub expires_in: i64,
    pub token_type: &'static str,
}

#[derive(Debug, Serialize)]
pub struct MeResponse {
    pub user_id: Uuid,
    pub role: String,
}

/// Result of a successful registration (HTTP 202). Carries NO access/refresh token — a
/// pending account cannot authenticate until approved. `profile_token` is a single-use,
/// purpose-scoped JWT the client immediately exchanges at `POST /profile/{guard,customer}`
/// to submit its onboarding profile.
#[derive(Debug, Serialize)]
pub struct RegisterResult {
    pub user_id: Uuid,
    pub profile_token: String,
}

// ----- Internal types shared across api/repo -----

/// The user fields the auth flows need (no password hash leaks past `repo`).
#[derive(Debug, Clone)]
pub struct AuthUserRow {
    pub id: Uuid,
    pub role: String,
    /// Current force-revoke-all version — stamped into the access token as `trv`.
    pub token_revocation_version: i32,
}
