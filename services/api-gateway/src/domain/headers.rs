//! PURE header rules for the proxy.
//!
//! Three responsibilities:
//!   - [`is_hop_by_hop`] — RFC 7230 §6.1 connection-scoped headers that must NOT be
//!     forwarded across the proxy boundary (plus `host`, which reqwest re-derives from
//!     the upstream URL).
//!   - [`is_spoofable_identity`] — client-supplied `x-user-*` headers the gateway
//!     injects from the *verified* JWT. These must be stripped from inbound requests so
//!     a client can't forge an identity the backend would trust.
//!   - [`security_headers`] — the fixed security response headers stamped on every edge
//!     response (parity with v1 nginx's global `add_header` block, plus 2026 hardening).
//!
//! All three are pure: `&str`/`&'static str` in and out, no `http`/axum types — the
//! transport layer (`handler::security_headers_mw`) turns the [`security_headers`] pairs
//! into real `HeaderName`/`HeaderValue`s and inserts them.

/// Hop-by-hop headers (RFC 7230 §6.1) + `host` — never forwarded to the upstream.
/// Compared case-insensitively (HTTP header names are case-insensitive).
const HOP_BY_HOP: &[&str] = &[
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
    // reqwest sets Host from the upstream URL; forwarding the edge Host would break
    // virtual-host routing and signed-URL host validation.
    "host",
    // Let reqwest manage framing/length for the (possibly rewritten) body.
    "content-length",
];

/// `true` if `name` (any case) is a hop-by-hop header that must be dropped before
/// forwarding to the upstream.
pub fn is_hop_by_hop(name: &str) -> bool {
    HOP_BY_HOP.iter().any(|h| name.eq_ignore_ascii_case(h))
}

/// `true` if `name` is a trusted-identity header the gateway owns (`x-user-id`,
/// `x-user-role`, and any future `x-user-*`). Inbound copies from the client are
/// stripped so they can't spoof the identity the backend reads.
pub fn is_spoofable_identity(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower == "x-user-id" || lower == "x-user-role" || lower.starts_with("x-user-")
}

/// Security response headers stamped on EVERY edge response, as `(name, value)` pairs.
/// Names are lowercase + values are valid constant header strings, so the transport layer
/// can build them with infallible `HeaderName`/`HeaderValue::from_static`. Ports v1 nginx's
/// global `add_header` block (`X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`,
/// `Referrer-Policy`, `Permissions-Policy`) and adds HSTS + a locked-down CSP for a JSON API.
pub fn security_headers() -> [(&'static str, &'static str); 7] {
    [
        // Clickjacking — the API edge is never meant to be framed.
        ("x-frame-options", "DENY"),
        // Stop browsers MIME-sniffing JSON into an executable type.
        ("x-content-type-options", "nosniff"),
        // Don't leak full request URLs (may carry ids) to third-party origins.
        ("referrer-policy", "strict-origin-when-cross-origin"),
        // OWASP-current guidance: disable the legacy XSS auditor (it introduced bugs);
        // CSP below is the real control. v1 set "1; mode=block"; "0" is the modern value.
        ("x-xss-protection", "0"),
        // TLS terminates in front of the gateway in prod, which forwards app headers to the
        // client; browsers ignore HSTS received over plain HTTP, so dev-over-HTTP is safe.
        // `includeSubDomains` assumes a dedicated API host (no plain-HTTP browser sibling).
        (
            "strict-transport-security",
            "max-age=31536000; includeSubDomains",
        ),
        // A JSON API loads no resources — lock everything down and reinforce anti-framing.
        (
            "content-security-policy",
            "default-src 'none'; frame-ancestors 'none'",
        ),
        // The API needs no browser features.
        (
            "permissions-policy",
            "camera=(), microphone=(), geolocation=()",
        ),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_hop_by_hop_case_insensitively() {
        assert!(is_hop_by_hop("Connection"));
        assert!(is_hop_by_hop("connection"));
        assert!(is_hop_by_hop("TRANSFER-ENCODING"));
        assert!(is_hop_by_hop("Keep-Alive"));
        assert!(is_hop_by_hop("Host"));
        assert!(is_hop_by_hop("content-length"));
    }

    #[test]
    fn passes_through_normal_headers() {
        assert!(!is_hop_by_hop("authorization"));
        assert!(!is_hop_by_hop("content-type"));
        assert!(!is_hop_by_hop("accept"));
        assert!(!is_hop_by_hop("x-correlation-id"));
    }

    #[test]
    fn strips_client_supplied_identity_headers() {
        assert!(is_spoofable_identity("X-User-Id"));
        assert!(is_spoofable_identity("x-user-id"));
        assert!(is_spoofable_identity("X-User-Role"));
        assert!(is_spoofable_identity("x-user-anything"));
    }

    #[test]
    fn keeps_non_identity_headers() {
        assert!(!is_spoofable_identity("authorization"));
        assert!(!is_spoofable_identity("x-requested-with"));
        assert!(!is_spoofable_identity("x-forwarded-for"));
        assert!(!is_spoofable_identity("user-agent"));
    }

    #[test]
    fn security_headers_cover_the_expected_set() {
        let hs = security_headers();
        let names: Vec<&str> = hs.iter().map(|(n, _)| *n).collect();
        for expected in [
            "x-frame-options",
            "x-content-type-options",
            "referrer-policy",
            "x-xss-protection",
            "strict-transport-security",
            "content-security-policy",
            "permissions-policy",
        ] {
            assert!(names.contains(&expected), "missing security header {expected}");
        }
    }

    #[test]
    fn security_headers_have_hardened_values() {
        let hs = security_headers();
        let get = |name: &str| hs.iter().find(|(n, _)| *n == name).map(|(_, v)| *v);
        assert_eq!(get("x-frame-options"), Some("DENY"));
        assert_eq!(get("x-content-type-options"), Some("nosniff"));
        assert_eq!(get("x-xss-protection"), Some("0"));
        assert!(get("content-security-policy")
            .unwrap()
            .contains("frame-ancestors 'none'"));
        assert!(get("strict-transport-security").unwrap().contains("max-age="));
    }

    // All names lowercase + values valid → `from_static` in the middleware can't panic.
    #[test]
    fn security_header_names_are_lowercase() {
        for (name, _) in security_headers() {
            assert_eq!(name, name.to_ascii_lowercase(), "{name} must be lowercase");
        }
    }
}
