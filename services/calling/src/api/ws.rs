//! WebSocket signaling relay (`GET /ws/call`).
//!
//! Mobile auth = **Bearer in the `Authorization` header on upgrade** (the `AuthUser` extractor
//! runs before the upgrade). A token in the URL query is NEVER read → such a request is
//! rejected 401 (v1 rule: no sensitive data in the WS URL). After open, the client sends
//! `{ "type":"signal", "call_id":<uuid>, "signal":<opaque SDP/ICE> }`; the server looks up
//! the call's two participants, verifies the sender is one of them, and forwards
//! `{ "type":"signal", "from":<uuid>, "call_id":<uuid>, "signal":... }` to the OTHER party's
//! live socket. A non-participant or unknown call is refused (IDOR protection on the wire) —
//! the server never trusts a client-supplied recipient.

use std::time::Duration;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::http::HeaderMap;
use axum::response::Response;
use futures::{SinkExt, StreamExt};
use jsonwebtoken::DecodingKey;
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::sync::mpsc;
use uuid::Uuid;

use shared::auth::{authenticate_token, extract_cookie_value, AuthUser, ACCESS_TOKEN_COOKIE};

use crate::domain::peer_of;
use crate::repo;
use crate::state::{CallDeps, Registry};

/// How often a live signaling session re-validates its access token (catches expiry +
/// force-revoke-all + per-jti revoke). Also doubles as a liveness ping. Access tokens are
/// short-lived (≤15 min), so this bounds how long a revoked/expired socket can linger.
const REAUTH_INTERVAL: Duration = Duration::from_secs(60);

/// Inbound signaling frame from a client.
#[derive(Debug, Deserialize)]
struct ClientSignal {
    call_id: Uuid,
    signal: Value,
}

/// GET /ws/call — authenticate the Bearer on upgrade, then run the signaling session.
/// `AuthUser` is the FIRST extractor so a missing/URL-only token is rejected (401) before any
/// upgrade work. The raw token is also captured so the session can RE-validate periodically
/// (an open socket must not outlive token expiry or a revocation).
pub async fn ws_call<S: CallDeps>(
    user: AuthUser,
    ws: WebSocketUpgrade,
    headers: HeaderMap,
    State(state): State<S>,
) -> Response {
    let uid = user.user_id;
    let token = token_from_headers(&headers);
    let db = state.db().clone();
    let registry = state.registry().clone();
    let redis = state.redis_conn().clone();
    let decoding_key = state.decoding_key().clone();
    ws.on_upgrade(move |socket| session(socket, uid, token, db, registry, redis, decoding_key))
}

