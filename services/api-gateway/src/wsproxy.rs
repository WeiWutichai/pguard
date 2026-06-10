//! Generic edge WebSocket proxy — `/v1/ws/{chat,track,call}` → the owning service's
//! own WS endpoint (`/ws/chat` · `/ws/track` · `/ws/call`). The gateway's FIRST true
//! WS proxy: it terminates the client upgrade at the edge, dials the backend's WS, and
//! relays frames both ways until either side closes (Close frames propagate).
//!
//! Pipeline on upgrade (same edge gates as the bespoke `/v1/ws/bookings/{id}` hub):
//!   1. **Rate-limit** the upgrade (Api tier, per-IP, fail-open).
//!   2. **CSWSH gate** — a present-but-disallowed `Origin` is rejected (CORS doesn't
//!      cover WS handshakes).
//!   3. **Bearer-on-upgrade** auth via [`crate::auth::validate`] — jti + trv, token from
//!      the `Authorization` header or `access_token` cookie, NEVER the URL.
//!   4. **Concurrent-session cap** (global semaphore) — live relays are bounded, not
//!      just the upgrade rate.
//!   5. **Dial the backend** WS (`UpstreamTable` base URL, `http→ws`), forwarding the
//!      original `Authorization` + a minimized `access_token` cookie so the backend
//!      re-validates the same token itself (defense-in-depth — backends keep their own
//!      auth + mid-session re-auth and close on expiry/revoke; the proxy stays a
//!      transparent relay).
//!   6. **Upgrade** the client and relay frames until either side closes.
//!
//! The backend is dialed BEFORE the client upgrade so a down/rejecting backend still
//! gets a real HTTP status (502 / 401) instead of a connect-then-instant-close.
//! Route → upstream mapping is pure ([`crate::domain::wsproxy::WS_PROXY_ROUTES`]).
//!
//! Documented limits (deliberate for the current contracts):
//!   - **No subprotocol negotiation** — `Sec-WebSocket-Protocol` is neither echoed nor
//!     forwarded; no pguard WS contract uses subprotocols.
//!   - **Plaintext upstreams only** — the WS client has no TLS backend compiled in;
//!     `https://` upstream URLs are refused at the pure layer (502, loud log).
//!   - **No per-frame rate limiting** — the relay is transparent; message-rate policy
//!     stays with the owning service (presence caps 1/s; chat/calling own theirs).
//!   - **Global concurrent-session cap** (`WS_PROXY_MAX_CONNECTIONS`, default 4096) on
//!     top of the per-IP upgrade rate limit; a per-user cap is a tracked follow-up.

use std::net::SocketAddr;
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use axum::extract::ws::{CloseFrame, Message, WebSocket, WebSocketUpgrade};
use axum::extract::{ConnectInfo, State};
use axum::http::{header, HeaderMap, HeaderValue, Method, StatusCode};
use axum::response::Response;
use futures::{SinkExt, StreamExt};
use tokio::net::TcpStream;
use tokio::sync::Semaphore;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode;
use tokio_tungstenite::tungstenite::protocol::CloseFrame as TCloseFrame;
use tokio_tungstenite::tungstenite::{Error as TError, Message as TMsg};
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

use crate::domain::ratelimit::RateDecision;
use crate::domain::routing::Tier;
use crate::domain::wsproxy::{backend_ws_url, WS_PROXY_ROUTES};
use crate::handler::{auth_err, err};
use crate::ratelimit;
use crate::state::AppState;

/// Per-frame size cap on the CLIENT side of the relay — same 1 MiB edge policy as the
/// REST body cap ([`crate::proxy::MAX_BODY_BYTES`]). Chat/track/call frames are small
/// JSON; an oversized client frame fails the read and tears the session down. The
/// backend side is trusted and keeps the library defaults.
const MAX_CLIENT_FRAME_BYTES: usize = crate::proxy::MAX_BODY_BYTES;

/// Upper bound for one relayed frame to be accepted by the receiving peer. A peer that
/// stops draining its socket for this long gets the session torn down (the relay holds
/// only one frame in flight, so a stuck send would otherwise hang the relay forever).
const RELAY_SEND_TIMEOUT: Duration = Duration::from_secs(30);

