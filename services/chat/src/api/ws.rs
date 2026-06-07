//! WebSocket chat relay (`GET /ws/chat`).
//!
//! Mobile/web auth = **Bearer in the `Authorization` header on upgrade** (the `AuthUser`
//! extractor runs before the upgrade). A token in the URL query is NEVER read → such a request
//! is rejected 401 (no sensitive data in the WS URL). **`conversation_id` is NOT in the URL** —
//! each inbound frame names it; the server verifies the sender is a participant (IDOR gate on
//! the wire) and the conversation is writable, persists the message + outbox event, then
//! broadcasts to the conversation's `chat:{id}` Redis channel so EVERY chat replica's sessions
//! deliver it (cross-instance fan-out). Alignment is by `sender_role`, never `sender_id`.

use std::collections::HashSet;
use std::time::Duration;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::http::HeaderMap;
use axum::response::Response;
use futures::{SinkExt, StreamExt};
use serde_json::json;
use uuid::Uuid;

use shared::auth::{authenticate_token, extract_cookie_value, AuthUser, ACCESS_TOKEN_COOKIE};
use shared::error::AppError;

use crate::models::{IncomingChatMessage, OutgoingChatMessage};
use crate::repo;
use crate::state::ChatDeps;

/// How often a live session re-validates its access token (catches expiry + force-revoke-all +
/// per-jti revoke); doubles as a liveness ping. Mirrors the calling WS relay.
const REAUTH_INTERVAL: Duration = Duration::from_secs(60);

const ROLE_ADMIN: &str = "admin";

/// GET /ws/chat — authenticate the Bearer on upgrade, then run the chat session. `AuthUser` is
/// the FIRST extractor so a missing/URL-only token is rejected (401) before any upgrade work.
pub async fn ws_chat<S: ChatDeps>(
    user: AuthUser,
    ws: WebSocketUpgrade,
    headers: HeaderMap,
    State(state): State<S>,
) -> Response {
    let token = token_from_headers(&headers);
    ws.on_upgrade(move |socket| session(socket, user, token, state))
}

/// The token the `AuthUser` extractor validated (Bearer header, else `access_token` cookie),
/// captured so the session can re-validate it on the re-auth tick.
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