/// The same token the `AuthUser` extractor validated (Bearer header, else `access_token`
/// cookie) — captured so the session can re-validate it on the re-auth tick.
fn token_from_headers(headers: &HeaderMap) -> Option<String> {
    if let Some(bearer) = headers
        .get("Authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
    {
        return Some(bearer.to_string());
    }
    headers
        .get("Cookie")
        .and_then(|v| v.to_str().ok())
        .and_then(|c| extract_cookie_value(c, ACCESS_TOKEN_COOKIE).map(|t| t.to_string()))
}

/// Drive one authenticated signaling session: register the socket, relay inbound signals to
/// the call peer, periodically re-validate the token, and deregister on close.
#[allow(clippy::too_many_arguments)]
async fn session(
    socket: WebSocket,
    uid: Uuid,
    token: Option<String>,
    db: sqlx::PgPool,
    registry: Registry,
    redis: redis::aio::ConnectionManager,
    decoding_key: DecodingKey,
) {
    let (mut sink, mut stream) = socket.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<String>();
    registry.lock().await.insert(uid, tx);

    let mut reauth = tokio::time::interval(REAUTH_INTERVAL);
    reauth.tick().await; // consume the immediate first tick

    tracing::info!(user = %uid, "ws signaling session open");

    loop {
        tokio::select! {
            // Outbound: a peer (or self, on error) pushed a frame to forward to this socket.
            outgoing = rx.recv() => match outgoing {
                Some(text) => {
                    if sink.send(Message::Text(text.into())).await.is_err() {
                        break;
                    }
                }
                None => break,
            },
            // Inbound: a frame from this client.
            incoming = stream.next() => match incoming {
                Some(Ok(Message::Text(text))) => {
                    handle_signal(&db, &registry, uid, text.as_str()).await;
                }
                Some(Ok(Message::Close(_))) | None | Some(Err(_)) => break,
                Some(Ok(_)) => {} // ignore ping/pong/binary
            },
            // Periodic re-auth + liveness: close if the token expired or was revoked, and ping
            // to surface a dead socket (a failed write breaks the loop → deregister).
            _ = reauth.tick() => {
                if let Some(t) = &token {
                    if authenticate_token(t, &decoding_key, &redis).await.is_err() {
                        tracing::info!(user = %uid, "ws token expired/revoked; closing session");
                        let _ = sink.send(Message::Close(None)).await;
                        break;
                    }
                }
                if sink.send(Message::Ping(Vec::new().into())).await.is_err() {
                    break;
                }
            },
        }
    }

    // Deregister — but only if the live entry is OURS. Dropping `rx` closes our `tx`; a
    // reconnect by the same user replaced the map entry with a fresh (open) sender, which we
    // must not evict.
    drop(rx);
    let mut reg = registry.lock().await;
    if reg.get(&uid).map(|s| s.is_closed()).unwrap_or(false) {
        reg.remove(&uid);
    }
    tracing::info!(user = %uid, "ws signaling session closed");
}

/// Parse + route one inbound signal: verify the sender is a participant of `call_id` and the
/// call is still active, then forward to the OTHER participant's live socket. Existence vs
/// membership is NOT distinguished on the wire (generic "cannot route") — only a confirmed
/// participant learns liveness/offline state.
async fn handle_signal(db: &sqlx::PgPool, registry: &Registry, sender: Uuid, text: &str) {
    let parsed: ClientSignal = match serde_json::from_str(text) {
        Ok(p) => p,
        Err(_) => {
            send_to(registry, sender, err_frame("invalid signal frame")).await;
            return;
        }
    };

    let (caller, callee, status) = match repo::participants(db, parsed.call_id).await {
        Ok(Some(p)) => p,
        Ok(None) => {
            // Unknown call — same generic message as non-participant (no existence oracle).
            send_to(
                registry,
                sender,
                err_frame("cannot route signal for this call"),
            )
            .await;
            return;
        }
        Err(e) => {
            tracing::warn!("ws participant lookup failed: {e}");
            send_to(registry, sender, err_frame("signal routing failed")).await;
            return;
        }
    };

    // Authorize FIRST (no client-supplied recipient) — a non-participant gets the SAME generic
    // message as an unknown call, so it can't probe call existence/membership.
    let peer = match peer_of(sender, caller, callee) {
        Some(p) => p,
        None => {
            send_to(
                registry,
                sender,
                err_frame("cannot route signal for this call"),
            )
            .await;
            return;
        }
    };

    // The sender is a confirmed participant — only now is it safe to reveal call liveness.
    if status.is_terminal() {
        send_to(registry, sender, err_frame("call is no longer active")).await;
        return;
    }

    let frame = json!({
        "type": "signal",
        "from": sender,
        "call_id": parsed.call_id,
        "signal": parsed.signal,
    })
    .to_string();

    // Forward to the peer if they're connected; otherwise tell the (participant) sender.
    let delivered = send_to(registry, peer, frame).await;
    if !delivered {
        send_to(registry, sender, err_frame("peer is offline")).await;
    }
}

/// Push a text frame to `uid`'s live socket. Returns whether a live, open sender existed.
async fn send_to(registry: &Registry, uid: Uuid, text: String) -> bool {
    let reg = registry.lock().await;
    match reg.get(&uid) {
        Some(tx) => tx.send(text).is_ok(),
        None => false,
    }
}

fn err_frame(message: &str) -> String {
    json!({ "type": "error", "message": message }).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::booking_client::BookingReader;
    use crate::models::InternalBooking;
    use crate::state::CallDeps;
    use axum::body::Body;
    use axum::http::{header, Request, StatusCode};
    use axum::routing::get;
    use axum::Router;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use shared::auth::{encode_jwt_with_key, HasJwtSecret};
    use shared::error::AppError;
    use sqlx::postgres::PgPoolOptions;
    use std::collections::HashMap;
    use std::sync::Arc;
    use std::time::Duration;
    use tokio::sync::Mutex;
    use tower::ServiceExt;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-callws-test!!!!";

    #[derive(Clone)]
    struct StubReader;
    impl BookingReader for StubReader {
        async fn get_booking(&self, _id: Uuid) -> Result<InternalBooking, AppError> {
            Err(AppError::NotFound("n/a".to_string()))
        }
    }

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
        redis: redis::aio::ConnectionManager,
        registry: Registry,
    }
    impl HasJwtSecret for TestDeps {
        fn jwt_secret(&self) -> &str {
            SECRET
        }
        fn decoding_key(&self) -> &DecodingKey {
            &self.dec
        }
        fn redis_conn(&self) -> &redis::aio::ConnectionManager {
            &self.redis
        }
    }
    impl CallDeps for TestDeps {
        type Reader = StubReader;
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn booking_reader(&self) -> &StubReader {
            // Never used by the WS path; present to satisfy the seam.
            unreachable!("ws tests do not call the booking reader")
        }
        fn registry(&self) -> &Registry {
            &self.registry
        }
        fn turn(&self) -> &crate::state::TurnConfig {
            // The WS signaling path never serves ICE; present only to satisfy the seam.
            unreachable!("ws tests do not serve ICE config")
        }
    }

    async fn router() -> Option<Router> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db,
            redis,
            registry: Arc::new(Mutex::new(HashMap::new())),
        };
        Some(
            Router::new()
                .route("/ws/call", get(ws_call::<TestDeps>))
                .with_state(deps),
        )
    }

    fn token() -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _jti) = encode_jwt_with_key(Uuid::new_v4(), "customer", 0, &ek, 15).unwrap();
        tok
    }

    /// Build a request with the standard WS upgrade headers; `auth` optionally adds the Bearer.
    fn upgrade_req(uri: &str, auth: Option<&str>) -> Request<Body> {
        let mut b = Request::builder()
            .method("GET")
            .uri(uri)
            .header(header::CONNECTION, "upgrade")
            .header(header::UPGRADE, "websocket")
            .header(header::SEC_WEBSOCKET_VERSION, "13")
            .header(header::SEC_WEBSOCKET_KEY, "dGhlIHNhbXBsZSBub25jZQ==");
        if let Some(t) = auth {
            b = b.header(header::AUTHORIZATION, format!("Bearer {t}"));
        }
        b.body(Body::empty()).unwrap()
    }

    #[tokio::test]
    async fn upgrade_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app.oneshot(upgrade_req("/ws/call", None)).await.unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn upgrade_rejects_token_in_url_query() {
        // The token ONLY in the query string is never read → still 401 (no sensitive data in URL).
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let uri = format!("/ws/call?token={}", token());
        let res = app.oneshot(upgrade_req(&uri, None)).await.unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn upgrade_accepts_bearer_on_upgrade() {
        // A valid Bearer on the upgrade request passes the auth gate (NOT 401). The exact 101
        // switch needs a real upgradeable connection (proven by `relay_offer_*` over a bound
        // server); via `oneshot` we assert auth was accepted.
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(upgrade_req("/ws/call", Some(&token())))
            .await
            .unwrap();
        assert_ne!(
            res.status(),
            StatusCode::UNAUTHORIZED,
            "a valid Bearer on upgrade must pass the auth gate"
        );
    }

    /// END-TO-END signaling relay over a REAL bound server + two REAL WS clients (Bearer on
    /// upgrade): the caller's offer is routed to the callee (and only to a participant). Gated
    /// on DATABASE_URL (call lookup) + TEST_REDIS_URL (AuthUser). Run against a migrated DB:
    ///   DATABASE_URL=... TEST_REDIS_URL=... cargo test -p pguard-calling -- relay_offer --nocapture
    #[tokio::test]
    async fn relay_offer_reaches_the_callee_peer() {
        use crate::booking_client::HttpBookingReader;
        use crate::state::AppState;
        use futures::SinkExt as _;
        use futures::StreamExt as _;
        use shared::config::JwtConfig;
        use tokio_tungstenite::tungstenite::client::IntoClientRequest;
        use tokio_tungstenite::tungstenite::Message as TMessage;

        let (Ok(db_url), Ok(redis_url)) = (
            std::env::var("DATABASE_URL"),
            std::env::var("TEST_REDIS_URL").or_else(|_| std::env::var("REDIS_CACHE_URL")),
        ) else {
            eprintln!("SKIP: DATABASE_URL + TEST_REDIS_URL required for the relay e2e");
            return;
        };
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&db_url)
            .await
            .expect("connect Postgres");
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .expect("redis conn");

        let caller = Uuid::new_v4();
        let callee = Uuid::new_v4();
        let call_id: Uuid = sqlx::query_scalar(
            "INSERT INTO calling.call_logs (caller_id, callee_id, booking_id, status) \
             VALUES ($1, $2, $3, 'accepted'::calling.call_status) RETURNING id",
        )
        .bind(caller)
        .bind(callee)
        .bind(Uuid::new_v4())
        .fetch_one(&db)
        .await
        .expect("seed call");

        let jwt_config = JwtConfig {
            secret: SECRET.to_string(),
            expiry_minutes: 15,
            encoding_key: EncodingKey::from_secret(SECRET.as_bytes()),
            decoding_key: DecodingKey::from_secret(SECRET.as_bytes()),
        };
        let state = AppState {
            db: db.clone(),
            redis_conn: redis,
            jwt_config,
            booking_reader: HttpBookingReader::new(
                reqwest::Client::new(),
                "http://127.0.0.1:1".to_string(),
                EncodingKey::from_secret(b"unused-service-secret-for-this-ws-relay-test-only!!"),
                60,
            ),
            registry: Arc::new(Mutex::new(HashMap::new())),
            turn: crate::state::TurnConfig {
                secret: None,
                stun_urls: vec![],
                turn_urls: vec![],
                ttl_secs: 3600,
            },
        };
        let app = Router::new()
            .route("/ws/call", get(ws_call::<AppState>))
            .with_state(state);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let _ = axum::serve(listener, app).await;
        });

        let mint = |uid: Uuid| {
            let ek = EncodingKey::from_secret(SECRET.as_bytes());
            encode_jwt_with_key(uid, "customer", 0, &ek, 15).unwrap().0
        };
        let connect = |uid: Uuid| async move {
            let mut req = format!("ws://{addr}/ws/call")
                .into_client_request()
                .unwrap();
            req.headers_mut().insert(
                "Authorization",
                format!("Bearer {}", mint(uid)).parse().unwrap(),
            );
            tokio_tungstenite::connect_async(req)
                .await
                .expect("ws connect")
                .0
        };

        let mut caller_ws = connect(caller).await;
        let mut callee_ws = connect(callee).await;
        // Let both sessions register in the server's registry before signaling.
        tokio::time::sleep(Duration::from_millis(200)).await;

        // Caller sends an SDP offer addressed to the call (peer is derived server-side).
        let offer = json!({ "call_id": call_id, "signal": { "sdp": "OFFER" } }).to_string();
        caller_ws.send(TMessage::Text(offer)).await.unwrap();

        // The callee must receive it, tagged with the sender + opaque signal.
        let received = tokio::time::timeout(Duration::from_secs(3), callee_ws.next())
            .await
            .expect("callee receives within timeout")
            .expect("stream item")
            .expect("ws message");
        let text = match received {
            TMessage::Text(t) => t.to_string(),
            other => panic!("expected text frame, got {other:?}"),
        };
        let v: Value = serde_json::from_str(&text).unwrap();
        assert_eq!(v["type"], json!("signal"));
        assert_eq!(v["from"], json!(caller), "relayed frame names the sender");
        assert_eq!(v["call_id"], json!(call_id));
        assert_eq!(
            v["signal"]["sdp"],
            json!("OFFER"),
            "opaque SDP relayed verbatim"
        );

        // IDOR-on-the-wire: a stranger (valid token, NOT a participant) cannot route on this
        // call — it gets a GENERIC error (no existence/membership oracle), nothing is relayed.
        let mut stranger_ws = connect(Uuid::new_v4()).await;
        tokio::time::sleep(Duration::from_millis(100)).await;
        let probe = json!({ "call_id": call_id, "signal": { "sdp": "EVIL" } }).to_string();
        stranger_ws.send(TMessage::Text(probe)).await.unwrap();
        let reply = tokio::time::timeout(Duration::from_secs(3), stranger_ws.next())
            .await
            .expect("stranger gets a reply")
            .expect("stream item")
            .expect("ws message");
        let st = match reply {
            TMessage::Text(t) => t.to_string(),
            other => panic!("expected text frame, got {other:?}"),
        };
        let sv: Value = serde_json::from_str(&st).unwrap();
        assert_eq!(
            sv["type"],
            json!("error"),
            "non-participant signal is refused"
        );
        assert_eq!(sv["message"], json!("cannot route signal for this call"));

        // cleanup
        let _ = sqlx::query("DELETE FROM calling.call_logs WHERE id = $1")
            .bind(call_id)
            .execute(&db)
            .await;
        server.abort();
    }
}
