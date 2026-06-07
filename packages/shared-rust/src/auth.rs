//! User JWT encode/decode, cookie helpers, and the [`AuthUser`] Axum extractor.
//! Ported from v1; issuer/audience rebranded `pguard`.
//!
//! The extractor accepts a `Bearer` header (mobile/API) or `access_token` cookie
//! (web), enforces CSRF (`X-Requested-With`) on cookie-based state-changing calls,
//! and checks the Redis jti revocation blocklist.

use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use chrono::Utc;
use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Header, Validation};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::error::AppError;

const JWT_ISSUER: &str = "pguard";
const JWT_AUDIENCE: &str = "pguard";

#[derive(Debug, Serialize, Deserialize, Clone, ToSchema)]
pub struct JwtClaims {
    pub sub: Uuid,
    pub role: String,
    pub exp: i64,
    pub iat: i64,
    pub iss: String,
    pub aud: String,
    /// Unique token ID for the revocation blocklist.
    pub jti: String,
    /// Per-user token-revocation version (force-revoke-all). A token is rejected when its
    /// `trv` is below the user's current version (checked in the [`AuthUser`] extractor).
    /// `#[serde(default)]` keeps older tokens (minted before this field) decoding as `trv = 0`.
    #[serde(default)]
    pub trv: i64,
}

pub fn encode_jwt(
    user_id: Uuid,
    role: &str,
    trv: i64,
    secret: &str,
    expiry_minutes: i64,
) -> Result<(String, String), AppError> {
    let key = EncodingKey::from_secret(secret.as_bytes());
    encode_jwt_with_key(user_id, role, trv, &key, expiry_minutes)
}

/// Encode a user JWT with a pre-computed [`EncodingKey`] (cached in `JwtConfig`).
/// `trv` stamps the issuer's current per-user revocation version. Returns `(token, jti)`.
pub fn encode_jwt_with_key(
    user_id: Uuid,
    role: &str,
    trv: i64,
    key: &EncodingKey,
    expiry_minutes: i64,
) -> Result<(String, String), AppError> {
    let now = Utc::now();
    let jti = Uuid::new_v4().to_string();
    let claims = JwtClaims {
        sub: user_id,
        role: role.to_string(),
        exp: (now + chrono::TimeDelta::minutes(expiry_minutes)).timestamp(),
        iat: now.timestamp(),
        iss: JWT_ISSUER.to_string(),
        aud: JWT_AUDIENCE.to_string(),
        jti: jti.clone(),
        trv,
    };

    let token = jsonwebtoken::encode(&Header::default(), &claims, key)
        .map_err(|e| AppError::Internal(format!("Failed to encode JWT: {e}")))?;
    Ok((token, jti))
}

pub fn decode_jwt(token: &str, secret: &str) -> Result<JwtClaims, AppError> {
    let key = DecodingKey::from_secret(secret.as_bytes());
    decode_jwt_with_key(token, &key)
}

/// Decode + validate a user JWT (HS256, iss/aud/exp checked).
pub fn decode_jwt_with_key(token: &str, key: &DecodingKey) -> Result<JwtClaims, AppError> {
    let mut validation = Validation::default();
    validation.algorithms = vec![Algorithm::HS256];
    validation.validate_exp = true;
    validation.set_issuer(&[JWT_ISSUER]);
    validation.set_audience(&[JWT_AUDIENCE]);

    let token_data = jsonwebtoken::decode::<JwtClaims>(token, key, &validation)
        .map_err(|e| AppError::Unauthorized(format!("Invalid token: {e}")))?;

    Ok(token_data.claims)
}

// ============================================================================
// Purpose-scoped single-use tokens (phone-verify + profile submission)
// ----------------------------------------------------------------------------
// Two short-lived JWTs that gate the OTP-registration handshake. Both are signed
// with the SAME user `JWT_SECRET` (so every service that holds `JwtConfig` can
// verify them) but carry a `purpose` claim and NO `iss`/`aud` — which keeps them
// structurally distinct from an access token (`decode_jwt_with_key` requires
// iss=aud="pguard" + a `role`, neither of which these carry, so an access token
// can never be mistaken for one of these and vice-versa). Single-use is enforced
// by the issuer storing the token's `jti` in Redis and the consumer `GETDEL`-ing
// it (the Redis bookkeeping lives in the services, not here — these helpers only
// mint/verify the JWT itself).
//
// The phone-verify half is ISSUED by otp (`/otp/verify`) and CONSUMED by identity
// (`/auth/register`); the profile half is ISSUED by identity's register response
// and CONSUMED by profile (`POST /profile/{guard,customer}`). Keeping both schemes
// here is the single source of truth for the claim shapes — the issuer and the
// consumer live in different service crates, so a divergent local copy would let
// one mint a token the other cannot decode.

