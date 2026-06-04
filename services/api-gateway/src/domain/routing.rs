//! PURE request routing: resolve a public `/v1/...` path to an upstream + tier.
//!
//! Ports the *intent* of v1's nginx routing (`../guard-dispatch/nginx/nginx.conf`):
//! per-service longest-prefix matching, a blocked `/internal/` location (404, not 403,
//! so the endpoint's existence isn't revealed), and tier tagging that drives the
//! rate-limit zones. The nginx syntax is not ported — only the routing decisions.
//!
//! Resource-based `/v1` versioning (CLAUDE.md "API versioning"): the gateway strips the
//! leading `/v1` before forwarding because backends serve their bare resource paths
//! (e.g. identity serves `/auth/login`, not `/v1/auth/login`).

/// Rate-limit tier for a resolved route. Maps to the v1 nginx zones:
/// `auth_limit` (5r/s), `otp_limit` (10r/m), `api_limit` (30r/s).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tier {
    /// Auth endpoints — brute-force sensitive (v1 `auth_limit`, ~5r/s).
    Auth,
    /// OTP / SMS endpoints — SMS-cost sensitive (v1 `otp_limit`, ~10r/min).
    Otp,
    /// General API (v1 `api_limit`, ~30r/s).
    Api,
}

/// Logical upstream key. The concrete URL is resolved from env at startup
/// (see `AppState::routes`); the pure layer only deals in keys.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Upstream {
    Identity,
    Otp,
    Profile,
    Booking,
    Notification,
}

impl Upstream {
    /// Stable string key (used for the env-resolved URL map + logs).
    pub fn as_str(self) -> &'static str {
        match self {
            Upstream::Identity => "identity",
            Upstream::Otp => "otp",
            Upstream::Profile => "profile",
            Upstream::Booking => "booking",
            Upstream::Notification => "notification",
        }
    }
}

/// Outcome of resolving an inbound request path.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RouteDecision {
    /// Path is forbidden at the public edge (e.g. anything `/internal/`). 404.
    Block,
    /// No known prefix matched. 404.
    NotFound,
    /// Forward to `upstream`, rewriting the path to `forward_path` (the `/v1` strip).
    Proxy {
        upstream: Upstream,
        /// Path to send to the upstream (leading `/v1` removed), e.g. `/auth/login`.
        forward_path: String,
        /// `true` if no access token is required (login/refresh/otp public endpoints).
        public: bool,
        tier: Tier,
    },
}

/// A single longest-prefix routing rule. `prefix` matches against the post-`/v1`
/// resource path (e.g. `/auth/`, `/bookings`).
struct Rule {
    prefix: &'static str,
    upstream: Upstream,
    tier: Tier,
}

/// The routing table, ordered longest-prefix-first so `/admin/guard-profiles` wins
/// over a hypothetical shorter `/admin` rule. Matches CLAUDE.md's gateway route map.
const RULES: &[Rule] = &[
    Rule {
        prefix: "/admin/guard-profiles",
        upstream: Upstream::Profile,
        tier: Tier::Api,
    },
    Rule {
        prefix: "/auth/",
        upstream: Upstream::Identity,
        tier: Tier::Auth,
    },
    Rule {
        prefix: "/otp/",
        upstream: Upstream::Otp,
        tier: Tier::Otp,
    },
    Rule {
        prefix: "/profile/",
        upstream: Upstream::Profile,
        tier: Tier::Api,
    },
    Rule {
        prefix: "/bookings",
        upstream: Upstream::Booking,
        tier: Tier::Api,
    },
    Rule {
        prefix: "/notifications",
        upstream: Upstream::Notification,
        tier: Tier::Api,
    },
    Rule {
        prefix: "/tokens",
        upstream: Upstream::Notification,
        tier: Tier::Api,
    },
];

/// Exact public (token-not-required) resource paths, post-`/v1` strip. Everything
/// else under a known prefix is PROTECTED (token validated at the edge).
const PUBLIC_PATHS: &[&str] = &[
    "/auth/login",
    "/auth/refresh",
    "/otp/challenge",
    "/otp/request",
    "/otp/verify",
];

