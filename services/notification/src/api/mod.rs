//! API layer — thin Axum transport handlers. No business logic beyond role gating
//! and orchestration of `repo` + the [`Pusher`] port.

use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::Json;
use chrono::Utc;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;
use shared::service_jwt::ServiceCaller;

use crate::fcm::{PushMessage, Pusher};
use crate::models::{
    Audience, AudienceCountsResponse, BroadcastMode, BroadcastResponse, BroadcastStatus,
    CreateBroadcastRequest, DeleteTokenRequest, ListBroadcastsQuery, ListNotificationsQuery,
    NotificationLogResponse, NotificationType, RegisterTokenRequest, RoleQuery,
    SendNotificationRequest, UnreadCountResponse, UpdateBroadcastRequest,
};
use crate::repo;
use crate::state::{AppState, InternalPushDeps};

/// Require the admin role (broadcasts are admin-only — explicit backend gate, never
/// frontend-only; carried from the v1 audit).
fn require_admin(user: &AuthUser) -> Result<(), AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "Only admins can manage broadcasts".to_string(),
        ));
    }
    Ok(())
}

/// Fetch the recipient's device tokens and fan out a push (best-effort).
async fn deliver(
    db: &sqlx::PgPool,
    pusher: &Arc<dyn Pusher>,
    user_id: Uuid,
    title: &str,
    body: &str,
    data: serde_json::Value,
) -> Result<(), AppError> {
    let tokens = repo::user_tokens(db, user_id).await?;
    pusher
        .push(&PushMessage {
            tokens,
            title: title.to_string(),
            body: body.to_string(),
            data,
        })
        .await
}

// ----- FCM tokens -----

pub async fn register_token(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<RegisterTokenRequest>,
) -> Result<Json<ApiResponse<()>>, AppError> {
    repo::register_token(&state.db, user.user_id, &req.token, &req.device_type).await?;
    Ok(Json(ApiResponse::success(())))
}

pub async fn unregister_token(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<DeleteTokenRequest>,
) -> Result<Json<ApiResponse<()>>, AppError> {
    repo::unregister_token(&state.db, user.user_id, &req.token).await?;
    Ok(Json(ApiResponse::success(())))
}

// ----- Notifications -----

pub async fn list_notifications(
    State(state): State<AppState>,
    user: AuthUser,
    Query(query): Query<ListNotificationsQuery>,
) -> Result<Json<ApiResponse<Vec<NotificationLogResponse>>>, AppError> {
    let items = repo::list_notifications(&state.db, user.user_id, &query).await?;
    Ok(Json(ApiResponse::success(items)))
}

pub async fn unread_count(
    State(state): State<AppState>,
    user: AuthUser,
    Query(query): Query<RoleQuery>,
) -> Result<Json<ApiResponse<UnreadCountResponse>>, AppError> {
    let count = repo::unread_count(&state.db, user.user_id, query.role.as_deref()).await?;
    Ok(Json(ApiResponse::success(UnreadCountResponse { count })))
}

pub async fn mark_all_as_read(
    State(state): State<AppState>,
    user: AuthUser,
    Query(query): Query<RoleQuery>,
) -> Result<Json<ApiResponse<UnreadCountResponse>>, AppError> {
    let count = repo::mark_all_as_read(&state.db, user.user_id, query.role.as_deref()).await?;
    Ok(Json(ApiResponse::success(UnreadCountResponse { count })))
}

pub async fn mark_as_read(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<NotificationLogResponse>>, AppError> {
    let item = repo::mark_as_read(&state.db, id, user.user_id).await?;
    Ok(Json(ApiResponse::success(item)))
}

/// Admin-only send. Role gating is enforced here (carried from the v1 audit: explicit
/// backend role checks, never frontend-only).
pub async fn send_notification(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<SendNotificationRequest>,
) -> Result<Json<ApiResponse<NotificationLogResponse>>, AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "Only admins can send notifications".to_string(),
        ));
    }
    let log = repo::insert_log(
        &state.db,
        req.user_id,
        &req.title,
        &req.body,
        req.notification_type.as_db_str(),
        &req.payload,
    )
    .await?;
    deliver(
        &state.db,
        &state.pusher,
        req.user_id,
        &req.title,
        &req.body,
        req.payload.clone().unwrap_or(serde_json::Value::Null),
    )
    .await?;
    Ok(Json(ApiResponse::success(log)))
}

