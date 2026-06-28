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

/// Switch a still-PENDING account's role without re-OTP. Authenticated by the still-valid
/// single-use `profile_token` from the prior register (presented as the Bearer), so the
/// onboarding "back → pick another role" path works within the profile token's lifetime.
#[derive(Debug, Deserialize)]
pub struct ReissueProfileTokenRequest {
    /// The newly-chosen `guard` | `customer` role.
    pub role: String,
}

/// Update the CALLER'S OWN self-profile (`PUT /auth/me`): `display_name` + `email` only. Phone,
/// role, and password are NEVER changed here (password has its own `PUT /auth/password`). `email`
/// is optional (omit / null / "" clears it); both are validated + normalized server-side.
#[derive(Debug, Deserialize)]
pub struct UpdateMeRequest {
    pub display_name: String,
    #[serde(default)]
    pub email: Option<String>,
}

/// Change the caller's OWN password (`PUT /auth/password`). `current_password` is the SHA-256 hex
/// of the CURRENT PIN (same shape as login's `password`); `new_pin_hash` is the SHA-256 hex of the
/// NEW PIN (same shape as register's `pin_hash`). Both are Argon2'd server-side.
#[derive(Debug, Deserialize)]
pub struct ChangePasswordRequest {
    pub current_password: String,
    pub new_pin_hash: String,
}

/// Batch id → name resolution over the service-JWT'd `POST /internal/users/names`.
#[derive(Debug, Deserialize)]
pub struct ResolveUsersRequest {
    /// The ids to resolve. Duplicates are de-duplicated server-side; an empty list → empty map.
    pub ids: Vec<Uuid>,
}

/// One resolved identity for the internal name-resolver — ONLY `{ role, display_name }`
/// (least-privilege; never phone/email). Keyed by id in the response map.
#[derive(Debug, Serialize)]
pub struct ResolvedUser {
    pub role: String,
    /// The user's display name, or `null` when none is set yet.
    pub display_name: Option<String>,
}

/// Query for `GET /admin/users/search?q=&limit=`.
#[derive(Debug, Deserialize)]
pub struct UserSearchQuery {
    /// Free-text query: matched against display_name / phone / email / exact id.
    pub q: Option<String>,
    /// Bounded result count (clamped server-side).
    pub limit: Option<i64>,
}

/// One admin-search hit — `phone_masked` only (never the full number; no other PII).
#[derive(Debug, Serialize)]
pub struct UserSearchResult {
    pub id: Uuid,
    pub role: String,
    pub display_name: Option<String>,
    pub phone_masked: String,
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
    /// The caller's own display name, or `null` if not set (an admin who hasn't filled it).
    pub display_name: Option<String>,
    /// The caller's own email, or `null` if not set.
    pub email: Option<String>,
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