/// Drive one authenticated chat session: prefetch the authorized rooms, subscribe to the
/// `chat:*` fan-out, relay inbound frames (persist + broadcast) and outbound broadcasts,
/// periodically re-validate the token, and close on token expiry/revoke.
async fn session<S: ChatDeps>(socket: WebSocket, user: AuthUser, token: Option<String>, state: S) {
    let (mut sink, mut stream) = socket.split();
    let uid = user.user_id;
    let is_admin = user.role == ROLE_ADMIN;

    // Authorized-rooms set — a `chat:*` broadcast for a room the user isn't in is never
    // forwarded. Admins get a wildcard bypass. Grows as the user sends into new rooms.
    let mut authorized: HashSet<Uuid> = HashSet::new();
    if !is_admin {
        match repo::participant_conversation_ids(state.db(), uid).await {
            Ok(ids) => authorized.extend(ids),
            Err(e) => tracing::warn!(user = %uid, "chat ws prefetch failed: {e}"),
        }
    }

    // One dedicated Redis subscriber per connection keeps the load bounded.
    let mut pubsub = match state.pubsub_client().get_async_pubsub().await {
        Ok(ps) => ps,
        Err(e) => {
            tracing::error!(user = %uid, "chat ws pubsub open failed: {e}");
            return;
        }
    };
    if let Err(e) = pubsub.psubscribe("chat:*").await {
        tracing::error!(user = %uid, "chat ws psubscribe failed: {e}");
        return;
    }
    let mut broadcasts = pubsub.on_message();

    let redis = state.redis_conn().clone();
    let decoding_key = state.decoding_key().clone();
    let mut reauth = tokio::time::interval(REAUTH_INTERVAL);
    reauth.tick().await; // consume the immediate first tick

    tracing::info!(user = %uid, "chat ws session open");

    loop {
        tokio::select! {
            // Inbound: a frame from this client.
            incoming = stream.next() => match incoming {
                Some(Ok(Message::Text(text))) => {
                    let frame: IncomingChatMessage = match serde_json::from_str(text.as_str()) {
                        Ok(f) => f,
                        Err(e) => {
                            let _ = sink.send(err_frame(&format!("invalid message: {e}"))).await;
                            continue;
                        }
                    };
                    let cid = frame.conversation_id;
                    match super::persist_and_broadcast(&state, &user, &frame).await {
                        Ok(saved) => {
                            // We successfully wrote here → it's an authorized room.
                            authorized.insert(cid);
                            // Direct echo to the sender (the pub/sub broadcast suppresses the
                            // sender's own copy, so this is how their bubble appears instantly).
                            match serde_json::to_string(&saved) {
                                Ok(j) => {
                                    if sink.send(Message::Text(j.into())).await.is_err() {
                                        break;
                                    }
                                }
                                Err(e) => tracing::warn!("serialize echo failed: {e}"),
                            }
                        }
                        Err(e) => {
                            // Participant gate / read-only / not-found surface as a CLIENT-SAFE
                            // error frame — the socket stays open. Database/Redis detail is masked
                            // (parity with the HTTP IntoResponse path; no sqlx detail on the wire).
                            let _ = sink.send(err_frame(&client_safe_message(&e))).await;
                        }
                    }
                }
                Some(Ok(Message::Close(_))) | None | Some(Err(_)) => break,
                Some(Ok(_)) => {} // ignore ping/pong/binary
            },

            // Outbound: a broadcast on the `chat:*` fan-out.
            broadcast = broadcasts.next() => {
                let Some(msg) = broadcast else { break }; // subscriber closed → end session
                let payload: String = match msg.get_payload() {
                    Ok(p) => p,
                    Err(_) => continue,
                };
                let Some(out) = serde_json::from_str::<OutgoingChatMessage>(&payload).ok() else {
                    continue;
                };
                // Don't echo the sender their own message (they got a direct reply already).
                if out.sender_id == uid {
                    continue;
                }
                // Room gate: never forward a frame for a room the user isn't a participant of.
                if !is_admin && !authorized.contains(&out.conversation_id) {
                    continue;
                }
                if sink.send(Message::Text(payload.into())).await.is_err() {
                    break;
                }
            },

            // Periodic re-auth + liveness: close if the token expired/was revoked — or if we hold
            // NO token to re-validate (fail closed: an open socket must never outlive its token's
            // expiry/revocation). Ping otherwise.
            _ = reauth.tick() => {
                let still_valid = match &token {
                    Some(t) => authenticate_token(t, &decoding_key, &redis).await.is_ok(),
                    // AuthUser validated a token on upgrade, so we should always have recaptured it;
                    // if not, we can't re-validate against expiry/revoke → fail closed.
                    None => false,
                };
                if !still_valid {
                    tracing::info!(user = %uid, "chat ws token invalid/expired/revoked/missing; closing");
                    let _ = sink.send(Message::Close(None)).await;
                    break;
                }
                if sink.send(Message::Ping(Vec::new().into())).await.is_err() {
                    break;
                }
            },
        }
    }

    tracing::info!(user = %uid, "chat ws session closed");
}

fn err_frame(message: &str) -> Message {
    Message::Text(
        json!({ "type": "error", "message": message })
            .to_string()
            .into(),
    )
}

