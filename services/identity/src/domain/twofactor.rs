//! PURE 2FA + secret-sealing primitives — CPU-only crypto (no DB/HTTP/async I/O), so it lives
//! in `domain` like [`super::password`]. Covers:
//!   - RFC-6238 TOTP via the vetted `totp-rs` crate (we do NOT hand-roll the OTP math),
//!   - AES-256-GCM seal/open of the TOTP secret at rest (`TOTP_ENC_KEY`),
//!   - one-time recovery-code generation + SHA-256 hashing,
//!   - the `otpauth://` provisioning URI for the authenticator-app QR.
//!
//! No secret or recovery code is ever logged here (the callers also `skip_all` the spans).

use aes_gcm::aead::{Aead, KeyInit, OsRng};
use aes_gcm::{AeadCore, Aes256Gcm, Key, Nonce};
use data_encoding::BASE32_NOPAD;
use rand::RngCore;
use sha2::{Digest, Sha256};
use totp_rs::{Algorithm, TOTP};

use shared::error::AppError;

/// TOTP digits (6 — the universal authenticator-app default).
const TOTP_DIGITS: usize = 6;
/// TOTP step (30s — RFC-6238 default).
const TOTP_STEP: u64 = 30;
/// Accepted skew window: ±1 step (so a code valid in the adjacent 30s window still passes — a
/// human typing the code as it rolls over). `totp-rs` checks `[t-skew, t+skew]`.
const TOTP_SKEW: u8 = 1;
/// Raw TOTP secret length in bytes (160-bit — the recommended minimum for SHA-1 HOTP/TOTP).
const TOTP_SECRET_BYTES: usize = 20;
/// Issuer label shown in the authenticator app.
const TOTP_ISSUER: &str = "pguard";

/// Number of one-time recovery codes minted at enable.
pub const RECOVERY_CODE_COUNT: usize = 10;
/// Bytes of entropy per recovery code (10 bytes → 16 base32 chars; ~80 bits).
const RECOVERY_CODE_BYTES: usize = 10;