/// Service-to-service direct push. **v2:** requires a valid service-JWT
/// (`ServiceCaller`); v1's equivalent was unauthenticated. Logs + pushes (in v2 the
/// caller no longer writes the notification schema itself).
///
/// Generic over [`InternalPushDeps`] so the service-JWT guard is testable in isolation.
pub async fn internal_push<S: InternalPushDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Json(req): Json<SendNotificationRequest>,
) -> Result<Json<ApiResponse<()>>, AppError> {
    tracing::info!(caller = %caller.service, user = %req.user_id, "internal push");
    repo::insert_log(
        state.db(),
        req.user_id,
        &req.title,
        &req.body,
        req.notification_type.as_db_str(),
        &req.payload,
    )
    .await?;
    let pusher = state.pusher();
    deliver(
        state.db(),
        &pusher,
        req.user_id,
        &req.title,
        &req.body,
        req.payload.clone().unwrap_or(serde_json::Value::Null),
    )
    .await?;
    Ok(Json(ApiResponse::success(())))
}

// ============================================================================
// Broadcast (admin bulk-send) — composer + draft + schedule + history + counts
// ----------------------------------------------------------------------------
// Audience is resolved CROSS-SERVICE: notification owns no user/role registry, so the
// fan-out asks profile (`profile_client`, service-JWT) for the recipient `user_id`s, then
// reuses the existing per-recipient log+push path (`insert_log` + `deliver`).

fn parse_audience(s: &str) -> Result<Audience, AppError> {
    match s {
        "all" => Ok(Audience::All),
        "guards" => Ok(Audience::Guards),
        "customers" => Ok(Audience::Customers),
        other => Err(AppError::Internal(format!(
            "unknown audience in db: {other}"
        ))),
    }
}

/// Fan a broadcast out to its audience: resolve recipients (profile, service-JWT), then for
/// each insert a `notification_logs` row + best-effort FCM push (mirrors `send_notification`).
/// Returns the number of recipients enqueued. Per-recipient failures are logged, not fatal —
/// one bad token/insert must not abort the whole campaign.
async fn fan_out(state: &AppState, b: &BroadcastResponse) -> Result<i64, AppError> {
    let audience = parse_audience(&b.audience)?;
    let recipients = state.profile_client.recipient_ids(audience).await?;
    let payload = Some(serde_json::json!({ "broadcast_id": b.id, "audience": b.audience }));
    let mut sent = 0i64;
    for uid in &recipients {
        if let Err(e) = repo::insert_log(
            &state.db,
            *uid,
            &b.title,
            &b.body,
            &b.notification_type,
            &payload,
        )
        .await
        {
            tracing::warn!(user = %uid, "broadcast log insert failed: {e}");
            continue;
        }
        // Best-effort push — a delivery failure must not drop the in-app notification.
        if let Err(e) = deliver(
            &state.db,
            &state.pusher,
            *uid,
            &b.title,
            &b.body,
            payload.clone().unwrap_or(serde_json::Value::Null),
        )
        .await
        {
            tracing::warn!(user = %uid, "broadcast push failed: {e}");
        }
        sent += 1;
    }
    Ok(sent)
}

/// POST /admin/broadcasts — compose a broadcast (send now / save draft / schedule).
pub async fn create_broadcast(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<CreateBroadcastRequest>,
) -> Result<Json<ApiResponse<BroadcastResponse>>, AppError> {
    require_admin(&user)?;
    if req.title.trim().is_empty() || req.body.trim().is_empty() {
        return Err(AppError::BadRequest(
            "title and body are required".to_string(),
        ));
    }
    let ntype = req.notification_type.unwrap_or(NotificationType::System);
    // `now` is persisted as a draft first, then fanned out + flipped to sent below.
    let status = match req.mode {
        BroadcastMode::Now | BroadcastMode::Draft => BroadcastStatus::Draft,
        BroadcastMode::Scheduled => match req.scheduled_at {
            Some(at) if at > Utc::now() => BroadcastStatus::Scheduled,
            _ => {
                return Err(AppError::BadRequest(
                    "scheduled_at must be a future time for a scheduled broadcast".to_string(),
                ))
            }
        },
    };
    let scheduled_at = if matches!(req.mode, BroadcastMode::Scheduled) {
        req.scheduled_at
    } else {
        None
    };
    let created = repo::create_broadcast(
        &state.db,
        user.user_id,
        req.audience.as_db_str(),
        req.title.trim(),
        req.body.trim(),
        ntype.as_db_str(),
        status.as_db_str(),
        scheduled_at,
    )
    .await?;

    if matches!(req.mode, BroadcastMode::Now) {
        let count = fan_out(&state, &created).await?;
        let sent = repo::mark_broadcast_sent(&state.db, created.id, count)
            .await?
            .ok_or_else(|| AppError::Internal("broadcast vanished after send".to_string()))?;
        return Ok(Json(ApiResponse::success(sent)));
    }
    Ok(Json(ApiResponse::success(created)))
}

