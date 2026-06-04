//! PURE header-filtering rules for the proxy.
//!
//! Two responsibilities, both decided on the (lowercased) header name only:
//!   - [`is_hop_by_hop`] — RFC 7230 §6.1 connection-scoped headers that must NOT be
//!     forwarded across the proxy boundary (plus `host`, which reqwest re-derives from
//!     the upstream URL).
//!   - [`is_spoofable_identity`] — client-supplied `x-user-*` headers the gateway
//!     injects from the *verified* JWT. These must be stripped from inbound requests so
//!     a client can't forge an identity the backend would trust.

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
}