/// Decode + validate the AES-256 key from its hex env value (`TOTP_ENC_KEY`). 64 hex chars →
/// 32 bytes. Done once at startup (fail-fast) so the request path holds a ready key.
pub fn parse_enc_key(hex: &str) -> Result<[u8; 32], AppError> {
    let bytes = data_encoding::HEXLOWER_PERMISSIVE
        .decode(hex.trim().as_bytes())
        .map_err(|_| AppError::Internal("TOTP_ENC_KEY must be hex".to_string()))?;
    if bytes.len() != 32 {
        return Err(AppError::Internal(
            "TOTP_ENC_KEY must be 32 bytes (64 hex chars) for AES-256-GCM".to_string(),
        ));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

/// Generate a fresh random TOTP secret (raw bytes). Returned to the caller for sealing +
/// for building the provisioning URI.
pub fn generate_totp_secret() -> Vec<u8> {
    let mut buf = vec![0u8; TOTP_SECRET_BYTES];
    OsRng.fill_bytes(&mut buf);
    buf
}

/// Build a [`TOTP`] over the raw secret bytes for `account` (the user's label, e.g. phone/email).
/// Pure constructor — the verify/URI helpers use it.
fn totp_for(secret: &[u8], account: &str) -> Result<TOTP, AppError> {
    TOTP::new(
        Algorithm::SHA1,
        TOTP_DIGITS,
        TOTP_SKEW,
        TOTP_STEP,
        secret.to_vec(),
        Some(TOTP_ISSUER.to_string()),
        account.to_string(),
    )
    .map_err(|e| AppError::Internal(format!("TOTP construction failed: {e}")))
}

/// The `otpauth://totp/...` provisioning URI for the authenticator-app QR + the base32 secret
/// (shown as a manual-entry fallback). The URI embeds issuer/account/secret/digits/period.
pub fn provisioning(secret: &[u8], account: &str) -> Result<(String, String), AppError> {
    let totp = totp_for(secret, account)?;
    let uri = totp.get_url();
    let base32 = BASE32_NOPAD.encode(secret);
    Ok((uri, base32))
}

/// Verify a presented 6-digit `code` against the raw `secret` at the current time (±skew).
/// Returns `false` for a wrong/expired code; only a malformed secret/system-time error is an
/// `Err`. `totp-rs`'s check is constant-time over the candidate windows.
pub fn verify_totp(secret: &[u8], account: &str, code: &str) -> Result<bool, AppError> {
    let totp = totp_for(secret, account)?;
    let code = code.trim();
    // Reject obviously-wrong shapes before the crypto (a non-6-digit string never matches).
    if code.len() != TOTP_DIGITS || !code.bytes().all(|b| b.is_ascii_digit()) {
        return Ok(false);
    }
    totp.check_current(code)
        .map_err(|e| AppError::Internal(format!("TOTP check failed (system time?): {e}")))
}

/// AES-256-GCM seal: `nonce(12) || ciphertext+tag`. A fresh random nonce per seal (GCM nonce
/// reuse is catastrophic, so never reuse). Stored as BYTEA. Pure compute.
pub fn seal_secret(key: &[u8; 32], plaintext: &[u8]) -> Result<Vec<u8>, AppError> {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
    let ct = cipher
        .encrypt(&nonce, plaintext)
        .map_err(|_| AppError::Internal("TOTP secret seal failed".to_string()))?;
    let mut out = Vec::with_capacity(nonce.len() + ct.len());
    out.extend_from_slice(nonce.as_slice());
    out.extend_from_slice(&ct);
    Ok(out)
}

/// AES-256-GCM open of a `seal_secret` blob (`nonce(12) || ct`). A tampered blob / wrong key
/// fails authentication → `Err` (never a silent wrong-plaintext).
pub fn open_secret(key: &[u8; 32], sealed: &[u8]) -> Result<Vec<u8>, AppError> {
    if sealed.len() < 12 {
        return Err(AppError::Internal(
            "sealed TOTP secret too short".to_string(),
        ));
    }
    let (nonce_bytes, ct) = sealed.split_at(12);
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    let nonce = Nonce::from_slice(nonce_bytes);
    cipher
        .decrypt(nonce, ct)
        .map_err(|_| AppError::Internal("TOTP secret open failed (tampered/wrong key)".to_string()))
}

/// SHA-256 hex of a value (recovery code or API-token secret). Hash-at-rest: only this is stored.
pub fn sha256_hex(value: &str) -> String {
    let digest = Sha256::digest(value.as_bytes());
    data_encoding::HEXLOWER.encode(&digest)
}

/// Generate `RECOVERY_CODE_COUNT` one-time recovery codes. Returns `(plaintext, hash)` pairs:
/// the plaintext is shown to the user ONCE; only the hash is persisted. Display form is a
/// base32 string split with a hyphen for legibility (e.g. `ABCD-EFGH-IJKL`).
pub fn generate_recovery_codes() -> Vec<(String, String)> {
    (0..RECOVERY_CODE_COUNT)
        .map(|_| {
            let mut raw = [0u8; RECOVERY_CODE_BYTES];
            OsRng.fill_bytes(&mut raw);
            let code = group_in_fours(&BASE32_NOPAD.encode(&raw));
            // Hash the NORMALIZED (no-hyphen, upper) form so the verify can re-derive it.
            let hash = sha256_hex(&normalize_recovery_code(&code));
            (code, hash)
        })
        .collect()
}

/// Normalize a presented recovery code for hashing/compare: strip hyphens/whitespace, uppercase.
/// So `abcd-efgh` and `ABCDEFGH` hash identically.
pub fn normalize_recovery_code(code: &str) -> String {
    code.chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect::<String>()
        .to_ascii_uppercase()
}

/// Insert a hyphen every 4 chars for display legibility.
fn group_in_fours(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + s.len() / 4);
    for (i, c) in s.chars().enumerate() {
        if i > 0 && i % 4 == 0 {
            out.push('-');
        }
        out.push(c);
    }
    out
}

// ───────────────────────────── API tokens ─────────────────────────────

/// Public prefix length (chars) of an API token — the displayed id + verify lookup key.
const API_TOKEN_PREFIX_BYTES: usize = 6; // → ~10 base32 chars
/// Secret half entropy (bytes) — the part hashed at rest.
const API_TOKEN_SECRET_BYTES: usize = 24; // ~192 bits
/// The literal namespace prefix that marks a bearer as a pguard API token (vs. a JWT). The
/// gateway/identity branch on this to route the credential to API-token verification.
pub const API_TOKEN_NAMESPACE: &str = "pguard_";

/// A freshly-minted API token: the FULL token (returned to the user ONCE), its public `prefix`
/// (stored + displayed), and the SHA-256 `secret_hash` (stored — never the secret).
pub struct NewApiToken {
    /// `pguard_<prefix>_<secret>` — shown to the user exactly once.
    pub full: String,
    pub prefix: String,
    pub secret_hash: String,
}

/// Mint a new API token. Format: `pguard_<prefix>_<secret>` where both halves are base32. The
/// `prefix` is the public lookup key; only `sha256_hex(secret)` is persisted.
pub fn generate_api_token() -> NewApiToken {
    let mut p = [0u8; API_TOKEN_PREFIX_BYTES];
    let mut s = [0u8; API_TOKEN_SECRET_BYTES];
    OsRng.fill_bytes(&mut p);
    OsRng.fill_bytes(&mut s);
    let prefix = BASE32_NOPAD.encode(&p).to_lowercase();
    let secret = BASE32_NOPAD.encode(&s).to_lowercase();
    let full = format!("{API_TOKEN_NAMESPACE}{prefix}_{secret}");
    let secret_hash = sha256_hex(&secret);
    NewApiToken {
        full,
        prefix,
        secret_hash,
    }
}

/// Parse a presented bearer as an API token → `(prefix, secret)`. Returns `None` if it is not in
/// the `pguard_<prefix>_<secret>` shape (so the caller falls back to JWT auth). Pure.
pub fn parse_api_token(token: &str) -> Option<(String, String)> {
    let rest = token.strip_prefix(API_TOKEN_NAMESPACE)?;
    let (prefix, secret) = rest.split_once('_')?;
    if prefix.is_empty() || secret.is_empty() {
        return None;
    }
    Some((prefix.to_string(), secret.to_string()))
}

/// Constant-time compare of a presented secret's hash against the stored hash (anti-timing).
pub fn api_token_secret_matches(presented_secret: &str, stored_hash: &str) -> bool {
    use subtle::ConstantTimeEq;
    let presented = sha256_hex(presented_secret);
    // Both are fixed-width lowercase hex; compare the bytes in constant time.
    presented.as_bytes().ct_eq(stored_hash.as_bytes()).into()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key() -> [u8; 32] {
        parse_enc_key(&"ab".repeat(32)).unwrap()
    }

    #[test]
    fn enc_key_must_be_32_bytes() {
        assert!(parse_enc_key(&"ab".repeat(32)).is_ok()); // 64 hex → 32 bytes
        assert!(parse_enc_key("deadbeef").is_err()); // too short
        assert!(parse_enc_key("zz".repeat(32).as_str()).is_err()); // not hex
    }

    #[test]
    fn seal_then_open_roundtrips_and_tamper_fails() {
        let k = key();
        let secret = generate_totp_secret();
        let sealed = seal_secret(&k, &secret).unwrap();
        // Nonce-prefixed, so two seals of the same secret differ (no nonce reuse).
        let sealed2 = seal_secret(&k, &secret).unwrap();
        assert_ne!(sealed, sealed2, "fresh nonce per seal");
        assert_eq!(open_secret(&k, &sealed).unwrap(), secret);

        // A flipped byte fails authentication.
        let mut bad = sealed.clone();
        let last = bad.len() - 1;
        bad[last] ^= 0xff;
        assert!(open_secret(&k, &bad).is_err());

        // A different key cannot open it.
        let k2 = parse_enc_key(&"cd".repeat(32)).unwrap();
        assert!(open_secret(&k2, &sealed).is_err());
    }

    #[test]
    fn totp_verifies_its_own_current_code() {
        let secret = generate_totp_secret();
        let totp = totp_for(&secret, "0812345678").unwrap();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let code = totp.generate(now);
        assert!(verify_totp(&secret, "0812345678", &code).unwrap());
        // A wrong code does not verify.
        assert!(!verify_totp(&secret, "0812345678", "000000").unwrap());
        // A non-6-digit shape is rejected without erroring.
        assert!(!verify_totp(&secret, "0812345678", "abc").unwrap());
    }

    #[test]
    fn provisioning_uri_is_otpauth_and_carries_issuer() {
        let secret = generate_totp_secret();
        let (uri, base32) = provisioning(&secret, "0812345678").unwrap();
        assert!(uri.starts_with("otpauth://totp/"), "got {uri}");
        assert!(uri.contains("issuer=pguard"));
        assert!(!base32.is_empty());
        // The base32 manual-entry secret decodes back to the raw bytes.
        assert_eq!(BASE32_NOPAD.decode(base32.as_bytes()).unwrap(), secret);
    }

    #[test]
    fn recovery_codes_are_unique_and_hash_normalizes() {
        let codes = generate_recovery_codes();
        assert_eq!(codes.len(), RECOVERY_CODE_COUNT);
        // Plaintext codes are distinct.
        let mut seen = std::collections::HashSet::new();
        for (plain, hash) in &codes {
            assert!(seen.insert(plain.clone()), "codes must be unique");
            // The stored hash matches the normalized plaintext (hyphen/case-insensitive).
            assert_eq!(*hash, sha256_hex(&normalize_recovery_code(plain)));
            // A hyphenated + lowercased variant verifies identically.
            let messy = plain.to_lowercase();
            assert_eq!(sha256_hex(&normalize_recovery_code(&messy)), *hash);
        }
    }

    #[test]
    fn api_token_parses_and_secret_matches_in_constant_time() {
        let tok = generate_api_token();
        assert!(tok.full.starts_with("pguard_"));
        let (prefix, secret) = parse_api_token(&tok.full).expect("parse own token");
        assert_eq!(prefix, tok.prefix);
        assert!(api_token_secret_matches(&secret, &tok.secret_hash));
        // A wrong secret does not match.
        assert!(!api_token_secret_matches(
            "not-the-secret",
            &tok.secret_hash
        ));
        // A non-namespaced bearer isn't an API token (→ caller falls back to JWT).
        assert!(parse_api_token("eyJ.jwt.token").is_none());
        assert!(parse_api_token("pguard_only").is_none());
    }
}
