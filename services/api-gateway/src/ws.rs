//! Booking-status WebSocket — terminated AT THE EDGE (gateway), reachable at
//! `GET /v1/ws/bookings/{id}`. Gives the mobile live-status screen a real push feed.
//!
//! Pipeline on upgrade (mirrors the edge HTTP pipeline + the calling service's WS auth):
//!   1. **Rate-limit** the upgrade (Api tier, per-IP, fail-open).
//!   2. **Bearer-on-upgrade** auth via [`crate::auth::validate`] — same jti/trv/CSRF checks
//!      as every `/v1` route. Token comes from the `Authorization` header (or `access_token`
//!      cookie), NEVER the URL query.
//!   3. **Participant-only**, delegated to booking's OWN `GET /bookings/{id}` called with the
//!      user's forwarded Bearer: booking's `403` is the gate, and the `200` body is the
//!      initial status snapshot. No service-JWT, no booking-schema coupling at the edge.
//!   4. **Upgrade** → push `booking_status` frames from the NATS hub, filtered to this booking.
//!
//! Live updates come from a single process-wide NATS subscription ([`run_status_hub`]) fanned
//! out over a broadcast channel — NOT polling. The frame matches the contract the mobile track
//! coded against: `{ "type":"booking_status", "booking_id", "status", "occurred_at", "guard_id"? }`.

use std::net::SocketAddr;
use std::time::Duration;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{ConnectInfo, Path, State};
use axum::http::{HeaderMap, HeaderValue, Method, StatusCode};
use axum::response::{IntoResponse, Response};
use futures::{SinkExt, StreamExt};
use jsonwebtoken::DecodingKey;
use tokio::sync::broadcast;
use uuid::Uuid;

use shared::auth::{authenticate_token, extract_cookie_value, ACCESS_TOKEN_COOKIE};
use shared::error::AppError;

use crate::domain::ratelimit::RateDecision;
use crate::domain::routing::{Tier, Upstream};
use crate::domain::ws::{parse_status_update, status_frame, StatusUpdate};
use crate::ratelimit;
use crate::state::AppState;

/// Re-validate the token mid-session this often (close the socket if expired/revoked).
const REAUTH_INTERVAL: Duration = Duration::from_secs(60);
/// Booking-status subject the hub subscribes to (the booking outbox relay publishes here).
const BOOKING_SUBJECT: &str = "pguard.events.booking.*";
/// Hub reconnect backoff on NATS connect/subscribe failure.
const HUB_RETRY: Duration = Duration::from_secs(2);

/// Background task: subscribe to `pguard.events.booking.*` once and fan every client-visible
/// status update out over `tx`. Reconnects forever (a NATS outage must not kill the gateway).
/// Spawned by `main`.
pub async fn run_status_hub(nats_url: String, tx: broadcast::Sender<StatusUpdate>) {
    loop {
        let client = match shared_events::connect(&nats_url).await {
            Ok(c) => c,
            Err(e) => {
                tracing::warn!("status-WS hub: NATS connect failed: {e}; retrying");
                tokio::time::sleep(HUB_RETRY).await;
                continue;
            }
        };
        let mut sub = match client.subscribe(BOOKING_SUBJECT.to_string()).await {
            Ok(s) => {
                tracing::info!(subject = BOOKING_SUBJECT, "status-WS hub subscribed");
                s
            }
            Err(e) => {
                tracing::warn!("status-WS hub: subscribe failed: {e}; retrying");
                tokio::time::sleep(HUB_RETRY).await;
                continue;
            }
        };
        while let Some(msg) = sub.next().await {
            // Verify the HMAC signature BEFORE fanning out — a forged booking event must not be
            // pushed to clients as a fake live-status frame. Fail-closed (mirrors the durable
            // consumers). The booking outbox relay publishes these signed via `publish_signed`.
            if !shared_events::verify_message(msg.headers.as_ref(), msg.payload.as_ref()) {
                observability::record_rejected_event("status-ws-hub");
                tracing::warn!(
                    "status-WS hub: dropping booking event with missing/invalid signature"
                );
                continue;
            }
            if let Some(update) = parse_status_update(msg.payload.as_ref()) {
                // A send error just means no client is currently connected — that's fine.
                let _ = tx.send(update);
            }
        }
        tracing::warn!("status-WS hub: subscription ended; reconnecting");
        tokio::time::sleep(HUB_RETRY).await;
    }
}