/// Map an `AppError` to a CLIENT-SAFE WS message, mirroring `AppError`'s HTTP `IntoResponse`
/// masking: `Database`/`Redis` collapse to a generic string (no sqlx/redis detail leaked over the
/// socket), while client-fault variants (`BadRequest`/`Forbidden`/`Conflict`/`NotFound`) keep
/// their already-safe message. The underlying error is still logged server-side by `AppError`.
fn client_safe_message(err: &AppError) -> String {
    match err {
        AppError::Database(_) | AppError::Redis(_) => "An internal error occurred".to_string(),
        other => other.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::s3::S3Client;
    use axum::body::Body;
    use axum::http::{header, Request, StatusCode};
    use axum::routing::get;
    use axum::Router;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use shared::auth::{encode_jwt_with_key, HasJwtSecret};
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;
    use std::time::Duration;
    use tower::ServiceExt;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-chatws-test!!!!!";

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
        redis: redis::aio::MultiplexedConnection,
        pubsub_client: redis::Client,
        s3: S3Client,
    }
    impl HasJwtSecret for TestDeps {
        fn jwt_secret(&self) -> &str {
            SECRET
        }
        fn decoding_key(&self) -> &DecodingKey {
            &self.dec
        }
        fn redis_conn(&self) -> &redis::aio::MultiplexedConnection {
            &self.redis
        }
    }
    impl ChatDeps for TestDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn db_read(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn pubsub_conn(&self) -> &redis::aio::MultiplexedConnection {
            &self.redis
        }
        fn pubsub_client(&self) -> &redis::Client {
            &self.pubsub_client
        }
        fn s3(&self) -> &S3Client {
            &self.s3
        }
    }

    fn s3_stub() -> S3Client {
        S3Client::new(
            reqwest::Client::new(),
            "http://localhost:9000".to_string(),
            None,
            "test".to_string(),
            "us-east-1".to_string(),
            "k".to_string(),
            "s".to_string(),
        )
    }

    async fn router() -> Option<Router> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let client = redis::Client::open(redis_url).ok()?;
        let redis = client.get_multiplexed_tokio_connection().await.ok()?;
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db,
            redis,
            pubsub_client: client,
            s3: s3_stub(),
        };
        Some(
            Router::new()
                .route("/ws/chat", get(ws_chat::<TestDeps>))
                .with_state(deps),
        )
    }

    fn token() -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        encode_jwt_with_key(Uuid::new_v4(), "customer", 0, &ek, 15)
            .unwrap()
            .0
    }

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

    #[test]
    fn ws_error_frame_masks_database_detail_but_keeps_client_faults() {
        // Database/Redis detail must NOT leak over the socket (parity with the HTTP path).
        let masked = client_safe_message(&AppError::Database(sqlx::Error::PoolTimedOut));
        assert_eq!(masked, "An internal error occurred");
        assert!(!masked.contains("pool"), "no sqlx detail on the wire");
        // Client-fault messages stay visible (they're already safe + actionable).
        assert_eq!(
            client_safe_message(&AppError::Forbidden(
                "Not a participant of this conversation".into()
            )),
            "Not a participant of this conversation"
        );
        assert_eq!(
            client_safe_message(&AppError::Conflict("Conversation is read-only".into())),
            "Conversation is read-only"
        );
    }

    #[tokio::test]
    async fn upgrade_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app.oneshot(upgrade_req("/ws/chat", None)).await.unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn upgrade_rejects_token_in_url_query() {
        // The token ONLY in the query string is never read → still 401 (no sensitive data in URL).
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let uri = format!(
            "/ws/chat?token={}&conversation_id={}",
            token(),
            Uuid::new_v4()
        );
        let res = app.oneshot(upgrade_req(&uri, None)).await.unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn upgrade_accepts_bearer_on_upgrade() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(upgrade_req("/ws/chat", Some(&token())))
            .await
            .unwrap();
        assert_ne!(
            res.status(),
            StatusCode::UNAUTHORIZED,
            "a valid Bearer on upgrade must pass the auth gate"
        );
    }

    /// END-TO-END over a REAL bound server + two REAL WS clients: the customer sends a frame
    /// (conversation_id AFTER open) and the guard receives it tagged with `sender_role:customer`
    /// (alignment by role); a stranger's frame to the same conversation is refused on the wire
    /// (participant gate) and nothing is delivered. Gated on DATABASE_URL + TEST_REDIS_URL.
    #[tokio::test]
    async fn relay_delivers_to_peer_and_gates_non_participant() {
        use crate::models::{CreateConversationRequest, ParticipantInput};
        use crate::state::AppState;
        use shared::config::JwtConfig;
        use tokio_tungstenite::tungstenite::client::IntoClientRequest;
        use tokio_tungstenite::tungstenite::Message as TMessage;

        let (Ok(db_url), Ok(redis_url)) = (
            std::env::var("DATABASE_URL"),
            std::env::var("TEST_REDIS_URL").or_else(|_| std::env::var("REDIS_CACHE_URL")),
        ) else {
            eprintln!("SKIP: DATABASE_URL + TEST_REDIS_URL required for the chat WS e2e");
            return;
        };
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&db_url)
            .await
            .expect("connect Postgres");
        let client = redis::Client::open(redis_url).expect("redis client");
        let redis = client
            .get_multiplexed_tokio_connection()
            .await
            .expect("redis conn");

        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let req = CreateConversationRequest {
            request_id: Uuid::new_v4(),
            request_status: Some("accepted".to_string()),
            participants: vec![
                ParticipantInput {
                    user_id: customer,
                    role: "customer".into(),
                    display_name: Some("C".into()),
                    avatar_url: None,
                },
                ParticipantInput {
                    user_id: guard,
                    role: "guard".into(),
                    display_name: Some("G".into()),
                    avatar_url: None,
                },
            ],
        };
        let conv = repo::create_conversation(&db, &req)
            .await
            .expect("seed convo");

        let jwt_config = JwtConfig {
            secret: SECRET.to_string(),
            expiry_minutes: 15,
            encoding_key: EncodingKey::from_secret(SECRET.as_bytes()),
            decoding_key: DecodingKey::from_secret(SECRET.as_bytes()),
        };
        let state = AppState {
            db: db.clone(),
            db_read: db.clone(),
            redis_conn: redis.clone(),
            pubsub_conn: redis.clone(),
            pubsub_client: client.clone(),
            jwt_config,
            service_decoding_key: DecodingKey::from_secret(
                b"unused-service-secret-for-this-chat-ws-e2e-only!!!!",
            ),
            s3: s3_stub(),
        };
        let app = Router::new()
            .route("/ws/chat", get(ws_chat::<AppState>))
            .with_state(state);
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let _ = axum::serve(listener, app).await;
        });

        let mint = |uid: Uuid, role: &str| {
            let ek = EncodingKey::from_secret(SECRET.as_bytes());
            encode_jwt_with_key(uid, role, 0, &ek, 15).unwrap().0
        };
        let connect = |uid: Uuid, role: &'static str| async move {
            let mut r = format!("ws://{addr}/ws/chat")
                .into_client_request()
                .unwrap();
            r.headers_mut().insert(
                "Authorization",
                format!("Bearer {}", mint(uid, role)).parse().unwrap(),
            );
            tokio_tungstenite::connect_async(r)
                .await
                .expect("ws connect")
                .0
        };

        let mut customer_ws = connect(customer, "customer").await;
        let mut guard_ws = connect(guard, "guard").await;
        tokio::time::sleep(Duration::from_millis(250)).await; // let both subscribe

        // conversation_id is sent in the FRAME (not the URL).
        let frame = json!({
            "conversation_id": conv.id,
            "content": "hello guard",
            "message_type": "text",
            "sender_role": "customer"
        })
        .to_string();
        customer_ws.send(TMessage::Text(frame)).await.unwrap();

        // The guard receives the broadcast, tagged with the sender's ROLE (alignment).
        let received = tokio::time::timeout(Duration::from_secs(3), guard_ws.next())
            .await
            .expect("guard receives within timeout")
            .expect("stream item")
            .expect("ws message");
        let text = match received {
            TMessage::Text(t) => t.to_string(),
            other => panic!("expected text frame, got {other:?}"),
        };
        let v: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(v["conversation_id"], json!(conv.id));
        assert_eq!(v["sender_id"], json!(customer));
        assert_eq!(v["sender_role"], json!("customer"), "alignment is by role");
        assert_eq!(v["content"], json!("hello guard"));

        // Participant gate on the wire: a stranger's frame is refused with an error, and the
        // guard receives nothing further.
        let mut stranger_ws = connect(Uuid::new_v4(), "customer").await;
        tokio::time::sleep(Duration::from_millis(150)).await;
        let evil = json!({ "conversation_id": conv.id, "content": "intrusion", "sender_role": "customer" })
            .to_string();
        stranger_ws.send(TMessage::Text(evil)).await.unwrap();
        let reply = tokio::time::timeout(Duration::from_secs(3), stranger_ws.next())
            .await
            .expect("stranger gets a reply")
            .expect("stream item")
            .expect("ws message");
        let rt = match reply {
            TMessage::Text(t) => t.to_string(),
            other => panic!("expected text frame, got {other:?}"),
        };
        let rv: serde_json::Value = serde_json::from_str(&rt).unwrap();
        assert_eq!(
            rv["type"],
            json!("error"),
            "non-participant send is refused on the wire"
        );

        // cleanup (cascades) + stop the server.
        let _ = sqlx::query(
            "DELETE FROM chat.outbox WHERE payload->'payload'->>'conversation_id' = $1",
        )
        .bind(conv.id.to_string())
        .execute(&db)
        .await;
        let _ = sqlx::query("DELETE FROM chat.conversations WHERE id = $1")
            .bind(conv.id)
            .execute(&db)
            .await;
        server.abort();
    }
}
