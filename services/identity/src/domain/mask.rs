//! PURE PII masking for admin-facing reads — no DB/HTTP/async I/O. 100% unit-testable.

/// Mask a phone number for the admin user-search result (`GET /admin/users/search`): keep the LAST
/// 4 digits, replace every earlier digit with `*`, and DROP all separators (so the masked form
/// carries no positional structure beyond the tail). A short number (≤4 digits) is fully masked.
/// A soft-deleted account's redacted placeholder (`deleted:<uuid>`, no digits) masks to all `*`.
pub fn mask_phone(phone: &str) -> String {
    let digits: Vec<char> = phone.chars().filter(|c| c.is_ascii_digit()).collect();
    if digits.is_empty() {
        // No digits (e.g. an erased placeholder) — return a fixed-width opaque mask.
        return "*".repeat(4);
    }
    let keep = 4.min(digits.len());
    let hidden = digits.len() - keep;
    let mut out = String::with_capacity(digits.len());
    out.extend(std::iter::repeat_n('*', hidden));
    out.extend(digits.iter().skip(hidden));
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn masks_thai_mobile_keeping_last_4() {
        assert_eq!(mask_phone("0812345678"), "******5678");
    }

    #[test]
    fn drops_separators() {
        assert_eq!(mask_phone("081-234-5678"), "******5678");
    }

    #[test]
    fn short_number_is_fully_masked() {
        assert_eq!(mask_phone("12"), "12"); // ≤4 digits: nothing to hide
        assert_eq!(mask_phone("12345"), "*2345");
    }

    #[test]
    fn no_digits_returns_opaque_mask() {
        assert_eq!(mask_phone("deleted:abc-def"), "****");
    }
}
