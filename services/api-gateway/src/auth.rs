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
///
/// Generic over the connection type so the gateway can pass its reconnecting
/// [`redis::aio::ConnectionManager`] (chaos case 3) — a Redis blip no longer wedges edge auth;
/// the next request after recovery self-heals. While Redis is down, the lookups error → 500
/// (fail-closed), unchanged.
#[tracing::instrument(skip_all, fields(method = %method))]
pub async fn validate<C>(
    headers: &HeaderMap,
    method: &Method,
    jwt: &JwtConfig,
    redis: &mut C,
) -> Result<VerifiedUser, AppError>
where
    C: redis::aio::ConnectionLike + Send,
{
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

    // ----- reconnect / fail-closed behaviour (hermetic, via the FlakyRedis double) -----

    const RECONNECT_SECRET: &str =
        "gateway-edge-auth-reconnect-secret-at-least-64-characters-long-hs256!!";

    /// A valid `JwtConfig` + a freshly-minted, non-expired access token for it.
    fn jwt_and_token() -> (JwtConfig, String) {
        use jsonwebtoken::{DecodingKey, EncodingKey};
        let jwt = JwtConfig {
            secret: RECONNECT_SECRET.to_string(),
            expiry_minutes: 15,
            encoding_key: EncodingKey::from_secret(RECONNECT_SECRET.as_bytes()),
            decoding_key: DecodingKey::from_secret(RECONNECT_SECRET.as_bytes()),
        };
        let (token, _jti) = shared::auth::encode_jwt_with_key(
            uuid::Uuid::new_v4(),
            "guard",
            0,
            &jwt.encoding_key,
            15,
        )
        .unwrap();
        (jwt, token)
    }

    fn bearer(token: &str) -> HeaderMap {
        let mut h = HeaderMap::new();
        h.insert(AUTHORIZATION, format!("Bearer {token}").parse().unwrap());
        h
    }

    /// Fail-CLOSED during a Redis outage: a structurally-valid token must be DENIED when the
    /// jti/trv lookup cannot run (the edge must not admit a token it can't confirm isn't revoked).
    #[tokio::test]
    async fn validate_fails_closed_when_redis_errors() {
        let (jwt, token) = jwt_and_token();
        let mut redis = crate::test_support::FlakyRedis::always_broken();
        let res = validate(&bearer(&token), &Method::GET, &jwt, &mut redis).await;
        assert!(
            res.is_err(),
            "edge auth MUST fail closed when the revocation lookup errors"
        );
    }

    /// Self-heal: the FIRST request during the outage is denied, but the NEXT request after Redis
    /// is back succeeds with no restart — proving the connection reconnects (chaos case 3 fix).
    #[tokio::test]
    async fn validate_recovers_after_redis_comes_back() {
        let (jwt, token) = jwt_and_token();
        // `validate` issues exactly two redis ops per request (exists → get). `fail_first = 1`
        // makes ONLY the first op (the `exists` jti lookup) error, so request #1 fails closed at
        // that lookup; from request #2 every reply is `Int(0)` (jti not revoked, current_trv 0).
        let mut redis = crate::test_support::FlakyRedis::new(1, 0);
        assert!(
            validate(&bearer(&token), &Method::GET, &jwt, &mut redis)
                .await
                .is_err(),
            "while Redis is down the request is denied (fail-closed)"
        );
        assert!(
            validate(&bearer(&token), &Method::GET, &jwt, &mut redis)
                .await
                .is_ok(),
            "the next request after Redis recovers must self-heal (no restart)"
        );
    }
}
