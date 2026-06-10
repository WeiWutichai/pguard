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
    Payment,
    Notification,
    Calling,
    Rating,
    Presence,
    Chat,
}

impl Upstream {
    /// Stable string key (used for the env-resolved URL map + logs).
    pub fn as_str(self) -> &'static str {
        match self {
            Upstream::Identity => "identity",
            Upstream::Otp => "otp",
            Upstream::Profile => "profile",
            Upstream::Booking => "booking",
            Upstream::Payment => "payment",
            Upstream::Notification => "notification",
            Upstream::Calling => "calling",
            Upstream::Rating => "rating",
            Upstream::Presence => "presence",
            Upstream::Chat => "chat",
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
///
/// `suffix` (rarely set) disambiguates rules that share a prefix but split by the
/// segment AFTER one wildcard path segment: a rule with `prefix: "/guards/"` and
/// `suffix: "/ratings"` matches `/guards/{id}/ratings` (and deeper subpaths) but not
/// `/guards/{id}/location`. This keeps `/guards/{id}/ratings` → rating while
/// `/guards/{id}/location`·`/history` → presence, with plain segment comparison —
/// no regex in the hot path. Suffix-less rules keep the original pure-prefix
/// semantics untouched.
struct Rule {
    prefix: &'static str,
    /// `Some("/seg")` → require `prefix` + exactly one wildcard segment + `/seg`
    /// (at a segment boundary). `None` → plain prefix match (the common case).
    suffix: Option<&'static str>,
    upstream: Upstream,
    tier: Tier,
}

impl Rule {
    /// `true` if `path` (post-`/v1` strip) matches this rule.
    fn matches(&self, path: &str) -> bool {
        if !path.starts_with(self.prefix) {
            return false;
        }
        let Some(suffix) = self.suffix else {
            return true;
        };
        // One wildcard segment (the `{id}`) must sit between the prefix and the suffix.
        let rest = &path[self.prefix.len()..];
        let Some((id, tail)) = rest.split_once('/') else {
            return false; // no segment after the wildcard → suffix can't match
        };
        if id.is_empty() {
            return false; // an empty `{id}` segment (`/guards//ratings`) is not a match
        }
        // Suffix literals are segment paths ("/seg") — strip the leading '/' without
        // indexing so a malformed future rule can't panic in the request path (a test
        // pins the invariant for every RULES entry).
        let Some(seg) = suffix.strip_prefix('/') else {
            return false;
        };
        // `tail` must BE the suffix segment(s) or continue past a segment boundary.
        match tail.strip_prefix(seg) {
            Some(after) => after.is_empty() || after.starts_with('/'),
            None => false,
        }
    }

    /// Specificity key for longest-match selection: prefix length first (the original
    /// longest-prefix semantics), then suffix length so a suffixed rule outranks a
    /// hypothetical suffix-less rule on the same prefix.
    fn specificity(&self) -> (usize, usize) {
        (self.prefix.len(), self.suffix.map_or(0, str::len))
    }
}

/// The routing table, ordered longest-prefix-first so `/admin/guard-profiles` wins
/// over a hypothetical shorter `/admin` rule. Matches CLAUDE.md's gateway route map.
const RULES: &[Rule] = &[
    Rule {
        prefix: "/admin/guard-profiles",
        suffix: None,
        upstream: Upstream::Profile,
        tier: Tier::Api,
    },
    Rule {
        // Review moderation (list + visibility). Admin authz is the rating service's own
        // job (role check on its side) — same pattern as `/admin/guard-profiles` → profile.
        prefix: "/admin/reviews",
        suffix: None,
        upstream: Upstream::Rating,
        tier: Tier::Api,
    },
    Rule {
        prefix: "/auth/",
        suffix: None,
        upstream: Upstream::Identity,
        tier: Tier::Auth,
    },
    Rule {
        // PDPA §19/§32 data export (identity aggregates across services). A specific prefix
        // (not bare `/me`) so it can't over-match a future `/me…` resource.
        prefix: "/me/data-export",
        suffix: None,
        upstream: Upstream::Identity,
        tier: Tier::Api,
    },
    Rule {
        prefix: "/otp/",
        suffix: None,
        upstream: Upstream::Otp,
        tier: Tier::Otp,
    },
    Rule {
        prefix: "/profile/",
        suffix: None,
        upstream: Upstream::Profile,
        tier: Tier::Api,
    },
    Rule {
        prefix: "/bookings",
        suffix: None,
        upstream: Upstream::Booking,
        tier: Tier::Api,
    },
    Rule {
        // Guard discovery (booking owns it; aggregates profile catalog + rating summaries).
        prefix: "/available-guards",
        suffix: None,
        upstream: Upstream::Booking,
        tier: Tier::Api,
    },
    Rule {
        prefix: "/payments",
        suffix: None,
        upstream: Upstream::Payment,
        tier: Tier::Api,
    },
    Rule {
        // WebRTC call control (REST): initiate/get/accept/reject/connected/end + the served ICE
        // config (`/calls/ice`). All require a token (bearerAuth in calling.yaml). The `/ws/call`
        // signaling upgrade is NOT here — it goes through the generic edge WS proxy
        // (`/v1/ws/{chat,track,call}`, see `crate::wsproxy`), which axum routes before this
        // catch-all table, like the status-WS hub's bespoke `/v1/ws/bookings/{id}`.
        prefix: "/calls",
        suffix: None,
        upstream: Upstream::Calling,
        tier: Tier::Api,
    },
    Rule {
        prefix: "/notifications",
        suffix: None,
        upstream: Upstream::Notification,
        tier: Tier::Api,
    },
    Rule {
        prefix: "/tokens",
        suffix: None,
        upstream: Upstream::Notification,
        tier: Tier::Api,
    },
    Rule {
        // Chat threads: collection + `/conversations/{id}/messages`·`/read` subpaths.
        prefix: "/conversations",
        suffix: None,
        upstream: Upstream::Chat,
        tier: Tier::Api,
    },
    Rule {
        // Chat attachment download/upload (`/attachments/{id}`).
        prefix: "/attachments",
        suffix: None,
        upstream: Upstream::Chat,
        tier: Tier::Api,
    },
    Rule {
        // Live guard locations (admin map list).
        prefix: "/locations",
        suffix: None,
        upstream: Upstream::Presence,
        tier: Tier::Api,
    },
    // `/guards/{id}/…` splits by the segment after the id: location/history → presence,
    // ratings → rating. The suffix mechanism (see [`Rule`]) keeps this a plain segment
    // comparison; an unknown `/guards/{id}/other` matches nothing → 404 at the edge.
    Rule {
        prefix: "/guards/",
        suffix: Some("/location"),
        upstream: Upstream::Presence,
        tier: Tier::Api,
    },
    Rule {
        prefix: "/guards/",
        suffix: Some("/history"),
        upstream: Upstream::Presence,
        tier: Tier::Api,
    },
    Rule {
        // Token-gated like every discovery surface — rating.yaml's getGuardRatings was
        // amended to bearerAuth to match (visibility filtering is the "public" part).
        prefix: "/guards/",
        suffix: Some("/ratings"),
        upstream: Upstream::Rating,
        tier: Tier::Api,
    },
    Rule {
        // Review submission (`/assignments/{id}/review`). Suffixed so ONLY the review
        // resource routes to rating — booking exposes no `/assignments` at the edge today,
        // and a future booking-owned `/assignments/{id}/…` resource can still be added
        // without colliding with this rule.
        prefix: "/assignments/",
        suffix: Some("/review"),
        upstream: Upstream::Rating,
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
    path == "/internal"
        || path.ends_with("/internal")
        || path.starts_with("/internal/")
        || path.contains("/internal/")
}

/// `true` if the path carries a percent-encoded path separator (`%2f`/`%5c`). Our resource
/// paths never contain one; allowing it would let `/v1/x%2finternal/y` slip past the
/// `/internal` block (a backend that later decodes `%2f` would then see the separator).
fn has_encoded_separator(path: &str) -> bool {
    let lower = path.to_ascii_lowercase();
    lower.contains("%2f") || lower.contains("%5c")
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
    // Reject percent-encoded path separators outright — they have no legitimate use in
    // our resource paths and would otherwise let an encoded `/internal/` slip the block.
    if has_encoded_separator(path) {
        return RouteDecision::Block;
    }

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
    // explicitly so ordering mistakes can't silently misroute. Suffix length breaks
    // prefix-length ties (a suffixed rule is the more specific one).
    let best = RULES
        .iter()
        .filter(|r| r.matches(stripped))
        .max_by_key(|r| r.specificity());

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
    fn data_export_routes_to_identity_api_tier_protected() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/me/data-export"));
        assert_eq!(up, Upstream::Identity);
        assert_eq!(fwd, "/me/data-export");
        assert!(!public, "data-export requires a token");
        assert_eq!(tier, Tier::Api);
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
    fn booking_lifecycle_subpaths_are_edge_reachable() {
        // The customer-facing lifecycle actions added to booking must resolve through the
        // gateway (the single `/bookings` prefix covers every subpath + method).
        for p in [
            "/v1/bookings/abc/cancel",
            "/v1/bookings/abc/review-completion",
            "/v1/bookings/abc/start",
            "/v1/bookings/abc/complete",
        ] {
            let (up, fwd, public, tier) = proxy(resolve(p));
            assert_eq!(up, Upstream::Booking, "{p}");
            assert_eq!(fwd, p.strip_prefix("/v1").unwrap());
            assert!(!public, "{p} requires a token");
            assert_eq!(tier, Tier::Api);
        }
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
        assert_eq!(resolve("/v1/"), RouteDecision::NotFound);
    }

    #[test]
    fn available_guards_routes_to_booking_protected() {
        // Discovery is edge-reachable (bearerAuth in the contract) → must resolve to booking,
        // authed, Api tier. (Regression for the gateway/OpenAPI route-map drift.)
        let (up, fwd, public, tier) = proxy(resolve("/v1/available-guards"));
        assert_eq!(up, Upstream::Booking);
        assert_eq!(fwd, "/available-guards");
        assert!(!public, "/available-guards requires a token");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn payments_routes_to_payment_api_tier_protected() {
        // Closes the money path at the edge: /v1/payments now reaches the payment service
        // (was NotFound). Authed (not public) + general API tier.
        let (up, fwd, public, tier) = proxy(resolve("/v1/payments"));
        assert_eq!(up, Upstream::Payment);
        assert_eq!(fwd, "/payments");
        assert!(!public, "/payments requires a token");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn calls_route_to_calling_api_tier_protected() {
        // The served ICE config (and all call-control REST) must reach the calling service through
        // the edge — was NotFound before the Calling upstream was wired. Authed + general API tier.
        let (up, fwd, public, tier) = proxy(resolve("/v1/calls/ice"));
        assert_eq!(up, Upstream::Calling);
        assert_eq!(fwd, "/calls/ice");
        assert!(!public, "/calls/ice requires a token");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn calls_subpaths_route_to_calling() {
        for p in [
            "/v1/calls/initiate",
            "/v1/calls/abc-123",
            "/v1/calls/abc/accept",
            "/v1/calls/abc/end",
        ] {
            let (up, fwd, public, _) = proxy(resolve(p));
            assert_eq!(up, Upstream::Calling, "{p}");
            assert_eq!(fwd, p.strip_prefix("/v1").unwrap());
            assert!(!public, "{p} requires a token");
        }
    }

    #[test]
    fn payments_subpaths_route_to_payment() {
        let (up, fwd, _, _) = proxy(resolve("/v1/payments/abc-123"));
        assert_eq!(up, Upstream::Payment);
        assert_eq!(fwd, "/payments/abc-123");
        let (up2, fwd2, _, _) = proxy(resolve("/v1/payments/abc/complete"));
        assert_eq!(up2, Upstream::Payment);
        assert_eq!(fwd2, "/payments/abc/complete");
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

    #[test]
    fn trailing_internal_segment_is_blocked() {
        // The collection root with no trailing slash must also be blocked.
        assert_eq!(resolve("/v1/notifications/internal"), RouteDecision::Block);
        // ...but a longer word that merely starts with "internal" is NOT the segment.
        assert!(matches!(
            resolve("/v1/notifications/internalish"),
            RouteDecision::Proxy { .. }
        ));
    }

    #[test]
    fn encoded_path_separator_is_blocked() {
        // %2f / %5c can't be used to smuggle an /internal/ past the literal check
        // (a backend that decodes them would otherwise see a real separator).
        for p in [
            "/v1/notifications%2finternal/push",
            "/v1/notifications/internal%2Fpush",
            "/v1/bookings%2f..%2fx",
            "/v1/profile%5cinternal",
        ] {
            assert_eq!(resolve(p), RouteDecision::Block, "{p} must be blocked");
        }
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
        assert_eq!(Upstream::Rating.as_str(), "rating");
        assert_eq!(Upstream::Presence.as_str(), "presence");
        assert_eq!(Upstream::Chat.as_str(), "chat");
    }

    // ----- chat routes (gateway routing gap) -----

    #[test]
    fn conversations_route_to_chat_api_tier_protected() {
        for p in [
            "/v1/conversations",
            "/v1/conversations/abc-123",
            "/v1/conversations/abc/messages",
            "/v1/conversations/abc/read",
        ] {
            let (up, fwd, public, tier) = proxy(resolve(p));
            assert_eq!(up, Upstream::Chat, "{p}");
            assert_eq!(fwd, p.strip_prefix("/v1").unwrap());
            assert!(!public, "{p} requires a token");
            assert_eq!(tier, Tier::Api);
        }
    }

    #[test]
    fn attachments_route_to_chat() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/attachments/abc-123"));
        assert_eq!(up, Upstream::Chat);
        assert_eq!(fwd, "/attachments/abc-123");
        assert!(!public, "/attachments requires a token");
        assert_eq!(tier, Tier::Api);
    }

    // ----- presence routes -----

    #[test]
    fn locations_route_to_presence_protected() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/locations"));
        assert_eq!(up, Upstream::Presence);
        assert_eq!(fwd, "/locations");
        assert!(!public, "/locations requires a token");
        assert_eq!(tier, Tier::Api);
    }

    // ----- rating routes -----

    #[test]
    fn assignment_review_routes_to_rating_protected() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/assignments/abc-123/review"));
        assert_eq!(up, Upstream::Rating);
        assert_eq!(fwd, "/assignments/abc-123/review");
        assert!(!public, "review submission requires a token");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn assignments_without_review_suffix_are_not_found() {
        // Only the review resource is rating's; the bare collection/item has no owner at
        // the edge (booking exposes no /assignments) so it must stay 404.
        assert_eq!(resolve("/v1/assignments"), RouteDecision::NotFound);
        assert_eq!(resolve("/v1/assignments/abc-123"), RouteDecision::NotFound);
        assert_eq!(
            resolve("/v1/assignments/abc/reviewers"),
            RouteDecision::NotFound,
            "a longer word merely starting with 'review' is NOT the segment"
        );
    }

    #[test]
    fn admin_reviews_route_to_rating() {
        for p in ["/v1/admin/reviews", "/v1/admin/reviews/abc/visibility"] {
            let (up, fwd, public, tier) = proxy(resolve(p));
            assert_eq!(up, Upstream::Rating, "{p}");
            assert_eq!(fwd, p.strip_prefix("/v1").unwrap());
            assert!(!public, "{p} requires a token");
            assert_eq!(tier, Tier::Api);
        }
    }

    #[test]
    fn admin_reviews_do_not_disturb_admin_guard_profiles() {
        // Both live under /admin/ — each goes to its own service, nothing else matches.
        let (up, _, _, _) = proxy(resolve("/v1/admin/guard-profiles/abc"));
        assert_eq!(up, Upstream::Profile);
        let (up, _, _, _) = proxy(resolve("/v1/admin/reviews/abc"));
        assert_eq!(up, Upstream::Rating);
        assert_eq!(resolve("/v1/admin/other"), RouteDecision::NotFound);
    }

    // ----- the /guards/{id}/… prefix collision (the slice's design point) -----

    #[test]
    fn guards_id_ratings_routes_to_rating() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/guards/abc-123/ratings"));
        assert_eq!(up, Upstream::Rating);
        assert_eq!(fwd, "/guards/abc-123/ratings");
        assert!(!public);
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn guards_id_location_and_history_route_to_presence() {
        for p in ["/v1/guards/abc-123/location", "/v1/guards/abc-123/history"] {
            let (up, fwd, public, tier) = proxy(resolve(p));
            assert_eq!(up, Upstream::Presence, "{p}");
            assert_eq!(fwd, p.strip_prefix("/v1").unwrap());
            assert!(!public, "{p} requires a token");
            assert_eq!(tier, Tier::Api);
        }
    }

    #[test]
    fn guards_suffix_subpaths_keep_their_upstream() {
        // Deeper subpaths after the discriminating segment stay with the same service.
        let (up, _, _, _) = proxy(resolve("/v1/guards/abc/ratings/summary"));
        assert_eq!(up, Upstream::Rating);
        let (up, _, _, _) = proxy(resolve("/v1/guards/abc/history/2026-06"));
        assert_eq!(up, Upstream::Presence);
    }

    #[test]
    fn guards_without_a_known_suffix_are_not_found() {
        assert_eq!(resolve("/v1/guards"), RouteDecision::NotFound);
        assert_eq!(resolve("/v1/guards/"), RouteDecision::NotFound);
        assert_eq!(resolve("/v1/guards/abc-123"), RouteDecision::NotFound);
        assert_eq!(resolve("/v1/guards/abc/profile"), RouteDecision::NotFound);
        // Suffix must sit at a segment boundary: a longer word doesn't match.
        assert_eq!(resolve("/v1/guards/abc/locations"), RouteDecision::NotFound);
        assert_eq!(resolve("/v1/guards/abc/ratingsx"), RouteDecision::NotFound);
        // Exactly ONE wildcard segment between prefix and suffix.
        assert_eq!(
            resolve("/v1/guards/a/b/ratings"),
            RouteDecision::NotFound,
            "suffix after two segments must not match"
        );
        // An empty wildcard segment is not a match.
        assert_eq!(resolve("/v1/guards//ratings"), RouteDecision::NotFound);
    }

    #[test]
    fn every_rule_suffix_is_a_well_formed_segment_path() {
        // Pins the invariant Rule::matches relies on: a suffix is "/<segment…>" with a
        // non-empty segment. A malformed entry would silently never match.
        for r in RULES {
            if let Some(s) = r.suffix {
                assert!(
                    s.starts_with('/') && s.len() >= 2,
                    "rule {}+{s:?} has a malformed suffix",
                    r.prefix
                );
            }
        }
    }

    #[test]
    fn guards_adversarial_ids_resolve_by_segment_position_only() {
        // An id that *spells* another rule's suffix must not confuse the match — only the
        // segment AFTER the id discriminates.
        let (up, _, _, _) = proxy(resolve("/v1/guards/ratings/location"));
        assert_eq!(up, Upstream::Presence, "id='ratings' is just an id");
        let (up, _, _, _) = proxy(resolve("/v1/guards/location/ratings"));
        assert_eq!(up, Upstream::Rating, "id='location' is just an id");
    }

    // ----- /internal block must hold for the new upstreams -----

    #[test]
    fn internal_paths_of_new_upstreams_are_blocked() {
        for p in [
            "/v1/conversations/internal/x",
            "/v1/attachments/internal",
            "/v1/locations/internal",
            "/v1/guards/abc/ratings/internal",
            "/v1/guards/abc/location/internal/x",
            "/v1/assignments/abc/review/internal",
            "/v1/admin/reviews/internal/x",
        ] {
            assert_eq!(resolve(p), RouteDecision::Block, "{p} must be blocked");
        }
        // Encoded-separator smuggling stays blocked for the new prefixes too.
        assert_eq!(
            resolve("/v1/conversations%2finternal/x"),
            RouteDecision::Block
        );
        assert_eq!(resolve("/v1/guards/abc%2finternal"), RouteDecision::Block);
    }
}
