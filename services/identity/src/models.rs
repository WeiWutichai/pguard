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

// ----- Internal types shared across api/repo -----

/// The user fields the auth flows need (no password hash leaks past `repo`).
#[derive(Debug, Clone)]
pub struct AuthUserRow {
    pub id: Uuid,
    pub role: String,
    /// Current force-revoke-all version — stamped into the access token as `trv`.
    pub token_revocation_version: i32,
}
