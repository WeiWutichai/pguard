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

/// ADD a SECOND pending role to an existing account (`POST /auth/register/add-role`). Unlike
/// `reissue` (which SWITCHES the one pending role) this is ADDITIVE — the account keeps its first
/// role and gains a second pending profile. Authorized by a FRESH `phone_verified_token` (OTP):
/// by the time a user is on the pending screen the register `profile_token` is already spent and
/// a pending account has no access token, so re-proving phone ownership is the only auth left.
/// The phone comes from the token, never the body.
#[derive(Debug, Deserialize)]
pub struct AddRoleRequest {
    pub phone_verified_token: String,
    /// The SECOND `guard` | `customer` role to add (must differ from the account's current role).
    pub role: String,
}

/// Body of `POST /auth/phone-status` — a post-OTP "does this phone already have an account?" probe.
/// Carries the FRESH single-use `phone_verified_token` (proving phone ownership); identity verifies
/// it WITHOUT consuming the single-use marker so the subsequent register/login still works.
#[derive(Debug, Deserialize)]
pub struct PhoneStatusRequest {
    pub phone_verified_token: String,
}

/// Response of `POST /auth/phone-status`.
#[derive(Debug, Serialize)]
pub struct PhoneStatusResponse {
    /// True when a live account already exists for the verified phone (→ the app sends the user to
    /// PIN-login instead of a fresh set-PIN registration).
    pub account_exists: bool,
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

/// Change the caller's LOGIN PHONE (`PATCH /auth/phone`). Two proofs are required: the single-use
/// `phone_change_token` (an otp-issued `phone_change`-purpose token proving ownership of the NEW
/// number — the new phone is taken FROM the token, NEVER from the body) AND `current_pin_hash` (the
/// SHA-256 hex of the CURRENT PIN, same shape as login's `password`) as a step-up. A wrong current
/// PIN → generic 401; a new number already held by an APPROVED account → 409 `PHONE_TAKEN`.
#[derive(Debug, Deserialize)]
pub struct ChangePhoneRequest {
    pub phone_change_token: String,
    pub current_pin_hash: String,
}

/// Reset a FORGOTTEN PIN (`POST /auth/reset-pin`). The phone is taken from the single-use
/// `phone_verified_token` (otp-issued) — NEVER from the body — so a caller can only reset the PIN
/// of a phone they just proved they own. `new_pin_hash` is the SHA-256 hex of the new PIN (same
/// shape as register's `pin_hash`), Argon2'd server-side. Unlike `PUT /auth/password` this needs NO
/// current PIN (the user forgot it): phone ownership + the single-use token ARE the authorization.
#[derive(Debug, Deserialize)]
pub struct ResetPinRequest {
    pub phone_verified_token: String,
    pub new_pin_hash: String,
}

/// Batch id → name resolution over the service-JWT'd `POST /internal/users/names`.
#[derive(Debug, Deserialize)]
pub struct ResolveUsersRequest {
    /// The ids to resolve. Duplicates are de-duplicated server-side; an empty list → empty map.
    pub ids: Vec<Uuid>,
}

/// One resolved identity for the internal name-resolver — `{ role, display_name, phone }`.
/// Keyed by id in the response map.
///
/// WHY A RESOLVER RETURNS A PHONE NUMBER: in pguard the phone IS the account's identity. People
/// sign up with it, log in with it (OTP + PIN on that number) and are contacted on it; it is the
/// one field `identity.users` guarantees is present and unique for EVERY account (`TEXT UNIQUE NOT
/// NULL`), while `display_name` is optional and frequently null mid-onboarding. So "resolve these
/// ids to who they are" is only answerable with the phone — a name alone leaves the admin approval
/// queue staring at `#5680b50f` with no way to reach the applicant. Still least-privilege: `email`,
/// password/2FA material and everything else stay home, and this endpoint is service-JWT'd +
/// blocked at the public edge, so the phone never leaves the internal mesh through here. Callers
/// that only need a label (profile's `POST /admin/users/resolve`) simply drop the field.
#[derive(Debug, Serialize)]
pub struct ResolvedUser {
    pub role: String,
    /// The user's display name, or `null` when none is set yet.
    pub display_name: Option<String>,
    /// The account's LOGIN phone (`identity.users.phone`) — always present for a live account
    /// (the column is `NOT NULL`); this is the number the person registered and signs in with,
    /// NOT any optional contact number a profile may separately hold.
    pub phone: String,
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
    /// The single ACTIVE role — the role embedded in the caller's current access token (the one
    /// they logged in / switched into). Unchanged shape for backward compat.
    pub role: String,
    /// The SET of APPROVED roles this account holds (multi-role, Option A). For a single-role
    /// user this is exactly `[role]`; for a dual-role user it carries both so the app can offer a
    /// role switch (`POST /auth/switch-role`). Always contains the active `role`.
    pub roles: Vec<String>,
    /// Roles the account has SUBMITTED a profile for but that are NOT yet approved (a pending
    /// second-role application). Distinct from `roles` (approved). Lets the mobile mode-picker show
    /// a submitted role as "pending approval" instead of re-offering its blank registration form.
    /// Best-effort: `[]` if the profile service can't be reached.
    #[serde(default)]
    pub pending_roles: Vec<String>,
    /// The caller's own display name, or `null` if not set (an admin who hasn't filled it).
    pub display_name: Option<String>,
    /// The caller's own email, or `null` if not set.
    pub email: Option<String>,
}

/// Login success body (no-2FA path). Extends [`TokenPair`] with `available_roles` so the app can
/// show a role picker when the account holds >1 role. BACKWARD COMPAT: a single-role user gets
/// the SAME token fields plus `available_roles: [their_role]` — every existing field is present
/// and unchanged, so an old client that ignores `available_roles` is unaffected. The active token
/// is minted with the user's registration/primary `role` (login behaviour is unchanged); the app
/// may then `POST /auth/switch-role` to mint a token for another enrolled role.
#[derive(Debug, Serialize)]
pub struct LoginTokenPair {
    #[serde(flatten)]
    pub tokens: TokenPair,
    /// The APPROVED roles this account holds (from `user_roles`). `[role]` for a single-role user.
    pub available_roles: Vec<String>,
}

/// Switch the caller's ACTIVE role (`POST /auth/switch-role`). The target `role` MUST be in the
/// caller's enrolled (`user_roles`) set — a role they are not enrolled in is rejected with 409
/// `ROLE_NOT_ENROLLED` and NO token is minted (the critical anti-escalation gate).
#[derive(Debug, Deserialize)]
pub struct SwitchRoleRequest {
    pub role: String,
}

/// Enrol the logged-in user in a NEW role they don't yet hold (`POST /auth/roles`). Returns a
/// single-use `profile_token` scoped to `(this user_id, role)` so the app can submit that role's
/// profile form → a PENDING second profile for the SAME user_id. The role enters `user_roles`
/// only on approval — this does NOT grant the role.
#[derive(Debug, Deserialize)]
pub struct EnrollRoleRequest {
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
