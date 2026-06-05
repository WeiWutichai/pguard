//! API layer — thin Axum transport handlers. No business logic beyond role gating +
//! orchestration of `repo`; the state machine + event mapping live in `domain` (pure),
//! and the atomic status+outbox write lives in `repo::transition`.
//!
//! Handlers are generic over [`BookingDeps`] so the `AuthUser` guard is unit-testable
//! with a lightweight state (no live DB/NATS), mirroring notification's seam pattern.

use axum::extract::{Path, State};
use axum::Json;
use uuid::Uuid;

use futures::StreamExt;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;
use shared::service_jwt::ServiceCaller;

use crate::discovery_client::{GuardCatalog, RatingReader};
use crate::domain::state::BookingStatus;
use crate::models::{AvailableGuard, BookingResponse, CreateBookingRequest, InternalBooking};
use crate::repo;
use crate::state::{BookingDeps, BookingInternalDeps, DiscoveryDeps};

/// Max concurrent rating-summary lookups when building the discovery list (bounds fan-out
/// to the rating service while keeping the page snappy).
const MAX_CONCURRENT_RATING: usize = 8;

/// Upper bound on a single booking's duration (defensive against absurd values flowing
/// into proration/payment).
const MAX_BOOKING_HOURS: i32 = 168; // 1 week
/// Guard-count bounds (mirror the DB CHECK + v1's 1..=20).
const MAX_GUARD_COUNT: i32 = 20;

/// Transition a booking to `new_status` on behalf of `actor` (the caller). `repo::transition`
/// enforces, inside the row-locked tx, that `actor` is allowed to drive this transition
/// (the assigned guard for in-flight changes). A fresh correlation id is generated for the
/// emitted event (threading the inbound trace's id is the observability follow-up).
async fn do_transition<S: BookingDeps>(
    state: &S,
    id: Uuid,
    actor: Uuid,
    new_status: BookingStatus,
    assign_guard: Option<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let booking = repo::transition(
        state.db(),
        id,
        actor,
        new_status,
        assign_guard,
        Uuid::new_v4(),
    )
    .await?;
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
    if req.hours <= 0 || req.hours > MAX_BOOKING_HOURS {
        return Err(AppError::BadRequest(format!(
            "hours must be between 1 and {MAX_BOOKING_HOURS}"
        )));
    }
    // Pricing inputs: default guard_count → 1, tip → 0. Validate before persisting so the
    // money path (expected_total = base_fee × hours × guard_count + tip) never sees junk.
    let guard_count = req.guard_count.unwrap_or(1);
    if !(1..=MAX_GUARD_COUNT).contains(&guard_count) {
        return Err(AppError::BadRequest(format!(
            "guard_count must be between 1 and {MAX_GUARD_COUNT}"
        )));
    }
    let tip = req.tip.unwrap_or(rust_decimal::Decimal::ZERO);
    if tip < rust_decimal::Decimal::ZERO {
        return Err(AppError::BadRequest("tip must not be negative".to_string()));
    }
    let booking = repo::create_booking(state.db(), user.user_id, &req, guard_count, tip).await?;
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
    do_transition(
        &state,
        id,
        user.user_id,
        BookingStatus::Accepted,
        Some(user.user_id),
    )
    .await
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
    do_transition(&state, id, user.user_id, BookingStatus::Declined, None).await
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
    do_transition(&state, id, user.user_id, BookingStatus::EnRoute, None).await
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
    do_transition(&state, id, user.user_id, BookingStatus::Arrived, None).await
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
    do_transition(&state, id, user.user_id, BookingStatus::Completed, None).await
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

/// GET /available-guards — discovery: the approved guard catalog (from profile) enriched
/// with each guard's live rating summary (from rating). booking owns discovery but neither
/// the catalog nor reviews, so it reads both owners over service-JWT and aggregates here.
///
/// Best-effort on ratings: a guard whose rating lookup fails still appears (with no
/// average / zero count) — one slow dependency never blanks the whole list. Rating lookups
/// run concurrently (bounded) and preserve the catalog's order.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn available_guards<S: DiscoveryDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<AvailableGuard>>>, AppError> {
    let guards = state.guard_catalog().list_approved_guards().await?;
    let rater = state.rating_reader();

    // Each entry carries whether its rating lookup fell back (best-effort), so we can emit a
    // single aggregate signal for a degraded list rather than only per-guard warns.
    let merged: Vec<(AvailableGuard, bool)> = futures::stream::iter(guards)
        .map(|g| async move {
            let (summary, ok) = match rater.guard_summary(g.user_id).await {
                Ok(s) => (s, true),
                Err(e) => {
                    // Best-effort: a per-guard rating failure must not fail the whole list.
                    tracing::warn!(guard_id = %g.user_id, "rating summary failed: {e}; defaulting");
                    (Default::default(), false)
                }
            };
            let guard = AvailableGuard {
                guard_id: g.user_id,
                years_of_experience: g.years_of_experience,
                average_rating: summary.average,
                review_count: summary.count,
            };
            (guard, !ok)
        })
        .buffered(MAX_CONCURRENT_RATING)
        .collect()
        .await;

    let rating_failures = merged.iter().filter(|(_, failed)| *failed).count();
    if rating_failures > 0 {
        tracing::warn!(
            rating_failures,
            total = merged.len(),
            "discovery returned with degraded ratings (rating service unreachable for some guards)"
        );
    }
    let items: Vec<AvailableGuard> = merged.into_iter().map(|(g, _)| g).collect();

    Ok(Json(ApiResponse::success(items)))
}

