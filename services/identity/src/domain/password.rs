//! Argon2 password + secret hashing. PURE compute (no DB/HTTP/async I/O), so it lives
//! in `domain` per CLAUDE.md (argon2 is CPU-only). The hashing itself is intentionally
//! slow; callers run it inside `spawn_blocking` (see `repo`) to keep the async runtime
//! responsive — that scheduling is I/O concern, not domain logic.

use argon2::password_hash::rand_core::OsRng;
use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;

use shared::error::AppError;

/// Hash a secret (password or refresh-secret) into an Argon2 PHC string with a fresh
/// random salt.
pub fn hash_secret(plaintext: &str) -> Result<String, AppError> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(plaintext.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| AppError::Internal(format!("hash failed: {e}")))
}

/// Verify `plaintext` against a stored Argon2 PHC `hash`. Constant-time within Argon2's
/// verifier. Returns `Ok(false)` for a wrong password; only a malformed stored hash is
/// an error.
pub fn verify_secret(plaintext: &str, hash: &str) -> Result<bool, AppError> {
    let parsed = PasswordHash::new(hash)
        .map_err(|e| AppError::Internal(format!("malformed stored hash: {e}")))?;
    Ok(Argon2::default()
        .verify_password(plaintext.as_bytes(), &parsed)
        .is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn correct_password_verifies() {
        let hash = hash_secret("hunter2-correct-horse").unwrap();
        assert!(verify_secret("hunter2-correct-horse", &hash).unwrap());
    }

    #[test]
    fn wrong_password_does_not_verify() {
        let hash = hash_secret("hunter2-correct-horse").unwrap();
        assert!(!verify_secret("wrong-password", &hash).unwrap());
    }

    #[test]
    fn hash_is_salted_so_two_hashes_differ() {
        let a = hash_secret("same-input").unwrap();
        let b = hash_secret("same-input").unwrap();
        assert_ne!(a, b, "fresh salt per hash");
        // ...yet both verify against the same plaintext.
        assert!(verify_secret("same-input", &a).unwrap());
        assert!(verify_secret("same-input", &b).unwrap());
    }

    #[test]
    fn hash_is_argon2id_phc() {
        let hash = hash_secret("x").unwrap();
        assert!(hash.starts_with("$argon2"), "PHC string, got: {hash}");
    }

    #[test]
    fn malformed_stored_hash_is_an_error_not_a_false() {
        let err = verify_secret("anything", "not-a-phc-string");
        assert!(err.is_err());
    }
}
