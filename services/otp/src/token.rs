//! Single-use phone-verified token — issuance side.
//!
//! The scheme (claims + encode/decode + purpose) now lives in [`shared::auth`] so that
//! identity can DECODE exactly what otp ENCODES (single source of truth for the claim
//! shape — issuer and consumer are in different service crates, so a divergent local copy
//! would let one mint a token the other cannot read). otp owns ISSUANCE; identity owns
//! CONSUMPTION (single-use enforced via the Redis jti this returns). Re-exported here so
//! the rest of the otp service keeps importing `crate::token::*`.

pub use shared::auth::encode_phone_verify_token;

#[cfg(test)]
mod tests {
    use super::*;
    use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Validation};
    use shared::auth::{PhoneVerifyClaims, PHONE_VERIFY_PURPOSE};

    const SECRET: &str = "test-secret-key-at-least-64-chars-long-for-testing-purposes-only!!";

    #[test]
    fn token_round_trips_and_carries_phone_purpose_jti() {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (token, jti) = encode_phone_verify_token("0812345678", &ek, 10).unwrap();

        let mut validation = Validation::default();
        validation.algorithms = vec![Algorithm::HS256];
        validation.validate_exp = true;
        validation.validate_aud = false;
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