/// Purpose marker for the phone-verified token (otp → identity). Consumers MUST
/// check `purpose == PHONE_VERIFY_PURPOSE`.
pub const PHONE_VERIFY_PURPOSE: &str = "phone_verify";

/// Profile-token purpose for a GUARD registration (identity → profile `/profile/guard`).
pub const PROFILE_PURPOSE_GUARD: &str = "guard_profile";
/// Profile-token purpose for a CUSTOMER registration (identity → profile `/profile/customer`).
pub const PROFILE_PURPOSE_CUSTOMER: &str = "customer_profile";

/// Build a `Validation` for the purpose-scoped tokens: HS256, expiry enforced, and
/// NO issuer/audience requirement (these tokens deliberately omit iss/aud). Without
/// disabling `validate_aud` the default validator would reject a token that carries
/// no `aud` claim.
fn purpose_token_validation() -> Validation {
    let mut v = Validation::new(Algorithm::HS256);
    v.validate_exp = true;
    v.validate_aud = false;
    v.required_spec_claims.clear();
    v
}

/// Claims for the short-lived phone-verification JWT. Carries the verified phone plus
/// a unique `jti` for single-use enforcement (tracked in Redis, consumed via GETDEL).
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct PhoneVerifyClaims {
    pub phone: String,
    pub purpose: String,
    pub jti: String,
    pub exp: i64,
    pub iat: i64,
}

/// Encode a phone-verification JWT with a unique `jti`. Returns `(token, jti)` so the
/// caller (otp) can store the jti in Redis "valid" for the consumer's single-use GETDEL.
pub fn encode_phone_verify_token(
    phone: &str,
    key: &EncodingKey,
    expiry_minutes: i64,
) -> Result<(String, String), AppError> {
    let now = Utc::now();
    let jti = Uuid::new_v4().to_string();
    let claims = PhoneVerifyClaims {
        phone: phone.to_string(),
        purpose: PHONE_VERIFY_PURPOSE.to_string(),
        jti: jti.clone(),
        exp: (now + chrono::TimeDelta::minutes(expiry_minutes)).timestamp(),
        iat: now.timestamp(),
    };
    let token = jsonwebtoken::encode(&Header::default(), &claims, key)
        .map_err(|e| AppError::Internal(format!("Failed to encode phone verify token: {e}")))?;
    Ok((token, jti))
}

/// Decode + verify a phone-verification JWT (signature, expiry, `purpose`). Returns
/// `(phone, jti)`; the caller then enforces single-use by `GETDEL`-ing the jti in Redis.
/// A wrong-purpose token (e.g. a profile token) is rejected so the schemes can't be crossed.
pub fn decode_phone_verify_token(
    token: &str,
    key: &DecodingKey,
) -> Result<(String, String), AppError> {
    let data = jsonwebtoken::decode::<PhoneVerifyClaims>(token, key, &purpose_token_validation())
        .map_err(|e| AppError::Unauthorized(format!("Invalid phone verify token: {e}")))?;
    if data.claims.purpose != PHONE_VERIFY_PURPOSE {
        return Err(AppError::Unauthorized(
            "Invalid phone verify token".to_string(),
        ));
    }
    Ok((data.claims.phone, data.claims.jti))
}

/// Claims for the short-lived, single-use profile-submission JWT. `sub` is the user id
/// (set by identity at register); `purpose` is `guard_profile` or `customer_profile` so
/// a token minted for one route is rejected on the other (purpose isolation).
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ProfileTokenClaims {
    pub sub: Uuid,
    pub purpose: String,
    pub jti: String,
    pub exp: i64,
    pub iat: i64,
}