/// `GET /v1/ws/bookings/{id}` — see module docs.
#[tracing::instrument(skip_all, fields(booking_id = %id))]
pub async fn ws_bookings(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Path(id): Path<Uuid>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Response {
    // 1) Rate-limit the upgrade (Api tier; fail-open on Redis error).
    let ip = ratelimit::client_ip(&headers, peer);
    {
        let mut redis = state.redis_conn.clone();
        if let RateDecision::Deny { retry_after_secs } =
            ratelimit::check(&mut redis, &state.limits, Tier::Api, &ip).await
        {
            let mut resp = (StatusCode::TOO_MANY_REQUESTS, "Rate limit exceeded").into_response();
            if let Ok(v) = HeaderValue::from_str(&retry_after_secs.to_string()) {
                resp.headers_mut().insert("retry-after", v);
            }
            return resp;
        }
    }

    // 2) Cross-Site-WebSocket-Hijacking gate: CORS does NOT cover WS upgrades and the GET
    // handshake bypasses the CSRF check, so a browser page could otherwise open this socket on a
    // victim's cookie. Reject a present-but-disallowed Origin (mobile/Bearer clients send none).
    let origin = headers
        .get(axum::http::header::ORIGIN)
        .and_then(|v| v.to_str().ok());
    if !crate::domain::ws::origin_allowed(origin, &state.allowed_origins) {
        return AppError::Forbidden("Origin not allowed".to_string()).into_response();
    }

    // 3) Bearer-on-upgrade auth at the edge (jti/trv/CSRF parity with all /v1 routes).
    {
        let mut redis = state.redis_conn.clone();
        if let Err(e) =
            crate::auth::validate(&headers, &Method::GET, &state.jwt_config, &mut redis).await
        {
            return e.into_response();
        }
    }
    let Some(token) = token_from_headers(&headers) else {
        return AppError::Unauthorized("Missing authentication token".to_string()).into_response();
    };

    // 4) Subscribe to the live feed BEFORE reading the snapshot, so a transition published while
    // we fetch the snapshot is buffered by this receiver and replayed after it — no lost update
    // in the (snapshot-read, subscribe) window.
    let rx = state.status_tx.subscribe();

    // 5) Participant-only + initial snapshot (delegated to booking's own GET /bookings/{id}).
    let snapshot = match fetch_snapshot(&state, id, &token).await {
        Ok(s) => s,
        Err(resp) => return resp,
    };

    // 6) Upgrade → live session.
    let decoding_key = state.jwt_config.decoding_key.clone();
    let redis = state.redis_conn.clone();
    ws.on_upgrade(move |socket| session(socket, id, token, snapshot, rx, decoding_key, redis))
}

/// Authorize the caller as a participant AND fetch the current status, by calling booking's
/// user-facing `GET /bookings/{id}` with the caller's Bearer. Booking's own participant check
/// (`403` for non-participants) is the gate; on `200` the body gives the snapshot status.
async fn fetch_snapshot(state: &AppState, id: Uuid, token: &str) -> Result<StatusUpdate, Response> {
    let base = state.routes.base_url(Upstream::Booking).ok_or_else(|| {
        AppError::Internal("booking upstream not configured".to_string()).into_response()
    })?;
    let resp = state
        .http
        .get(format!("{base}/bookings/{id}"))
        .header(axum::http::header::AUTHORIZATION, format!("Bearer {token}"))
        .send()
        .await
        .map_err(|e| {
            tracing::warn!("status-WS: booking unreachable: {e}");
            AppError::Internal("booking service unavailable".to_string()).into_response()
        })?;

    match resp.status().as_u16() {
        200..=299 => {}
        401 => return Err(AppError::Unauthorized("Unauthorized".to_string()).into_response()),
        // Generic 403 — same as booking's non-participant response (no existence oracle).
        403 => {
            return Err(
                AppError::Forbidden("Not a participant in this booking".to_string())
                    .into_response(),
            )
        }
        404 => return Err(AppError::NotFound("Booking not found".to_string()).into_response()),
        _ => {
            return Err(AppError::Internal("booking status unavailable".to_string()).into_response())
        }
    }

    let text = resp
        .text()
        .await
        .map_err(|_| AppError::Internal("bad booking response".to_string()).into_response())?;
    let v: serde_json::Value = serde_json::from_str(&text)
        .map_err(|_| AppError::Internal("bad booking response".to_string()).into_response())?;
    let data = v.get("data").cloned().unwrap_or(v);
    let status = data
        .get("status")
        .and_then(|s| s.as_str())
        .unwrap_or("requested")
        .to_string();
    let guard_id = data
        .get("guard_id")
        .and_then(|g| g.as_str())
        .map(str::to_string);

    Ok(StatusUpdate {
        booking_id: id.to_string(),
        status,
        occurred_at: chrono::Utc::now().to_rfc3339(),
        guard_id,
    })
}

/// The live session: send the initial snapshot, then forward this booking's status updates as
/// they arrive over the broadcast hub. Periodically re-auth (close on expiry/revoke) + ping.
async fn session(
    socket: WebSocket,
    id: Uuid,
    token: String,
    snapshot: StatusUpdate,
    mut rx: broadcast::Receiver<StatusUpdate>,
    decoding_key: DecodingKey,
    redis: redis::aio::ConnectionManager,
) {
    let (mut sink, mut stream) = socket.split();
    let id_str = id.to_string();

    // Initial snapshot so the client has state immediately (covers a connect that lands
    // mid-flight; live transitions, including pending_completion via booking.completion_requested,
    // then arrive over the hub).
    let first = status_frame(
        &snapshot.booking_id,
        &snapshot.status,
        &snapshot.occurred_at,
        snapshot.guard_id.as_deref(),
    );
    if sink
        .send(Message::Text(first.to_string().into()))
        .await
        .is_err()
    {
        return;
    }

    let mut reauth = tokio::time::interval(REAUTH_INTERVAL);
    reauth.tick().await; // consume the immediate first tick

    loop {
        tokio::select! {
            recv = rx.recv() => {
                match recv {
                    // Only forward events for THIS booking (the connection's scope).
                    Ok(update) if update.booking_id == id_str => {
                        let f = status_frame(
                            &update.booking_id,
                            &update.status,
                            &update.occurred_at,
                            update.guard_id.as_deref(),
                        );
                        if sink.send(Message::Text(f.to_string().into())).await.is_err() {
                            break;
                        }
                    }
                    Ok(_) => {} // another booking's event — ignore
                    Err(broadcast::error::RecvError::Lagged(n)) => {
                        tracing::warn!(booking = %id_str, skipped = n, "status-WS lagged; client may REST-refresh");
                    }
                    Err(broadcast::error::RecvError::Closed) => break,
                }
            }
            client = stream.next() => {
                match client {
                    Some(Ok(Message::Close(_))) | None | Some(Err(_)) => break,
                    Some(Ok(_)) => {} // read-only feed: ignore inbound client frames
                }
            }
            _ = reauth.tick() => {
                if authenticate_token(&token, &decoding_key, &redis).await.is_err() {
                    tracing::info!(booking = %id_str, "status-WS token expired/revoked; closing");
                    let _ = sink.send(Message::Close(None)).await;
                    break;
                }
                if sink.send(Message::Ping(Vec::new().into())).await.is_err() {
                    break;
                }
            }
        }
    }
}

/// Token from the `Authorization: Bearer` header (mobile/API) or the `access_token` cookie
/// (web) — never the URL query (mirrors `shared::auth::AuthUser` + the calling WS).
fn token_from_headers(headers: &HeaderMap) -> Option<String> {
    if let Some(bearer) = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
    {
        return Some(bearer.to_string());
    }
    headers
        .get(axum::http::header::COOKIE)
        .and_then(|v| v.to_str().ok())
        .and_then(|c| extract_cookie_value(c, ACCESS_TOKEN_COOKIE).map(str::to_string))
}

#[cfg(test)]
mod e2e_tests {
    //! End-to-end booking-status WS through the gateway, against REAL NATS + Redis with a stub
    //! booking upstream. Gated on `NATS_URL` + (`TEST_REDIS_URL`|`REDIS_CACHE_URL`) so the
    //! hermetic `cargo test` skips it. Run:
    //!   NATS_URL=nats://localhost:4222 TEST_REDIS_URL=redis://localhost:6380 \
    //!     cargo test -p pguard-api-gateway -- ws_e2e --nocapture
    use super::*;

    use std::time::Duration;

    use axum::extract::Path as AxPath;
    use axum::routing::get as axget;
    use axum::Json;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use tokio_tungstenite::tungstenite::client::IntoClientRequest;

    use shared::auth::encode_jwt_with_key;
    use shared::config::JwtConfig;

    const SECRET: &str = "gateway-ws-e2e-secret-at-least-64-characters-long-hs256-aaaaaaaaaa!!";
    const PARTICIPANT_BOOKING: &str = "11111111-1111-1111-1111-111111111111";
    const OTHER_BOOKING: &str = "99999999-9999-9999-9999-999999999999";
    /// Event-signing key for the WS-hub tests (the hub verifies; the test publishes signed).
    const WS_TEST_KEY: &[u8] =
        b"api-gateway-ws-hub-event-signing-test-key-at-least-64-chars-long!!";

    fn infra() -> Option<(String, String)> {
        let nats = std::env::var("NATS_URL").ok()?;
        let redis = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        Some((nats, redis))
    }

    /// Stub booking upstream: GET /bookings/{id} → 200 (participant) for PARTICIPANT_BOOKING,
    /// else 403 (mirrors booking's non-participant response). Returns its base URL.
    async fn spawn_stub_booking() -> String {
        async fn get_booking(AxPath(id): AxPath<String>) -> Response {
            if id == PARTICIPANT_BOOKING {
                Json(serde_json::json!({
                    "success": true,
                    "data": { "id": id, "status": "accepted", "guard_id": null }
                }))
                .into_response()
            } else {
                (StatusCode::FORBIDDEN, "forbidden").into_response()
            }
        }
        let app = axum::Router::new().route("/bookings/{id}", axget(get_booking));
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        format!("http://{addr}")
    }

    /// Boot the gateway WS route over real Redis + the NATS hub + the stub booking upstream.
    /// Returns the gateway base addr + the broadcast sender (unused) kept alive via AppState.
    async fn spawn_gateway(nats: &str, redis_url: &str, booking_url: &str) -> SocketAddr {
        let redis_conn = shared::redis_client::create_connection_manager(redis_url)
            .await
            .unwrap();
        let jwt_config = JwtConfig {
            secret: SECRET.to_string(),
            expiry_minutes: 15,
            encoding_key: EncodingKey::from_secret(SECRET.as_bytes()),
            decoding_key: DecodingKey::from_secret(SECRET.as_bytes()),
        };
        let routes =
            crate::state::UpstreamTable::from_env().with_override(Upstream::Booking, booking_url);
        // The hub now verifies signed booking events — set the process key so the test can
        // publish signed and the hub accepts it (first-write-wins; shared across this binary).
        shared_events::init_signing_key(WS_TEST_KEY);
        let (status_tx, _) = broadcast::channel(256);
        {
            let tx = status_tx.clone();
            let nats = nats.to_string();
            tokio::spawn(async move { run_status_hub(nats, tx).await });
        }
        let state = AppState {
            http: reqwest::Client::new(),
            redis_conn,
            jwt_config,
            routes,
            limits: crate::domain::ratelimit::Limits {
                otp_per_min: 100_000,
                otp_verify_per_min: 100_000,
                auth_per_sec: 100_000,
                api_per_sec: 100_000,
            },
            status_tx,
            allowed_origins: std::sync::Arc::from(vec!["http://localhost:3000".to_string()]),
        };
        let app = axum::Router::new()
            .route("/v1/ws/bookings/{id}", axget(ws_bookings))
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

    fn token(role: &str) -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        encode_jwt_with_key(Uuid::new_v4(), role, 0, &ek, 15)
            .unwrap()
            .0
    }

    async fn connect_ws(
        addr: SocketAddr,
        booking: &str,
        bearer: Option<&str>,
    ) -> Result<
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
        (),
    > {
        let mut req = format!("ws://{addr}/v1/ws/bookings/{booking}")
            .into_client_request()
            .unwrap();
        if let Some(b) = bearer {
            req.headers_mut()
                .insert("authorization", format!("Bearer {b}").parse().unwrap());
        }
        match tokio_tungstenite::connect_async(req).await {
            Ok((stream, _)) => Ok(stream),
            Err(_) => Err(()),
        }
    }

    #[tokio::test]
    async fn ws_e2e_auth_participant_and_live_push() {
        let Some((nats, redis_url)) = infra() else {
            eprintln!("SKIP: NATS_URL + TEST_REDIS_URL/REDIS_CACHE_URL required");
            return;
        };
        let booking_url = spawn_stub_booking().await;
        let addr = spawn_gateway(&nats, &redis_url, &booking_url).await;
        // Give the hub a moment to establish its NATS subscription before publishing.
        tokio::time::sleep(Duration::from_millis(400)).await;

        // 1) No token → upgrade rejected (401).
        assert!(
            connect_ws(addr, PARTICIPANT_BOOKING, None).await.is_err(),
            "unauthenticated upgrade must be rejected"
        );

        // 2) Valid token but NOT a participant (stub returns 403) → upgrade rejected.
        let tok = token("customer");
        assert!(
            connect_ws(addr, OTHER_BOOKING, Some(&tok)).await.is_err(),
            "non-participant upgrade must be rejected"
        );

        // 2b) Valid token + participant booking but a DISALLOWED Origin (browser CSWSH) → rejected.
        {
            let mut req = format!("ws://{addr}/v1/ws/bookings/{PARTICIPANT_BOOKING}")
                .into_client_request()
                .unwrap();
            req.headers_mut()
                .insert("authorization", format!("Bearer {tok}").parse().unwrap());
            req.headers_mut()
                .insert("origin", "http://evil.example.com".parse().unwrap());
            assert!(
                tokio_tungstenite::connect_async(req).await.is_err(),
                "a cross-origin (disallowed Origin) upgrade must be rejected"
            );
        }

        // 3) Participant → connects, receives the initial snapshot, then a live push.
        let mut ws = connect_ws(addr, PARTICIPANT_BOOKING, Some(&tok))
            .await
            .expect("participant should connect");

        // 3a) initial snapshot frame (status = accepted, from the stub).
        let snap = read_text(&mut ws).await.expect("snapshot frame");
        let v: serde_json::Value = serde_json::from_str(&snap).unwrap();
        assert_eq!(v["type"], "booking_status");
        assert_eq!(v["booking_id"], PARTICIPANT_BOOKING);
        assert_eq!(v["status"], "accepted");

        // 3b) publish an en_route event to NATS → expect a live frame.
        let nc = shared_events::connect(&nats).await.unwrap();
        let envelope = serde_json::json!({
            "event_id": Uuid::new_v4().to_string(),
            "event_type": shared_events::topics::BOOKING_GUARD_EN_ROUTE,
            "occurred_at": "2026-06-05T10:00:00Z",
            "correlation_id": Uuid::new_v4().to_string(),
            "payload": { "booking_id": PARTICIPANT_BOOKING, "customer_id": "c1", "guard_id": "g1" }
        });
        // Publish SIGNED (the hub verifies fail-closed) — sign the exact bytes with the test key.
        let bytes = serde_json::to_vec(&envelope).unwrap();
        let mut hdrs = async_nats::HeaderMap::new();
        hdrs.insert(
            shared_events::SIGNATURE_HEADER,
            shared_events::sign_bytes(&bytes, WS_TEST_KEY).as_str(),
        );
        nc.publish_with_headers(
            shared_events::topics::BOOKING_GUARD_EN_ROUTE.to_string(),
            hdrs,
            bytes.into(),
        )
        .await
        .unwrap();
        nc.flush().await.unwrap();

        let live = read_text(&mut ws).await.expect("live frame");
        let lv: serde_json::Value = serde_json::from_str(&live).unwrap();
        assert_eq!(lv["type"], "booking_status");
        assert_eq!(lv["booking_id"], PARTICIPANT_BOOKING);
        assert_eq!(lv["status"], "en_route");
        assert_eq!(lv["guard_id"], "g1");
    }

    /// Read the next text frame (skipping pings), with a timeout so a hang fails the test.
    async fn read_text(
        ws: &mut tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
    ) -> Option<String> {
        use tokio_tungstenite::tungstenite::Message as TMsg;
        let deadline = Duration::from_secs(5);
        loop {
            match tokio::time::timeout(deadline, ws.next()).await {
                Ok(Some(Ok(TMsg::Text(t)))) => return Some(t.to_string()),
                Ok(Some(Ok(_))) => continue, // ping/pong/binary — keep waiting for text
                _ => return None,
            }
        }
    }
}
