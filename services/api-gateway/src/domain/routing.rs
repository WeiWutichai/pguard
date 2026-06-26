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
    /// OTP send/challenge — SMS-cost sensitive (v1 `otp_limit`, ~10r/min). The real per-phone
    /// SMS abuse guard lives in the otp service (single live code + per-phone cooldown); this is
    /// the coarse per-IP backstop.
    Otp,
    /// OTP VERIFY — split from [`Tier::Otp`] so a burst of challenge/request traffic on a shared
    /// per-IP (carrier-NAT) bucket can never starve a legitimate code verification. Verify is
    /// cheap (no SMS) and the otp service already caps verify attempts per code, so this tier is
    /// generous. See `domain::ratelimit::Limits::otp_verify_per_min`.
    OtpVerify,
    /// General API (v1 `api_limit`, ~30r/s).
    Api,
}

/// Per-route request-body cap. The gateway buffers the request body before forwarding;
/// almost every route uses [`BodyCap::Default`] (1 MiB — a DoS guard, also the WS frame
/// cap via `proxy::MAX_BODY_BYTES`). The upload routes whose OpenAPI contract allows a
/// larger body opt into a wider cap: the check-in photo + guard credential/avatar uploads
/// take [`BodyCap::Large`] (12 MiB — a single image), and the chat image attachment takes
/// the wider [`BodyCap::Chat`] (30 MiB — photos straight off a modern phone camera run well
/// past 12 MiB). The cap is decided here (pure) and applied in `proxy::forward`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BodyCap {
    /// 1 MiB — the edge default for every non-upload route.
    Default,
    /// 12 MiB — carve-out for the single-image upload routes (check-in photo, guard
    /// credential image, avatar): covers a ≤10 MiB image plus multipart framing.
    Large,
    /// 30 MiB — the chat image-attachment carve-out (`POST /attachments`). Sits ABOVE
    /// [`BodyCap::Large`] because a chat photo can be an unedited full-resolution camera
    /// shot; the chat service's own `DefaultBodyLimit` is 210 MiB (it re-validates per-kind:
    /// image ≤10 MiB / video ≤200 MiB), so this is purely the edge buffer ceiling. Large
    /// video uploads through the edge are still out of scope (kept below the 200 MiB video
    /// contract on purpose).
    Chat,
}

impl BodyCap {
    /// 1 MiB. Pinned equal to `crate::proxy::MAX_BODY_BYTES` by a test so the edge default
    /// and the WS frame cap never drift apart.
    pub const DEFAULT_BYTES: usize = 1024 * 1024;
    /// 12 MiB — the single-image carve-out cap.
    pub const LARGE_BYTES: usize = 12 * 1024 * 1024;
    /// 30 MiB — the chat attachment carve-out cap.
    pub const CHAT_BYTES: usize = 30 * 1024 * 1024;

