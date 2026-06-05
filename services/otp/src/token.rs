//! Single-use phone-verified token. Ported from v1
//! `../guard-dispatch/services/shared/src/auth.rs` (the phone-verify half — the v2 shared
//! crate did not carry it over). Lives here, not in `domain/`, because it uses
//! `jsonwebtoken`; the OTP service owns issuance and profile/identity own consumption
//! (single-use enforced via the Redis jti this returns).

use chrono::Utc;
use jsonwebtoken::{EncodingKey, Header};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use shared::error::AppError;

/// Purpose marker baked into the token so it cannot be mistaken for an access/refresh
/// token. Consumers must check `purpose == "phone_verify"`.
pub const PHONE_VERIFY_PURPOSE: &str = "phone_verify";

/// Claims for the short-lived phone-verification JWT. Carries the verified phone plus a
/// unique `jti` for single-use enforcement (tracked in Redis, consumed via GETDEL).
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct PhoneVerifyClaims {
    pub phone: String,
    pub purpose: String,
    pub jti: String,
    pub exp: i64,
    pub iat: i64,
}

/// Encode a phone-verification JWT with a unique `jti`. Returns `(token, jti)` so the
/// caller can store the jti in Redis "valid" for single-use GETDEL.
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

#[cfg(test)]
mod tests {
    use super::*;
    use jsonwebtoken::{Algorithm, DecodingKey, Validation};

    const SECRET: &str = "test-secret-key-at-least-64-chars-long-for-testing-purposes-only!!";

    #[test]
    fn token_round_trips_and_carries_phone_purpose_jti() {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (token, jti) = encode_phone_verify_token("0812345678", &ek, 10).unwrap();

        let mut validation = Validation::default();
        validation.algorithms = vec![Algorithm::HS256];
        validation.validate_exp = true;
        let dk = DecodingKey::from_secret(SECRET.as_bytes());
        let data = jsonwebtoken::decode::<PhoneVerifyClaims>(&token, &dk, &validation).unwrap();

        assert_eq!(data.claims.phone, "0812345678");
        assert_eq!(data.claims.purpose, PHONE_VERIFY_PURPOSE);
        assert_eq!(data.claims.jti, jti);
        assert_eq!(data.claims.exp - data.claims.iat, 10 * 60);
    }

    #[test]
    fn each_token_has_a_unique_jti() {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (_, j1) = encode_phone_verify_token("0812345678", &ek, 10).unwrap();
        let (_, j2) = encode_phone_verify_token("0812345678", &ek, 10).unwrap();
        assert_ne!(j1, j2, "jti must be unique per issuance (single-use)");
    }
}