/// Encode a single-use profile-submission JWT for `user_id` scoped to `purpose`
/// ([`PROFILE_PURPOSE_GUARD`] / [`PROFILE_PURPOSE_CUSTOMER`]). Returns `(token, jti)`;
/// the issuer (identity) stores the jti in Redis "valid" for the consumer's GETDEL.
pub fn encode_profile_token(
    user_id: Uuid,
    purpose: &str,
    key: &EncodingKey,
    expiry_minutes: i64,
) -> Result<(String, String), AppError> {
    let now = Utc::now();
    let jti = Uuid::new_v4().to_string();
    let claims = ProfileTokenClaims {
        sub: user_id,
        purpose: purpose.to_string(),
        jti: jti.clone(),
        exp: (now + chrono::TimeDelta::minutes(expiry_minutes)).timestamp(),
        iat: now.timestamp(),
    };
    let token = jsonwebtoken::encode(&Header::default(), &claims, key)
        .map_err(|e| AppError::Internal(format!("Failed to encode profile token: {e}")))?;
    Ok((token, jti))
}

/// Decode + verify a profile-submission JWT, enforcing `purpose == expected_purpose`
/// (purpose isolation: a guard token MUST fail on the customer route and vice-versa).
/// Returns `(user_id, jti)`; the caller (profile) then enforces single-use via GETDEL.
/// A non-profile token (an access token has no `purpose`) fails to decode here, so the
/// caller can cleanly fall through to standard `AuthUser` auth.
pub fn decode_profile_token(
    token: &str,
    key: &DecodingKey,
    expected_purpose: &str,
) -> Result<(Uuid, String), AppError> {
    let data = jsonwebtoken::decode::<ProfileTokenClaims>(token, key, &purpose_token_validation())
        .map_err(|e| AppError::Unauthorized(format!("Invalid profile token: {e}")))?;
    if data.claims.purpose != expected_purpose {
        return Err(AppError::Unauthorized("Invalid profile token".to_string()));
    }
    Ok((data.claims.sub, data.claims.jti))
}

/// Build a Set-Cookie value for an httpOnly, Secure, SameSite=Lax cookie.
pub fn build_cookie(name: &str, value: &str, max_age_secs: i64, path: &str) -> String {
    format!("{name}={value}; HttpOnly; Secure; SameSite=Lax; Path={path}; Max-Age={max_age_secs}")
}

/// Build a Set-Cookie value that clears/expires a cookie.
pub fn build_clear_cookie(name: &str, path: &str) -> String {
    format!("{name}=; HttpOnly; Secure; SameSite=Lax; Path={path}; Max-Age=0")
}

pub const ACCESS_TOKEN_COOKIE: &str = "access_token";
pub const REFRESH_TOKEN_COOKIE: &str = "refresh_token";

/// Extract a named cookie value from a `Cookie` header string.
pub fn extract_cookie_value<'a>(cookie_header: &'a str, name: &str) -> Option<&'a str> {
    cookie_header.split(';').map(|s| s.trim()).find_map(|pair| {
        let (key, value) = pair.split_once('=')?;
        if key.trim() == name {
            Some(value.trim())
        } else {
            None
        }
    })
}

/// Validate a raw access token END-TO-END: decode (signature/exp/iss/aud) THEN check the
/// Redis per-jti revocation blocklist + per-user force-revoke-all (`trv`). Returns the claims,
/// or `Unauthorized` if expired/revoked. Shared by the [`AuthUser`] extractor (one-shot, per
/// request) AND by long-lived sessions (e.g. the calling WS relay) that must RE-validate
/// periodically — an open socket must not outlive token expiry or a force-revoke-all.
pub async fn authenticate_token(
    token: &str,
    decoding_key: &DecodingKey,
    redis: &redis::aio::MultiplexedConnection,
) -> Result<JwtClaims, AppError> {
    let claims = decode_jwt_with_key(token, decoding_key)?;
    let mut redis = redis.clone();

    let is_revoked: bool = redis
        .exists(format!("revoked_jti:{}", claims.jti))
        .await
        .unwrap_or(false);
    if is_revoked {
        return Err(AppError::Unauthorized("Token has been revoked".to_string()));
    }

    // Per-user force-revoke-all: a token stamped with a version older than the user's current
    // one is rejected. `user_trv:{user_id}` absent ⇒ version 0 (never revoked).
    let current_trv: i64 = redis
        .get::<_, Option<i64>>(format!("user_trv:{}", claims.sub))
        .await
        .unwrap_or(None)
        .unwrap_or(0);
    if claims.trv < current_trv {
        return Err(AppError::Unauthorized("Token has been revoked".to_string()));
    }

    Ok(claims)
}

/// Authenticated user, extracted from a validated (non-revoked) JWT.
#[derive(Debug, Clone, ToSchema)]
pub struct AuthUser {
    pub user_id: Uuid,
    pub role: String,
}

