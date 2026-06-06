//! API layer — thin Axum transport handlers. No business logic beyond role gating +
//! orchestration of the booking-reader (authoritative verification), `domain` (pure
//! validation + aggregation), and `repo` (the atomic submit + outbox write).
//!
//! Handlers are generic over the [`RatingDeps`] / [`RatingInternalDeps`] seams so the
//! `AuthUser` / `ServiceCaller` guards are unit-testable with a lightweight state (no live
//! booking service / Redis), mirroring booking + payment.

use axum::extract::{Path, Query, State};
use axum::Json;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;
use shared::service_jwt::ServiceCaller;

use crate::booking_client::BookingReader;
use crate::domain::{is_reviewable_status, validate_review};
use crate::models::{
    AdminReviewsQuery, AdminReviewsResponse, CreateReviewRequest, GuardRatingsResponse,
    RatingSummaryResponse, SetVisibilityRequest, SubmitReviewResponse,
};
use crate::repo;
use crate::state::{RatingDeps, RatingInternalDeps};

/// How many reviews a public ratings page returns (newest first).
const PUBLIC_REVIEWS_LIMIT: i64 = 100;

/// POST /assignments/{id}/review — a customer reviews a completed assignment (= booking).
///
/// Authz discipline (CLAUDE.md — never trust the client):
///  1. Validate the ratings (`overall` required + categories, all `1..=5`) BEFORE any I/O.
///  2. VERIFY against the authoritative booking (service-JWT'd internal read): the caller
///     must be the booking's customer AND the booking must be `completed`.
///  3. `guard_id` comes from the booking, not the request.
///  4. One review per assignment (DB UNIQUE) + emit `rating.submitted` in ONE tx (outbox).
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, assignment_id = %assignment_id))]
pub async fn submit_review<S: RatingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(assignment_id): Path<Uuid>,
    Json(req): Json<CreateReviewRequest>,
) -> Result<Json<ApiResponse<SubmitReviewResponse>>, AppError> {
    if user.role != "customer" {
        return Err(AppError::Forbidden(
            "Only customers can submit reviews".to_string(),
        ));
    }

    // (1) validate ratings + text length before any I/O. Generic, field-named message.
    validate_review(
        req.overall_rating,
        req.punctuality,
        req.professionalism,
        req.communication,
        req.appearance,
        req.review_text.as_deref(),
    )
    .map_err(|e| AppError::BadRequest(e.message().to_string()))?;

    // (2) authoritative verification — the review decision trusts the booking, not the body.
    let booking = state.booking_reader().get_booking(assignment_id).await?;

    if booking.customer_id != user.user_id {
        // Generic 403 — never reveal whether the booking exists / belongs to someone else.
        return Err(AppError::Forbidden(
            "You can only review your own bookings".to_string(),
        ));
    }
    if !is_reviewable_status(&booking.status) {
        return Err(AppError::Conflict(
            "You can only review a completed booking".to_string(),
        ));
    }
    // (3) the reviewed guard comes from the booking (a completed booking always has one).
    let Some(guard_id) = booking.guard_id else {
        return Err(AppError::Conflict(
            "Booking has no assigned guard to review".to_string(),
        ));
    };

    // (4) one-per-assignment insert + rating.submitted outbox event, in ONE tx.
    let id = repo::submit_review_tx(
        state.db(),
        guard_id,
        user.user_id,
        assignment_id,
        &req,
        Uuid::new_v4(),
    )
    .await?;

    Ok(Json(ApiResponse::success(SubmitReviewResponse { id })))
}

/// GET /guards/{id}/ratings — PUBLIC guard discovery: visible reviews + aggregate summary.
/// Only `is_visible = true` reviews are returned/aggregated (admin-hidden never surface).
#[tracing::instrument(skip(state), fields(guard_id = %guard_id))]
pub async fn guard_ratings<S: RatingDeps>(
    State(state): State<S>,
    Path(guard_id): Path<Uuid>,
) -> Result<Json<ApiResponse<GuardRatingsResponse>>, AppError> {
    // Public list read → replica (C5.3).
    let (summary, reviews) =
        repo::guard_ratings(state.db_read(), guard_id, PUBLIC_REVIEWS_LIMIT).await?;
    Ok(Json(ApiResponse::success(GuardRatingsResponse {
        guard_id,
        average: summary.average,
        count: summary.count,
        reviews,
    })))
}

