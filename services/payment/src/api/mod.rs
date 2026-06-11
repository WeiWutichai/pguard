//! API layer — thin Axum transport handlers. No business logic beyond role gating +
//! orchestration of the booking-reader (authoritative verification), `domain` (pure
//! validation + proration), and `repo` (the atomic charge/proration writes). THE MONEY PATH.
//!
//! Handlers are generic over [`PaymentDeps`] so the `AuthUser` guard + role/idempotency
//! gates are unit-testable with a lightweight state (no live booking service), mirroring
//! booking's seam.

use axum::extract::{Path, State};
use axum::Json;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;
use shared::service_jwt::ServiceCaller;

use crate::booking_client::BookingReader;
use crate::domain::{amount_covers_expected, expected_total, is_payable_status, validate_payment};
use crate::models::{CompletePaymentRequest, CreatePaymentRequest, PaymentResponse};
use crate::repo;
use crate::state::PaymentDeps;
use crate::state::PaymentInternalDeps;

/// POST /payments — a customer pays for a booking.
///
/// Money-rule discipline (CLAUDE.md):
///  1. VERIFY against the authoritative booking (service-JWT'd internal read), never the
///     client: caller must be the booking's customer; booking must be in a payable status.
///  2. `guard_id` for the event comes from the booking, not the request.
///  3. Validate the amount: well-formed (`> 0`, `<= cap`, ≤2dp) AND covers the SERVER-computed
///     `expected_total` (`base_fee × hours × guard_count + tip`, all from the booking). A
///     client can never undercut the authoritative price; surplus is an extra tip.
///  4. Idempotent insert + `payment.completed` event in ONE tx (transactional outbox).
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, booking_id = %req.booking_id))]
pub async fn create_payment<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Json(req): Json<CreatePaymentRequest>,
) -> Result<Json<ApiResponse<PaymentResponse>>, AppError> {
    if user.role != "customer" {
        return Err(AppError::Forbidden(
            "Only customers can make payments".to_string(),
        ));
    }

    // (3) validate the amount BEFORE any I/O. Generic, non-enumerating message.
    validate_payment(&req.payment_method, req.amount)
        .map_err(|e| AppError::BadRequest(e.message().to_string()))?;

    // (1) authoritative verification — the money decision trusts the booking, not the body.
    let booking = state.booking_reader().get_booking(req.booking_id).await?;

    if booking.customer_id != user.user_id {
        // Generic 403 — never reveal whether the booking exists / belongs to someone else.
        return Err(AppError::Forbidden(
            "You can only pay for your own bookings".to_string(),
        ));
    }
    if !is_payable_status(&booking.status) {
        return Err(AppError::Conflict(
            "Booking is not in a payable state".to_string(),
        ));
    }

    // (3b) the authoritative total — computed from the booking's server-owned pricing inputs,
    // never the request body. The amount must cover it (a client can't undercut the price).
    let expected = expected_total(
        booking.base_fee,
        booking.hours,
        booking.guard_count,
        booking.tip,
    );
    if !amount_covers_expected(req.amount, expected) {
        // Generic message — do NOT echo the expected total (no internal/pricing leak).
        return Err(AppError::BadRequest(
            "Payment amount does not cover the booking total".to_string(),
        ));
    }

    // (4) idempotent charge + outbox event. `guard_id` + `expected_total` from the booking (2).
    let payment = repo::charge_idempotent(
        state.db(),
        booking.id,
        booking.customer_id,
        booking.guard_id,
        req.amount,
        expected,
        &req.payment_method,
        Uuid::new_v4(),
    )
    .await?;

    Ok(Json(ApiResponse::success(payment)))
}

