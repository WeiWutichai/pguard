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

// ----- 2FA (#144) -----

/// `POST /auth/2fa/enable` body: the 6-digit TOTP code from the authenticator app, proving the
/// user scanned the provisioning QR before 2FA is switched on.
#[derive(Debug, Deserialize)]
pub struct Enable2faRequest {
    pub code: String,
}

/// `POST /auth/2fa/disable` body: EITHER a live TOTP `code` OR the account `password` (SHA-256 hex,
/// same shape as login) confirms intent before 2FA is turned off. At least one must be present.
#[derive(Debug, Deserialize)]
pub struct Disable2faRequest {
    #[serde(default)]
    pub code: Option<String>,
    #[serde(default)]
    pub password: Option<String>,
}

/// `POST /auth/2fa/verify` body (second login step): the `challenge_token` returned by login when
/// 2FA is enabled, plus EITHER a TOTP `code` OR a one-time `recovery_code`.
#[derive(Debug, Deserialize)]
pub struct Verify2faRequest {
    pub challenge_token: String,
    #[serde(default)]
    pub code: Option<String>,
    #[serde(default)]
    pub recovery_code: Option<String>,
}

/// `POST /auth/2fa/setup` response: the `otpauth://` provisioning URI (for the QR) + the base32
/// `secret` (manual-entry fallback). 2FA is NOT yet enabled — the client must call `/2fa/enable`.
#[derive(Debug, Serialize)]
pub struct Setup2faResponse {
    pub otpauth_uri: String,
    pub secret: String,
}

/// `POST /auth/2fa/enable` response: the one-time recovery codes (shown ONCE — never retrievable
/// again). The client must prompt the user to store them.
#[derive(Debug, Serialize)]
pub struct Enable2faResponse {
    pub recovery_codes: Vec<String>,
}

/// Login outcome when 2FA is enabled: NO token pair, just a short-lived `challenge_token` the
/// client passes back to `/auth/2fa/verify` with a code. `two_factor_required` is always `true`
/// (a discriminator for the client).
#[derive(Debug, Serialize)]
pub struct TwoFactorChallenge {
    pub two_factor_required: bool,
    pub challenge_token: String,
}

// ----- Admin API tokens (#144) -----

/// `POST /v1/admin/api-tokens` body: a human label for the token ("CI deploy bot").
#[derive(Debug, Deserialize)]
pub struct CreateApiTokenRequest {
    pub name: String,
}

/// `POST /v1/admin/api-tokens` response: the FULL token shown EXACTLY ONCE (`pguard_<prefix>_<secret>`)
/// plus the metadata. The secret is never returned again — only the prefix is listed thereafter.
#[derive(Debug, Serialize)]
pub struct CreateApiTokenResponse {
    pub id: Uuid,
    pub name: String,
    pub prefix: String,
    /// The full bearer token — store it now; it is NOT retrievable later.
    pub token: String,
}

/// One row in `GET /v1/admin/api-tokens` — NEVER the secret. `revoked` is derived from `revoked_at`.
#[derive(Debug, Serialize)]
pub struct ApiTokenView {
    pub id: Uuid,
    pub name: String,
    pub prefix: String,
    pub role: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub last_used_at: Option<chrono::DateTime<chrono::Utc>>,
    pub revoked: bool,
}

// ----- Per-device sessions (#144) -----

/// One active session (refresh family) in `GET /v1/auth/sessions`. `current` marks the caller's
/// own session (the one whose refresh token was presented). `ip` may be masked by the handler.
#[derive(Debug, Serialize)]
pub struct SessionView {
    pub family_id: Uuid,
    pub user_agent: Option<String>,
    pub ip: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub last_used_at: Option<chrono::DateTime<chrono::Utc>>,
    pub current: bool,
}

// ----- Internal: API-token verification (service-JWT, for the gateway) -----

/// `POST /internal/api-tokens/verify` body: a presented `pguard_…` bearer the gateway received.
#[derive(Debug, Deserialize)]
pub struct VerifyApiTokenRequest {
    pub token: String,
}

/// `POST /internal/api-tokens/verify` response: the resolved principal when the token is valid.
#[derive(Debug, Serialize)]
pub struct VerifyApiTokenResponse {
    pub user_id: Uuid,
    pub role: String,
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