/// GET /admin/broadcasts — campaign history (drafts + scheduled + sent), newest first.
pub async fn list_broadcasts(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ListBroadcastsQuery>,
) -> Result<Json<ApiResponse<Vec<BroadcastResponse>>>, AppError> {
    require_admin(&user)?;
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);
    let rows = repo::list_broadcasts(&state.db, limit, offset).await?;
    Ok(Json(ApiResponse::success(rows)))
}

/// GET /admin/broadcasts/{id} — one campaign.
pub async fn get_broadcast(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BroadcastResponse>>, AppError> {
    require_admin(&user)?;
    let b = repo::get_broadcast(&state.db, id)
        .await?
        .ok_or_else(|| AppError::NotFound("Broadcast not found".to_string()))?;
    Ok(Json(ApiResponse::success(b)))
}

/// PUT /admin/broadcasts/{id} — edit a DRAFT (sent/scheduled broadcasts are immutable → 409).
pub async fn update_broadcast(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateBroadcastRequest>,
) -> Result<Json<ApiResponse<BroadcastResponse>>, AppError> {
    require_admin(&user)?;
    let updated = repo::update_draft_broadcast(
        &state.db,
        id,
        req.audience.map(|a| a.as_db_str()),
        req.title.as_deref(),
        req.body.as_deref(),
        req.notification_type.map(|t| t.as_db_str()),
        req.scheduled_at,
    )
    .await?;
    match updated {
        Some(b) => Ok(Json(ApiResponse::success(b))),
        None => {
            // Distinguish missing vs not-a-draft for a useful error.
            if repo::get_broadcast(&state.db, id).await?.is_some() {
                Err(AppError::Conflict(
                    "only draft broadcasts can be edited".to_string(),
                ))
            } else {
                Err(AppError::NotFound("Broadcast not found".to_string()))
            }
        }
    }
}

/// POST /admin/broadcasts/{id}/send — send a draft/scheduled broadcast NOW.
pub async fn send_broadcast(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BroadcastResponse>>, AppError> {
    require_admin(&user)?;
    let b = repo::get_broadcast(&state.db, id)
        .await?
        .ok_or_else(|| AppError::NotFound("Broadcast not found".to_string()))?;
    if b.status == "sent" {
        return Err(AppError::Conflict("broadcast already sent".to_string()));
    }
    let count = fan_out(&state, &b).await?;
    let sent = repo::mark_broadcast_sent(&state.db, id, count)
        .await?
        .ok_or_else(|| AppError::Internal("broadcast vanished after send".to_string()))?;
    Ok(Json(ApiResponse::success(sent)))
}

/// GET /admin/audience-counts — recipient totals per audience (composer picker). `all` is the
/// sum (guard/customer roles are disjoint, matching profile's UNION), so two lookups suffice.
pub async fn audience_counts(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<ApiResponse<AudienceCountsResponse>>, AppError> {
    require_admin(&user)?;
    let guards = state
        .profile_client
        .recipient_ids(Audience::Guards)
        .await?
        .len() as i64;
    let customers = state
        .profile_client
        .recipient_ids(Audience::Customers)
        .await?
        .len() as i64;
    Ok(Json(ApiResponse::success(AudienceCountsResponse {
        all: guards + customers,
        guards,
        customers,
    })))
}

/// One scheduler tick: dispatch all due scheduled broadcasts (called on a timer from `main`).
/// State-changing work that owns its retry via the `status` ledger — a row stays `scheduled`
/// until a fan-out succeeds and flips it to `sent`. Returns how many were dispatched this tick.
pub async fn dispatch_due_broadcasts(state: &AppState) -> Result<u64, AppError> {
    let due = repo::due_broadcasts(&state.db, 20).await?;
    let mut dispatched = 0u64;
    for b in &due {
        match fan_out(state, b).await {
            Ok(count) => {
                if let Err(e) = repo::mark_broadcast_sent(&state.db, b.id, count).await {
                    tracing::error!(broadcast = %b.id, "mark_sent failed after fan-out: {e}");
                } else {
                    dispatched += 1;
                }
            }
            Err(e) => {
                tracing::warn!(broadcast = %b.id, "scheduled broadcast fan-out failed (will retry): {e}")
            }
        }
    }
    Ok(dispatched)
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::post;
    use axum::Router;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use shared::service_jwt::{encode_service_jwt, HasServiceJwt};
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;
    use tower::ServiceExt;

    use crate::fcm::NoopPusher;

    const SECRET: &str = "service-secret-at-least-64-characters-long-for-internal-hs256-test!!";

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
        pusher: Arc<dyn Pusher>,
    }

    impl HasServiceJwt for TestDeps {
        fn service_decoding_key(&self) -> &DecodingKey {
            &self.dec
        }
    }
    impl InternalPushDeps for TestDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn pusher(&self) -> Arc<dyn Pusher> {
            self.pusher.clone()
        }
    }

    fn router() -> Router {
        // Lazy pool to a closed port — never connects unless a handler queries (it
        // won't, because rejected requests short-circuit at the ServiceCaller guard).
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db,
            pusher: Arc::new(NoopPusher),
        };
        Router::new()
            .route(
                "/internal/notifications/push",
                post(internal_push::<TestDeps>),
            )
            .with_state(deps)
    }

    fn push_body() -> Body {
        Body::from(
            serde_json::json!({
                "user_id": "00000000-0000-0000-0000-000000000001",
                "title": "t",
                "body": "b",
                "notification_type": "system"
            })
            .to_string(),
        )
    }

    #[tokio::test]
    async fn internal_push_rejects_missing_token() {
        let res = router()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/internal/notifications/push")
                    .header("content-type", "application/json")
                    .body(push_body())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn internal_push_rejects_invalid_token() {
        let res = router()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/internal/notifications/push")
                    .header("authorization", "Bearer not.a.valid.jwt")
                    .header("content-type", "application/json")
                    .body(push_body())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn internal_push_accepts_valid_service_token() {
        // A valid service-JWT must pass the guard. The handler then tries to query the
        // (unreachable) DB, so the response is NOT 401 — proving auth was accepted.
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let token = encode_service_jwt("booking", &ek, 60).unwrap();
        let res = router()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/internal/notifications/push")
                    .header("authorization", format!("Bearer {token}"))
                    .header("content-type", "application/json")
                    .body(push_body())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_ne!(
            res.status(),
            StatusCode::UNAUTHORIZED,
            "valid service token must pass the guard"
        );
    }

    // ----- broadcast: admin role gate (Redis-gated, mirrors profile's router tests) -----

    const USER_SECRET: &str =
        "user-secret-at-least-64-characters-long-for-the-hs256-notif-test!!!!";

    /// AppState-backed router for the broadcast admin routes. `require_admin` runs AFTER the
    /// `AuthUser` extractor (which needs a live Redis for the revocation check), so this is
    /// Redis-gated like profile's `router()`; the 403 fires before profile_client/DB is touched.
    async fn broadcast_router() -> Option<Router> {
        use crate::profile_client::ProfileClient;

        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis_conn = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let jwt_config = shared::config::JwtConfig {
            secret: USER_SECRET.to_string(),
            expiry_minutes: 15,
            encoding_key: EncodingKey::from_secret(USER_SECRET.as_bytes()),
            decoding_key: DecodingKey::from_secret(USER_SECRET.as_bytes()),
        };
        let service_jwt_config = shared::config::ServiceJwtConfig {
            encoding_key: EncodingKey::from_secret(SECRET.as_bytes()),
            decoding_key: DecodingKey::from_secret(SECRET.as_bytes()),
            ttl_secs: 60,
        };
        let profile_client = ProfileClient::new(
            reqwest::Client::new(),
            "http://127.0.0.1:1".to_string(),
            service_jwt_config.encoding_key.clone(),
            service_jwt_config.ttl_secs,
        );
        let state = AppState {
            db,
            redis_conn,
            jwt_config,
            service_jwt_config,
            pusher: Arc::new(NoopPusher),
            profile_client,
        };
        Some(
            Router::new()
                .route("/admin/broadcasts", post(create_broadcast))
                .with_state(state),
        )
    }

    fn user_token(role: &str) -> String {
        let ek = EncodingKey::from_secret(USER_SECRET.as_bytes());
        let (tok, _) = shared::auth::encode_jwt_with_key(Uuid::new_v4(), role, 0, &ek, 60).unwrap();
        tok
    }

    #[tokio::test]
    async fn create_broadcast_rejects_non_admin() {
        let Some(app) = broadcast_router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let body = serde_json::json!({
            "audience": "all", "title": "t", "body": "b", "mode": "draft"
        });
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/admin/broadcasts")
                    .header("authorization", format!("Bearer {}", user_token("guard")))
                    .header("content-type", "application/json")
                    .body(Body::from(body.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "a non-admin must not create a broadcast"
        );
    }
}
