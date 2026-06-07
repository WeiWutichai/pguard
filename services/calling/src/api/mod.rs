//! API layer — thin Axum transport handlers (REST call control) + the WS signaling module.
//! No business logic beyond authz gating + orchestration of the booking-reader (participant
//! verification), `domain` (pure state machine), and `repo` (atomic state writes + outbox).
//!
//! Handlers are generic over [`CallDeps`] so the `AuthUser` guard + authz are unit-testable
//! with a lightweight state (no live booking service), mirroring payment/rating.

pub mod ws;

use axum::extract::{Path, State};
use axum::Json;
use chrono::Utc;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;

use crate::booking_client::BookingReader;
use crate::domain::{is_callable_status, is_valid_call_type, peer_of};
use crate::models::{CallResponse, EndCallRequest, IceConfig, InitiateCallRequest};
use crate::repo;
use crate::state::CallDeps;

const DEFAULT_CALL_TYPE: &str = "audio";

/// POST /calls/initiate — start a call to the OTHER participant of a booking.
///
/// Authz (CLAUDE.md — never trust the client): the caller must be the booking's customer or
/// assigned guard (verified via booking's service-JWT'd internal read); the `callee` is
/// DERIVED as the other participant, never supplied by the client (no dialing strangers).
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, booking_id = %req.booking_id))]
pub async fn initiate_call<S: CallDeps>(
    State(state): State<S>,
    user: AuthUser,
    Json(req): Json<InitiateCallRequest>,
) -> Result<Json<ApiResponse<CallResponse>>, AppError> {
    let call_type = req.call_type.as_deref().unwrap_or(DEFAULT_CALL_TYPE);
    if !is_valid_call_type(call_type) {
        return Err(AppError::BadRequest(
            "call_type must be audio or video".to_string(),
        ));
    }

    // Authoritative participant check against the booking (never the request body).
    let booking = state.booking_reader().get_booking(req.booking_id).await?;
    // A call only makes sense during an active job (guard assigned, not done/cancelled).
    if !is_callable_status(&booking.status) {
        return Err(AppError::Conflict(
            "Booking is not in an active state for calling".to_string(),
        ));
    }
    let guard_id = booking
        .guard_id
        .ok_or_else(|| AppError::Conflict("Booking has no assigned guard to call".to_string()))?;
    // The callee is the OTHER participant; a non-participant caller has no peer → 403.
    let callee_id = peer_of(user.user_id, booking.customer_id, guard_id).ok_or_else(|| {
        AppError::Forbidden("You can only call within your own booking".to_string())
    })?;

    let call = repo::initiate(
        state.db(),
        user.user_id,
        callee_id,
        req.booking_id,
        call_type,
        Uuid::new_v4(),
    )
    .await?;
    Ok(Json(ApiResponse::success(call)))
}

/// GET /calls/{id} — fetch a call the caller participates in (or admin).
#[tracing::instrument(skip(state), fields(user = %user.user_id, call_id = %id))]
pub async fn get_call<S: CallDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<CallResponse>>, AppError> {
    let call = repo::get_call(state.db(), id).await?;
    if call.caller_id != user.user_id && call.callee_id != user.user_id && user.role != "admin" {
        return Err(AppError::Forbidden(
            "Not a participant in this call".to_string(),
        ));
    }
    Ok(Json(ApiResponse::success(call)))
}

/// PUT /calls/{id}/accept — the callee accepts (`initiated → accepted`). The SQL guard
/// enforces "only the callee, only while ringing" (a non-match → 404).
#[tracing::instrument(skip(state), fields(user = %user.user_id, call_id = %id))]
pub async fn accept_call<S: CallDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<CallResponse>>, AppError> {
    let call = repo::accept(state.db(), id, user.user_id, Uuid::new_v4()).await?;
    Ok(Json(ApiResponse::success(call)))
}

/// PUT /calls/{id}/reject — the callee declines (`initiated → rejected`).
#[tracing::instrument(skip(state), fields(user = %user.user_id, call_id = %id))]
pub async fn reject_call<S: CallDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<CallResponse>>, AppError> {
    let call = repo::reject(state.db(), id, user.user_id, Uuid::new_v4()).await?;
    Ok(Json(ApiResponse::success(call)))
}

/// PUT /calls/{id}/connected — either participant reports media flowing (`accepted →
/// connected`). A media milestone — no cross-service event.
#[tracing::instrument(skip(state), fields(user = %user.user_id, call_id = %id))]
pub async fn connected_call<S: CallDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<CallResponse>>, AppError> {
    let call = repo::mark_connected(state.db(), id, user.user_id).await?;
    Ok(Json(ApiResponse::success(call)))
}

/// PUT /calls/{id}/end — either participant ends (`→ ended`, or `→ missed` if never answered).
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, call_id = %id))]
pub async fn end_call<S: CallDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    req: Option<Json<EndCallRequest>>,
) -> Result<Json<ApiResponse<CallResponse>>, AppError> {
    let reason = req
        .and_then(|Json(r)| r.reason)
        .unwrap_or_else(|| "hangup".to_string());
    let call = repo::end(state.db(), id, user.user_id, &reason, Uuid::new_v4()).await?;
    Ok(Json(ApiResponse::success(call)))
}