/// GET /admin/reviews — admin moderation list with filters; stats over the UNFILTERED set.
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn list_admin_reviews<S: RatingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<AdminReviewsQuery>,
) -> Result<Json<ApiResponse<AdminReviewsResponse>>, AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "Only admins can list all reviews".to_string(),
        ));
    }
    // The `rating` filter, when present, must be a whole star (matches the OpenAPI bounds and
    // avoids binding an out-of-range value the SMALLINT column can never match).
    if let Some(r) = q.rating {
        if !(1..=5).contains(&r) {
            return Err(AppError::BadRequest(
                "rating filter must be between 1 and 5".to_string(),
            ));
        }
    }
    // Admin moderation list read → replica (C5.3).
    let resp = repo::list_admin_reviews(
        state.db_read(),
        q.guard_id,
        q.rating,
        q.is_visible,
        q.search.as_deref(),
        q.limit.unwrap_or(50),
        q.offset.unwrap_or(0),
    )
    .await?;
    Ok(Json(ApiResponse::success(resp)))
}

/// PUT /admin/reviews/{id}/visibility — admin toggles a review's public visibility.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, review_id = %review_id))]
pub async fn set_review_visibility<S: RatingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(review_id): Path<Uuid>,
    Json(req): Json<SetVisibilityRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "Only admins can moderate reviews".to_string(),
        ));
    }
    repo::set_visibility(state.db(), review_id, req.is_visible).await?;
    Ok(Json(ApiResponse::success(serde_json::json!({
        "id": review_id,
        "is_visible": req.is_visible,
    }))))
}

/// GET /internal/guards/{id}/rating-summary — service-JWT'd summary for booking's
/// available-guards discovery (AVG + COUNT of VISIBLE reviews). Guarded by [`ServiceCaller`].
#[tracing::instrument(skip(state), fields(caller = %caller.service, guard_id = %guard_id))]
pub async fn internal_rating_summary<S: RatingInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Path(guard_id): Path<Uuid>,
) -> Result<Json<ApiResponse<RatingSummaryResponse>>, AppError> {
    let summary = repo::guard_summary(state.db_read(), guard_id).await?;
    Ok(Json(ApiResponse::success(RatingSummaryResponse {
        guard_id,
        average: summary.average,
        count: summary.count,
    })))
}

// ----- GET /internal/users/{user_id}/export (PDPA §19/§32 data export) -----

