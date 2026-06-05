//! Service-to-service JWT (v2). Replaces v1's *unauthenticated* `/internal/*`
//! endpoints (audit Issue: `/internal/push` had no auth — CLAUDE.md "Service auth").
//!
//! Internal callers present a short-lived JWT signed with a **separate** secret
//! (`SERVICE_JWT_SECRET`, see [`crate::config::ServiceJwtConfig`]), with
//! `sub = "<svc-name>-service"`, `iss = "pguard"`, `aud = "pguard-internal"`.
//! The callee validates it via [`decode_service_jwt`] or the [`ServiceCaller`] extractor.

use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use chrono::Utc;
use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};

use crate::error::AppError;

const SERVICE_JWT_ISSUER: &str = "pguard";
const SERVICE_JWT_AUDIENCE: &str = "pguard-internal";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ServiceClaims {
    /// Calling service identity, e.g. `"booking-service"`.
    pub sub: String,
    pub iss: String,
    pub aud: String,
    pub exp: i64,
    pub iat: i64,
}

/// Encode a service JWT for `service_name` (the bare name, e.g. `"booking"`; the
/// `-service` suffix is appended). `ttl_secs` is typically small (≈60s).
pub fn encode_service_jwt(
    service_name: &str,
    key: &EncodingKey,
    ttl_secs: i64,
) -> Result<String, AppError> {
    let now = Utc::now();
    let claims = ServiceClaims {
        sub: format!("{service_name}-service"),
        iss: SERVICE_JWT_ISSUER.to_string(),
        aud: SERVICE_JWT_AUDIENCE.to_string(),
        exp: (now + chrono::TimeDelta::seconds(ttl_secs)).timestamp(),
        iat: now.timestamp(),
    };

    jsonwebtoken::encode(&Header::default(), &claims, key)
        .map_err(|e| AppError::Internal(format!("Failed to encode service JWT: {e}")))
}

/// Decode + validate a service JWT (HS256, iss/aud/exp checked).
pub fn decode_service_jwt(token: &str, key: &DecodingKey) -> Result<ServiceClaims, AppError> {
    let mut validation = Validation::default();
    validation.algorithms = vec![Algorithm::HS256];
    validation.validate_exp = true;
    validation.set_issuer(&[SERVICE_JWT_ISSUER]);
    validation.set_audience(&[SERVICE_JWT_AUDIENCE]);

    let data = jsonwebtoken::decode::<ServiceClaims>(token, key, &validation)
        .map_err(|e| AppError::Unauthorized(format!("Invalid service token: {e}")))?;

    Ok(data.claims)
}

/// Authenticated internal caller, extracted from a service JWT in the
/// `Authorization: Bearer <token>` header. Guards every internal endpoint.
#[derive(Debug, Clone)]
pub struct ServiceCaller {
    /// e.g. `"booking-service"`.
    pub service: String,
}

/// State requirement for the [`ServiceCaller`] extractor.
pub trait HasServiceJwt {
    fn service_decoding_key(&self) -> &DecodingKey;
}

impl<T: HasServiceJwt> HasServiceJwt for std::sync::Arc<T> {
    fn service_decoding_key(&self) -> &DecodingKey {
        T::service_decoding_key(self)
    }
}

impl<S> FromRequestParts<S> for ServiceCaller
where
    S: Send + Sync + HasServiceJwt,
{
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let token = parts
            .headers
            .get("Authorization")
            .and_then(|v| v.to_str().ok())
            .and_then(|h| h.strip_prefix("Bearer ").map(|t| t.to_string()))
            .ok_or_else(|| AppError::Unauthorized("Missing service token".to_string()))?;

        let claims = decode_service_jwt(&token, state.service_decoding_key())?;
        Ok(ServiceCaller {
            service: claims.sub,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_SECRET: &str =
        "service-secret-at-least-64-characters-long-for-internal-hs256-test!!";

    fn keys() -> (EncodingKey, DecodingKey) {
        (
            EncodingKey::from_secret(TEST_SECRET.as_bytes()),
            DecodingKey::from_secret(TEST_SECRET.as_bytes()),
        )
    }

    #[test]
    fn encode_then_decode_roundtrip() {
        let (ek, dk) = keys();
        let token = encode_service_jwt("booking", &ek, 60).unwrap();
        let claims = decode_service_jwt(&token, &dk).unwrap();
        assert_eq!(claims.sub, "booking-service");
        assert_eq!(claims.iss, "pguard");
        assert_eq!(claims.aud, "pguard-internal");
    }

    #[test]
    fn decode_with_wrong_secret_fails() {
        let (ek, _) = keys();
        let token = encode_service_jwt("payment", &ek, 60).unwrap();
        let wrong = DecodingKey::from_secret(
            b"a-different-secret-key-that-is-also-64-chars-long-for-the-test!!!",
        );
        assert!(decode_service_jwt(&token, &wrong).is_err());
    }

    #[test]
    fn expired_service_token_fails() {
        let (ek, dk) = keys();
        // TTL of -1h => expired well beyond jsonwebtoken's default 60s leeway.
        let token = encode_service_jwt("rating", &ek, -3600).unwrap();
        assert!(decode_service_jwt(&token, &dk).is_err());
    }

    #[test]
    fn sub_carries_service_suffix() {
        let (ek, dk) = keys();
        let token = encode_service_jwt("chat", &ek, 60).unwrap();
        let claims = decode_service_jwt(&token, &dk).unwrap();
        assert_eq!(claims.sub, "chat-service");
    }
}
