//! OTP code primitives — generation, message formatting, phone validation, hashing,
//! and the constant-time hash compare. Ported faithfully from v1
//! `../guard-dispatch/services/shared/src/otp.rs` and the OTP hash/compare in v1
//! `../guard-dispatch/services/auth/src/service.rs`.

use shared::error::AppError;

/// Generate a random numeric OTP code of the given length.
/// Uses `rand::thread_rng()` for cryptographically sufficient randomness.
pub fn generate_otp(length: usize) -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    (0..length)
        .map(|_| rng.gen_range(0..10).to_string())
        .collect()
}

/// Format the OTP message in Thai for SMS delivery.
///
/// Kept short (≤ 40 chars) so the hex-encoded UCS-2 text fits in a single
/// SMS segment (160 hex chars) = 1 credit. Brand name shows as sender ID.
pub fn format_otp_message(code: &str, expiry_minutes: i64) -> String {
    format!("รหัส OTP: {code} หมดอายุใน {expiry_minutes} นาที")
}

/// Validate Thai phone number format: 10 digits starting with 0.
/// Strips non-digit characters before validation.
pub fn validate_thai_phone(phone: &str) -> Result<String, AppError> {
    let digits: String = phone.chars().filter(|c| c.is_ascii_digit()).collect();
    if digits.len() != 10 || !digits.starts_with('0') {
        return Err(AppError::BadRequest(
            "Invalid phone format — must be 10 digits starting with 0".to_string(),
        ));
    }
    Ok(digits)
}

/// Convert Thai local phone (0812345678) to international format (66812345678)
/// for the INET SMS API which accepts both formats.
pub fn to_international_format(phone: &str) -> String {
    let digits: String = phone.chars().filter(|c| c.is_ascii_digit()).collect();
    if let Some(stripped) = digits.strip_prefix('0') {
        format!("66{stripped}")
    } else {
        digits
    }
}

/// SHA-256 hash a value and return a lowercase hex string. OTP codes are stored as
/// this hash (never plaintext) so a DB dump/backup leak cannot reveal live codes.
pub fn sha256_hex(input: &str) -> String {
    use sha2::{Digest, Sha256};
    format!("{:x}", Sha256::digest(input.as_bytes()))
}

/// Constant-time comparison of two hex hash strings. Compares the SHA-256 hex of the
/// submitted code against the stored hash without leaking match-progress via timing
/// (security-reviewer §3: "Constant-time compare (`subtle::ConstantTimeEq`)").
pub fn hashes_match(stored_hash: &str, candidate_hash: &str) -> bool {
    use subtle::ConstantTimeEq;
    // `ct_eq` is constant time only for equal-length inputs; SHA-256 hex is always 64
    // chars, so this is exercised on uniform-length values. The bool conversion is also
    // branchless (`subtle::Choice`).
    stored_hash
        .as_bytes()
        .ct_eq(candidate_hash.as_bytes())
        .into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_otp_correct_length() {
        let code = generate_otp(6);
        assert_eq!(code.len(), 6);
    }

    #[test]
    fn generate_otp_only_digits() {
        let code = generate_otp(6);
        assert!(code.chars().all(|c| c.is_ascii_digit()));
    }

    #[test]
    fn generate_otp_different_each_time() {
        // Very unlikely to generate the same 6-digit code repeatedly.
        let codes: Vec<String> = (0..10).map(|_| generate_otp(6)).collect();
        let unique: std::collections::HashSet<&String> = codes.iter().collect();
        assert!(unique.len() > 1, "OTP codes should be random");
    }

    #[test]
    fn format_otp_message_contains_code() {
        let msg = format_otp_message("123456", 5);
        assert!(msg.contains("123456"));
        assert!(msg.contains("5 นาที"));
    }

    #[test]
    fn format_otp_message_fits_single_sms_segment() {
        let msg = format_otp_message("123456", 5);
        let char_count = msg.chars().count();
        // ≤ 40 chars so hex-encoded UCS-2 (×4) ≤ 160 = 1 SMS segment = 1 credit.
        assert!(
            char_count <= 40,
            "OTP message too long: {char_count} chars (max 40 for 1 credit)"
        );
    }

    #[test]
    fn validate_thai_phone_valid() {
        assert_eq!(validate_thai_phone("0812345678").unwrap(), "0812345678");
    }

    #[test]
    fn validate_thai_phone_with_dashes() {
        assert_eq!(validate_thai_phone("081-234-5678").unwrap(), "0812345678");
    }

    #[test]
    fn validate_thai_phone_with_spaces() {
        assert_eq!(validate_thai_phone("081 234 5678").unwrap(), "0812345678");
    }

    #[test]
    fn validate_thai_phone_too_short() {
        assert!(validate_thai_phone("081234567").is_err());
    }

    #[test]
    fn validate_thai_phone_not_starting_with_zero() {
        assert!(validate_thai_phone("1812345678").is_err());
    }

    #[test]
    fn to_international_format_converts() {
        assert_eq!(to_international_format("0812345678"), "66812345678");
    }

    #[test]
    fn to_international_format_already_international() {
        assert_eq!(to_international_format("66812345678"), "66812345678");
    }

    #[test]
    fn sha256_hex_produces_64_char_lowercase_hex() {
        let hash = sha256_hex("123456");
        assert_eq!(hash.len(), 64);
        assert!(hash
            .chars()
            .all(|c| c.is_ascii_hexdigit() && !c.is_uppercase()));
    }

    #[test]
    fn sha256_hex_is_deterministic() {
        assert_eq!(sha256_hex("same-input"), sha256_hex("same-input"));
    }

    #[test]
    fn sha256_hex_differs_for_different_inputs() {
        assert_ne!(sha256_hex("123456"), sha256_hex("654321"));
    }

    #[test]
    fn sha256_hex_never_contains_original_input() {
        let input = "123456";
        assert!(!sha256_hex(input).contains(input));
    }

    #[test]
    fn hashes_match_true_for_equal_hashes() {
        let a = sha256_hex("123456");
        let b = sha256_hex("123456");
        assert!(hashes_match(&a, &b));
    }

    #[test]
    fn hashes_match_false_for_different_hashes() {
        let a = sha256_hex("123456");
        let b = sha256_hex("654321");
        assert!(!hashes_match(&a, &b));
    }
}
