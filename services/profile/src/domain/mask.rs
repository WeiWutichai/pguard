//! Bank-account-number masking (PDPA §7 — "Bank / PII" in the security-reviewer
//! checklist). Read responses to non-admin callers show only the last 4 characters;
//! admin endpoints return the full value.
//!
//! Ported from v1 `../guard-dispatch/services/auth/src/service.rs` (~line 2404) and its
//! unit tests (~line 3487). Pure — no I/O.

/// The placeholder [`mask_account_number`] substitutes for every hidden character. Declared
/// once so the masker and the write-back guard ([`looks_masked`]) can never drift apart.
pub const MASK_CHAR: char = '*';

/// Mask a bank account number to its last 4 characters: every character before the last
/// four becomes `*`. Numbers of 4 characters or fewer are returned unchanged (there is
/// nothing left to reveal by masking them, and over-masking a short value would leak its
/// length without protecting anything new).
///
/// Operates on `char`s, not bytes, so a multi-byte string can never panic on a non-char
/// boundary slice (the v1 byte-slice version was ASCII-only by luck).
pub fn mask_account_number(account_number: &str) -> String {
    let chars: Vec<char> = account_number.chars().collect();
    if chars.len() > 4 {
        let masked_len = chars.len() - 4;
        let last4: String = chars[masked_len..].iter().collect();
        format!("{}{}", MASK_CHAR.to_string().repeat(masked_len), last4)
    } else {
        account_number.to_string()
    }
}

/// `true` when `value` still carries the mask placeholder — i.e. the client is writing back a
/// value it READ masked, not a real one.
///
/// Both `account_number` and `tax_id` are returned MASKED on owner reads, and both are written
/// from the request body, so a client that loads the profile, edits one unrelated field and PUTs
/// the whole object back would otherwise persist `"******7890"` as the real bank account / TIN —
/// silently making the guard unpayable. `MASK_CHAR` can never appear in a genuine account number
/// or Thai TIN (both are digits), so its presence can only be that unintended round-trip.
/// `None` → `false` (an absent field is not a masked one).
pub fn looks_masked(value: Option<&str>) -> bool {
    value.is_some_and(|v| v.contains(MASK_CHAR))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn masks_long_number_to_last_4() {
        // Ported assertion from v1 service.rs bank_account_number_masked_long_number.
        assert_eq!(mask_account_number("1234567890"), "******7890");
    }

    #[test]
    fn masked_value_hides_leading_digits() {
        let masked = mask_account_number("1234567890");
        assert!(
            !masked.contains("123456"),
            "leading digits must be masked, got {masked}"
        );
        assert!(
            masked.ends_with("7890"),
            "last 4 must survive, got {masked}"
        );
    }

    #[test]
    fn masks_exactly_5_digits() {
        // v1 bank_account_number_masked_exactly_5_digits.
        assert_eq!(mask_account_number("12345"), "*2345");
    }

    #[test]
    fn does_not_mask_when_4_or_fewer() {
        // v1 bank_account_number_not_masked_when_4_or_fewer_digits.
        assert_eq!(mask_account_number("1234"), "1234");
        assert_eq!(mask_account_number("123"), "123");
        assert_eq!(mask_account_number("1"), "1");
        assert_eq!(mask_account_number(""), "");
    }

    #[test]
    fn keeps_only_last_4() {
        // v1 bank_account_number_masked_last_4_only.
        let masked = mask_account_number("9876543210");
        assert_eq!(masked, "******3210");
        assert_eq!(&masked[masked.len() - 4..], "3210");
    }

    #[test]
    fn looks_masked_catches_a_read_back_value() {
        // The exact round-trip the guard exists for: whatever the owner read comes back masked,
        // and re-PUTting it must be recognisable as such (ties the predicate to the masker, so a
        // change to the placeholder can never silently disarm the write-back guard).
        assert!(looks_masked(Some(&mask_account_number("1234567890"))));
        assert!(looks_masked(Some(&mask_account_number("1234567890123")))); // 13-digit Thai TIN
    }

    #[test]
    fn looks_masked_passes_real_and_absent_values() {
        assert!(!looks_masked(None), "an absent field is not a masked one");
        assert!(!looks_masked(Some("")));
        assert!(!looks_masked(Some("1234567890")));
        assert!(!looks_masked(Some("1234567890123")));
        // A value SHORT enough that the masker leaves it alone must also pass — it is genuinely
        // unmasked, so re-writing it is a legitimate (if pointless) write.
        assert!(!looks_masked(Some(&mask_account_number("1234"))));
    }

    #[test]
    fn handles_multibyte_without_panicking() {
        // 6 multi-byte chars → 2 masked + last 4 preserved (char-wise, no byte-boundary panic).
        let masked = mask_account_number("กขคงจฉ");
        assert_eq!(masked.chars().count(), 6);
        assert!(masked.starts_with("**"));
        assert!(masked.ends_with("คงจฉ"));
    }
}
