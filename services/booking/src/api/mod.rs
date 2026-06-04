//! API layer — thin Axum transport handlers. No business logic beyond role gating +
//! orchestration of `repo`; the state machine + event mapping live in `domain` (pure),
//! and the atomic status+outbox write lives in `repo::transition`.
//!
//! Handlers are generic over [`BookingDeps`] so the `AuthUser` guard is unit-testable
//! with a lightweight state (no live DB/NATS), mirroring notification's seam pattern.

use axum::extract::{Path, State};
use axum::Json;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;

use crate::domain::state::BookingStatus;
use crate::models::{BookingResponse, CreateBookingRequest};
use crate::repo;
use crate::state::BookingDeps;

/// Transition a booking to `new_status`, generating a fresh correlation id for the
/// emitted event. (Threading the inbound trace's correlation id from headers is the
/// observability follow-up; the envelope already carries the field.)
async fn do_transition<S: BookingDeps>(
    state: &S,
    id: Uuid,
    new_status: BookingStatus,
    assign_guard: Option<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let booking =
        repo::transition(state.db(), id, new_status, assign_guard, Uuid::new_v4()).await?;
    Ok(Json(ApiResponse::success(booking)))
}

/// POST /bookings — a customer creates a booking request (status = requested).
#[tracing::instrument(skip(state, req), fields(user = %user.user_id))]
pub async fn create_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Json(req): Json<CreateBookingRequest>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    if user.role != "customer" {
        return Err(AppError::Forbidden(
            "Only customers can create bookings".to_string(),
        ));
    }
    if req.hours <= 0 {
        return Err(AppError::BadRequest("hours must be positive".to_string()));
    }
    let booking = repo::create_booking(state.db(), user.user_id, &req).await?;
    Ok(Json(ApiResponse::success(booking)))
}

/// POST /bookings/{id}/accept — a guard accepts → status = accepted, guard_id = caller.
/// Enqueues `pguard.events.booking.job_accepted` in the same transaction (outbox).
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn accept_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    if user.role != "guard" {
        return Err(AppError::Forbidden(
            "Only guards can accept bookings".to_string(),
        ));
    }
    do_transition(&state, id, BookingStatus::Accepted, Some(user.user_id)).await
}

/// POST /bookings/{id}/decline — a guard declines → status = declined (outbox event).
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn decline_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    if user.role != "guard" {
        return Err(AppError::Forbidden(
            "Only guards can decline bookings".to_string(),
        ));
    }
    do_transition(&state, id, BookingStatus::Declined, None).await
}

/// POST /bookings/{id}/en-route — the assigned guard is en route (outbox event).
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn en_route_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    if user.role != "guard" {
        return Err(AppError::Forbidden(
            "Only the assigned guard can update status".to_string(),
        ));
    }
    do_transition(&state, id, BookingStatus::EnRoute, None).await
}

/// POST /bookings/{id}/arrived — the assigned guard has arrived (outbox event).
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn arrived_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    if user.role != "guard" {
        return Err(AppError::Forbidden(
            "Only the assigned guard can update status".to_string(),
        ));
    }
    do_transition(&state, id, BookingStatus::Arrived, None).await
}

/// POST /bookings/{id}/complete — the assigned guard completes the job (outbox event).
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn complete_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    if user.role != "guard" {
        return Err(AppError::Forbidden(
            "Only the assigned guard can update status".to_string(),
        ));
    }
    do_transition(&state, id, BookingStatus::Completed, None).await
}

/// GET /bookings/{id} — fetch one booking the caller participates in.
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn get_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let booking = repo::get_booking(state.db(), id).await?;
    if booking.customer_id != user.user_id && booking.guard_id != Some(user.user_id) {
        return Err(AppError::Forbidden(
            "Not a participant in this booking".to_string(),
        ));
    }
    Ok(Json(ApiResponse::success(booking)))
}

/// GET /bookings — list the caller's bookings (as customer or assigned guard).
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn list_bookings<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<BookingResponse>>>, AppError> {
    let items = repo::list_bookings(state.db(), user.user_id).await?;
    Ok(Json(ApiResponse::success(items)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::{get, post};
    use axum::Router;
    use jsonwebtoken::DecodingKey;
    use shared::auth::HasJwtSecret;
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;
    use std::time::Duration;
    use tower::ServiceExt;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-booking-test!!!";

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
        redis: redis::aio::MultiplexedConnection,
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
    impl BookingDeps for TestDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
    }

    /// Build the booking router over a lightweight test state. The `AuthUser` extractor
    /// requires `HasJwtSecret`, which mandates a real [`redis::aio::MultiplexedConnection`]
    /// for the jti revocation blocklist — there is no public way to construct one without
    /// connecting. So, exactly like the repo's real-DB test, these router tests are
    /// hermetic by default and only run when a test Redis is provided via `TEST_REDIS_URL`
    /// (falling back to `REDIS_CACHE_URL`). Returns `None` → the caller SKIPs.
    ///
    /// The auth-reject paths never query Redis (they fail at token parse/decode first), so
    /// a reachable Redis is enough; its contents are irrelevant.
    async fn router() -> Option<Router> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = redis::Client::open(redis_url)
            .ok()?
            .get_multiplexed_tokio_connection()
            .await
            .ok()?;
        // Lazy pool to a closed port — never connects unless a handler queries (rejected
        // requests short-circuit at the AuthUser guard before any DB access).
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db,
            redis,
        };
        Some(
            Router::new()
                .route("/bookings", post(create_booking::<TestDeps>))
                .route("/bookings/{id}/accept", post(accept_booking::<TestDeps>))
                .route("/bookings/{id}", get(get_booking::<TestDeps>))
                .with_state(deps),
        )
    }

    fn create_body() -> Body {
        Body::from(
            serde_json::json!({
                "address": "1 Test Rd",
                "scheduled_at": "2026-06-04T10:00:00Z",
                "hours": 4
            })
            .to_string(),
        )
    }

    #[tokio::test]
    async fn create_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/bookings")
                    .header("content-type", "application/json")
                    .body(create_body())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn create_rejects_invalid_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/bookings")
                    .header("authorization", "Bearer not.a.valid.jwt")
                    .header("content-type", "application/json")
                    .body(create_body())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn accept_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/bookings/{id}/accept"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }
}