/// Export the reviews a user AUTHORED for a cross-service data export. `ServiceCaller`-gated
/// (only identity's aggregator reaches this) and scoped strictly to the path `user_id`.
#[tracing::instrument(skip(state), fields(caller = %caller.service, user = %user_id))]
pub async fn internal_export_user<S: RatingInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    let reviews = repo::export_user_reviews(state.db_read(), user_id).await?;
    Ok(Json(ApiResponse::success(reviews)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::InternalBooking;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::{get, post};
    use axum::Router;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use shared::auth::{encode_jwt_with_key, HasJwtSecret};
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;
    use std::time::Duration;
    use tower::ServiceExt;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-rating-test!!!!!";

    /// Stub booking reader — canned booking (or NotFound), no HTTP. Lets the role/authz gates
    /// be tested hermetically.
    #[derive(Clone)]
    struct StubReader {
        booking: Option<InternalBooking>,
    }
    impl BookingReader for StubReader {
        async fn get_booking(&self, _booking_id: Uuid) -> Result<InternalBooking, AppError> {
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
    impl RatingDeps for TestDeps {
        type Reader = StubReader;
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn booking_reader(&self) -> &StubReader {
            &self.reader
        }
    }

    /// Router over a lightweight state. The `AuthUser` extractor needs a real Redis
    /// connection (jti blocklist), so these tests are hermetic by default and only run when
    /// `TEST_REDIS_URL`/`REDIS_CACHE_URL` is set (→ `None` SKIPs). The auth-reject + role +
    /// authz paths short-circuit before any DB query, so the lazy pool to a closed port is safe.
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
        };
        Some(
            Router::new()
                .route("/assignments/{id}/review", post(submit_review::<TestDeps>))
                .route("/admin/reviews", get(list_admin_reviews::<TestDeps>))
                .with_state(deps),
        )
    }

    fn token(user_id: Uuid, role: &str) -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _jti) = encode_jwt_with_key(user_id, role, 0, &ek, 15).unwrap();
        tok
    }

    fn review_body(overall: i32) -> Body {
        Body::from(serde_json::json!({ "overall_rating": overall }).to_string())
    }

    fn completed_booking(customer_id: Uuid) -> InternalBooking {
        InternalBooking {
            customer_id,
            guard_id: Some(Uuid::new_v4()),
            status: "completed".to_string(),
        }
    }

    async fn submit(app: Router, tok: Option<&str>, body: Body) -> StatusCode {
        let mut b = Request::builder()
            .method("POST")
            .uri("/assignments/00000000-0000-0000-0000-000000000001/review")
            .header("content-type", "application/json");
        if let Some(t) = tok {
            b = b.header("authorization", format!("Bearer {t}"));
        }
        app.oneshot(b.body(body).unwrap()).await.unwrap().status()
    }

    #[tokio::test]
    async fn submit_rejects_missing_token() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(
            submit(app, None, review_body(5)).await,
            StatusCode::UNAUTHORIZED
        );
    }

    #[tokio::test]
    async fn submit_rejects_invalid_token() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(
            submit(app, Some("not.a.valid.jwt"), review_body(5)).await,
            StatusCode::UNAUTHORIZED
        );
    }

    #[tokio::test]
    async fn submit_rejects_non_customer_role() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = token(Uuid::new_v4(), "guard");
        assert_eq!(
            submit(app, Some(&tok), review_body(5)).await,
            StatusCode::FORBIDDEN
        );
    }

    #[tokio::test]
    async fn submit_rejects_out_of_range_before_io() {
        // overall=6 is rejected at validation, before the booking read → 400.
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = token(Uuid::new_v4(), "customer");
        assert_eq!(
            submit(app, Some(&tok), review_body(6)).await,
            StatusCode::BAD_REQUEST
        );
    }

    #[tokio::test]
    async fn submit_rejects_reviewing_someone_elses_booking() {
        // Caller is a customer, but the authoritative booking belongs to a DIFFERENT customer.
        let me = Uuid::new_v4();
        let app = router(Some(completed_booking(Uuid::new_v4()))).await;
        let Some(app) = app else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = token(me, "customer");
        assert_eq!(
            submit(app, Some(&tok), review_body(5)).await,
            StatusCode::FORBIDDEN
        );
    }

    #[tokio::test]
    async fn submit_rejects_non_completed_booking() {
        // Owner matches, but the booking is not completed → 409.
        let me = Uuid::new_v4();
        let booking = InternalBooking {
            customer_id: me,
            guard_id: Some(Uuid::new_v4()),
            status: "accepted".to_string(),
        };
        let Some(app) = router(Some(booking)).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = token(me, "customer");
        assert_eq!(
            submit(app, Some(&tok), review_body(5)).await,
            StatusCode::CONFLICT
        );
    }

    #[tokio::test]
    async fn admin_reviews_rejects_non_admin() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = token(Uuid::new_v4(), "customer");
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/reviews")
                    .header("authorization", format!("Bearer {tok}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    // ----- internal rating-summary: service-JWT guard (no Redis/DB needed) -----

    const SERVICE_SECRET: &str =
        "service-secret-at-least-64-characters-long-for-internal-hs256-test!!";

    #[derive(Clone)]
    struct InternalDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
    }
    impl shared::service_jwt::HasServiceJwt for InternalDeps {
        fn service_decoding_key(&self) -> &DecodingKey {
            &self.dec
        }
    }
    impl RatingInternalDeps for InternalDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
    }

    fn internal_router() -> Router {
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let deps = InternalDeps {
            dec: Arc::new(DecodingKey::from_secret(SERVICE_SECRET.as_bytes())),
            db,
        };
        Router::new()
            .route(
                "/internal/guards/{id}/rating-summary",
                get(internal_rating_summary::<InternalDeps>),
            )
            .with_state(deps)
    }

    const INTERNAL_URI: &str =
        "/internal/guards/00000000-0000-0000-0000-000000000001/rating-summary";

    #[tokio::test]
    async fn internal_summary_rejects_missing_token() {
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(INTERNAL_URI)
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn internal_summary_rejects_invalid_token() {
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(INTERNAL_URI)
                    .header("authorization", "Bearer not.a.valid.jwt")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn internal_summary_accepts_valid_service_token() {
        // A valid service-JWT must pass the guard; the handler then queries the (unreachable)
        // DB, so the response is NOT 401 — proving auth was accepted before any DB access.
        use shared::service_jwt::encode_service_jwt;
        let ek = EncodingKey::from_secret(SERVICE_SECRET.as_bytes());
        let tok = encode_service_jwt("booking", &ek, 60).unwrap();
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(INTERNAL_URI)
                    .header("authorization", format!("Bearer {tok}"))
                    .body(Body::empty())
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
