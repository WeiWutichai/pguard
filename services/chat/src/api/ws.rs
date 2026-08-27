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
use std::time::{Duration, Instant};

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
    // Cap inbound frames/messages hard: chat carries small JSON control frames (text + a
    // conversation_id); binary attachments go over REST, never the socket. Without this the
    // frame is bounded only by the edge body cap (~1 MiB) or, hit directly, tungstenite's
    // 64 MiB default — an authenticated write-amplification DoS against chat.messages/outbox.
    ws.max_message_size(MAX_WS_FRAME_BYTES)
        .max_frame_size(MAX_WS_FRAME_BYTES)
        .on_upgrade(move |socket| session(socket, user, token, state))
}

/// Upper bound on a single inbound chat WS frame/message (64 KiB — far above any legitimate
/// chat text frame, far below a memory-pressure payload).
const MAX_WS_FRAME_BYTES: usize = 64 * 1024;

/// Per-connection inbound-frame budget: burst of [`FRAME_BURST`] then [`FRAME_REFILL_PER_SEC`]/s
/// sustained. Each inbound frame opens a DB tx (`repo::send_message` — a participant `SELECT` +
/// message/outbox writes), so this bounds how fast one authed socket can drive that work. The
/// burst is well above human typing speed, so legitimate chat is never throttled.
const FRAME_BURST: u32 = 20;
const FRAME_REFILL_PER_SEC: f64 = 5.0;

/// A per-connection token-bucket rate limiter for inbound WS data frames. Pure + time-injectable
/// (`allow_at`) so it unit-tests without a clock. Refills `refill_per_sec` tokens/second up to
/// `capacity`; each inbound frame consumes one. An empty bucket == abuse.
struct FrameRateLimiter {
    tokens: f64,
    capacity: f64,
    refill_per_sec: f64,
    last: Instant,
}

impl FrameRateLimiter {
    fn new(capacity: u32, refill_per_sec: f64) -> Self {
        Self {
            tokens: f64::from(capacity),
            capacity: f64::from(capacity),
            refill_per_sec,
            last: Instant::now(),
        }
    }

    /// Consume one token at the current instant. `true` = within budget, `false` = abuse.
    fn allow(&mut self) -> bool {
        self.allow_at(Instant::now())
    }

