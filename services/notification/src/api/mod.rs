//! API layer — thin Axum transport handlers. No business logic beyond role gating
//! and orchestration of `repo` + the [`Pusher`] port.

use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::Json;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;
use shared::service_jwt::ServiceCaller;

use crate::fcm::{PushMessage, Pusher};
use crate::models::{
    DeleteTokenRequest, ListNotificationsQuery, NotificationLogResponse, RegisterTokenRequest,
    RoleQuery, SendNotificationRequest, UnreadCountResponse,
};
use crate::repo;
use crate::state::{AppState, InternalPushDeps};

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
}
