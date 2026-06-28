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

/// Mask an IP address for the per-device sessions list (#144). Keeps enough to RECOGNISE the
/// network (so a user can tell "home" from "work") while redacting the host. IPv4 → keep the first
/// two octets, redact the rest (`203.0.x.x`). IPv6 → keep the first two hextets, redact the rest
/// (`2001:db8::/…` → `2001:db8:x`). A non-IP / empty string returns `*` (opaque). Pure.
pub fn mask_ip(ip: &str) -> String {
    let ip = ip.trim();
    if ip.is_empty() {
        return "*".to_string();
    }
    if ip.contains('.') && !ip.contains(':') {
        // IPv4 (or IPv4-mapped without a port): keep the first two octets.
        let parts: Vec<&str> = ip.split('.').collect();
        if parts.len() == 4 && parts.iter().all(|p| p.parse::<u8>().is_ok()) {
            return format!("{}.{}.x.x", parts[0], parts[1]);
        }
        return "*".to_string();
    }
    if ip.contains(':') {
        // IPv6: keep the first two hextets.
        let head: Vec<&str> = ip.split(':').take(2).collect();
        if head.len() == 2 && !head[0].is_empty() {
            return format!("{}:{}:x", head[0], head[1]);
        }
    }
    "*".to_string()
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

    #[test]
    fn masks_ipv4_to_first_two_octets() {
        assert_eq!(mask_ip("203.0.113.42"), "203.0.x.x");
        assert_eq!(mask_ip(" 10.1.2.3 "), "10.1.x.x");
    }

    #[test]
    fn masks_ipv6_to_first_two_hextets() {
        assert_eq!(mask_ip("2001:db8:1234:5678::1"), "2001:db8:x");
    }

    #[test]
    fn non_ip_or_empty_is_opaque() {
        assert_eq!(mask_ip(""), "*");
        assert_eq!(mask_ip("not-an-ip"), "*");
        assert_eq!(mask_ip("999.1.1.1"), "*"); // octet out of range
    }
}