/// GET /calls/ice — the ICE server list (STUN + short-lived per-caller HMAC TURN credentials) the
/// authenticated caller feeds into its `RTCPeerConnection`. Credentials are minted PER REQUEST,
/// time-boxed (`TurnConfig.ttl_secs`), and scoped to the caller's id — never static in the client,
/// never the raw coturn secret (CLAUDE.md: no long-lived shared credentials reach the device).
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn ice_config<S: CallDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<IceConfig>>, AppError> {
    let turn = state.turn();
    let cfg = IceConfig::build(
        &turn.stun_urls,
        &turn.turn_urls,
        turn.secret.as_deref(),
        &user.user_id.to_string(),
        Utc::now().timestamp(),
        turn.ttl_secs,
    );
    Ok(Json(ApiResponse::success(cfg)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::InternalBooking;
    use crate::state::{Registry, TurnConfig};
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::{get, post};
    use axum::Router;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use shared::auth::{encode_jwt_with_key, HasJwtSecret};
    use sqlx::postgres::PgPoolOptions;
    use std::collections::HashMap;
    use std::sync::Arc;
    use std::time::Duration;
    use tokio::sync::Mutex;
    use tower::ServiceExt;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-calling-test!!!!";

    #[derive(Clone)]
    struct StubReader {
        booking: Option<InternalBooking>,
    }
    impl BookingReader for StubReader {
        async fn get_booking(&self, _id: Uuid) -> Result<InternalBooking, AppError> {
            self.booking
                .clone()
                .ok_or_else(|| AppError::NotFound("Booking not found".to_string()))
        }
    }

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
        redis: redis::aio::MultiplexedConnection,
        reader: StubReader,
        registry: Registry,
        turn: TurnConfig,
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
    impl CallDeps for TestDeps {
        type Reader = StubReader;
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn booking_reader(&self) -> &StubReader {
            &self.reader
        }
        fn registry(&self) -> &Registry {
            &self.registry
        }
        fn turn(&self) -> &TurnConfig {
            &self.turn
        }
    }

    fn test_turn() -> TurnConfig {
        TurnConfig {
            secret: Some("test-turn-secret".to_string()),
            stun_urls: vec!["stun:stun.l.google.com:19302".to_string()],
            turn_urls: vec!["turn:turn.test:3478?transport=udp".to_string()],
            ttl_secs: 3600,
        }
    }

    async fn router(booking: Option<InternalBooking>) -> Option<Router> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = redis::Client::open(redis_url)
            .ok()?
            .get_multiplexed_tokio_connection()
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
            reader: StubReader { booking },
            registry: Arc::new(Mutex::new(HashMap::new())),
            turn: test_turn(),
        };
        Some(
            Router::new()
                .route("/calls/initiate", post(initiate_call::<TestDeps>))
                .route("/calls/ice", get(ice_config::<TestDeps>))
                .with_state(deps),
        )
    }

    fn token(user_id: Uuid, role: &str) -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _jti) = encode_jwt_with_key(user_id, role, 0, &ek, 15).unwrap();
        tok
    }

    fn initiate_body(booking_id: Uuid) -> Body {
        Body::from(
            serde_json::json!({ "booking_id": booking_id, "call_type": "audio" }).to_string(),
        )
    }

    async fn post_initiate(app: Router, tok: Option<&str>, booking_id: Uuid) -> StatusCode {
        let mut b = Request::builder()
            .method("POST")
            .uri("/calls/initiate")
            .header("content-type", "application/json");
        if let Some(t) = tok {
            b = b.header("authorization", format!("Bearer {t}"));
        }
        app.oneshot(b.body(initiate_body(booking_id)).unwrap())
            .await
            .unwrap()
            .status()
    }

    #[tokio::test]
    async fn initiate_rejects_missing_token() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(
            post_initiate(app, None, Uuid::new_v4()).await,
            StatusCode::UNAUTHORIZED
        );
    }

    #[tokio::test]
    async fn initiate_rejects_non_participant() {
        // The caller is authenticated but is neither the booking's customer nor its guard.
        let booking = InternalBooking {
            customer_id: Uuid::new_v4(),
            guard_id: Some(Uuid::new_v4()),
            status: "accepted".to_string(),
        };
        let Some(app) = router(Some(booking)).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = token(Uuid::new_v4(), "customer"); // a stranger
        assert_eq!(
            post_initiate(app, Some(&tok), Uuid::new_v4()).await,
            StatusCode::FORBIDDEN
        );
    }

    #[tokio::test]
    async fn initiate_rejects_unassigned_booking() {
        // Caller IS the customer, but the booking has no guard yet → 409 (no one to call).
        let me = Uuid::new_v4();
        let booking = InternalBooking {
            customer_id: me,
            guard_id: None,
            status: "requested".to_string(),
        };
        let Some(app) = router(Some(booking)).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = token(me, "customer");
        assert_eq!(
            post_initiate(app, Some(&tok), Uuid::new_v4()).await,
            StatusCode::CONFLICT
        );
    }

    #[tokio::test]
    async fn ice_config_serves_stun_and_short_lived_turn() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = token(Uuid::new_v4(), "customer");
        let req = Request::builder()
            .method("GET")
            .uri("/calls/ice")
            .header("authorization", format!("Bearer {tok}"))
            .body(Body::empty())
            .unwrap();
        let res = app.oneshot(req).await.unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        let servers = v["data"]["ice_servers"]
            .as_array()
            .expect("ice_servers array");
        assert!(
            servers.iter().any(|s| s["credential"].is_null()),
            "a STUN entry (no creds)"
        );
        let turn = servers
            .iter()
            .find(|s| s["credential"].is_string())
            .expect("a TURN entry with credentials");
        assert!(
            turn["username"].as_str().unwrap().contains(':'),
            "TURN username is <expiry>:<user>"
        );
        assert!(!turn["credential"].as_str().unwrap().is_empty());
        // The static coturn secret must NEVER reach the client.
        assert!(
            !String::from_utf8_lossy(&bytes).contains("test-turn-secret"),
            "the static auth secret must never be serialized"
        );
    }
}
