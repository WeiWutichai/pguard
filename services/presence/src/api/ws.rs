//! GPS-over-WebSocket ingress (`GET /ws/track`) — the core of the presence slice.
//!
//! It also carries the guard's **"พร้อมรับงาน" availability declaration**
//! (`{"type":"availability","available":bool}`), which is what makes them offerable to customers.
//! Availability rides on the SOCKET rather than a REST flag on purpose: intent must not outlive
//! the connection that declared it, or a killed app would leave a durable "available" behind for
//! the next session — one the app also opens merely to track an active job — to inherit. That
//! inheritance, in its original form (offerability keyed on "a GPS fix arrived"), is exactly the
//! defect this frame removes: streaming GPS for a job is not consent to be offered new work.
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

    // Per-connection session token: stamped on every upsert + fences the offline write so only
    // THIS session can mark its own row offline. A late-closing OLD socket (stale `session`) can
    // no longer clobber a freshly-reconnected live session offline (no more last-disconnect-wins).
    let session = Uuid::new_v4();

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
    // The guard's DECLARED "พร้อมรับงาน" intent for THIS session. Starts FALSE and only an
    // explicit `{"type":"availability","available":true}` frame turns it on: opening a GPS socket
    // must never, by itself, offer the guard to customers — that was the bug (the app also opens
    // this socket to track an active job, with the toggle off). Session-scoped by construction, so
    // a killed app leaves no durable "available" for the next session to inherit.
    let mut available = false;
    // Throttle clock for the `last_seen_at` session-liveness touch (see `touch_seen_if_due`).
    // Seeded "one interval ago" like the rate clocks so the FIRST inbound frame stamps liveness.
    let mut last_seen_write = seed
        .checked_sub(domain::SEEN_TOUCH_INTERVAL)
        .unwrap_or(seed);
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
                // SESSION liveness: a fix, a keep-alive, or a bare Pong all prove the socket is
                // still driven, so stamp `last_seen_at` (throttled). One place, every liveness
                // frame type — which is the point: the discovery offerable set expires on this
                // column, so a row whose service died stops being offered even though
                // `set_offline` (WS-task-only) never ran for it.
                //
                // Binary is excluded on the same grounds the reaper excludes it below: presence
                // speaks JSON text, so a client emitting only binary is not a working client and
                // must not be able to hold its row alive.
                if !matches!(msg, Message::Binary(_)) {
                    touch_seen_if_due(&db, guard_id, session, &mut last_seen_write).await;
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
                            session,
                            text.as_str(),
                            &mut last_gps,
                            &mut last_heartbeat,
                            &mut available,
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
    // Fenced on `session` — only THIS session can offline its own row, so a late close from a
    // superseded socket can never knock a live reconnect offline.
    if let Err(e) = repo::set_offline(&db, guard_id, session).await {
        tracing::error!(guard = %guard_id, "failed to set guard offline on disconnect: {e}");
    }
    tracing::info!(guard = %guard_id, "gps ws session closed");
}

/// Stamp SESSION liveness (`last_seen_at`) for this connection, at most once per
/// [`domain::SEEN_TOUCH_INTERVAL`]. Throttled because the discovery liveness window is minutes
/// wide while frames arrive by the second — one single-row UPDATE per live guard per 30s is
/// plenty to keep the row alive, and bounds the write amplification of the whole scheme.
///
/// Best-effort: a failed touch is logged, never fatal. Worst case the row ages out of the
/// offerable set and the next successful touch (or fix) restores it — the fail-safe direction.
async fn touch_seen_if_due(
    db: &sqlx::PgPool,
    guard_id: Uuid,
    session: Uuid,
    last_seen_write: &mut Instant,
) {
    if !domain::seen_touch_due(last_seen_write.elapsed()) {
        return;
    }
    *last_seen_write = Instant::now();
    if let Err(e) = repo::touch_seen(db, guard_id, session).await {
        tracing::warn!(guard = %guard_id, "failed to stamp gps ws session liveness: {e}");
    }
}