/// POST /payments/{booking_id}/complete — ADMIN override to apply proration on job
/// completion. The primary finalization path is the `booking.completed` event consumer
/// (see `events::consumer`); this stays as a manual override (e.g. a stuck event).
///
/// Actor gate: admin only (a customer cannot prorate their own payment). The booked hours +
/// status are read from the authoritative booking (never the client). **Idempotent**: if the
/// event consumer already finalized this payment, `repo::apply_proration` returns the current
/// row unchanged — the admin call can never stack a second refund on top.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, booking_id = %booking_id))]
pub async fn complete_payment<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(booking_id): Path<Uuid>,
    Json(req): Json<CompletePaymentRequest>,
) -> Result<Json<ApiResponse<PaymentResponse>>, AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "Only admins can finalize payments".to_string(),
        ));
    }

    // Read the authoritative booked hours + status from booking (never trust the client).
    let booking = state.booking_reader().get_booking(booking_id).await?;

    // Proration is only legitimate once the job is actually completed — otherwise there is
    // no factual "actual hours worked" basis (mirrors the charge path's status discipline).
    if !crate::domain::is_finalizable_status(&booking.status) {
        return Err(AppError::Conflict(
            "Booking is not completed; cannot prorate".to_string(),
        ));
    }

    // Proration (tip-protected) + refund event live in repo, shared with the event consumer.
    let updated = repo::apply_proration(
        state.db(),
        booking_id,
        booking.hours,
        req.actual_seconds,
        Uuid::new_v4(),
    )
    .await?;
    Ok(Json(ApiResponse::success(updated)))
}

/// GET /payments/{id} — fetch one payment the caller owns (or admin).
#[tracing::instrument(skip(state), fields(user = %user.user_id, payment_id = %id))]
pub async fn get_payment<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<PaymentResponse>>, AppError> {
    let payment = repo::get_payment(state.db(), id).await?;
    if payment.customer_id != user.user_id && user.role != "admin" {
        // Generic 403 (no resource enumeration).
        return Err(AppError::Forbidden("Not your payment".to_string()));
    }
    Ok(Json(ApiResponse::success(payment)))
}

/// GET /payments — list the caller's payments (as the paying customer).
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn list_payments<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<PaymentResponse>>>, AppError> {
    // List read → replica (C5.3); single get_payment stays on the primary (money read).
    let items = repo::list_payments(state.db_read(), user.user_id).await?;
    Ok(Json(ApiResponse::success(items)))
}

// ----- GET /internal/users/{user_id}/export (PDPA §19/§32 data export) -----