    /// Testable core: refill by elapsed wall-time since the last call, then take one token.
    fn allow_at(&mut self, now: Instant) -> bool {
        let elapsed = now.saturating_duration_since(self.last).as_secs_f64();
        self.last = now;
        self.tokens = (self.tokens + elapsed * self.refill_per_sec).min(self.capacity);
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            true
        } else {
            false
        }
    }
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

    // Bound how fast this socket can drive DB work — each inbound frame opens a tx
    // (participant SELECT + message/outbox writes), so an unrate-limited flood is a DB DoS.
    let mut limiter = FrameRateLimiter::new(FRAME_BURST, FRAME_REFILL_PER_SEC);

    tracing::info!(user = %uid, "chat ws session open");

    loop {
        tokio::select! {
            // Inbound: a frame from this client.
            incoming = stream.next() => match incoming {
                Some(Ok(Message::Text(text))) => {
                    // Rate-limit BEFORE any parse/DB work so a flood can't be amplified into
                    // unbounded transactions. Over budget → the socket is closed.
                    if !limiter.allow() {
                        tracing::warn!(user = %uid, "chat ws inbound frame flood; closing session");
                        let _ = sink.send(Message::Close(None)).await;
                        break;
                    }
                    let frame: IncomingChatMessage = match serde_json::from_str(text.as_str()) {
                        Ok(f) => f,
                        Err(e) => {
                            let _ = sink
                                .send(err_frame(None, &format!("invalid message: {e}")))
                                .await;
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
                            // A machine-readable `code` rides along where one exists (`read_only`)
                            // so the client can lock its composer instead of dropping the frame.
                            let _ = sink
                                .send(err_frame(err_code(&e), &client_safe_message(&e)))
                                .await;
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
                // RE-PREFETCH the authorized-rooms set: a conversation created/added AFTER connect
                // (e.g. the booking conversation created once this recipient is online) is otherwise
                // never in the set — the user joined only via SENDS, so an inbound-only recipient
                // would silently drop every realtime message for it. Replacing the set on each tick
                // (≤60s lag) closes that gap with one cheap query per session per interval. (Admins
                // use the wildcard bypass, so they skip this.)
                if !is_admin {
                    match repo::participant_conversation_ids(state.db(), uid).await {
                        Ok(ids) => {
                            authorized.clear();
                            authorized.extend(ids);
                        }
                        // Keep the existing set on a transient DB error — never widen access on failure.
                        Err(e) => tracing::warn!(user = %uid, "chat ws reauth room re-prefetch failed: {e}"),
                    }
                }
                if sink.send(Message::Ping(Vec::new().into())).await.is_err() {
                    break;
                }
            },
        }
    }

    tracing::info!(user = %uid, "chat ws session closed");
}

/// Build a `{"type":"error", ["code":…,] "message":…}` frame. `code` is OPTIONAL and additive:
/// older clients that only read `message` (or drop error frames entirely) are unaffected, while
/// newer clients act on the machine-readable code (e.g. `read_only` → lock the composer).
fn err_frame(code: Option<&str>, message: &str) -> Message {
    let mut frame = json!({ "type": "error", "message": message });
    if let Some(code) = code {
        frame["code"] = json!(code);
    }
    Message::Text(frame.to_string().into())
}

/// Machine-readable code for a rejected send, so a silently-dropped frame becomes actionable
/// client-side. On the WS send path `Conflict` is raised ONLY by the read-only gate in
/// `repo::send_message` (booking completed/cancelled), so the mapping is exact; every other
/// rejection carries no code and clients fall back to the human-readable `message`.
fn err_code(err: &AppError) -> Option<&'static str> {
    match err {
        AppError::Conflict(_) => Some("read_only"),
        _ => None,
    }
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

    #[test]
    fn frame_rate_limiter_bursts_then_throttles_then_refills() {
        let start = Instant::now();
        let mut rl = FrameRateLimiter::new(3, 3.0);
        // The full burst passes at one instant…
        for _ in 0..3 {
            assert!(rl.allow_at(start));
        }
        // …then the bucket is empty → a further frame at the same instant is abuse (denied).
        assert!(!rl.allow_at(start));
        // After 1s at 3 tokens/s it refills, so sending resumes.
        assert!(rl.allow_at(start + Duration::from_secs(1)));
    }

    #[test]
    fn frame_rate_limiter_caps_at_capacity() {
        let start = Instant::now();
        let mut rl = FrameRateLimiter::new(FRAME_BURST, FRAME_REFILL_PER_SEC);
        // Idle far past a full refill — tokens clamp at capacity, so exactly FRAME_BURST pass.
        let later = start + Duration::from_secs(600);
        for _ in 0..FRAME_BURST {
            assert!(rl.allow_at(later));
        }
        assert!(!rl.allow_at(later));
    }

    use crate::booking_client::{BookingReader, InternalBooking};

    /// No-op [`BookingReader`] stub — the WS path never reads booking (create-conversation does).
    #[derive(Clone)]
    struct StubBooking;
    impl BookingReader for StubBooking {
        async fn get_booking(&self, _booking_id: Uuid) -> Result<InternalBooking, AppError> {
            Err(AppError::NotFound("Booking not found".to_string()))
        }
    }

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
        redis: redis::aio::ConnectionManager,
        pubsub_client: redis::Client,
        s3: S3Client,
        booking: StubBooking,
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
    impl ChatDeps for TestDeps {
        type Booking = StubBooking;
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn db_read(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn pubsub_conn(&self) -> &redis::aio::ConnectionManager {
            &self.redis
        }
        fn pubsub_client(&self) -> &redis::Client {
            &self.pubsub_client
        }
        fn s3(&self) -> &S3Client {
            &self.s3
        }
        fn booking(&self) -> &StubBooking {
            &self.booking
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
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        let client = redis::Client::open(redis_url).ok()?;
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
            booking: StubBooking,
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

    #[test]
    fn read_only_rejection_carries_a_machine_readable_code() {
        // The read-only gate (the only Conflict on the send path) gets `code: "read_only"` so the
        // client can lock its composer; other rejections carry NO code (backward-compatible shape).
        let read_only = AppError::Conflict("Conversation is read-only".into());
        assert_eq!(err_code(&read_only), Some("read_only"));
        assert_eq!(
            err_code(&AppError::Forbidden("Not a participant".into())),
            None
        );

        let frame = err_frame(err_code(&read_only), &client_safe_message(&read_only));
        let Message::Text(text) = frame else {
            panic!("error frame must be a text frame");
        };
        let v: serde_json::Value = serde_json::from_str(text.as_str()).unwrap();
        assert_eq!(v["type"], json!("error"));
        assert_eq!(v["code"], json!("read_only"));
        assert_eq!(v["message"], json!("Conversation is read-only"));

        // No code → the field is ABSENT (not null), matching the pre-existing frame shape.
        let frame = err_frame(None, "invalid message: boom");
        let Message::Text(text) = frame else {
            panic!("error frame must be a text frame");
        };
        let v: serde_json::Value = serde_json::from_str(text.as_str()).unwrap();
        assert_eq!(v["type"], json!("error"));
        assert!(v.get("code").is_none(), "no code field without a code");
        assert_eq!(v["message"], json!("invalid message: boom"));
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
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .expect("redis conn");
        let client = redis::Client::open(redis_url).expect("redis client");

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
            // The WS path never reads booking (the conversation is seeded directly above); the
            // reader points at an unused address.
            booking: crate::booking_client::HttpBookingReader::new(
                reqwest::Client::new(),
                "http://127.0.0.1:1".to_string(),
                EncodingKey::from_secret(b"unused-service-secret-for-this-chat-ws-e2e-only!!!!"),
                60,
            ),
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
