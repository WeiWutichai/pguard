//! Edge auth: validate the access token for PROTECTED routes BEFORE proxying.
//!
//! This is the deferred jti/trv enforcement, hoisted to the edge (CLAUDE.md
//! "JWT validation at edge"). It mirrors `shared::auth::AuthUser` exactly — same token
//! sources (Bearer header / `access_token` cookie), same CSRF rule (`X-Requested-With`
//! on cookie-based state-changing calls), same Redis checks (`revoked_jti:{jti}`,
//! `user_trv:{sub}`) — so the gateway and the backends agree. Backends KEEP their own
//! `AuthUser` validation (defense-in-depth); this is an additional early gate.
//!
//! On success it returns the verified [`VerifiedUser`] so the proxy can inject trusted
//! `X-User-Id` / `X-User-Role` headers (after stripping any client-supplied ones).

use axum::http::{HeaderMap, Method};
use redis::AsyncCommands;
use uuid::Uuid;

use shared::auth::{decode_jwt_with_key, extract_cookie_value, ACCESS_TOKEN_COOKIE};
use shared::config::JwtConfig;
use shared::error::AppError;

/// Identity proven by a validated, non-revoked access token.
pub struct VerifiedUser {
    pub user_id: Uuid,
    pub role: String,
}

/// Where the token came from — controls the CSRF requirement.
#[derive(Clone, Copy, PartialEq, Eq)]
enum TokenSource {
    Bearer,
    Cookie,
}

/// Extract the access token from `Authorization: Bearer` (mobile/API) or the
/// `access_token` cookie (web). Returns the token + its source, or `None`.
fn extract_token(headers: &HeaderMap) -> Option<(String, TokenSource)> {
    // Strategy 1: Authorization: Bearer <token>.
    if let Some(tok) = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
        .map(|t| t.to_string())
    {
        return Some((tok, TokenSource::Bearer));
    }

    // Strategy 2: access_token cookie.
    headers
        .get(axum::http::header::COOKIE)
        .and_then(|v| v.to_str().ok())
        .and_then(|cookies| {
            extract_cookie_value(cookies, ACCESS_TOKEN_COOKIE).map(|t| t.to_string())
        })
        .map(|t| (t, TokenSource::Cookie))
}

/// Validate a protected request at the edge. Returns the verified user on success.
///
/// Steps (same order as `shared::auth::AuthUser`):
///   1. Extract token (Bearer or cookie) → 401 if missing.
///   2. CSRF: cookie + state-changing method requires `X-Requested-With` → 403.
///   3. Decode + verify signature/iss/aud/exp → 401 on failure.
///   4. Redis `revoked_jti:{jti}` blocklist → 401 if revoked.
///   5. Redis `user_trv:{sub}` force-revoke-all → 401 if `claims.trv` is stale.
#[tracing::instrument(skip_all, fields(method = %method))]
pub async fn validate(
    headers: &HeaderMap,
    method: &Method,
    jwt: &JwtConfig,
    redis: &mut redis::aio::MultiplexedConnection,
) -> Result<VerifiedUser, AppError> {
    let (token, source) = extract_token(headers)
        .ok_or_else(|| AppError::Unauthorized("Missing authentication token".to_string()))?;

    // CSRF parity with shared::auth: cookie-based state-changing calls need the header.
    if source == TokenSource::Cookie
        && is_state_changing(method)
        && !headers.contains_key("x-requested-with")
    {
        return Err(AppError::Forbidden(
            "Missing X-Requested-With header".to_string(),
        ));
    }

    let claims = decode_jwt_with_key(&token, &jwt.decoding_key)?;

    // jti blocklist (per-token revoke). Fail-CLOSED on the lookup is unnecessary here:
    // a Redis error surfaces as `redis::RedisError` → 500, which is correct for an auth
    // decision (we must not let a token through when we can't confirm it isn't revoked).
    let revoked: bool = redis
        .exists(format!("revoked_jti:{}", claims.jti))
        .await
        .map_err(AppError::from)?;
    if revoked {
        return Err(AppError::Unauthorized("Token has been revoked".to_string()));
    }

    // Per-user force-revoke-all: reject tokens stamped below the current version.
    let current_trv: i64 = redis
        .get::<_, Option<i64>>(format!("user_trv:{}", claims.sub))
        .await
        .map_err(AppError::from)?
        .unwrap_or(0);
    if claims.trv < current_trv {
        return Err(AppError::Unauthorized("Token has been revoked".to_string()));
    }

    Ok(VerifiedUser {
        user_id: claims.sub,
        role: claims.role,
    })
}

fn is_state_changing(m: &Method) -> bool {
    matches!(
        *m,
        Method::POST | Method::PUT | Method::PATCH | Method::DELETE
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::header::{AUTHORIZATION, COOKIE};

    fn hm(pairs: &[(axum::http::HeaderName, &str)]) -> HeaderMap {
        let mut h = HeaderMap::new();
        for (k, v) in pairs {
            h.insert(k.clone(), v.parse().unwrap());
        }
        h
    }

    #[test]
    fn extract_token_prefers_bearer() {
        let h = hm(&[(AUTHORIZATION, "Bearer abc.def.ghi")]);
        let (tok, src) = extract_token(&h).unwrap();
        assert_eq!(tok, "abc.def.ghi");
        assert!(src == TokenSource::Bearer);
    }

    #[test]
    fn extract_token_falls_back_to_cookie() {
        let h = hm(&[(COOKIE, "access_token=cookie.tok.val; other=x")]);
        let (tok, src) = extract_token(&h).unwrap();
        assert_eq!(tok, "cookie.tok.val");
        assert!(src == TokenSource::Cookie);
    }

    #[test]
    fn extract_token_none_when_absent() {
        assert!(extract_token(&HeaderMap::new()).is_none());
        // A Cookie without access_token yields nothing.
        let h = hm(&[(COOKIE, "session=x; other=y")]);
        assert!(extract_token(&h).is_none());
    }

    #[test]
    fn state_changing_methods_classified() {
        for m in [Method::POST, Method::PUT, Method::PATCH, Method::DELETE] {
            assert!(is_state_changing(&m));
        }
        for m in [Method::GET, Method::HEAD, Method::OPTIONS] {
            assert!(!is_state_changing(&m));
        }
    }
}