/// `true` if a (post-strip) path component is exactly `/internal` or `/internal/...`,
/// or contains an `/internal/` segment anywhere. Ports v1's blocked
/// `^~ /notification/internal/` location — service-JWT'd endpoints must never be
/// reachable from the public edge.
fn is_internal(path: &str) -> bool {
    path == "/internal" || path.starts_with("/internal/") || path.contains("/internal/")
}

/// Resolve an inbound request path (the raw URI path, e.g. `/v1/auth/login`) into a
/// [`RouteDecision`]. Query strings must be stripped by the caller before this point.
///
/// Order of checks:
///   1. `/healthz` is handled by the router directly, never reaches here.
///   2. Block anything containing `/internal/` (checked on BOTH the raw and stripped
///      path so `/internal/...` and `/v1/internal/...` are both blocked).
///   3. Require the `/v1` prefix; strip it.
///   4. Longest-prefix match against [`RULES`]; unknown → [`RouteDecision::NotFound`].
///   5. Classify public vs protected via [`PUBLIC_PATHS`].
pub fn resolve(path: &str) -> RouteDecision {
    // Block /internal even if a client tries to reach it without the /v1 prefix.
    if is_internal(path) {
        return RouteDecision::Block;
    }

    // Require and strip the /v1 version prefix. Accept exactly "/v1" + ("/" | end).
    let stripped = match strip_v1(path) {
        Some(s) => s,
        None => return RouteDecision::NotFound,
    };

    // Defense in depth: block /internal after the strip too.
    if is_internal(stripped) {
        return RouteDecision::Block;
    }

    // Longest-prefix match. RULES is ordered, but we also pick the longest match
    // explicitly so ordering mistakes can't silently misroute.
    let best = RULES
        .iter()
        .filter(|r| stripped.starts_with(r.prefix))
        .max_by_key(|r| r.prefix.len());

    match best {
        Some(rule) => RouteDecision::Proxy {
            upstream: rule.upstream,
            forward_path: stripped.to_string(),
            public: PUBLIC_PATHS.contains(&stripped),
            tier: rule.tier,
        },
        None => RouteDecision::NotFound,
    }
}

