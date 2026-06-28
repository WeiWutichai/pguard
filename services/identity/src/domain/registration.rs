//! PURE registration decisions — no DB, no HTTP, no async I/O. 100% unit-testable.
//!
//! Role choice + role→profile-token-purpose mapping + defensive phone re-validation for
//! `POST /auth/register`. The transport handler (`api`) orchestrates these with the Redis
//! single-use GETDEL and the `repo` UPSERT.

use shared::auth::{PROFILE_PURPOSE_CUSTOMER, PROFILE_PURPOSE_GUARD};
use shared::error::AppError;
use shared::models::UserRole;

/// Validate the role chosen at registration. `admin` can NEVER be self-assigned via the
/// public register endpoint (privilege escalation) → `Forbidden`; an unknown role →
/// `BadRequest`. Only `guard`/`customer` are accepted (the two self-service roles).
pub fn validate_registration_role(role: &str) -> Result<UserRole, AppError> {
    match role.parse::<UserRole>() {
        Ok(UserRole::Admin) => Err(AppError::Forbidden(
            "The admin role cannot be self-assigned".to_string(),
        )),
        Ok(r) => Ok(r),
        Err(_) => Err(AppError::BadRequest(format!("Unknown role: {role}"))),
    }
}

/// Map a registration role to the single-use profile-token purpose for its onboarding route
/// (`guard` → `/profile/guard`, `customer` → `/profile/customer`). `admin` is already
/// rejected by [`validate_registration_role`] before this is called, so the admin arm is
/// unreachable in practice — but it FAILS LOUD (`Forbidden`) rather than silently minting a
/// wrong-purpose token, in case the call order is ever refactored. Returning `Result` keeps
/// the request path panic-free (no `unreachable!()`).
pub fn profile_purpose_for_role(role: &UserRole) -> Result<&'static str, AppError> {
    match role {
        UserRole::Guard => Ok(PROFILE_PURPOSE_GUARD),
        UserRole::Customer => Ok(PROFILE_PURPOSE_CUSTOMER),
        UserRole::Admin => Err(AppError::Forbidden(
            "The admin role has no profile-submission route".to_string(),
        )),
    }
}

/// Defensive re-validation + normalization of the phone extracted from the (already
/// otp-validated) phone-verify token: 10 digits starting with 0, non-digits stripped.
/// Belt-and-suspenders — otp validated it at issuance, but identity never trusts a value
/// off the wire without re-checking. Returns the normalized digit string.
pub fn validate_thai_phone(phone: &str) -> Result<String, AppError> {
    let digits: String = phone.chars().filter(|c| c.is_ascii_digit()).collect();
    if digits.len() != 10 || !digits.starts_with('0') {
        return Err(AppError::BadRequest(
            "Invalid phone format — must be 10 digits starting with 0".to_string(),
        ));
    }
    Ok(digits)
}

/// A client-supplied `pin_hash` is the lowercase-hex SHA-256 of the user's PIN (identity
/// then Argon2's it as the password). Validate shape defensively: exactly 64 hex chars.
pub fn validate_pin_hash(pin_hash: &str) -> Result<(), AppError> {
    let ok = pin_hash.len() == 64 && pin_hash.bytes().all(|b| b.is_ascii_hexdigit());
    if !ok {
        return Err(AppError::BadRequest(
            "pin_hash must be a 64-character hex SHA-256 digest".to_string(),
        ));
    }
    Ok(())
}

/// Max self-set display name length (`PUT /auth/me`). Wide enough for a full Thai/EN name.
pub const MAX_DISPLAY_NAME_LEN: usize = 120;

/// Validate + normalize a self-set `display_name` (`PUT /auth/me`): trim, then require 1..=120
/// CHARACTERS (not bytes — a Thai name is multibyte). Empty-after-trim → BadRequest. Returns the
/// trimmed value to store.
pub fn validate_display_name(raw: &str) -> Result<String, AppError> {
    let trimmed = raw.trim();
    let len = trimmed.chars().count();
    if len == 0 {
        return Err(AppError::BadRequest(
            "display_name must not be empty".to_string(),
        ));
    }
    if len > MAX_DISPLAY_NAME_LEN {
        return Err(AppError::BadRequest(format!(
            "display_name must be at most {MAX_DISPLAY_NAME_LEN} characters"
        )));
    }
    Ok(trimmed.to_string())
}