    /// The cap in bytes — what `proxy::forward` buffers up to before a 413.
    pub fn bytes(self) -> usize {
        match self {
            BodyCap::Default => Self::DEFAULT_BYTES,
            BodyCap::Large => Self::LARGE_BYTES,
            BodyCap::Chat => Self::CHAT_BYTES,
        }
    }
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
    /// EXTERNAL upstream (NOT an internal pguard service): the public OSRM routing demo
    /// (`OSRM_PRIMARY_URL`, with `OSRM_MIRROR_URL` as the gateway's failover). The device
    /// (Thai mobile network) can't reliably reach OSRM directly but always reaches the VPS,
    /// so the gateway proxies `/v1/osrm/<rest>` → `{OSRM_PRIMARY_URL}/<rest>` (the `/osrm`
    /// segment is stripped in [`resolve`]). Token-gated like any protected `/v1` route — the
    /// gateway auths the caller, then forwards (OSRM itself needs no auth). The handler's
    /// OSRM-specific mirror retry lives in `proxy::forward_osrm`.
    Osrm,
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
            Upstream::Osrm => "osrm",
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
        /// Max request body the gateway will buffer for this route before a 413.
        body_cap: BodyCap,
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
        // Admin customer directory (list). Admin authz is the profile service's own job —
        // same pattern as `/admin/guard-profiles` → profile.
        prefix: "/admin/customer-profiles",
        suffix: None,
        upstream: Upstream::Profile,
        tier: Tier::Api,
    },
    Rule {
        // Admin PDPA data-access audit log (read). Admin authz is the profile service's job.
        prefix: "/admin/access-audit",
        suffix: None,
        upstream: Upstream::Profile,
        tier: Tier::Api,
    },
    Rule {
        // Admin guard-document expiry surface (read). Profile owns the document_expiry table.
        prefix: "/admin/documents",
        suffix: None,
        upstream: Upstream::Profile,
        tier: Tier::Api,
    },
    Rule {
        // Admin recruitment pipeline (list + stage move). The single prefix also routes the
        // `/candidates/{id}/stage` subpath. Profile owns guard_profiles.recruitment_stage.
        prefix: "/admin/recruitment",
        suffix: None,
        upstream: Upstream::Profile,
        tier: Tier::Api,
    },
    Rule {
        // Admin booking operations (cross-user list + guard-assign). The single prefix rule
        // also routes the `/{id}/assign` subpath (suffix: None matches every subpath). Admin
        // authz is the booking service's own job.
        prefix: "/admin/bookings",
        suffix: None,
        upstream: Upstream::Booking,
        tier: Tier::Api,
    },
    Rule {
        // Admin payment ledger (cross-user, read-only). Admin authz is the payment service's job.
        prefix: "/admin/payments",
        suffix: None,
        upstream: Upstream::Payment,
        tier: Tier::Api,
    },
    Rule {
        // Admin service-catalog (pricing) CRUD — hosted by booking. The single prefix also
        // routes the `/services/{id}` subpath. Admin authz is the booking service's job.
        prefix: "/admin/pricing",
        suffix: None,
        upstream: Upstream::Booking,
        tier: Tier::Api,
    },
    Rule {
        // Admin call log (cross-user, read-only). Admin authz is the calling service's job.
        prefix: "/admin/calls",
        suffix: None,
        upstream: Upstream::Calling,
        tier: Tier::Api,
    },
    Rule {
        // Admin conversation list (cross-user, read-only). The message pane reuses the existing
        // /conversations/{id}/messages rule. Admin authz is the chat service's job.
        prefix: "/admin/conversations",
        suffix: None,
        upstream: Upstream::Chat,
        tier: Tier::Api,
    },
    Rule {
        // Admin broadcast (bulk-send) — composer + draft + schedule + history. The single prefix
        // also routes the `/{id}` + `/{id}/send` subpaths. Admin authz is the notification
        // service's job (it resolves the audience via profile's service-JWT'd internal read).
        prefix: "/admin/broadcasts",
        suffix: None,
        upstream: Upstream::Notification,
        tier: Tier::Api,
    },
    Rule {
        // Broadcast audience recipient counts (composer picker). Notification owns it.
        prefix: "/admin/audience-counts",
        suffix: None,
        upstream: Upstream::Notification,
        tier: Tier::Api,
    },
    Rule {
        // Admin automation rules (CRUD). The single prefix also routes the `/rules/{id}`
        // subpath. Notification hosts the rule store (the canonical action is "notify").
        prefix: "/admin/automation",
        suffix: None,
        upstream: Upstream::Notification,
        tier: Tier::Api,
    },
    Rule {
        // Admin revenue-trend report (analytics). Payment owns the money series. A more
        // specific prefix than a hypothetical `/admin/reports` so it routes to its own service.
        prefix: "/admin/reports/revenue",
        suffix: None,
        upstream: Upstream::Payment,
        tier: Tier::Api,
    },
    Rule {
        // Admin booking analytics report (volume + utilization + retention). Booking owns it.
        prefix: "/admin/reports/bookings",
        suffix: None,
        upstream: Upstream::Booking,
        tier: Tier::Api,
    },
    Rule {
        // Per-customer booking counts (admin customers page aggregates). Booking owns it. A
        // distinct prefix from `/admin/reports/bookings` (which it does NOT match).
        prefix: "/admin/reports/customer-bookings",
        suffix: None,
        upstream: Upstream::Booking,
        tier: Tier::Api,
    },
    Rule {
        // Per-customer total spend (admin customers page aggregates). Payment owns the money.
        prefix: "/admin/reports/customer-spend",
        suffix: None,
        upstream: Upstream::Payment,
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
        // More specific than `/otp/` (longest-prefix wins) so verify gets its OWN rate-limit
        // bucket — challenge/request churn on a shared per-IP (NAT) window must not starve it.
        prefix: "/otp/verify",
        suffix: None,
        upstream: Upstream::Otp,
        tier: Tier::OtpVerify,
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
        // Customer-facing active service catalog (booking owns it) — the mobile booking flow lists
        // these and sends the chosen service_id; admin pricing lives under /admin/pricing/services.
        prefix: "/services",
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
        // Customer-readable guard MINI-profile (name + experience) for the live-tracking map.
        // profile owns guard_profiles; the IDOR + approval gate is the profile service's job.
        // Token-gated (NOT in PUBLIC_PATHS) — the gate needs AuthUser. `/public` is the segment
        // after the `{id}`, so it can't collide with `/location`·`/history` (presence) or
        // `/ratings` (rating).
        prefix: "/guards/",
        suffix: Some("/public"),
        upstream: Upstream::Profile,
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
    Rule {
        // EXTERNAL OSRM routing proxy: `/v1/osrm/<rest>` → `{OSRM_PRIMARY_URL}/<rest>`. The
        // `/osrm` segment is additionally stripped from `forward_path` in `resolve` (see the
        // strip below), so `/osrm/route/v1/driving/{coords}` forwards as `/route/v1/driving/
        // {coords}`. Token-gated (NOT in PUBLIC_PATHS) — the gateway auths the caller before
        // forwarding to OSRM (OSRM needs no auth). Api tier (rate-limited). The mirror-retry
        // failover is the handler's job (`proxy::forward_osrm`), not a routing concern.
        prefix: "/osrm/",
        suffix: None,
        upstream: Upstream::Osrm,
        tier: Tier::Api,
    },
];