impl<S> FromRequestParts<S> for AuthUser
where
    S: Send + Sync + HasJwtSecret,
{
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        // Strategy 1: Authorization: Bearer <token> (mobile/API).
        let token = parts
            .headers
            .get("Authorization")
            .and_then(|v| v.to_str().ok())
            .and_then(|h| h.strip_prefix("Bearer ").map(|t| t.to_string()));

        let from_bearer = token.is_some();

        // Strategy 2: access_token cookie (web).
        let token = token.or_else(|| {
            parts
                .headers
                .get("Cookie")
                .and_then(|v| v.to_str().ok())
                .and_then(|cookies| extract_cookie_value(cookies, ACCESS_TOKEN_COOKIE))
                .map(|t| t.to_string())
        });

        let token = token
            .ok_or_else(|| AppError::Unauthorized("Missing authentication token".to_string()))?;

        // CSRF: cookie-based state-changing calls must carry X-Requested-With.
        if !from_bearer {
            let m = &parts.method;
            let is_state_changing = m == axum::http::Method::POST
                || m == axum::http::Method::PUT
                || m == axum::http::Method::PATCH
                || m == axum::http::Method::DELETE;
            if is_state_changing && !parts.headers.contains_key("x-requested-with") {
                return Err(AppError::Forbidden(
                    "Missing X-Requested-With header".to_string(),
                ));
            }
        }

        // Decode + revocation/force-revoke checks (shared with long-lived WS re-auth).
        let claims = authenticate_token(&token, state.decoding_key(), state.redis_conn()).await?;

        Ok(AuthUser {
            user_id: claims.sub,
            role: claims.role,
        })
    }
}

/// State requirement for the [`AuthUser`] extractor.
pub trait HasJwtSecret {
    fn jwt_secret(&self) -> &str;
    fn decoding_key(&self) -> &DecodingKey;
    fn redis_conn(&self) -> &redis::aio::MultiplexedConnection;
}