/// Validate + normalize an OPTIONAL self-set `email` (`PUT /auth/me`). LOOSE shape (mirrors
/// profile's `validate_email`: must contain `@` + `.`, length 5..=254) — real verification is out
/// of scope — then LOWERCASED so the `UNIQUE(email)` constraint is case-insensitive. `None` or
/// blank → `Ok(None)` (the field is cleared). Returns the lowercased address to store, or `None`.
pub fn validate_email(raw: Option<&str>) -> Result<Option<String>, AppError> {
    match raw.map(str::trim) {
        None | Some("") => Ok(None),
        Some(v) if v.len() >= 5 && v.len() <= 254 && v.contains('@') && v.contains('.') => {
            Ok(Some(v.to_lowercase()))
        }
        Some(_) => Err(AppError::BadRequest(
            "email must be a valid address".to_string(),
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn guard_and_customer_roles_are_accepted() {
        assert_eq!(
            validate_registration_role("guard").unwrap(),
            UserRole::Guard
        );
        assert_eq!(
            validate_registration_role("customer").unwrap(),
            UserRole::Customer
        );
        // Case-insensitive (UserRole::from_str lowercases).
        assert_eq!(
            validate_registration_role("Customer").unwrap(),
            UserRole::Customer
        );
    }

    #[test]
    fn admin_role_is_forbidden() {
        let err = validate_registration_role("admin").unwrap_err();
        assert!(matches!(err, AppError::Forbidden(_)), "got {err:?}");
        // Case variants must also be rejected.
        assert!(matches!(
            validate_registration_role("ADMIN").unwrap_err(),
            AppError::Forbidden(_)
        ));
    }

    #[test]
    fn unknown_role_is_bad_request() {
        assert!(matches!(
            validate_registration_role("superuser").unwrap_err(),
            AppError::BadRequest(_)
        ));
        assert!(matches!(
            validate_registration_role("").unwrap_err(),
            AppError::BadRequest(_)
        ));
    }

    #[test]
    fn purpose_maps_by_role() {
        assert_eq!(
            profile_purpose_for_role(&UserRole::Guard).unwrap(),
            PROFILE_PURPOSE_GUARD
        );
        assert_eq!(
            profile_purpose_for_role(&UserRole::Customer).unwrap(),
            PROFILE_PURPOSE_CUSTOMER
        );
        // admin has no profile route — fails loud rather than minting a wrong-purpose token.
        assert!(matches!(
            profile_purpose_for_role(&UserRole::Admin).unwrap_err(),
            AppError::Forbidden(_)
        ));
    }

    #[test]
    fn phone_validation_normalizes_and_rejects() {
        assert_eq!(validate_thai_phone("081-234-5678").unwrap(), "0812345678");
        assert_eq!(validate_thai_phone("0812345678").unwrap(), "0812345678");
        assert!(validate_thai_phone("12345678").is_err());
        assert!(validate_thai_phone("8112345678").is_err()); // doesn't start with 0
        assert!(validate_thai_phone("081234567").is_err()); // 9 digits
    }

    #[test]
    fn pin_hash_shape_is_validated() {
        let ok = "a".repeat(64);
        assert!(validate_pin_hash(&ok).is_ok());
        assert!(validate_pin_hash(&"a".repeat(63)).is_err()); // too short
        assert!(validate_pin_hash(&"a".repeat(65)).is_err()); // too long
        assert!(validate_pin_hash(&"g".repeat(64)).is_err()); // non-hex
    }

    #[test]
    fn display_name_trims_and_bounds() {
        assert_eq!(validate_display_name("  Somchai  ").unwrap(), "Somchai");
        // Multibyte Thai name counts CHARACTERS, not bytes.
        let thai = "สมชาย ใจดี";
        assert_eq!(validate_display_name(thai).unwrap(), thai);
        assert!(matches!(
            validate_display_name("   ").unwrap_err(),
            AppError::BadRequest(_)
        ));
        let too_long = "x".repeat(MAX_DISPLAY_NAME_LEN + 1);
        assert!(matches!(
            validate_display_name(&too_long).unwrap_err(),
            AppError::BadRequest(_)
        ));
        // Exactly at the cap is OK.
        assert!(validate_display_name(&"x".repeat(MAX_DISPLAY_NAME_LEN)).is_ok());
    }

    #[test]
    fn email_is_optional_lowercased_and_shape_checked() {
        assert_eq!(validate_email(None).unwrap(), None);
        assert_eq!(validate_email(Some("   ")).unwrap(), None);
        assert_eq!(
            validate_email(Some("  Admin@Example.COM ")).unwrap(),
            Some("admin@example.com".to_string())
        );
        assert!(matches!(
            validate_email(Some("nope")).unwrap_err(),
            AppError::BadRequest(_)
        ));
        assert!(matches!(
            validate_email(Some("a@bcd")).unwrap_err(), // no dot
            AppError::BadRequest(_)
        ));
    }
}