/// Exact public (token-not-required) resource paths, post-`/v1` strip. Everything
/// else under a known prefix is PROTECTED (token validated at the edge).
const PUBLIC_PATHS: &[&str] = &[
    "/auth/login",
    "/auth/refresh",
    // Registration is unauthenticated at the HTTP layer — it carries a single-use
    // `phone_verified_token` in the BODY (consumed internally), not an access token. Without
    // this, the edge access-token validator rejects every register attempt (401) and new-user
    // onboarding cannot complete through the gateway.
    "/auth/register",
    // Role switch during onboarding ("back → pick another role"): authenticated by the still-valid
    // `profile_token` from the prior register (Bearer), NOT an access token — identity validates it
    // internally. Like `/auth/register`, the edge access-token validator can't decode it, so it must
    // be edge-public.
    "/auth/register/reissue",
    // Initial profile submission is DUAL-AUTH: the client presents a purpose-scoped
    // `profile_token` (not an access token) as Bearer, which the profile service validates
    // itself (or an `AuthUser` for later updates). The edge access-token validator cannot
    // decode a purpose token, so these must be edge-public; profile enforces auth internally.
    "/profile/guard",
    "/profile/customer",
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

/// The body-cap carve-out for a (post-`/v1`-strip) resource path. Kept SEPARATE from the
/// routing [`RULES`] (which stay byte-for-byte unchanged) so cap policy and routing policy
/// don't entangle — and so this can be SEGMENT-BOUNDARY precise where a plain prefix rule
/// could not: a near-miss like `/attachmentsx` or `/bookings/x/progress-reportsx` keeps the
/// 1 MiB default. The upload routes split by cap:
///   - `POST /attachments`                  — chat image attachment → [`BodyCap::Chat`] (30 MiB)
///   - `/bookings/{id}/progress-reports`    — guard hourly check-in photo → [`BodyCap::Large`] (12 MiB)
///   - `/profile/guard/{id}/documents`·`/avatar` — credential image / avatar → [`BodyCap::Large`]
///
/// Method-agnostic (the edge resolves on path only): the sibling GET on each path carries no
/// request body, so the larger cap is irrelevant to it; and both backends re-validate the
/// upload (own `DefaultBodyLimit` + magic-byte/size check + IDOR), so a larger gateway buffer
/// bypasses no backend protection. Each cap is still bounded (≤ 30 MiB for chat, ≤ 12 MiB for the
/// single-image routes), and per-IP rate limiting (edge + gateway) bounds concurrent large uploads
/// — peak buffered memory is `≤ 30 MiB × in-flight-large-uploads`, not unbounded.
///
/// NOTE (layer asymmetry, safe direction): this matches a touch WIDER than staging nginx —
/// deeper subpaths (`/attachments/{id}`, `/bookings/{id}/progress-reports/{n}`) get `Large`
/// here, while `nginx.staging.conf` carves only the exact upload paths (downloads/deep
/// subpaths fall to its 2m default). nginx being stricter can never widen the edge; but if a
/// future slice adds a REAL deep upload subpath, widen the nginx location to match.
fn body_cap_for(stripped: &str) -> BodyCap {
    // `POST /attachments` (exact, or a trailing-slash variant) — NOT `/attachmentsx`. The chat
    // image attachment gets the WIDER 30 MiB cap (a full-res phone photo overflows 12 MiB).
    if stripped == "/attachments" || stripped.starts_with("/attachments/") {
        return BodyCap::Chat;
    }
    // `/bookings/{id}/progress-reports`: exactly one non-empty `{id}` segment, then the
    // `progress-reports` segment at a boundary (so `…/progress-reportsx` does NOT match).
    if let Some(rest) = stripped.strip_prefix("/bookings/") {
        if let Some((id, tail)) = rest.split_once('/') {
            if !id.is_empty()
                && (tail == "progress-reports" || tail.starts_with("progress-reports/"))
            {
                return BodyCap::Large;
            }
        }
    }
    // `/profile/guard/{user_id}/documents` (credential image) and `…/avatar` (profile picture):
    // one non-empty `{user_id}` segment, then the segment at a boundary (so `…/documentsx` /
    // `…/avatarx` do NOT match).
    if let Some(rest) = stripped.strip_prefix("/profile/guard/") {
        if let Some((id, tail)) = rest.split_once('/') {
            if !id.is_empty()
                && (tail == "documents"
                    || tail.starts_with("documents/")
                    || tail == "avatar"
                    || tail.starts_with("avatar/"))
            {
                return BodyCap::Large;
            }
        }
    }
    BodyCap::Default
}

/// `true` for `/profile/guard/{user_id}/documents` (one non-empty `{user_id}` segment, then
/// `documents` at a boundary). Edge-PUBLIC for the SAME reason as the `/profile/guard` submit
/// (see PUBLIC_PATHS): the registration upload presents a purpose-scoped `guard_doc_upload` Bearer
/// (NOT an access token) that the edge cannot decode, and the post-approval path an access token —
/// BOTH are validated by the profile service (`GuardDocWriter` / `AuthUser`, own-only). So a
/// no-/invalid-credential request still gets the service's 401/403; it is NOT anonymously open.
/// The Large body cap (above) + the edge rate-limit still apply.
fn is_guard_documents_path(stripped: &str) -> bool {
    if let Some(rest) = stripped.strip_prefix("/profile/guard/") {
        if let Some((id, tail)) = rest.split_once('/') {
            return !id.is_empty() && (tail == "documents" || tail.starts_with("documents/"));
        }
    }
    false
}

/// The path to forward to `upstream`, given the `/v1`-stripped resource path. For every
/// upstream this is the stripped path verbatim; the EXTERNAL [`Upstream::Osrm`] proxy
/// additionally removes the leading `/osrm` segment so `/osrm/route/v1/driving/{coords}`
/// forwards to the OSRM base as `/route/v1/driving/{coords}`. A bare `/osrm` (the `/osrm/`
/// rule can't actually match it — there is no trailing segment — but be total anyway) maps
/// to `/`. Pure (no I/O).
fn forward_path_for(upstream: Upstream, stripped: &str) -> String {
    if upstream == Upstream::Osrm {
        // `stripped` matched the `/osrm/` rule, so it always starts with `/osrm/`; strip the
        // segment, keeping the remainder's leading slash (so the OSRM base joins cleanly).
        if let Some(rest) = stripped.strip_prefix("/osrm") {
            // `rest` keeps its own leading '/' (e.g. "/route/v1/driving/...").
            return if rest.is_empty() {
                "/".to_string()
            } else {
                rest.to_string()
            };
        }
    }
    stripped.to_string()
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
///   5. Classify public vs protected via [`PUBLIC_PATHS`]; attach the per-route body cap
///      ([`body_cap_for`], a carve-out for the two upload routes).
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
            // The EXTERNAL OSRM upstream additionally strips the leading `/osrm` segment so
            // `/osrm/route/v1/driving/{coords}` forwards to the OSRM base as `/route/v1/
            // driving/{coords}`. Every other upstream forwards the bare `/v1`-stripped path.
            forward_path: forward_path_for(rule.upstream, stripped),
            // Edge-public if an exact public path OR the guard documents route (dual-auth like the
            // `/profile/guard` submit — the profile service validates the purpose/access token).
            public: PUBLIC_PATHS.contains(&stripped) || is_guard_documents_path(stripped),
            tier: rule.tier,
            body_cap: body_cap_for(stripped),
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
                ..
            } => (upstream, forward_path, public, tier),
            other => panic!("expected Proxy, got {other:?}"),
        }
    }

    /// The body cap of a resolved Proxy decision (the carve-out tests assert on this).
    fn body_cap(d: RouteDecision) -> BodyCap {
        match d {
            RouteDecision::Proxy { body_cap, .. } => body_cap,
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
    fn register_and_initial_profile_submission_are_public() {
        // Registration carries a phone_verified_token in the body (no access token); initial
        // profile submission carries a purpose-scoped profile_token the profile service validates
        // itself. Both MUST be edge-public or onboarding is rejected (401) at the gateway.
        for path in [
            "/v1/auth/register",
            "/v1/auth/register/reissue",
            "/v1/profile/guard",
            "/v1/profile/customer",
        ] {
            let (_, _, public, _) = proxy(resolve(path));
            assert!(
                public,
                "{path} must be public at the edge (dual-auth onboarding)"
            );
        }
        // …but the authenticated profile read stays protected.
        let (_, _, public, _) = proxy(resolve("/v1/profile/me"));
        assert!(!public, "/profile/me requires a token");
    }

    #[test]
    fn auth_revoke_all_is_protected() {
        // Self-serve "sign out everywhere" — under /auth/ → identity, token-required (NOT public).
        let (up, fwd, public, tier) = proxy(resolve("/v1/auth/revoke-all"));
        assert_eq!(up, Upstream::Identity);
        assert_eq!(fwd, "/auth/revoke-all");
        assert!(!public, "/auth/revoke-all requires a token");
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
        // challenge + request share the SMS-cost Otp tier...
        for p in ["/v1/otp/request", "/v1/otp/challenge"] {
            let (up, fwd, public, tier) = proxy(resolve(p));
            assert_eq!(up, Upstream::Otp, "{p}");
            assert_eq!(fwd, p.strip_prefix("/v1").unwrap(), "{p}");
            assert!(public, "{p}");
            assert_eq!(tier, Tier::Otp, "{p}");
        }
    }

    #[test]
    fn otp_verify_gets_its_own_tier() {
        // ...but verify is split onto its own tier (longest-prefix wins over `/otp/`) so
        // request/challenge churn on a shared per-IP bucket can't starve a real verification.
        let (up, fwd, public, tier) = proxy(resolve("/v1/otp/verify"));
        assert_eq!(up, Upstream::Otp);
        assert_eq!(fwd, "/otp/verify");
        assert!(public);
        assert_eq!(tier, Tier::OtpVerify);
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
    fn admin_recruitment_routes_to_profile() {
        for p in [
            "/v1/admin/recruitment/candidates",
            "/v1/admin/recruitment/candidates/abc/stage",
        ] {
            let (up, fwd, public, tier) = proxy(resolve(p));
            assert_eq!(up, Upstream::Profile, "{p}");
            assert_eq!(fwd, p.strip_prefix("/v1").unwrap());
            assert!(!public, "{p} requires a token");
            assert_eq!(tier, Tier::Api);
        }
    }

    #[test]
    fn admin_documents_route_to_profile() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/admin/documents/expiring"));
        assert_eq!(up, Upstream::Profile);
        assert_eq!(fwd, "/admin/documents/expiring");
        assert!(!public, "admin routes are edge-protected");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn admin_access_audit_routes_to_profile() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/admin/access-audit"));
        assert_eq!(up, Upstream::Profile);
        assert_eq!(fwd, "/admin/access-audit");
        assert!(!public, "admin routes are edge-protected");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn admin_customer_profiles_routes_to_profile() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/admin/customer-profiles"));
        assert_eq!(up, Upstream::Profile);
        assert_eq!(fwd, "/admin/customer-profiles");
        assert!(!public, "admin routes are edge-protected");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn customer_services_catalog_routes_to_booking() {
        // Customer-facing catalog list (the mobile booking flow) → booking, edge-protected.
        let (up, fwd, public, tier) = proxy(resolve("/v1/services"));
        assert_eq!(up, Upstream::Booking);
        assert_eq!(fwd, "/services");
        assert!(!public, "services list requires a token");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn admin_bookings_routes_to_booking() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/admin/bookings"));
        assert_eq!(up, Upstream::Booking);
        assert_eq!(fwd, "/admin/bookings");
        assert!(!public, "admin routes are edge-protected");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn admin_conversations_routes_to_chat() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/admin/conversations"));
        assert_eq!(up, Upstream::Chat);
        assert_eq!(fwd, "/admin/conversations");
        assert!(!public, "admin routes are edge-protected");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn admin_broadcasts_route_to_notification() {
        for p in [
            "/v1/admin/broadcasts",
            "/v1/admin/broadcasts/abc-123",
            "/v1/admin/broadcasts/abc/send",
        ] {
            let (up, fwd, public, tier) = proxy(resolve(p));
            assert_eq!(up, Upstream::Notification, "{p}");
            assert_eq!(fwd, p.strip_prefix("/v1").unwrap());
            assert!(!public, "{p} requires a token");
            assert_eq!(tier, Tier::Api);
        }
    }

    #[test]
    fn admin_audience_counts_routes_to_notification() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/admin/audience-counts"));
        assert_eq!(up, Upstream::Notification);
        assert_eq!(fwd, "/admin/audience-counts");
        assert!(!public, "admin routes are edge-protected");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn admin_automation_routes_to_notification() {
        for p in [
            "/v1/admin/automation/rules",
            "/v1/admin/automation/rules/abc",
        ] {
            let (up, fwd, public, tier) = proxy(resolve(p));
            assert_eq!(up, Upstream::Notification, "{p}");
            assert_eq!(fwd, p.strip_prefix("/v1").unwrap());
            assert!(!public, "{p} requires a token");
            assert_eq!(tier, Tier::Api);
        }
    }

    #[test]
    fn admin_reports_split_by_owning_service() {
        // Revenue analytics → payment; booking analytics → booking. Distinct prefixes, each
        // edge-protected, Api tier.
        let (up, fwd, public, tier) = proxy(resolve("/v1/admin/reports/revenue"));
        assert_eq!(up, Upstream::Payment);
        assert_eq!(fwd, "/admin/reports/revenue");
        assert!(!public, "admin routes are edge-protected");
        assert_eq!(tier, Tier::Api);

        let (up2, fwd2, public2, _) = proxy(resolve("/v1/admin/reports/bookings"));
        assert_eq!(up2, Upstream::Booking);
        assert_eq!(fwd2, "/admin/reports/bookings");
        assert!(!public2);

        // Per-customer aggregates (admin customers page) — distinct prefixes, each to its owner.
        let (up3, fwd3, public3, _) = proxy(resolve("/v1/admin/reports/customer-bookings"));
        assert_eq!(up3, Upstream::Booking);
        assert_eq!(fwd3, "/admin/reports/customer-bookings");
        assert!(!public3);

        let (up4, fwd4, _, _) = proxy(resolve("/v1/admin/reports/customer-spend"));
        assert_eq!(up4, Upstream::Payment);
        assert_eq!(fwd4, "/admin/reports/customer-spend");
    }

    #[test]
    fn admin_calls_routes_to_calling() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/admin/calls"));
        assert_eq!(up, Upstream::Calling);
        assert_eq!(fwd, "/admin/calls");
        assert!(!public, "admin routes are edge-protected");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn admin_pricing_routes_to_booking() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/admin/pricing/services"));
        assert_eq!(up, Upstream::Booking);
        assert_eq!(fwd, "/admin/pricing/services");
        assert!(!public, "admin routes are edge-protected");
        assert_eq!(tier, Tier::Api);
        // subpath (/{id}) routes via the same prefix.
        let (up2, fwd2, _, _) = proxy(resolve("/v1/admin/pricing/services/abc"));
        assert_eq!(up2, Upstream::Booking);
        assert_eq!(fwd2, "/admin/pricing/services/abc");
    }

    #[test]
    fn admin_payments_routes_to_payment() {
        let (up, fwd, public, tier) = proxy(resolve("/v1/admin/payments"));
        assert_eq!(up, Upstream::Payment);
        assert_eq!(fwd, "/admin/payments");
        assert!(!public, "admin routes are edge-protected");
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn admin_bookings_assign_subpath_routes_to_booking() {
        // The single `/admin/bookings` prefix rule must also route the assign subpath, and it
        // must NOT collide with the `/bookings` rule (different prefix).
        let (up, fwd, _, _) = proxy(resolve("/v1/admin/bookings/abc/assign"));
        assert_eq!(up, Upstream::Booking);
        assert_eq!(fwd, "/admin/bookings/abc/assign");
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
        assert_eq!(Upstream::Osrm.as_str(), "osrm");
    }

    // ----- OSRM external routing proxy -----

    #[test]
    fn osrm_route_forwards_with_osrm_segment_stripped_and_is_protected() {
        // The whole point of the slice: `/v1/osrm/route/v1/driving/{coords}` → Osrm upstream,
        // forward_path has BOTH `/v1` and the `/osrm` segment stripped → `/route/v1/driving/...`.
        let (up, fwd, public, tier) =
            proxy(resolve("/v1/osrm/route/v1/driving/100.5,13.7;100.6,13.8"));
        assert_eq!(up, Upstream::Osrm);
        assert_eq!(fwd, "/route/v1/driving/100.5,13.7;100.6,13.8");
        assert!(
            !public,
            "/osrm proxy requires a token (NOT a public open proxy)"
        );
        assert_eq!(tier, Tier::Api);
    }

    #[test]
    fn osrm_subpaths_strip_only_the_leading_osrm_segment() {
        // A deeper subpath keeps everything after `/osrm`; an inner `osrm` token in the path is
        // NOT stripped (only the leading segment is).
        let (up, fwd, _, _) = proxy(resolve("/v1/osrm/table/v1/driving/100.5,13.7"));
        assert_eq!(up, Upstream::Osrm);
        assert_eq!(fwd, "/table/v1/driving/100.5,13.7");
        // `osrm` appearing again as a later segment must be preserved verbatim.
        let (_, fwd2, _, _) = proxy(resolve("/v1/osrm/route/osrm/x"));
        assert_eq!(fwd2, "/route/osrm/x");
    }

    #[test]
    fn osrm_bare_collection_is_not_found() {
        // The `/osrm/` rule needs a trailing segment; bare `/osrm` (no slash) matches nothing.
        assert_eq!(resolve("/v1/osrm"), RouteDecision::NotFound);
    }

    #[test]
    fn osrm_internal_smuggle_is_blocked() {
        // The /internal block must hold for the external proxy too — never let an `/internal`
        // segment (or encoded separator) ride the OSRM passthrough.
        assert_eq!(resolve("/v1/osrm/internal/x"), RouteDecision::Block);
        assert_eq!(resolve("/v1/osrm/route%2finternal"), RouteDecision::Block);
    }

    #[test]
    fn forward_path_for_only_strips_osrm_for_osrm_upstream() {
        // Pure helper: only the Osrm upstream strips `/osrm`; every other upstream forwards the
        // stripped path verbatim (a path that happens to start with `/osrm` stays intact).
        assert_eq!(
            forward_path_for(Upstream::Osrm, "/osrm/route/v1"),
            "/route/v1"
        );
        assert_eq!(forward_path_for(Upstream::Osrm, "/osrm"), "/");
        assert_eq!(
            forward_path_for(Upstream::Booking, "/osrm/route/v1"),
            "/osrm/route/v1",
            "non-OSRM upstreams never strip /osrm"
        );
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

    // ----- body-cap carve-out (the upload routes) -----

    #[test]
    fn carved_upload_routes_get_large_body_cap() {
        // The chat image attachment gets the WIDER 30 MiB cap (full-res phone photo).
        assert_eq!(
            body_cap(resolve("/v1/attachments")),
            BodyCap::Chat,
            "POST /attachments (chat image upload) → 30 MiB"
        );
        assert_eq!(
            body_cap(resolve("/v1/bookings/abc-123/progress-reports")),
            BodyCap::Large,
            "POST /bookings/{{id}}/progress-reports (guard check-in)"
        );
        // The attachment download shares the prefix — the wider cap is harmless (GET has no
        // body), and the routing is unchanged (still Chat).
        let d = resolve("/v1/attachments/abc-123");
        assert_eq!(body_cap(d.clone()), BodyCap::Chat);
        assert_eq!(proxy(d).0, Upstream::Chat);
        // Guard document upload — Large cap, routed to profile, token-gated.
        assert_eq!(
            body_cap(resolve("/v1/profile/guard/abc-123/documents")),
            BodyCap::Large,
            "POST /profile/guard/{{id}}/documents (guard credential image)"
        );
        // Guard avatar upload — same Large carve-out + routing + token gate.
        let av = resolve("/v1/profile/guard/abc-123/avatar");
        assert_eq!(
            body_cap(av.clone()),
            BodyCap::Large,
            "POST /profile/guard/{{id}}/avatar (guard profile picture)"
        );
        assert_eq!(proxy(av.clone()).0, Upstream::Profile);
        assert!(!proxy(av).2, "avatar upload requires a token (not public)");
        // Near-miss keeps the 1 MiB default.
        assert_eq!(
            body_cap(resolve("/v1/profile/guard/abc/avatarx")),
            BodyCap::Default,
            "avatar suffix not at a boundary"
        );
    }

    #[test]
    fn profile_guard_documents_is_edge_public_dual_auth_and_boundary_precise() {
        let d = resolve("/v1/profile/guard/abc-123/documents");
        let (up, fwd, public, _) = proxy(d.clone());
        assert_eq!(up, Upstream::Profile);
        assert_eq!(fwd, "/profile/guard/abc-123/documents");
        // Edge-PUBLIC (dual-auth, like /profile/guard submit): registration presents a
        // `guard_doc_upload` purpose token the edge can't decode; the profile service validates it
        // (or an access token) + enforces own-only. A no-token request still gets the service's 401.
        assert!(
            public,
            "guard documents is edge-public dual-auth (profile validates the purpose/access token)"
        );
        assert_eq!(body_cap(d), BodyCap::Large);
        // Boundary precision — near-misses are NOT public (and keep the 1 MiB default).
        let near = resolve("/v1/profile/guard/abc/documentsx");
        assert!(
            !proxy(near.clone()).2,
            "suffix not at a boundary → not public"
        );
        assert_eq!(body_cap(near), BodyCap::Default);
        assert!(
            !proxy(resolve("/v1/profile/guard//documents")).2,
            "empty {{user_id}} segment → not public"
        );
        // The avatar upload is NOT made public by this rule (no purpose token; access-token only).
        assert!(
            !proxy(resolve("/v1/profile/guard/abc-123/avatar")).2,
            "avatar stays edge-protected (access-token only)"
        );
        // The one-write profile submit stays public + default cap (unchanged).
        let submit = resolve("/v1/profile/guard");
        assert_eq!(body_cap(submit.clone()), BodyCap::Default);
        assert!(
            proxy(submit).2,
            "/profile/guard submit is still public (dual-auth)"
        );
    }

    #[test]
    fn carve_out_does_not_widen_near_miss_paths() {
        // DoD #1 adversarial set: every near-miss + the unrelated routes keep the 1 MiB
        // default. A `…x` suffix is a DIFFERENT segment, so it must NOT inherit Large.
        for p in [
            "/v1/attachmentsx",                        // different segment, not /attachments
            "/v1/bookings/abc/progress-reportsx",      // suffix not at a boundary
            "/v1/bookings/abc",                        // GET one booking
            "/v1/bookings",                            // collection
            "/v1/bookings/abc/cancel",                 // a different booking subpath
            "/v1/bookings//progress-reports",          // empty {id} segment
            "/v1/bookings/abc/extra/progress-reports", // two segments before the suffix
            "/v1/auth/login",
            "/v1/otp/request",
            "/v1/conversations/abc/messages",
            "/v1/payments/abc",
        ] {
            assert_eq!(
                body_cap(resolve(p)),
                BodyCap::Default,
                "{p} must keep the 1 MiB default cap"
            );
        }
    }

    #[test]
    fn carve_out_keeps_routing_unchanged_for_near_misses() {
        // `/attachmentsx` still routes to Chat (pre-existing prefix behaviour) — the carve-out
        // changed only the CAP function, never the RULES table, so routing is byte-identical.
        let (up, _, _, _) = proxy(resolve("/v1/attachmentsx"));
        assert_eq!(up, Upstream::Chat);
        // `/bookings/{id}/progress-reportsx` still routes to Booking via the plain prefix.
        let (up, fwd, _, _) = proxy(resolve("/v1/bookings/abc/progress-reportsx"));
        assert_eq!(up, Upstream::Booking);
        assert_eq!(fwd, "/bookings/abc/progress-reportsx");
    }

    #[test]
    fn ws_paths_never_reach_the_body_cap_proxy() {
        // The WS upgrade routes are handled by `crate::wsproxy` (axum routes them before the
        // catch-all), with their OWN 1 MiB frame cap. They are not in RULES, so `resolve`
        // returns NotFound — they can never pick up a Large REST body cap.
        for p in [
            "/v1/ws/chat",
            "/v1/ws/track",
            "/v1/ws/call",
            "/v1/ws/bookings/abc",
        ] {
            assert_eq!(resolve(p), RouteDecision::NotFound, "{p}");
        }
    }

    #[test]
    fn deeper_progress_reports_subpath_still_large() {
        // A hypothetical deeper subpath under the check-in resource stays Large (boundary
        // match), consistent with the routing suffix semantics elsewhere.
        assert_eq!(
            body_cap(resolve("/v1/bookings/abc/progress-reports/99")),
            BodyCap::Large
        );
    }

    #[test]
    fn chat_attachment_cap_is_30_mib_and_above_large() {
        // The chat attachment carve-out is 30 MiB — strictly wider than the 12 MiB single-image
        // cap (a full-res phone photo overflows 12 MiB) and the 1 MiB edge default.
        assert_eq!(BodyCap::CHAT_BYTES, 30 * 1024 * 1024);
        assert_eq!(BodyCap::Chat.bytes(), 30 * 1024 * 1024);
        assert!(
            BodyCap::Chat.bytes() > BodyCap::Large.bytes(),
            "chat attachment cap must exceed the single-image cap"
        );
        assert!(BodyCap::Large.bytes() > BodyCap::Default.bytes());
        // Stays BELOW the chat service's 200 MiB video contract on purpose (edge buffers an
        // image, not a video; the service re-validates per-kind).
        assert!(BodyCap::Chat.bytes() < 200 * 1024 * 1024);
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
    fn guards_id_public_routes_to_profile_protected() {
        // Customer-readable guard mini-profile → profile, token-required (IDOR gate needs AuthUser).
        let (up, fwd, public, tier) = proxy(resolve("/v1/guards/abc-123/public"));
        assert_eq!(up, Upstream::Profile);
        assert_eq!(fwd, "/guards/abc-123/public");
        assert!(!public, "/guards/{{id}}/public requires a token");
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