/// Handle one inbound text frame: classify, then run the keep-alive (rate-limited, NO DB), the
/// availability declaration, or the GPS pipeline (rate-limited, validate+sanitize, persist +
/// publish, ack). The heartbeat is gated on its OWN clock so it can never consume the GPS 1/sec
/// slot. `available` is the session's declared "พร้อมรับงาน" intent — read by the GPS path (every
/// fix re-asserts it) and written by the availability path.
#[allow(clippy::too_many_arguments)]
async fn handle_text(
    db: &sqlx::PgPool,
    redis_pub: &redis::aio::ConnectionManager,
    tx: &mpsc::UnboundedSender<Message>,
    guard_id: Uuid,
    session: Uuid,
    text: &str,
    last_gps: &mut Instant,
    last_heartbeat: &mut Instant,
    available: &mut bool,
) {
    match domain::classify(text) {
        Ok(ClientFrame::Heartbeat) => {
            // Keep-alive only: rate-limit to 1/10s and drop excess. NEVER touches the GPS
            // clock, recorded_at, or is_online. (Session liveness was already stamped by the
            // caller for this frame — that is the keep-alive's whole job now.)
            if domain::rate_allows(last_heartbeat.elapsed(), domain::HEARTBEAT_MIN_INTERVAL) {
                *last_heartbeat = Instant::now();
            }
        }
        Ok(ClientFrame::Availability(next)) => {
            // The guard flipped "พร้อมรับงาน". Record it for the session AND push it to the row
            // now, so toggling OFF removes the guard from discovery immediately rather than at the
            // next fix — a guard tracking a stationary job may not send one for 90s, and every one
            // of those seconds is a customer able to book someone who said they were done.
            //
            // NOT rate-limited: this is a user-intent edge, not a stream. The pre-parse frame-flood
            // ceiling already bounds abuse, and dropping a toggle would leave the row lying about
            // the guard. Unchanged value → still written (cheap, idempotent, and it re-asserts
            // intent if a previous write raced a session takeover).
            *available = next;
            if let Err(e) = repo::set_availability(db, guard_id, session, next).await {
                tracing::error!(guard = %guard_id, available = next, "failed to record availability: {e}");
                let _ = tx.send(error_frame("could not record availability; retry"));
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
                // The fix re-asserts the session's DECLARED availability, which is what keeps a
                // PREVIOUS session's stale `true` from surviving: a socket opened by a job-
                // tracking lease alone declares nothing, so its first fix writes `false`.
                repo::upsert_location(db, guard_id, session, recorded_at, *available, &clean),
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

    /// Bind a REAL presence server (the WS route only) on an ephemeral port against a REAL
    /// Postgres + Redis, returning the pool, its address, and the serve task. `None` when the
    /// backing services are absent (callers SKIP) — keeps `cargo test` offline-safe.
    /// Gated on DATABASE_URL (migrated: presence 0001-0005) + TEST_REDIS_URL.
    async fn e2e_server() -> Option<(
        sqlx::PgPool,
        std::net::SocketAddr,
        tokio::task::JoinHandle<()>,
    )> {
        use crate::state::{AppState, DbBookingAuthz};
        use shared::config::{JwtConfig, ServiceJwtConfig};

        let db_url = std::env::var("DATABASE_URL").ok()?;
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&db_url)
            .await
            .expect("connect Postgres");
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .expect("redis conn");

        let jwt_config = JwtConfig {
            secret: SECRET.to_string(),
            expiry_minutes: 15,
            encoding_key: EncodingKey::from_secret(SECRET.as_bytes()),
            decoding_key: DecodingKey::from_secret(SECRET.as_bytes()),
        };
        // The WS e2e path never validates a service-JWT; a throwaway key satisfies the field.
        let service_jwt_config = ServiceJwtConfig {
            encoding_key: EncodingKey::from_secret(SECRET.as_bytes()),
            decoding_key: DecodingKey::from_secret(SECRET.as_bytes()),
            ttl_secs: 60,
        };
        let state = AppState {
            db: db.clone(),
            db_read: db.clone(),
            redis_cache: redis.clone(),
            redis_pub: redis,
            jwt_config,
            service_jwt_config,
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
        Some((db, addr, server))
    }

    /// Open a REAL guard WS session against [`e2e_server`] (Bearer on the upgrade, as production).
    async fn e2e_connect(
        addr: std::net::SocketAddr,
        guard_id: Uuid,
    ) -> tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>
    {
        use tokio_tungstenite::tungstenite::client::IntoClientRequest;

        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let tok = encode_jwt_with_key(guard_id, "guard", 0, &ek, 15)
            .unwrap()
            .0;
        let mut req = format!("ws://{addr}/ws/track")
            .into_client_request()
            .unwrap();
        req.headers_mut()
            .insert("Authorization", format!("Bearer {tok}").parse().unwrap());
        let (ws, _) = tokio_tungstenite::connect_async(req)
            .await
            .expect("ws connect");
        ws
    }

    /// END-TO-END over a REAL bound server + a REAL WS client (Bearer on upgrade): a guard
    /// sends a valid fix → gets an `ack` with a persisted `recorded_at` + the guard is online;
    /// a `(0,0)` fix → `error` frame (socket stays open); on close the guard is set offline.
    /// Run:
    ///   DATABASE_URL=... TEST_REDIS_URL=... cargo test -p pguard-presence -- ws_gps_e2e --nocapture
    #[tokio::test]
    async fn ws_gps_e2e_ack_validate_and_offline_on_close() {
        use tokio_tungstenite::tungstenite::Message as TMessage;

        let Some((db, addr, server)) = e2e_server().await else {
            eprintln!("SKIP: DATABASE_URL + TEST_REDIS_URL required for the gps ws e2e");
            return;
        };
        let guard_id = Uuid::new_v4();
        let mut ws = e2e_connect(addr, guard_id).await;

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

    /// END-TO-END proof of the QA 08/09/2569 rule over a REAL socket, exercised exactly the way
    /// the mobile app drives it: *"Guard ที่ยังไม่ได้เปิด Online Status ต้องไม่แสดงอยู่ในหน้าเลือก
    /// Guard ให้ Customer เลือก"*.
    ///
    /// The sequence IS the bug report. A guard opens tracking for an active job with the toggle
    /// off (the app opens this same socket for `online || jobIds.isNotEmpty`), streams GPS, and
    /// must stay out of `online_guard_locations` the whole time. Only the explicit declaration
    /// puts them in, and taking it back — or dropping the socket — takes them out again.
    #[tokio::test]
    async fn ws_availability_e2e_gates_the_customers_guard_list() {
        use tokio_tungstenite::tungstenite::Message as TMessage;

        let Some((db, addr, server)) = e2e_server().await else {
            eprintln!("SKIP: DATABASE_URL + TEST_REDIS_URL required for the availability ws e2e");
            return;
        };
        let guard_id = Uuid::new_v4();
        let mut ws = e2e_connect(addr, guard_id).await;

        // The offerable set as booking's discovery reads it, at this instant.
        let offered = |db: sqlx::PgPool| async move {
            repo::online_guard_locations(&db, domain::session_liveness_cutoff(Utc::now()))
                .await
                .expect("offerable set")
                .iter()
                .any(|(id, _, _)| *id == guard_id)
        };

        // 1) Streaming GPS with the toggle OFF (job tracking) — connected, but NOT for sale.
        ws.send(TMessage::Text(
            json!({ "type": "location", "lat": 13.7563, "lng": 100.5018 }).to_string(),
        ))
        .await
        .unwrap();
        assert_eq!(next_json(&mut ws).await["type"], json!("ack"));
        let row = repo::latest_location(&db, guard_id).await.expect("latest");
        assert!(row.is_online, "the guard IS connected (the live map works)");
        assert!(
            !offered(db.clone()).await,
            "a guard who never switched Online Status on must NOT be in the customer's list, \
             even while streaming GPS"
        );

        // 2) Guard taps "พร้อมรับงาน" → offerable, with NO new fix needed.
        ws.send(TMessage::Text(
            json!({ "type": "availability", "available": true }).to_string(),
        ))
        .await
        .unwrap();
        wait_until(
            || offered(db.clone()),
            "declaring availability offers the guard",
        )
        .await;

        // 3) Guard taps it off → out of the list at once, while still connected + streaming.
        ws.send(TMessage::Text(
            json!({ "type": "availability", "available": false }).to_string(),
        ))
        .await
        .unwrap();
        wait_until(
            || {
                let db = db.clone();
                async move { !offered(db).await }
            },
            "withdrawing availability removes the guard immediately",
        )
        .await;
        assert!(
            repo::latest_location(&db, guard_id)
                .await
                .expect("latest")
                .is_online,
            "withdrawing the offer must not disconnect the guard"
        );

        // 4) Declared available, then the socket drops → the declaration dies with the session,
        //    so a LATER session (one a job-tracking lease opens) cannot inherit it.
        ws.send(TMessage::Text(
            json!({ "type": "availability", "available": true }).to_string(),
        ))
        .await
        .unwrap();
        wait_until(|| offered(db.clone()), "available again before the drop").await;
        ws.close(None).await.unwrap();
        wait_until(
            || {
                let db = db.clone();
                async move { !offered(db).await }
            },
            "a disconnect removes the guard from the customer's list",
        )
        .await;
        let row = repo::latest_location(&db, guard_id).await.expect("latest");
        assert!(!row.is_online, "disconnect sets offline");
        assert!(
            !row.available_for_work,
            "disconnect also revokes the declaration — nothing durable is left to inherit"
        );

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

    /// Poll `cond` until it holds, or fail with `what`. The WS session applies a frame
    /// asynchronously (the client gets no ack for an availability declaration), so the test must
    /// wait for the write rather than race it — bounded at ~5s so a real regression still fails
    /// fast instead of hanging.
    async fn wait_until<F, Fut>(mut cond: F, what: &str)
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = bool>,
    {
        for _ in 0..50 {
            if cond().await {
                return;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        panic!("timed out waiting: {what}");
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