// ----- GET /internal/bookings/{id} (service-to-service) -----

/// Internal read used by the payment service to make the money decision against the
/// authoritative booking — never trusting a client-supplied customer/guard/status. Guarded
/// by [`ServiceCaller`] (a valid service-JWT); v1 had no auth on cross-service reads.
/// Returns only `{ id, customer_id, guard_id, status, hours }`. Generic over
/// [`BookingInternalDeps`] so the guard is unit-testable (mirrors identity's
/// `internal_revoke_all`).
#[tracing::instrument(skip(state), fields(caller = %caller.service, booking_id = %id))]
pub async fn get_internal_booking<S: BookingInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<InternalBooking>>, AppError> {
    let booking = repo::get_internal(state.db(), id).await?;
    Ok(Json(ApiResponse::success(booking)))
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

    // ----- internal read: service-JWT guard (no Redis/DB needed) -----

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
    impl BookingInternalDeps for InternalDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
    }

    /// Build the internal router over a lightweight test state. The `ServiceCaller`
    /// extractor only needs the service decoding key — no Redis, no live DB. Rejected
    /// requests short-circuit at the guard before any DB access, so a lazy pool to a
    /// closed port is safe (mirrors identity's internal_revoke_all test).
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
                "/internal/bookings/{id}",
                get(get_internal_booking::<InternalDeps>),
            )
            .with_state(deps)
    }

    const INTERNAL_URI: &str = "/internal/bookings/00000000-0000-0000-0000-000000000001";

    #[tokio::test]
    async fn internal_read_rejects_missing_token() {
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
    async fn internal_read_rejects_invalid_token() {
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
    async fn internal_read_accepts_valid_service_token() {
        // A valid service-JWT (as minted by the payment service) must pass the guard. The
        // handler then queries the (unreachable) DB, so the response is NOT 401 — proving
        // auth was accepted before any DB access.
        use jsonwebtoken::EncodingKey;
        use shared::service_jwt::encode_service_jwt;
        let ek = EncodingKey::from_secret(SERVICE_SECRET.as_bytes());
        let tok = encode_service_jwt("payment", &ek, 60).unwrap();
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

    // ----- /available-guards discovery aggregation (stub readers; Redis-gated for AuthUser) -----

    use crate::discovery_client::{CatalogGuard, GuardCatalog, GuardRatingSummary, RatingReader};

    /// Catalog stub — returns a canned approved-guard list, no HTTP.
    #[derive(Clone)]
    struct StubCatalog {
        guards: Vec<CatalogGuard>,
    }
    impl GuardCatalog for StubCatalog {
        async fn list_approved_guards(&self) -> Result<Vec<CatalogGuard>, AppError> {
            Ok(self.guards.clone())
        }
    }

    /// Rating stub — returns avg 4.50/count 2 for `good`, and ERRORS for any other guard so
    /// the handler's best-effort default (None/0) path is exercised.
    #[derive(Clone)]
    struct StubRater {
        good: Uuid,
    }
    impl RatingReader for StubRater {
        async fn guard_summary(&self, guard_id: Uuid) -> Result<GuardRatingSummary, AppError> {
            if guard_id == self.good {
                Ok(GuardRatingSummary {
                    average: Some("4.50".parse().unwrap()),
                    count: 2,
                })
            } else {
                Err(AppError::Internal("rating unreachable".to_string()))
            }
        }
    }

    #[derive(Clone)]
    struct DiscoveryTestDeps {
        dec: Arc<DecodingKey>,
        redis: redis::aio::MultiplexedConnection,
        catalog: StubCatalog,
        rater: StubRater,
    }
    impl HasJwtSecret for DiscoveryTestDeps {
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
    impl crate::state::DiscoveryDeps for DiscoveryTestDeps {
        type Catalog = StubCatalog;
        type Rating = StubRater;
        fn guard_catalog(&self) -> &StubCatalog {
            &self.catalog
        }
        fn rating_reader(&self) -> &StubRater {
            &self.rater
        }
    }

    async fn discovery_router(catalog: StubCatalog, rater: StubRater) -> Option<Router> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = redis::Client::open(redis_url)
            .ok()?
            .get_multiplexed_tokio_connection()
            .await
            .ok()?;
        // available_guards never touches the DB (only the readers) — no pool needed.
        let deps = DiscoveryTestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            redis,
            catalog,
            rater,
        };
        Some(
            Router::new()
                .route(
                    "/available-guards",
                    get(available_guards::<DiscoveryTestDeps>),
                )
                .with_state(deps),
        )
    }

    fn user_token(role: &str) -> String {
        use shared::auth::encode_jwt_with_key;
        let ek = jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _jti) = encode_jwt_with_key(Uuid::new_v4(), role, 0, &ek, 15).unwrap();
        tok
    }

    #[tokio::test]
    async fn available_guards_rejects_missing_token() {
        let app = discovery_router(
            StubCatalog { guards: vec![] },
            StubRater {
                good: Uuid::new_v4(),
            },
        )
        .await;
        let Some(app) = app else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/available-guards")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn available_guards_merges_catalog_and_ratings_best_effort() {
        let good = Uuid::new_v4(); // has a rating
        let bad = Uuid::new_v4(); // rating lookup errors → best-effort default
        let catalog = StubCatalog {
            guards: vec![
                CatalogGuard {
                    user_id: good,
                    years_of_experience: Some(5),
                },
                CatalogGuard {
                    user_id: bad,
                    years_of_experience: None,
                },
            ],
        };
        let Some(app) = discovery_router(catalog, StubRater { good }).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/available-guards")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token("customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let body = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let data = v["data"].as_array().expect("data array");
        assert_eq!(data.len(), 2, "both approved guards listed");
        // Order preserved (catalog order): good first, then bad.
        assert_eq!(data[0]["guard_id"], serde_json::json!(good));
        assert_eq!(data[0]["average_rating"], serde_json::json!("4.50"));
        assert_eq!(data[0]["review_count"], serde_json::json!(2));
        assert_eq!(data[0]["years_of_experience"], serde_json::json!(5));
        // The guard whose rating lookup failed still appears, with best-effort defaults.
        assert_eq!(data[1]["guard_id"], serde_json::json!(bad));
        assert!(
            data[1]["average_rating"].is_null(),
            "no rating → null average"
        );
        assert_eq!(data[1]["review_count"], serde_json::json!(0));
    }
}
