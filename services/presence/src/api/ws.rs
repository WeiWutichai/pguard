//! GPS-over-WebSocket ingress (`GET /ws/track`) — the core of the presence slice.
//!
//! Auth mirrors `/ws/call`: **Bearer in the `Authorization` header on upgrade** (the `AuthUser`
//! extractor runs before the upgrade; a token only in the URL query is NEVER read → 401). On
//! top of that, presence applies a **role gate before the upgrade**: only a `guard` may stream
//! GPS (admin/customer ingest → 403). After open, the guard streams bare `GpsUpdate` JSON
//! frames; the server validates + sanitizes each (domain), rate-limits to 1/sec, upserts the
//! current position + appends history + republishes the raw fix to Redis pub/sub for the admin
//! map, and acks. A 30s/10s ping-pong reaper closes zombie sockets; ANY disconnect marks the
//! guard offline. Keep-alives (pong, `{"type":"heartbeat"}`) never advance freshness/online.
//!
//! Session shape mirrors `services/calling/src/api/ws.rs`: split sink/stream + an mpsc outbound
//! conduit drained by the `select!` loop. (Unlike calling there is no cross-socket peer relay —
//! raw GPS fans out via Redis, not back through the WS — so there is no shared registry; the
//! mpsc is this session's single outbound path.)
//!
//! Deferred (tracked, NOT in this slice's spec scope): (1) append-only `audit.gps_updates`
//! ingestion trail for GPS-fraud non-repudiation (v1 audit risk #6 — a cross-cutting audit
//! workstream, separate from `location_history` which is the operational store); (2) a
//! pre-parse inbound frame-rate ceiling that closes egregiously-abusive sockets (the 1/sec
//! limit runs after parse; the frame-size cap below bounds per-frame memory in the meantime).

use std::time::Instant;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{FromRequestParts, State};
use axum::http::request::Parts;
use axum::http::HeaderMap;
use axum::response::Response;
use chrono::{DateTime, Utc};
use futures::{SinkExt, StreamExt};
use jsonwebtoken::DecodingKey;
use serde_json::json;
use tokio::sync::mpsc;
use uuid::Uuid;

use shared::auth::{
    authenticate_token, extract_cookie_value, AuthUser, HasJwtSecret, ACCESS_TOKEN_COOKIE,
};
use shared::error::AppError;

use crate::domain::{self, ClientFrame};
use crate::events;
use crate::models::GpsEvent;
use crate::repo;
use crate::state::PresenceDeps;

/// How often a live GPS session re-validates its access token — catches expiry, a force-revoke-
/// all, and a per-jti revoke. Access tokens are short-lived (≤15 min), so this bounds how long a
/// revoked/expired socket can keep streaming.
const REAUTH_INTERVAL: std::time::Duration = std::time::Duration::from_secs(60);

/// Cap on a single WS message/frame. A GPS fix is < 1 KB; 16 KB is generous slack. This bounds
/// the per-frame allocation so a (authenticated) client can't push axum/tungstenite's 64 MiB
/// default into a `String` — a memory-DoS the 1/sec rate limit (which runs AFTER parse) would
/// not catch.
const MAX_WS_MESSAGE_BYTES: usize = 16 * 1024;

/// `AuthUser` narrowed to the `guard` role, captured WITH the raw token (for WS re-auth).
///
/// This is a SEPARATE extractor placed BEFORE `WebSocketUpgrade` on purpose: an unauthenticated
/// caller is rejected 401 and a non-guard 403 during EXTRACTION — before any upgrade machinery
/// runs — so a forbidden caller always gets a clean 401/403, never an upgrade-mechanics status
/// (e.g. 426). Admin/customer GPS ingest is forbidden. Bearer/cookie only (the `AuthUser`
/// extractor never reads the URL query → a query-only token is 401).
pub struct GuardOnly {
    guard_id: Uuid,
    token: Option<String>,
}

impl<S> FromRequestParts<S> for GuardOnly
where
    S: Send + Sync + HasJwtSecret,
{
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let user = AuthUser::from_request_parts(parts, state).await?;
        if user.role != "guard" {
            return Err(AppError::Forbidden(
                "Only guards may stream GPS".to_string(),
            ));
        }
        Ok(GuardOnly {
            guard_id: user.user_id,
            token: token_from_headers(&parts.headers),
        })
    }
}