/// Strip a leading `/v1` version segment, returning the remaining resource path
/// (which always keeps its own leading slash). `/v1/auth/login` → `/auth/login`;
/// `/v1` → `/`; non-`/v1` (incl. `/v10/...`) → `None`.
fn strip_v1(path: &str) -> Option<&str> {
    if path == "/v1" {
        return Some("/");
    }
    // Only a true `/v1/` segment; `path[3..]` keeps the leading '/' of the resource.
    if path.starts_with("/v1/") {
        Some(&path[3..])
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn proxy(d: RouteDecision) -> (Upstream, String, bool, Tier) {
        match d {
            RouteDecision::Proxy {
                upstream,
                forward_path,
                public,
                tier,
            } => (upstream, forward_path, public, tier),
            other => panic!("expected Proxy, got {other:?}"),
        }
    }

    // ----- /v1 strip -----

    #[test]
    fn strips_v1_prefix_before_forwarding() {
        let (up, fwd, _, _) = proxy(resolve("/v1/auth/login"));
        assert_eq!(up, Upstream::Identity);
        assert_eq!(fwd, "/auth/login", "leading /v1 must be removed");
    }

    #[test]
    fn bare_v1_resolves_to_root_and_not_found() {
        // "/v1" → "/" which matches no prefix.
        assert_eq!(resolve("/v1"), RouteDecision::NotFound);
    }

    #[test]
    fn missing_v1_prefix_is_not_found() {
        // Backends are only reachable under /v1; a bare /auth/login at the edge 404s.
        assert_eq!(resolve("/auth/login"), RouteDecision::NotFound);
        assert_eq!(resolve("/"), RouteDecision::NotFound);
        assert_eq!(resolve("/v2/auth/login"), RouteDecision::NotFound);
    }

    // ----- per-prefix routing + tier -----

    #[test]
    fn auth_routes_to_identity_auth_tier() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/auth/login"));
        assert_eq!(up, Upstream::Identity);
        assert_eq!(fwd, "/auth/login");
        assert!(public, "/auth/login is public");
        assert_eq!(tier, Tier::Auth);
    }

    #[test]
    fn auth_me_is_protected() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/auth/me"));
        assert_eq!(up, Upstream::Identity);
        assert_eq!(fwd, "/auth/me");
        assert!(!public, "/auth/me requires a token");
        assert_eq!(tier, Tier::Auth);
    }

    #[test]
    fn otp_routes_to_otp_otp_tier() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/otp/request"));
        assert_eq!(up, Upstream::Otp);
        assert_eq!(fwd, "/otp/request");
        assert!(public);
        assert_eq!(tier, Tier::Otp);
    }

    #[test]
    fn profile_routes_to_profile_api_tier_protected() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/profile/me"));
        assert_eq!(up, Upstream::Profile);
        assert_eq!(fwd, "/profile/me");
        assert!(!public);
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn admin_guard_profiles_routes_to_profile() {
        let (up, fwd, _, tier) = proxy(resolve("/v1/admin/guard-profiles"));
        assert_eq!(up, Upstream::Profile);
        assert_eq!(fwd, "/admin/guard-profiles");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn admin_guard_profiles_subpath_routes_to_profile() {
        let (up, fwd, _, _) = proxy(resolve("/v1/admin/guard-profiles/abc/approve"));
        assert_eq!(up, Upstream::Profile);
        assert_eq!(fwd, "/admin/guard-profiles/abc/approve");
    }

    #[test]
    fn bookings_routes_to_booking() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/bookings/123"));
        assert_eq!(up, Upstream::Booking);
        assert_eq!(fwd, "/bookings/123");
        assert!(!public);
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn bookings_collection_routes_to_booking() {
        let (up, fwd, _, _) = proxy(resolve("/v1/bookings"));
        assert_eq!(up, Upstream::Booking);
        assert_eq!(fwd, "/bookings");
    }

    #[test]
    fn notifications_routes_to_notification() {
        let (up, fwd, _, tier) = proxy(resolve("/v1/notifications/unread-count"));
        assert_eq!(up, Upstream::Notification);
        assert_eq!(fwd, "/notifications/unread-count");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn tokens_routes_to_notification() {
        let (up, fwd, _, _) = proxy(resolve("/v1/tokens"));
        assert_eq!(up, Upstream::Notification);
        assert_eq!(fwd, "/tokens");
    }

    // ----- unknown prefix -----

    #[test]
    fn unknown_prefix_is_not_found() {
        assert_eq!(resolve("/v1/unknown"), RouteDecision::NotFound);
        assert_eq!(resolve("/v1/payments"), RouteDecision::NotFound);
        assert_eq!(resolve("/v1/"), RouteDecision::NotFound);
    }

    // ----- /internal block (the security-critical case) -----

    #[test]
    fn internal_paths_are_blocked() {
        assert_eq!(
            resolve("/v1/notifications/internal/push"),
            RouteDecision::Block
        );
        assert_eq!(resolve("/v1/internal/push"), RouteDecision::Block);
        assert_eq!(resolve("/internal/push"), RouteDecision::Block);
        assert_eq!(resolve("/internal"), RouteDecision::Block);
        assert_eq!(resolve("/v1/internal"), RouteDecision::Block);
    }

    #[test]
    fn internal_block_takes_priority_over_routing() {
        // Even though /notifications routes to notification, the /internal segment
        // must short-circuit to Block (never proxied to the public edge).
        assert_eq!(
            resolve("/v1/notifications/internal/anything"),
            RouteDecision::Block
        );
    }

    // ----- public allowlist completeness -----

    #[test]
    fn exact_public_allowlist() {
        for p in [
            "/v1/auth/login",
            "/v1/auth/refresh",
            "/v1/otp/challenge",
            "/v1/otp/request",
            "/v1/otp/verify",
        ] {
            let (_, _, public, _) = proxy(resolve(p));
            assert!(public, "{p} must be public");
        }
        // Near-misses must be protected.
        for p in ["/v1/auth/logout", "/v1/otp/admin", "/v1/auth/login/extra"] {
            let (_, _, public, _) = proxy(resolve(p));
            assert!(!public, "{p} must NOT be public");
        }
    }

    #[test]
    fn upstream_as_str_is_stable() {
        assert_eq!(Upstream::Identity.as_str(), "identity");
        assert_eq!(Upstream::Notification.as_str(), "notification");
    }
}