/// Export a user's OWN payments for a cross-service data export. `ServiceCaller`-gated (only
/// identity's aggregator reaches this) and scoped strictly to the path `user_id`.
#[tracing::instrument(skip(state), fields(caller = %caller.service, user = %user_id))]
pub async fn internal_export_user<S: PaymentInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    let payments = repo::export_user_payments(state.db_read(), user_id).await?;
    Ok(Json(ApiResponse::success(payments)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::InternalBooking;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::post;
    use axum::Router;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use rust_decimal::Decimal;
    use shared::auth::{encode_jwt_with_key, HasJwtSecret};
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;
    use std::time::Duration;
    use tower::ServiceExt;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-payment-test!!!";

    /// A booking reader stub — returns a canned booking (or NotFound) without any HTTP. Lets
    /// the role/auth gates be tested hermetically.
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
        redis: redis::aio::ConnectionManager,
        reader: StubReader,
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
    impl PaymentDeps for TestDeps {
        type Reader = StubReader;
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn booking_reader(&self) -> &StubReader {
            &self.reader
        }
    }

    /// Build the payment router over a lightweight test state. The `AuthUser` extractor
    /// requires a real `redis::aio::ConnectionManager` (the jti blocklist), which can't
    /// be constructed without connecting. So these router tests are hermetic by default and
    /// only run when a test Redis is provided via `TEST_REDIS_URL` (falling back to
    /// `REDIS_CACHE_URL`). Returns `None` → the caller SKIPs. The auth-reject paths never
    /// query Redis (they fail at token parse first), so a reachable Redis is enough.
    async fn router(booking: Option<InternalBooking>) -> Option<Router> {
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
            reader: StubReader { booking },
        };
        Some(
            Router::new()
                .route("/payments", post(create_payment::<TestDeps>))
                .with_state(deps),
        )
    }

    fn customer_token(user_id: Uuid, role: &str) -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _jti) = encode_jwt_with_key(user_id, role, 0, &ek, 15).unwrap();
        tok
    }

    fn pay_body(booking_id: Uuid, amount: &str) -> Body {
        Body::from(
            serde_json::json!({
                "booking_id": booking_id,
                "amount": amount.parse::<Decimal>().unwrap(),
                "payment_method": "promptpay"
            })
            .to_string(),
        )
    }

    #[tokio::test]
    async fn create_rejects_missing_token() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/payments")
                    .header("content-type", "application/json")
                    .body(pay_body(Uuid::new_v4(), "100.00"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn create_rejects_invalid_token() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/payments")
                    .header("authorization", "Bearer not.a.valid.jwt")
                    .header("content-type", "application/json")
                    .body(pay_body(Uuid::new_v4(), "100.00"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn create_rejects_non_customer_role() {
        // A guard token must be rejected at the role gate (403), before any booking read.
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = customer_token(Uuid::new_v4(), "guard");
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/payments")
                    .header("authorization", format!("Bearer {tok}"))
                    .header("content-type", "application/json")
                    .body(pay_body(Uuid::new_v4(), "100.00"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn create_rejects_non_positive_amount() {
        // Amount validation fires before the booking read — a zero amount is a 400.
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = customer_token(Uuid::new_v4(), "customer");
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/payments")
                    .header("authorization", format!("Bearer {tok}"))
                    .header("content-type", "application/json")
                    .body(pay_body(Uuid::new_v4(), "0"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn create_rejects_paying_someone_elses_booking() {
        // The caller is a customer, but the (authoritative) booking belongs to a DIFFERENT
        // customer → 403. Proves the money decision trusts the booking, not the JWT subject
        // matching a client-supplied field. No DB needed (rejected before the charge).
        let me = Uuid::new_v4();
        let other = Uuid::new_v4();
        let booking_id = Uuid::new_v4();
        let booking = InternalBooking {
            id: booking_id,
            customer_id: other, // not me
            guard_id: Some(Uuid::new_v4()),
            status: "accepted".to_string(),
            hours: 4,
            base_fee: "500.00".parse().unwrap(),
            guard_count: 1,
            tip: Decimal::ZERO,
        };
        let Some(app) = router(Some(booking)).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = customer_token(me, "customer");
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/payments")
                    .header("authorization", format!("Bearer {tok}"))
                    .header("content-type", "application/json")
                    .body(pay_body(booking_id, "100.00"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn create_rejects_unpayable_status() {
        // Owner matches, but the booking is not `accepted` → 409 (not payable).
        let me = Uuid::new_v4();
        let booking_id = Uuid::new_v4();
        let booking = InternalBooking {
            id: booking_id,
            customer_id: me,
            guard_id: None,
            status: "requested".to_string(), // not payable
            hours: 4,
            base_fee: "500.00".parse().unwrap(),
            guard_count: 1,
            tip: Decimal::ZERO,
        };
        let Some(app) = router(Some(booking)).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = customer_token(me, "customer");
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/payments")
                    .header("authorization", format!("Bearer {tok}"))
                    .header("content-type", "application/json")
                    .body(pay_body(booking_id, "100.00"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::CONFLICT);
    }

    #[tokio::test]
    async fn create_rejects_amount_below_expected() {
        // Owner + payable, but the amount is below the SERVER-computed total
        // (500 × 4h × 1 + 0 = 2000) → 400. Proves the client can't undercut the price.
        // Rejected before the DB charge, so no live DB is needed.
        let me = Uuid::new_v4();
        let booking_id = Uuid::new_v4();
        let booking = InternalBooking {
            id: booking_id,
            customer_id: me,
            guard_id: Some(Uuid::new_v4()),
            status: "accepted".to_string(),
            hours: 4,
            base_fee: "500.00".parse().unwrap(),
            guard_count: 1,
            tip: Decimal::ZERO,
        };
        let Some(app) = router(Some(booking)).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = customer_token(me, "customer");
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/payments")
                    .header("authorization", format!("Bearer {tok}"))
                    .header("content-type", "application/json")
                    .body(pay_body(booking_id, "1999.99")) // one satang short of 2000.00
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::BAD_REQUEST);
    }
}
