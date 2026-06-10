//! PURE helpers for the generic edge WebSocket proxy — no axum / tungstenite / tokio here.
//!
//! The proxy exposes `/v1/ws/{chat,track,call}` at the edge and relays to the owning
//! service's own WS endpoint. This module holds the decisions: which edge path maps to
//! which (upstream, backend path) pair, and how an upstream's `http(s)://` base URL
//! becomes the `ws(s)://` handshake URL. The relay I/O lives in `crate::wsproxy`.
//!
//! NOT here: `/v1/ws/bookings/{id}` — that is the bespoke NATS-fed status hub
//! (`crate::ws`), terminated at the gateway, not proxied.

use super::routing::Upstream;

/// Edge WS proxy routes: public path → (upstream, backend WS path). The gateway
/// registers each public path explicitly (they match before the catch-all), so this
/// table is the single source of truth for both registration and tests.
pub const WS_PROXY_ROUTES: &[(&str, Upstream, &str)] = &[
    ("/v1/ws/chat", Upstream::Chat, "/ws/chat"),
    ("/v1/ws/track", Upstream::Presence, "/ws/track"),
    ("/v1/ws/call", Upstream::Calling, "/ws/call"),
];

/// Derive the backend WebSocket handshake URL from an upstream base URL (as resolved by
/// `UpstreamTable`, e.g. `http://chat:3010`) and the backend WS path (e.g. `/ws/chat`).
/// `http` → `ws`, `https` → `wss`; any other scheme is refused (`None`) — the proxy
/// must not dial a URL it doesn't understand.
pub fn backend_ws_url(base_url: &str, ws_path: &str) -> Option<String> {
    let rest = base_url
        .strip_prefix("http://")
        .map(|r| ("ws://", r))
        .or_else(|| base_url.strip_prefix("https://").map(|r| ("wss://", r)));
    let (scheme, host) = rest?;
    if host.is_empty() {
        return None;
    }
    Some(format!("{scheme}{host}{ws_path}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_every_edge_ws_path_to_its_upstream() {
        let lookup = |p: &str| {
            WS_PROXY_ROUTES
                .iter()
                .find(|(public, _, _)| *public == p)
                .map(|&(_, up, backend)| (up, backend))
        };
        assert_eq!(lookup("/v1/ws/chat"), Some((Upstream::Chat, "/ws/chat")));
        assert_eq!(
            lookup("/v1/ws/track"),
            Some((Upstream::Presence, "/ws/track"))
        );
        assert_eq!(lookup("/v1/ws/call"), Some((Upstream::Calling, "/ws/call")));
        // The bespoke status hub is NOT proxied through this table.
        assert_eq!(lookup("/v1/ws/bookings"), None);
        assert_eq!(WS_PROXY_ROUTES.len(), 3);
    }

    #[test]
    fn backend_url_swaps_scheme_only() {
        assert_eq!(
            backend_ws_url("http://chat:3010", "/ws/chat").as_deref(),
            Some("ws://chat:3010/ws/chat")
        );
        assert_eq!(
            backend_ws_url("https://presence.internal", "/ws/track").as_deref(),
            Some("wss://presence.internal/ws/track")
        );
    }

    #[test]
    fn backend_url_refuses_unknown_or_empty() {
        assert_eq!(backend_ws_url("ftp://chat:3010", "/ws/chat"), None);
        assert_eq!(backend_ws_url("chat:3010", "/ws/chat"), None);
        assert_eq!(backend_ws_url("http://", "/ws/chat"), None);
        assert_eq!(backend_ws_url("", "/ws/chat"), None);
    }
}