/// Default global cap on concurrent proxied WS sessions (each holds one client and one
/// backend socket). Override with `WS_PROXY_MAX_CONNECTIONS`.
const DEFAULT_MAX_CONNECTIONS: usize = 4096;

/// Global concurrent-session permits, sized once from env on first use.
static WS_PERMITS: OnceLock<Arc<Semaphore>> = OnceLock::new();

fn ws_permits() -> &'static Arc<Semaphore> {
    WS_PERMITS.get_or_init(|| {
        let cap = std::env::var("WS_PROXY_MAX_CONNECTIONS")
            .ok()
            .and_then(|v| v.parse::<usize>().ok())
            .filter(|&n| n > 0)
            .unwrap_or(DEFAULT_MAX_CONNECTIONS);
        Arc::new(Semaphore::new(cap))
    })
}

/// `GET /v1/ws/chat` → chat `/ws/chat`.
pub async fn ws_chat(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Response {
    proxy_upgrade(state, peer, headers, ws, "/v1/ws/chat").await
}

/// `GET /v1/ws/track` → presence `/ws/track`.
pub async fn ws_track(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Response {
    proxy_upgrade(state, peer, headers, ws, "/v1/ws/track").await
}

/// `GET /v1/ws/call` → calling `/ws/call`.
pub async fn ws_call(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Response {
    proxy_upgrade(state, peer, headers, ws, "/v1/ws/call").await
}

/// The shared edge pipeline (rate-limit → CSWSH gate → auth → backend dial → upgrade).
/// `public_path` keys into [`WS_PROXY_ROUTES`] — the pure table stays the single source
/// of truth for which upstream/backend path each edge WS path proxies to.
#[tracing::instrument(skip_all, fields(ws_path = public_path))]
async fn proxy_upgrade(
    state: AppState,
    peer: SocketAddr,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
    public_path: &'static str,
) -> Response {
    let Some(&(_, upstream, backend_path)) =
        WS_PROXY_ROUTES.iter().find(|(p, _, _)| *p == public_path)
    else {
        // Unreachable: every registered route is in the table (pinned by a domain test).
        tracing::error!(
            ws_path = public_path,
            "WS proxy route not in WS_PROXY_ROUTES"
        );
        return err(StatusCode::INTERNAL_SERVER_ERROR, "Misconfigured route");
    };

    // 1) Rate-limit the upgrade (Api tier; fail-open on Redis error) — as ws_bookings.
    let ip = ratelimit::client_ip(&headers, peer);
    {
        let mut redis = state.redis_conn.clone();
        if let RateDecision::Deny { retry_after_secs } =
            ratelimit::check(&mut redis, &state.limits, Tier::Api, &ip).await
        {
            let mut resp = err(StatusCode::TOO_MANY_REQUESTS, "Rate limit exceeded");
            if let Ok(v) = HeaderValue::from_str(&retry_after_secs.to_string()) {
                resp.headers_mut().insert("retry-after", v);
            }
            return resp;
        }
    }

    // 2) CSWSH gate: reject a present-but-disallowed Origin (browser cookie clients).
    // (`err`, not raw AppError — every gateway-originated response wears the uniform
    // ApiResponse envelope, same as the REST edge.)
    let origin = headers.get(header::ORIGIN).and_then(|v| v.to_str().ok());
    if !crate::domain::ws::origin_allowed(origin, &state.allowed_origins) {
        return err(StatusCode::FORBIDDEN, "Origin not allowed");
    }

    // 3) Bearer-on-upgrade auth at the edge (jti/trv parity with every /v1 route; the
    // GET handshake is not state-changing so the cookie-CSRF rule doesn't apply).
    {
        let mut redis = state.redis_conn.clone();
        if let Err(e) =
            crate::auth::validate(&headers, &Method::GET, &state.jwt_config, &mut redis).await
        {
            return auth_err(e);
        }
    }

    // 4) Concurrent-session cap. The per-IP limiter above bounds upgrade RATE; this
    // bounds the number of LIVE relays (each holds a gateway↔backend socket pair), so
    // an authenticated client can't exhaust file descriptors by accumulating sessions.
    // Checked after auth so anonymous floods can't consume permits. (A per-user cap is
    // a tracked follow-up.)
    let Ok(permit) = ws_permits().clone().try_acquire_owned() else {
        tracing::warn!(ws_path = public_path, "WS proxy at connection capacity");
        return err(
            StatusCode::SERVICE_UNAVAILABLE,
            "Too many concurrent connections",
        );
    };

    // 5) Dial the backend WS, forwarding the caller's credentials for its own re-check.
    let Some(base) = state.routes.base_url(upstream) else {
        // Should never happen — UpstreamTable inserts every variant.
        tracing::error!(upstream = upstream.as_str(), "no base URL for upstream");
        return err(StatusCode::BAD_GATEWAY, "Upstream service unavailable");
    };
    let Some(url) = backend_ws_url(base, backend_path) else {
        tracing::error!(
            upstream = upstream.as_str(),
            base,
            "unsupported upstream URL scheme for a WS dial (plaintext http:// only)"
        );
        return err(StatusCode::BAD_GATEWAY, "Upstream service unavailable");
    };
    let mut backend_req = match url.as_str().into_client_request() {
        Ok(r) => r,
        Err(e) => {
            tracing::error!(upstream = upstream.as_str(), "bad backend WS URL: {e}");
            return err(StatusCode::BAD_GATEWAY, "Upstream service unavailable");
        }
    };
    // Deliberate ALLOWLIST: only the caller's credentials cross to the backend — no
    // client x-user-* (identity comes from the backend's own token validation), no
    // client trace context, no Sec-WebSocket-Protocol (no pguard WS contract uses
    // subprotocols; the proxy doesn't negotiate them).
    if let Some(v) = headers.get(header::AUTHORIZATION) {
        backend_req
            .headers_mut()
            .insert(header::AUTHORIZATION, v.clone());
    }
    // Cookie is minimized to the access_token — refresh/CSRF cookies stay scoped to
    // the identity service and never reach chat/presence/calling.
    if let Some(tok) = headers
        .get(header::COOKIE)
        .and_then(|v| v.to_str().ok())
        .and_then(|c| shared::auth::extract_cookie_value(c, shared::auth::ACCESS_TOKEN_COOKIE))
    {
        if let Ok(hv) =
            HeaderValue::from_str(&format!("{}={tok}", shared::auth::ACCESS_TOKEN_COOKIE))
        {
            backend_req.headers_mut().insert(header::COOKIE, hv);
        }
    }
    // Propagate the edge trace context so the backend's WS span joins THIS trace (the
    // client's own traceparent never reaches the backend — this is a fresh edge root).
    observability::inject_context(backend_req.headers_mut());

    let backend = match tokio_tungstenite::connect_async(backend_req).await {
        Ok((stream, _resp)) => stream,
        // The backend refused the upgrade with a real HTTP status — surface auth
        // verdicts (the token may have expired/revoked between our check and theirs),
        // map everything else to a generic 502.
        Err(TError::Http(resp)) => {
            let status = resp.status();
            tracing::warn!(upstream = upstream.as_str(), %status, "backend WS upgrade refused");
            return match status {
                StatusCode::UNAUTHORIZED => err(StatusCode::UNAUTHORIZED, "Unauthorized"),
                StatusCode::FORBIDDEN => err(StatusCode::FORBIDDEN, "Forbidden"),
                _ => err(StatusCode::BAD_GATEWAY, "Upstream service unavailable"),
            };
        }
        Err(e) => {
            tracing::warn!(upstream = upstream.as_str(), "backend WS unreachable: {e}");
            return err(StatusCode::BAD_GATEWAY, "Upstream service unavailable");
        }
    };

    // 6) Upgrade the client and relay. Client frames are size-capped at the edge; the
    // session permit travels with the relay and frees on disconnect.
    ws.max_message_size(MAX_CLIENT_FRAME_BYTES)
        .max_frame_size(MAX_CLIENT_FRAME_BYTES)
        .on_upgrade(move |client| async move {
            let _permit = permit;
            relay(client, backend).await;
        })
}

/// Relay frames between the client (axum) and backend (tungstenite) sockets until
/// either side closes or errors. Close frames propagate (code + reason preserved);
/// after the loop both sinks get a best-effort close so neither side is left hanging.
///
/// ONE frame in flight total (the `select!` couples the directions): awaiting each
/// `send` is the backpressure, and nothing is buffered beyond that frame. The cost is
/// head-of-line blocking across directions — a peer that stops reading stalls the
/// relay — so every forward is bounded by [`RELAY_SEND_TIMEOUT`]; a send that can't
/// complete within it tears the session down instead of leaking a hung relay.
async fn relay(client: WebSocket, backend: WebSocketStream<MaybeTlsStream<TcpStream>>) {
    let (mut c_sink, mut c_stream) = client.split();
    let (mut b_sink, mut b_stream) = backend.split();

    loop {
        tokio::select! {
            inbound = c_stream.next() => match inbound {
                Some(Ok(msg)) => {
                    let closing = matches!(msg, Message::Close(_));
                    if !timed_send(&mut b_sink, client_to_backend(msg)).await || closing {
                        break;
                    }
                }
                // Abrupt client drop / read error → tell the backend we're done.
                Some(Err(_)) | None => {
                    let _ = timed_send(&mut b_sink, TMsg::Close(None)).await;
                    break;
                }
            },
            outbound = b_stream.next() => match outbound {
                Some(Ok(msg)) => {
                    let closing = matches!(msg, TMsg::Close(_));
                    // `Frame` (raw, never produced in normal reads) converts to None.
                    if let Some(m) = backend_to_client(msg) {
                        if !timed_send(&mut c_sink, m).await {
                            break;
                        }
                    }
                    if closing {
                        break;
                    }
                }
                Some(Err(_)) | None => {
                    let _ = timed_send(&mut c_sink, Message::Close(None)).await;
                    break;
                }
            },
        }
    }

    // Best-effort close handshake on whichever side is still open (errors ignored —
    // a side that already closed just rejects the duplicate).
    let _ = b_sink.close().await;
    let _ = c_sink.close().await;
}

/// Send one frame with [`RELAY_SEND_TIMEOUT`]. `false` on error OR timeout — either
/// way the relay loop exits and both sides get closed.
async fn timed_send<S, M>(sink: &mut S, msg: M) -> bool
where
    S: futures::Sink<M> + Unpin,
{
    matches!(
        tokio::time::timeout(RELAY_SEND_TIMEOUT, sink.send(msg)).await,
        Ok(Ok(()))
    )
}

/// axum WS frame → tungstenite frame (client → backend direction).
fn client_to_backend(msg: Message) -> TMsg {
    match msg {
        Message::Text(t) => TMsg::Text(t.as_str().to_owned()),
        Message::Binary(b) => TMsg::Binary(b.to_vec()),
        Message::Ping(p) => TMsg::Ping(p.to_vec()),
        Message::Pong(p) => TMsg::Pong(p.to_vec()),
        Message::Close(frame) => TMsg::Close(frame.map(|f| TCloseFrame {
            code: CloseCode::from(f.code),
            reason: std::borrow::Cow::Owned(f.reason.as_str().to_owned()),
        })),
    }
}

/// tungstenite frame → axum WS frame (backend → client direction). `None` for the raw
/// `Frame` variant, which `read` never yields in normal (non-raw) operation.
fn backend_to_client(msg: TMsg) -> Option<Message> {
    match msg {
        TMsg::Text(t) => Some(Message::Text(t.into())),
        TMsg::Binary(b) => Some(Message::Binary(b.into())),
        TMsg::Ping(p) => Some(Message::Ping(p.into())),
        TMsg::Pong(p) => Some(Message::Pong(p.into())),
        TMsg::Close(frame) => Some(Message::Close(frame.map(|f| CloseFrame {
            code: u16::from(f.code),
            reason: f.reason.as_ref().into(),
        }))),
        TMsg::Frame(_) => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ----- pure frame-conversion round-trips (hermetic) -----

    #[test]
    fn text_and_binary_round_trip() {
        let t = client_to_backend(Message::Text("hello".into()));
        assert_eq!(t, TMsg::Text("hello".to_string()));
        assert_eq!(
            backend_to_client(t),
            Some(Message::Text("hello".into())),
            "text survives both directions"
        );

        let b = client_to_backend(Message::Binary(vec![1u8, 2, 3].into()));
        assert_eq!(b, TMsg::Binary(vec![1, 2, 3]));
        assert_eq!(
            backend_to_client(b),
            Some(Message::Binary(vec![1u8, 2, 3].into()))
        );
    }

    #[test]
    fn ping_pong_round_trip() {
        assert_eq!(
            client_to_backend(Message::Ping(vec![9u8].into())),
            TMsg::Ping(vec![9])
        );
        assert_eq!(
            backend_to_client(TMsg::Pong(vec![7u8])),
            Some(Message::Pong(vec![7u8].into()))
        );
    }

    #[test]
    fn close_frame_preserves_code_and_reason() {
        let ax = Message::Close(Some(CloseFrame {
            code: 4001,
            reason: "going away".into(),
        }));
        let tung = client_to_backend(ax);
        match &tung {
            TMsg::Close(Some(f)) => {
                assert_eq!(u16::from(f.code), 4001);
                assert_eq!(f.reason, "going away");
            }
            other => panic!("expected Close(Some), got {other:?}"),
        }
        match backend_to_client(tung) {
            Some(Message::Close(Some(f))) => {
                assert_eq!(f.code, 4001);
                assert_eq!(f.reason.as_str(), "going away");
            }
            other => panic!("expected Close(Some), got {other:?}"),
        }
    }

    #[test]
    fn bare_close_round_trips_as_none_frame() {
        assert_eq!(client_to_backend(Message::Close(None)), TMsg::Close(None));
        assert_eq!(
            backend_to_client(TMsg::Close(None)),
            Some(Message::Close(None))
        );
    }
}

#[cfg(test)]
mod e2e_tests {
    //! End-to-end WS proxy through the gateway against a stub chat backend, with REAL
    //! Redis for the edge jti/trv checks. Gated on `TEST_REDIS_URL`|`REDIS_CACHE_URL`
    //! so the hermetic `cargo test` skips it (same gating as the status-WS e2e). Run:
    //!   TEST_REDIS_URL=redis://localhost:6380 \
    //!     cargo test -p pguard-api-gateway -- wsproxy::e2e --nocapture
    use super::*;

    use std::time::Duration;

    use axum::routing::get as axget;
    use futures::{SinkExt, StreamExt};
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use tokio::sync::mpsc;
    use uuid::Uuid;

    use shared::auth::encode_jwt_with_key;
    use shared::config::JwtConfig;

    const SECRET: &str = "gateway-wsproxy-e2e-secret-at-least-64-characters-long-hs256-aaaa!!";

    fn redis_url() -> Option<String> {
        std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()
    }

    /// Stub chat backend: `GET /ws/chat` upgrades unconditionally, reports whether the
    /// gateway forwarded an `Authorization` header, echoes text frames as `echo:<text>`,
    /// initiates a server-side Close (code 4002) on `please-close`, and pushes lifecycle
    /// events (`handshake` / `close-received` / `ended`) into the test's channel.
    async fn spawn_stub_backend(events: mpsc::UnboundedSender<String>) -> String {
        #[derive(Clone)]
        struct Stub {
            events: mpsc::UnboundedSender<String>,
        }

        async fn ws_chat_stub(
            State(stub): State<Stub>,
            headers: HeaderMap,
            ws: WebSocketUpgrade,
        ) -> Response {
            let _ = stub.events.send("handshake".to_string());
            let has_auth = headers
                .get(header::AUTHORIZATION)
                .and_then(|v| v.to_str().ok())
                .is_some_and(|v| v.starts_with("Bearer "));
            ws.on_upgrade(move |mut socket| async move {
                let first = if has_auth {
                    "auth:present"
                } else {
                    "auth:absent"
                };
                if socket.send(Message::Text(first.into())).await.is_err() {
                    return;
                }
                while let Some(Ok(msg)) = socket.next().await {
                    match msg {
                        Message::Text(t) if t.as_str() == "please-close" => {
                            let _ = socket
                                .send(Message::Close(Some(CloseFrame {
                                    code: 4002,
                                    reason: "server says bye".into(),
                                })))
                                .await;
                            break;
                        }
                        Message::Text(t) => {
                            let frame = format!("echo:{}", t.as_str());
                            if socket.send(Message::Text(frame.into())).await.is_err() {
                                break;
                            }
                        }
                        // Echo binary unchanged (proves binary frames cross the relay).
                        Message::Binary(b) => {
                            if socket.send(Message::Binary(b)).await.is_err() {
                                break;
                            }
                        }
                        Message::Close(_) => {
                            let _ = stub.events.send("close-received".to_string());
                            break;
                        }
                        _ => {}
                    }
                }
                let _ = stub.events.send("ended".to_string());
            })
        }

        let app = axum::Router::new()
            .route("/ws/chat", axget(ws_chat_stub))
            .with_state(Stub { events });
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        format!("http://{addr}")
    }

    /// Boot the gateway's `/v1/ws/chat` proxy route over real Redis with the chat
    /// upstream pointed at the stub backend.
    async fn spawn_gateway(redis_url: &str, chat_url: &str) -> SocketAddr {
        let redis_conn = shared::redis_client::create_redis_client(redis_url)
            .unwrap()
            .get_multiplexed_tokio_connection()
            .await
            .unwrap();
        let jwt_config = JwtConfig {
            secret: SECRET.to_string(),
            expiry_minutes: 15,
            encoding_key: EncodingKey::from_secret(SECRET.as_bytes()),
            decoding_key: DecodingKey::from_secret(SECRET.as_bytes()),
        };
        let routes = crate::state::UpstreamTable::from_env()
            .with_override(crate::domain::routing::Upstream::Chat, chat_url);
        let state = AppState {
            http: reqwest::Client::new(),
            redis_conn,
            jwt_config,
            routes,
            limits: crate::domain::ratelimit::Limits {
                otp_per_min: 100_000,
                auth_per_sec: 100_000,
                api_per_sec: 100_000,
            },
            status_tx: tokio::sync::broadcast::channel(16).0,
            allowed_origins: std::sync::Arc::from(vec!["http://localhost:3000".to_string()]),
        };
        let app = axum::Router::new()
            .route("/v1/ws/chat", axget(ws_chat))
            .with_state(state);
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(
                listener,
                app.into_make_service_with_connect_info::<SocketAddr>(),
            )
            .await
            .unwrap();
        });
        addr
    }

    fn token() -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        encode_jwt_with_key(Uuid::new_v4(), "customer", 0, &ek, 15)
            .unwrap()
            .0
    }

    async fn connect(
        addr: SocketAddr,
        bearer: Option<&str>,
        origin: Option<&str>,
    ) -> Result<
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
        Option<StatusCode>,
    > {
        let mut req = format!("ws://{addr}/v1/ws/chat")
            .as_str()
            .into_client_request()
            .unwrap();
        if let Some(b) = bearer {
            req.headers_mut()
                .insert("authorization", format!("Bearer {b}").parse().unwrap());
        }
        if let Some(o) = origin {
            req.headers_mut().insert("origin", o.parse().unwrap());
        }
        match tokio_tungstenite::connect_async(req).await {
            Ok((stream, _)) => Ok(stream),
            Err(TError::Http(resp)) => Err(Some(resp.status())),
            Err(_) => Err(None),
        }
    }

    /// Next text frame (skipping ping/pong), with a timeout so a hang fails the test.
    async fn read_text(
        ws: &mut tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
    ) -> Option<String> {
        loop {
            match tokio::time::timeout(Duration::from_secs(5), ws.next()).await {
                Ok(Some(Ok(TMsg::Text(t)))) => return Some(t),
                Ok(Some(Ok(TMsg::Ping(_) | TMsg::Pong(_)))) => continue,
                _ => return None,
            }
        }
    }

    async fn next_event(rx: &mut mpsc::UnboundedReceiver<String>) -> Option<String> {
        tokio::time::timeout(Duration::from_secs(5), rx.recv())
            .await
            .ok()
            .flatten()
    }

    #[tokio::test]
    async fn wsproxy_e2e_auth_relay_and_close_propagation() {
        let Some(redis) = redis_url() else {
            eprintln!("SKIP: TEST_REDIS_URL/REDIS_CACHE_URL required");
            return;
        };
        let (events_tx, mut events) = mpsc::unbounded_channel();
        let backend_url = spawn_stub_backend(events_tx).await;
        let addr = spawn_gateway(&redis, &backend_url).await;

        // 1) No token → 401 at the edge, BEFORE any backend handshake.
        match connect(addr, None, None).await {
            Err(Some(status)) => assert_eq!(status, StatusCode::UNAUTHORIZED),
            other => panic!("unauthenticated upgrade must be 401, got {other:?}"),
        }

        // 2) Valid token but a disallowed browser Origin → 403 (CSWSH gate), still no
        // backend handshake.
        let tok = token();
        match connect(addr, Some(&tok), Some("http://evil.example.com")).await {
            Err(Some(status)) => assert_eq!(status, StatusCode::FORBIDDEN),
            other => panic!("cross-origin upgrade must be 403, got {other:?}"),
        }

        // 3) Valid token → relays. The FIRST backend handshake happens only now, which
        // proves (1) and (2) were rejected at the edge before reaching the backend.
        let mut ws = connect(addr, Some(&tok), None)
            .await
            .expect("authenticated upgrade should connect");
        assert_eq!(next_event(&mut events).await.as_deref(), Some("handshake"));
        assert_eq!(
            read_text(&mut ws).await.as_deref(),
            Some("auth:present"),
            "gateway must forward the Authorization header to the backend"
        );

        // Echo round-trip through the relay (client → gateway → backend → gateway → client).
        ws.send(TMsg::Text("hello".to_string())).await.unwrap();
        assert_eq!(read_text(&mut ws).await.as_deref(), Some("echo:hello"));

        // Binary frames cross the relay intact too.
        ws.send(TMsg::Binary(vec![0xde, 0xad, 0xbe, 0xef]))
            .await
            .unwrap();
        let mut got_binary = None;
        while let Ok(Some(Ok(msg))) = tokio::time::timeout(Duration::from_secs(5), ws.next()).await
        {
            if let TMsg::Binary(b) = msg {
                got_binary = Some(b);
                break;
            }
        }
        assert_eq!(
            got_binary.as_deref(),
            Some(&[0xde, 0xad, 0xbe, 0xef][..]),
            "binary frame must relay unchanged"
        );

        // 4) BACKEND-initiated close propagates to the client with code + reason.
        ws.send(TMsg::Text("please-close".to_string()))
            .await
            .unwrap();
        let mut saw_close = false;
        while let Ok(Some(Ok(msg))) = tokio::time::timeout(Duration::from_secs(5), ws.next()).await
        {
            if let TMsg::Close(frame) = msg {
                let f = frame.expect("close frame with code/reason");
                assert_eq!(u16::from(f.code), 4002);
                assert_eq!(f.reason, "server says bye");
                saw_close = true;
                break;
            }
        }
        assert!(saw_close, "backend Close must reach the client");
        assert_eq!(next_event(&mut events).await.as_deref(), Some("ended"));

        // 5) CLIENT-initiated close propagates to the backend.
        let mut ws2 = connect(addr, Some(&tok), None)
            .await
            .expect("second authenticated upgrade");
        assert_eq!(next_event(&mut events).await.as_deref(), Some("handshake"));
        assert_eq!(read_text(&mut ws2).await.as_deref(), Some("auth:present"));
        ws2.close(None).await.unwrap();
        assert_eq!(
            next_event(&mut events).await.as_deref(),
            Some("close-received"),
            "client Close must reach the backend session"
        );
        assert_eq!(next_event(&mut events).await.as_deref(), Some("ended"));
    }

    #[tokio::test]
    async fn wsproxy_e2e_backend_down_is_502() {
        let Some(redis) = redis_url() else {
            eprintln!("SKIP: TEST_REDIS_URL/REDIS_CACHE_URL required");
            return;
        };
        // Chat upstream pointed at a port nothing listens on → the pre-upgrade dial
        // fails and the client gets a real 502, not a connect-then-drop.
        let addr = spawn_gateway(&redis, "http://127.0.0.1:1").await;
        match connect(addr, Some(&token()), None).await {
            Err(Some(status)) => assert_eq!(status, StatusCode::BAD_GATEWAY),
            other => panic!("backend-down upgrade must be 502, got {other:?}"),
        }
    }
}