/// GET /ws/track — gate on the guard role (via [`GuardOnly`], before the upgrade), then run the
/// GPS session. A missing/URL-only token → 401 and a non-guard → 403, both during extraction.
pub async fn ws_track<S: PresenceDeps>(
    GuardOnly { guard_id, token }: GuardOnly,
    ws: WebSocketUpgrade,
    State(state): State<S>,
) -> Response {
    let db = state.db().clone();
    let redis_pub = state.redis_pub().clone();
    let redis_cache = state.redis_conn().clone();
    let decoding_key = state.decoding_key().clone();
    // Bound per-frame size — a GPS fix is tiny; reject oversized frames before they allocate.
    let ws = ws
        .max_message_size(MAX_WS_MESSAGE_BYTES)
        .max_frame_size(MAX_WS_MESSAGE_BYTES);
    ws.on_upgrade(move |socket| {
        session(
            socket,
            guard_id,
            token,
            db,
            redis_pub,
            redis_cache,
            decoding_key,
        )
    })
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

/// Drive one authenticated guard GPS session: accept fixes (validated, rate-limited, persisted,
/// republished), keep the socket alive with a ping-pong reaper, periodically re-validate the
/// token, and mark the guard offline on ANY exit.
#[allow(clippy::too_many_arguments)]
async fn session(
    socket: WebSocket,
    guard_id: Uuid,
    token: Option<String>,
    db: sqlx::PgPool,
    redis_pub: redis::aio::ConnectionManager,
    redis_cache: redis::aio::ConnectionManager,
    decoding_key: DecodingKey,
) {
    let (mut sink, mut stream) = socket.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();

    // Rate-limit clocks: seed "one interval ago" so the FIRST fix/heartbeat is always allowed.
    // `checked_sub` (not `-`) avoids a panic if the host's monotonic clock is younger than the
    // interval — a guard connecting within ~10s of system boot. The `unwrap_or(seed)` fallback is
    // unreachable in practice (a server is not accepting connections that early) and at worst
    // rate-limits the very first frame for one interval.
    let seed = Instant::now();
    let mut last_gps = seed.checked_sub(domain::GPS_MIN_INTERVAL).unwrap_or(seed);
    let mut last_heartbeat = seed
        .checked_sub(domain::HEARTBEAT_MIN_INTERVAL)
        .unwrap_or(seed);
    // Ping-pong reaper state.
    let mut last_activity = Instant::now();
    let mut ping_sent_at: Option<Instant> = None;
    // Inbound frame-flood backstop (v1 audit risk #13): count ALL inbound frames in a rolling 1s
    // window and close as abusive past the ceiling. The per-second GPS gate + heartbeat gate run
    // AFTER parse, so they do not bound a flood of junk/parse-fail frames.
    let mut frame_window = Instant::now();
    let mut frames_in_window: u32 = 0;

    let mut reauth = tokio::time::interval(REAUTH_INTERVAL);
    reauth.tick().await; // consume the immediate first tick

    tracing::info!(guard = %guard_id, "gps ws session open");

    loop {
        // Dynamic ping/pong deadline (mirrors v1 tracking handlers.rs:69-75).
        let wait = domain::ping_wait(ping_sent_at.map(|t| t.elapsed()), last_activity.elapsed());
        let tick = tokio::time::sleep(wait);
        tokio::pin!(tick);

        tokio::select! {
            // Outbound: drain the session's ack/error/ping frames to the socket.
            outgoing = rx.recv() => match outgoing {
                Some(msg) => {
                    if sink.send(msg).await.is_err() {
                        break;
                    }
                }
                None => break,
            },
            // Inbound: a frame from the guard.
            incoming = stream.next() => {
                // Stream end / recv error → close (nothing to count).
                let msg = match incoming {
                    Some(Ok(m)) => m,
                    Some(Err(e)) => {
                        tracing::warn!(guard = %guard_id, "gps ws recv error: {e}");
                        break;
                    }
                    None => break,
                };
                // Frame-flood backstop: count EVERY inbound frame (any type, before parse) in a
                // rolling 1s window; close as abusive past the ceiling (v1 audit risk #13). This
                // runs before classify so a flood of junk/parse-fail frames can't burn CPU.
                if frame_window.elapsed() >= std::time::Duration::from_secs(1) {
                    frame_window = Instant::now();
                    frames_in_window = 0;
                }
                frames_in_window += 1;
                if domain::frame_flood(frames_in_window) {
                    tracing::warn!(guard = %guard_id, "gps ws inbound frame flood; closing as abusive");
                    break;
                }
                match msg {
                    Message::Text(text) => {
                        last_activity = Instant::now();
                        ping_sent_at = None; // any data proves liveness
                        handle_text(
                            &db,
                            &redis_pub,
                            &tx,
                            guard_id,
                            text.as_str(),
                            &mut last_gps,
                            &mut last_heartbeat,
                        )
                        .await;
                    }
                    Message::Pong(_) => {
                        // Liveness ONLY — must NOT touch recorded_at and must NOT set online
                        // (else a guard who lost GPS but holds the socket stays falsely green).
                        last_activity = Instant::now();
                        ping_sent_at = None;
                    }
                    Message::Ping(_) => {
                        // Client-initiated ping (axum auto-replies Pong); count as activity.
                        last_activity = Instant::now();
                    }
                    // presence speaks JSON text only — binary is ignored AND deliberately not
                    // counted as liveness (a client streaming only binary is reaped as a zombie).
                    Message::Binary(_) => {}
                    Message::Close(_) => break,
                }
            },
            // Ping-pong reaper: send a ping when idle; close as a zombie if a pong is overdue.
            _ = &mut tick => {
                match ping_sent_at {
                    Some(sent) if sent.elapsed() >= domain::PONG_TIMEOUT => {
                        tracing::warn!(guard = %guard_id, "gps ws pong timeout (zombie); closing");
                        break;
                    }
                    Some(_) => { /* still within the pong window — recompute + keep waiting */ }
                    None => {
                        if tx.send(Message::Ping(Vec::new().into())).is_err() {
                            break;
                        }
                        ping_sent_at = Some(Instant::now());
                    }
                }
            },
            // Periodic re-auth: close if the token expired or was revoked (an open GPS socket
            // must not outlive its access token).
            _ = reauth.tick() => {
                if let Some(t) = &token {
                    if authenticate_token(t, &decoding_key, &redis_cache).await.is_err() {
                        tracing::info!(guard = %guard_id, "gps ws token expired/revoked; closing");
                        let _ = sink.send(Message::Close(None)).await;
                        break;
                    }
                }
            },
        }
    }

    // Disconnect (any cause): mark the guard offline so discovery/the map drop them immediately.
    if let Err(e) = repo::set_offline(&db, guard_id).await {
        tracing::error!(guard = %guard_id, "failed to set guard offline on disconnect: {e}");
    }
    tracing::info!(guard = %guard_id, "gps ws session closed");
}

/// Handle one inbound text frame: classify, then either run the heartbeat keep-alive (rate-
/// limited, NO DB) or the GPS pipeline (rate-limited, validate+sanitize, persist + publish,
/// ack). The heartbeat is gated on its OWN clock so it can never consume the GPS 1/sec slot.
async fn handle_text(
    db: &sqlx::PgPool,
    redis_pub: &redis::aio::ConnectionManager,
    tx: &mpsc::UnboundedSender<Message>,
    guard_id: Uuid,
    text: &str,
    last_gps: &mut Instant,
    last_heartbeat: &mut Instant,
) {
    match domain::classify(text) {
        Ok(ClientFrame::Heartbeat) => {
            // Keep-alive only: rate-limit to 1/10s and drop excess. NEVER touches the GPS
            // clock, recorded_at, or is_online.
            if domain::rate_allows(last_heartbeat.elapsed(), domain::HEARTBEAT_MIN_INTERVAL) {
                *last_heartbeat = Instant::now();
            }
        }
        Ok(ClientFrame::Gps(update)) => {
            // Server rate limit: drop fixes that arrive faster than 1/sec (silently).
            if !domain::rate_allows(last_gps.elapsed(), domain::GPS_MIN_INTERVAL) {
                return;
            }
            *last_gps = Instant::now();

            let clean = match update.validated() {
                Ok(c) => c,
                Err(e) => {
                    let _ = tx.send(error_frame(e));
                    return;
                }
            };

            // One server timestamp for the live row, the history row, and the ack — all consistent.
            let recorded_at = Utc::now();
            let event = GpsEvent {
                guard_id,
                lat: clean.lat,
                lng: clean.lng,
                accuracy: clean.accuracy,
                heading: clean.heading,
                speed: clean.speed,
                recorded_at,
            };

            // Independent writes run concurrently (mirrors v1 tracking handlers.rs:172).
            let (upsert_res, history_res, publish_res) = tokio::join!(
                repo::upsert_location(db, guard_id, recorded_at, &clean),
                repo::insert_history(db, guard_id, recorded_at, &clean),
                events::publish_gps(redis_pub, &event),
            );

            if let Err(e) = upsert_res {
                // The live position is the source of truth for the ack — if it failed, do NOT
                // ack a recorded_at that was never persisted.
                tracing::error!(guard = %guard_id, "upsert_location failed: {e}");
                return;
            }
            if let Err(e) = history_res {
                tracing::warn!(guard = %guard_id, "insert_history failed: {e}");
            }
            if let Err(e) = publish_res {
                // Redis publish failure = log-and-continue: the DB write already succeeded and
                // the next fix re-publishes.
                tracing::warn!(guard = %guard_id, "gps publish failed (log-and-continue): {e}");
            }

            let _ = tx.send(ack_frame(recorded_at));
        }
        Err(e) => {
            // Unparseable / non-GPS frame — keep the detailed serde reason in the server log only
            // and reply with a GENERIC message (no internal deserialization detail on the wire —
            // §9 generic errors). The socket stays open. (Coordinate-validation messages such as
            // "(0,0) is rejected" are intentional, fixed strings sent from the Gps arm above.)
            tracing::debug!(guard = %guard_id, "rejected unparseable gps frame: {e}");
            let _ = tx.send(error_frame("invalid frame"));
        }
    }
}

/// `{ "type": "ack", "recorded_at": <ts> }` — sent only after a real upsert (non-null ts).
fn ack_frame(recorded_at: DateTime<Utc>) -> Message {
    Message::Text(
        json!({ "type": "ack", "recorded_at": recorded_at })
            .to_string()
            .into(),
    )
}

/// `{ "type": "error", "message": <reason> }` for a rejected/invalid update.
fn error_frame(message: &str) -> Message {
    Message::Text(
        json!({ "type": "error", "message": message })
            .to_string()
            .into(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::{BookingAuthz, PresenceDeps};
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

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-presencews-test!!!";

    #[derive(Clone)]
    struct StubAuthz;
    impl BookingAuthz for StubAuthz {
        async fn has_active_booking(&self, _c: Uuid, _g: Uuid) -> Result<bool, AppError> {
            Ok(false)
        }
    }

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
        redis: redis::aio::ConnectionManager,
        authz: StubAuthz,
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
    impl PresenceDeps for TestDeps {
        type Authz = StubAuthz;
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn booking_authz(&self) -> &StubAuthz {
            &self.authz
        }
        fn redis_pub(&self) -> &redis::aio::ConnectionManager {
            &self.redis
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
            authz: StubAuthz,
        };
        Some(
            Router::new()
                .route("/ws/track", get(ws_track::<TestDeps>))
                .with_state(deps),
        )
    }

    fn token(role: &str) -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        encode_jwt_with_key(Uuid::new_v4(), role, 0, &ek, 15)
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

    #[tokio::test]
    async fn upgrade_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app.oneshot(upgrade_req("/ws/track", None)).await.unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn upgrade_rejects_token_in_url_query() {
        // The token ONLY in the query string is never read → 401 (no sensitive data in the URL).
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let uri = format!("/ws/track?token={}", token("guard"));
        let res = app.oneshot(upgrade_req(&uri, None)).await.unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn upgrade_rejects_non_guard_role() {
        // A VALID customer token is authenticated but not authorized to stream GPS → 403.
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(upgrade_req("/ws/track", Some(&token("customer"))))
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
        // admin is also forbidden from ingest.
        let Some(app) = router().await else { return };
        let res = app
            .oneshot(upgrade_req("/ws/track", Some(&token("admin"))))
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn upgrade_accepts_guard_bearer() {
        // A valid guard Bearer passes the auth + role gate (NOT 401/403). The 101 switch needs a
        // real upgradeable connection; via `oneshot` we assert the gate was passed.
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(upgrade_req("/ws/track", Some(&token("guard"))))
            .await
            .unwrap();
        assert_ne!(res.status(), StatusCode::UNAUTHORIZED);
        assert_ne!(
            res.status(),
            StatusCode::FORBIDDEN,
            "a valid guard Bearer must pass the upgrade gate"
        );
    }

    /// END-TO-END over a REAL bound server + a REAL WS client (Bearer on upgrade): a guard
    /// sends a valid fix → gets an `ack` with a persisted `recorded_at` + the guard is online;
    /// a `(0,0)` fix → `error` frame (socket stays open); on close the guard is set offline.
    /// Gated on DATABASE_URL (migrated: presence 0001/0002) + TEST_REDIS_URL. Run:
    ///   DATABASE_URL=... TEST_REDIS_URL=... cargo test -p pguard-presence -- ws_gps_e2e --nocapture
    #[tokio::test]
    async fn ws_gps_e2e_ack_validate_and_offline_on_close() {
        use crate::state::{AppState, DbBookingAuthz};
        use shared::config::JwtConfig;
        use tokio_tungstenite::tungstenite::client::IntoClientRequest;
        use tokio_tungstenite::tungstenite::Message as TMessage;

        let (Ok(db_url), Ok(redis_url)) = (
            std::env::var("DATABASE_URL"),
            std::env::var("TEST_REDIS_URL").or_else(|_| std::env::var("REDIS_CACHE_URL")),
        ) else {
            eprintln!("SKIP: DATABASE_URL + TEST_REDIS_URL required for the gps ws e2e");
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

        let guard_id = Uuid::new_v4();
        let jwt_config = JwtConfig {
            secret: SECRET.to_string(),
            expiry_minutes: 15,
            encoding_key: EncodingKey::from_secret(SECRET.as_bytes()),
            decoding_key: DecodingKey::from_secret(SECRET.as_bytes()),
        };
        let state = AppState {
            db: db.clone(),
            redis_cache: redis.clone(),
            redis_pub: redis,
            jwt_config,
            booking_authz: DbBookingAuthz { db: db.clone() },
        };
        let app = Router::new()
            .route("/ws/track", get(ws_track::<AppState>))
            .with_state(state);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let _ = axum::serve(listener, app).await;
        });

        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let tok = encode_jwt_with_key(guard_id, "guard", 0, &ek, 15)
            .unwrap()
            .0;
        let mut req = format!("ws://{addr}/ws/track")
            .into_client_request()
            .unwrap();
        req.headers_mut()
            .insert("Authorization", format!("Bearer {tok}").parse().unwrap());
        let (mut ws, _) = tokio_tungstenite::connect_async(req)
            .await
            .expect("ws connect");

        // 1) valid fix → ack with a recorded_at.
        ws.send(TMessage::Text(
            json!({ "lat": 13.7563, "lng": 100.5018, "accuracy": 9.0 }).to_string(),
        ))
        .await
        .unwrap();
        let ack = next_json(&mut ws).await;
        assert_eq!(ack["type"], json!("ack"));
        assert!(ack["recorded_at"].is_string(), "ack carries a recorded_at");

        // guard is now online.
        let row = repo::latest_location(&db, guard_id).await.expect("latest");
        assert!(row.is_online);
        assert_eq!(row.lat, 13.7563);

        // 2) a SECOND valid fix sent immediately is DROPPED by the 1/sec rate gate — no ack
        // arrives within the window (the drop is silent, by spec).
        ws.send(TMessage::Text(
            json!({ "lat": 13.7600, "lng": 100.5100 }).to_string(),
        ))
        .await
        .unwrap();
        let dropped = tokio::time::timeout(Duration::from_millis(800), next_json(&mut ws)).await;
        assert!(
            dropped.is_err(),
            "a fix sent <1s after the previous must be dropped (no ack)"
        );

        // 3) null-island fix → error frame, socket stays open. Wait out the 1/sec gate first so
        // the fix reaches validation (a dropped fix never updates the rate clock).
        tokio::time::sleep(Duration::from_millis(1100)).await;
        ws.send(TMessage::Text(
            json!({ "lat": 0.0, "lng": 0.0 }).to_string(),
        ))
        .await
        .unwrap();
        let err = next_json(&mut ws).await;
        assert_eq!(err["type"], json!("error"));

        // 4) close → guard set offline.
        ws.close(None).await.unwrap();
        let mut offline = false;
        for _ in 0..50 {
            if let Ok(r) = repo::latest_location(&db, guard_id).await {
                if !r.is_online {
                    offline = true;
                    break;
                }
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        assert!(offline, "disconnect must set the guard offline");

        // teardown
        let _ = sqlx::query("DELETE FROM presence.guard_locations WHERE guard_id = $1")
            .bind(guard_id)
            .execute(&db)
            .await;
        let _ = sqlx::query("DELETE FROM presence.location_history WHERE user_id = $1")
            .bind(guard_id)
            .execute(&db)
            .await;
        server.abort();
    }

    #[cfg(test)]
    async fn next_json(
        ws: &mut tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
    ) -> serde_json::Value {
        loop {
            let msg = tokio::time::timeout(std::time::Duration::from_secs(3), ws.next())
                .await
                .expect("frame within timeout")
                .expect("stream item")
                .expect("ws message");
            if let tokio_tungstenite::tungstenite::Message::Text(t) = msg {
                return serde_json::from_str(&t).expect("json frame");
            }
            // ignore server pings/pongs
        }
    }
}
