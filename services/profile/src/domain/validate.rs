//! Pure field validation for profile writes. Bounds are defensive (reject absurd values
//! before they reach the DB / downstream payment+rating logic). No I/O.

/// Plausible bounds for a guard's self-reported years of experience. A negative value is
/// nonsense; the upper bound rejects obvious garbage without being so tight it rejects a
/// long career.
const MAX_YEARS_OF_EXPERIENCE: i32 = 80;

/// Free-text upper bound shared by short text fields (names, workplace, address). Keeps a
/// single oversized field from bloating a row or a log line.
pub const MAX_TEXT_LEN: usize = 500;

/// Bank account numbers are short; cap defensively (digits + a few separators).
pub const MAX_ACCOUNT_NUMBER_LEN: usize = 34; // IBAN max length, generous for TH accounts.

/// Validate optional years-of-experience. `None` is allowed (field is optional).
pub fn validate_years_of_experience(years: Option<i32>) -> Result<(), String> {
    match years {
        None => Ok(()),
        Some(y) if (0..=MAX_YEARS_OF_EXPERIENCE).contains(&y) => Ok(()),
        Some(_) => Err(format!(
            "years_of_experience must be between 0 and {MAX_YEARS_OF_EXPERIENCE}"
        )),
    }
}

/// Validate an optional bounded text field. `None`/empty is allowed (fields are optional).
pub fn validate_text(value: Option<&str>, field: &str, max: usize) -> Result<(), String> {
    match value {
        None => Ok(()),
        Some(v) if v.chars().count() <= max => Ok(()),
        Some(_) => Err(format!("{field} must be at most {max} characters")),
    }
}

/// Validate an optional email (loose, mirrors v1 — real verification is out of scope): must
/// contain `@` and `.`, length in `[5, MAX_TEXT_LEN]`. `None`/empty → Ok (optional field).
pub fn validate_email(value: Option<&str>) -> Result<(), String> {
    match value.map(str::trim) {
        None | Some("") => Ok(()),
        Some(v)
            if v.len() >= 5 && v.len() <= MAX_TEXT_LEN && v.contains('@') && v.contains('.') =>
        {
            Ok(())
        }
        Some(_) => Err("email must be a valid address".to_string()),
    }
}

/// Validate an optional Thai phone in national format: at least 10 digits starting with `0`
/// (mirrors the otp/identity phone shape — separators are ignored, not a carrier lookup).
/// `None`/empty → Ok (optional field).
pub fn validate_thai_phone(value: Option<&str>, field: &str) -> Result<(), String> {
    match value.map(str::trim) {
        None | Some("") => Ok(()),
        Some(v) => {
            let digits: String = v.chars().filter(char::is_ascii_digit).collect();
            if digits.len() >= 10 && digits.len() <= 15 && digits.starts_with('0') {
                Ok(())
            } else {
                Err(format!(
                    "{field} must be a valid Thai phone (≥10 digits starting with 0)"
                ))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn years_none_is_ok() {
        assert!(validate_years_of_experience(None).is_ok());
    }

    #[test]
    fn years_in_range_is_ok() {
        assert!(validate_years_of_experience(Some(0)).is_ok());
        assert!(validate_years_of_experience(Some(10)).is_ok());
        assert!(validate_years_of_experience(Some(MAX_YEARS_OF_EXPERIENCE)).is_ok());
    }

    #[test]
    fn years_negative_is_rejected() {
        assert!(validate_years_of_experience(Some(-1)).is_err());
    }

    #[test]
    fn years_above_max_is_rejected() {
        assert!(validate_years_of_experience(Some(MAX_YEARS_OF_EXPERIENCE + 1)).is_err());
    }

    #[test]
    fn text_none_and_short_are_ok() {
        assert!(validate_text(None, "f", MAX_TEXT_LEN).is_ok());
        assert!(validate_text(Some("hello"), "f", MAX_TEXT_LEN).is_ok());
    }

    #[test]
    fn text_at_limit_is_ok() {
        let s = "a".repeat(MAX_TEXT_LEN);
        assert!(validate_text(Some(&s), "f", MAX_TEXT_LEN).is_ok());
    }

    #[test]
    fn text_over_limit_is_rejected() {
        let s = "a".repeat(MAX_TEXT_LEN + 1);
        assert!(validate_text(Some(&s), "f", MAX_TEXT_LEN).is_err());
    }

    #[test]
    fn text_counts_chars_not_bytes() {
        // 5 multi-byte chars must NOT be rejected by a max of 5 (would fail if counting bytes).
        assert!(validate_text(Some("กขคงจ"), "f", 5).is_ok());
    }

    #[test]
    fn email_none_empty_and_valid_are_ok() {
        assert!(validate_email(None).is_ok());
        assert!(validate_email(Some("  ")).is_ok());
        assert!(validate_email(Some("a@b.co")).is_ok());
    }

    #[test]
    fn email_missing_at_or_dot_or_too_short_is_rejected() {
        assert!(validate_email(Some("nope")).is_err());
        assert!(validate_email(Some("a@bcd")).is_err()); // no dot
        assert!(validate_email(Some("a.bcd")).is_err()); // no @
        assert!(validate_email(Some("a@b.")).is_err()); // len 4 < 5
    }

    #[test]
    fn phone_none_empty_and_valid_are_ok() {
        assert!(validate_thai_phone(None, "phone").is_ok());
        assert!(validate_thai_phone(Some(""), "phone").is_ok());
        assert!(validate_thai_phone(Some("0812345678"), "phone").is_ok());
        assert!(validate_thai_phone(Some("08-1234-5678"), "phone").is_ok()); // separators ignored
    }

    #[test]
    fn phone_wrong_shape_is_rejected() {
        assert!(validate_thai_phone(Some("12345"), "phone").is_err()); // too short
        assert!(validate_thai_phone(Some("8123456789"), "phone").is_err()); // no leading 0
    }
}