impl<T: HasJwtSecret> HasJwtSecret for std::sync::Arc<T> {
    fn jwt_secret(&self) -> &str {
        T::jwt_secret(self)
    }
    fn decoding_key(&self) -> &DecodingKey {
        T::decoding_key(self)
    }
    fn redis_conn(&self) -> &redis::aio::MultiplexedConnection {
        T::redis_conn(self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_SECRET: &str = "test-secret-key-at-least-64-chars-long-for-testing-purposes-only!!";

    #[test]
    fn encode_then_decode_roundtrip() {
        let user_id = Uuid::new_v4();
        let (token, jti) = encode_jwt(user_id, "admin", 7, TEST_SECRET, 60).unwrap();
        let claims = decode_jwt(&token, TEST_SECRET).unwrap();
        assert_eq!(claims.sub, user_id);
        assert_eq!(claims.role, "admin");
        assert_eq!(claims.jti, jti);
        assert_eq!(claims.aud, "pguard");
        assert_eq!(claims.iss, "pguard");
        assert_eq!(claims.trv, 7, "revocation version round-trips");
    }

    #[test]
    fn decode_with_wrong_secret_fails() {
        let (token, _) = encode_jwt(Uuid::new_v4(), "guard", 0, TEST_SECRET, 60).unwrap();
        assert!(decode_jwt(&token, "wrong-secret").is_err());
    }

    #[test]
    fn decode_garbage_token_fails() {
        assert!(decode_jwt("not.a.jwt", TEST_SECRET).is_err());
    }

    #[test]
    fn jwt_expiry_is_set_correctly() {
        let (token, _) = encode_jwt(Uuid::new_v4(), "guard", 0, TEST_SECRET, 15).unwrap();
        let claims = decode_jwt(&token, TEST_SECRET).unwrap();
        assert_eq!(claims.exp - claims.iat, 15 * 60);
    }

    // ----- phone-verify token (otp → identity) -----

    #[test]
    fn phone_verify_token_round_trips_phone_and_jti() {
        let ek = EncodingKey::from_secret(TEST_SECRET.as_bytes());
        let dk = DecodingKey::from_secret(TEST_SECRET.as_bytes());
        let (token, jti) = encode_phone_verify_token("0812345678", &ek, 10).unwrap();
        let (phone, decoded_jti) = decode_phone_verify_token(&token, &dk).unwrap();
        assert_eq!(phone, "0812345678");
        assert_eq!(
            decoded_jti, jti,
            "jti round-trips for single-use bookkeeping"
        );
    }

    #[test]
    fn phone_verify_token_each_issuance_has_unique_jti() {
        let ek = EncodingKey::from_secret(TEST_SECRET.as_bytes());
        let (_, j1) = encode_phone_verify_token("0812345678", &ek, 10).unwrap();
        let (_, j2) = encode_phone_verify_token("0812345678", &ek, 10).unwrap();
        assert_ne!(j1, j2, "jti must be unique per issuance (single-use)");
    }

    #[test]
    fn phone_verify_token_rejects_wrong_secret() {
        let ek = EncodingKey::from_secret(TEST_SECRET.as_bytes());
        let (token, _) = encode_phone_verify_token("0812345678", &ek, 10).unwrap();
        let wrong = DecodingKey::from_secret(
            b"another-secret-key-at-least-64-chars-long-for-the-negative-test!!",
        );
        assert!(decode_phone_verify_token(&token, &wrong).is_err());
    }

    // ----- profile token (identity → profile), with purpose isolation -----

    #[test]
    fn profile_token_round_trips_user_and_jti() {
        let ek = EncodingKey::from_secret(TEST_SECRET.as_bytes());
        let dk = DecodingKey::from_secret(TEST_SECRET.as_bytes());
        let uid = Uuid::new_v4();
        let (token, jti) = encode_profile_token(uid, PROFILE_PURPOSE_GUARD, &ek, 15).unwrap();
        let (decoded_uid, decoded_jti) =
            decode_profile_token(&token, &dk, PROFILE_PURPOSE_GUARD).unwrap();
        assert_eq!(decoded_uid, uid);
        assert_eq!(decoded_jti, jti);
    }

    #[test]
    fn profile_token_purpose_isolation_guard_fails_on_customer_route() {
        let ek = EncodingKey::from_secret(TEST_SECRET.as_bytes());
        let dk = DecodingKey::from_secret(TEST_SECRET.as_bytes());
        let (guard_tok, _) =
            encode_profile_token(Uuid::new_v4(), PROFILE_PURPOSE_GUARD, &ek, 15).unwrap();
        // Decoding a guard token while expecting the customer purpose MUST fail.
        assert!(decode_profile_token(&guard_tok, &dk, PROFILE_PURPOSE_CUSTOMER).is_err());

        let (cust_tok, _) =
            encode_profile_token(Uuid::new_v4(), PROFILE_PURPOSE_CUSTOMER, &ek, 15).unwrap();
        assert!(decode_profile_token(&cust_tok, &dk, PROFILE_PURPOSE_GUARD).is_err());
    }

    #[test]
    fn profile_token_each_issuance_has_unique_jti() {
        let ek = EncodingKey::from_secret(TEST_SECRET.as_bytes());
        let uid = Uuid::new_v4();
        let (_, j1) = encode_profile_token(uid, PROFILE_PURPOSE_GUARD, &ek, 15).unwrap();
        let (_, j2) = encode_profile_token(uid, PROFILE_PURPOSE_GUARD, &ek, 15).unwrap();
        assert_ne!(j1, j2, "jti must be unique per issuance (single-use)");
    }

    #[test]
    fn profile_token_rejects_wrong_secret() {
        let ek = EncodingKey::from_secret(TEST_SECRET.as_bytes());
        let (token, _) =
            encode_profile_token(Uuid::new_v4(), PROFILE_PURPOSE_GUARD, &ek, 15).unwrap();
        let wrong = DecodingKey::from_secret(
            b"another-secret-key-at-least-64-chars-long-for-the-negative-test!!",
        );
        assert!(decode_profile_token(&token, &wrong, PROFILE_PURPOSE_GUARD).is_err());
    }

    /// Cross-scheme confusion guard: an ACCESS token (carries iss/aud/role, no `purpose`)
    /// must NOT decode as a profile token, and a profile token must NOT decode as an access
    /// token — even though all three are signed with the same secret. This is what lets the
    /// profile dual-auth resolver cleanly tell a profile_token apart from a Bearer access token.
    #[test]
    fn access_token_and_profile_token_are_not_interchangeable() {
        let ek = EncodingKey::from_secret(TEST_SECRET.as_bytes());
        let dk = DecodingKey::from_secret(TEST_SECRET.as_bytes());

        let (access, _) = encode_jwt(Uuid::new_v4(), "guard", 0, TEST_SECRET, 15).unwrap();
        assert!(
            decode_profile_token(&access, &dk, PROFILE_PURPOSE_GUARD).is_err(),
            "an access token must not pass as a profile token"
        );

        let (profile, _) =
            encode_profile_token(Uuid::new_v4(), PROFILE_PURPOSE_GUARD, &ek, 15).unwrap();
        assert!(
            decode_jwt(&profile, TEST_SECRET).is_err(),
            "a profile token must not pass as an access token (no iss/aud/role)"
        );
    }

    #[test]
    fn build_cookie_contains_required_attributes() {
        let cookie = build_cookie("access_token", "abc123", 3600, "/");
        assert!(cookie.contains("access_token=abc123"));
        assert!(cookie.contains("HttpOnly"));
        assert!(cookie.contains("Secure"));
        assert!(cookie.contains("SameSite=Lax"));
        assert!(cookie.contains("Max-Age=3600"));
    }

    #[test]
    fn build_clear_cookie_sets_max_age_zero() {
        let cookie = build_clear_cookie("access_token", "/");
        assert!(cookie.contains("Max-Age=0"));
        assert!(cookie.contains("HttpOnly"));
    }

    #[test]
    fn extract_cookie_value_finds_named_cookie() {
        assert_eq!(
            extract_cookie_value("access_token=abc123; other=xyz", "access_token"),
            Some("abc123")
        );
    }

    #[test]
    fn extract_cookie_value_handles_spaces() {
        assert_eq!(
            extract_cookie_value("  access_token = mytoken ; other = val  ", "access_token"),
            Some("mytoken")
        );
    }

    #[test]
    fn extract_cookie_value_returns_none_for_missing() {
        assert_eq!(extract_cookie_value("other=xyz", "access_token"), None);
    }

    /// The `AuthUser` extractor enforces force-revoke-all: a token whose `trv` is below the
    /// user's current revocation version (Redis `user_trv:{id}`) is rejected; a current one
    /// passes. Redis-gated (TEST_REDIS_URL / REDIS_CACHE_URL); hermetic-skips otherwise.
    #[tokio::test]
    async fn auth_user_rejects_stale_trv_and_accepts_current() {
        let Ok(redis_url) =
            std::env::var("TEST_REDIS_URL").or_else(|_| std::env::var("REDIS_CACHE_URL"))
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let conn = redis::Client::open(redis_url)
            .expect("redis client")
            .get_multiplexed_tokio_connection()
            .await
            .expect("redis conn");

        struct St {
            key: DecodingKey,
            redis: redis::aio::MultiplexedConnection,
        }
        impl HasJwtSecret for St {
            fn jwt_secret(&self) -> &str {
                TEST_SECRET
            }
            fn decoding_key(&self) -> &DecodingKey {
                &self.key
            }
            fn redis_conn(&self) -> &redis::aio::MultiplexedConnection {
                &self.redis
            }
        }
        let state = St {
            key: DecodingKey::from_secret(TEST_SECRET.as_bytes()),
            redis: conn.clone(),
        };
        let ek = EncodingKey::from_secret(TEST_SECRET.as_bytes());
        let user_id = Uuid::new_v4();

        let mut c = conn.clone();
        let _: () = c
            .set(format!("user_trv:{user_id}"), 5i64)
            .await
            .expect("set marker");

        // Stale token (trv 4 < current 5) → rejected.
        let (stale, _) = encode_jwt_with_key(user_id, "guard", 4, &ek, 60).unwrap();
        let req = axum::http::Request::builder()
            .header(axum::http::header::AUTHORIZATION, format!("Bearer {stale}"))
            .body(())
            .unwrap();
        let (mut parts, _) = req.into_parts();
        assert!(
            AuthUser::from_request_parts(&mut parts, &state)
                .await
                .is_err(),
            "stale-trv token must be rejected"
        );

        // Current token (trv 5) → accepted.
        let (cur, _) = encode_jwt_with_key(user_id, "guard", 5, &ek, 60).unwrap();
        let req2 = axum::http::Request::builder()
            .header(axum::http::header::AUTHORIZATION, format!("Bearer {cur}"))
            .body(())
            .unwrap();
        let (mut parts2, _) = req2.into_parts();
        assert!(
            AuthUser::from_request_parts(&mut parts2, &state)
                .await
                .is_ok(),
            "current-trv token must pass"
        );

        let _: () = c.del(format!("user_trv:{user_id}")).await.expect("cleanup");
    }
}
