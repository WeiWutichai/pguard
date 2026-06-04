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

use crate::booking_client::BookingReader;
use crate::domain::{compute_proration, is_payable_status, validate_payment};
use crate::models::{CompletePaymentRequest, CreatePaymentRequest, PaymentResponse};
use crate::repo;
use crate::state::PaymentDeps;

/// POST /payments — a customer pays for a booking.
///
/// Money-rule discipline (CLAUDE.md):
///  1. VERIFY against the authoritative booking (service-JWT'd internal read), never the
///     client: caller must be the booking's customer; booking must be in a payable status.
///  2. `guard_id` for the event comes from the booking, not the request.
///  3. Validate the (client-supplied) amount: `> 0`, `<= cap` (authoritative price is a
///     tracked follow-up — v2 booking has no price column yet).
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

    // (4) idempotent charge + outbox event. `guard_id` from the booking (2).
    let payment = repo::charge_idempotent(
        state.db(),
        booking.id,
        booking.customer_id,
        booking.guard_id,
        req.amount,
        &req.payment_method,
        Uuid::new_v4(),
    )
    .await?;

    Ok(Json(ApiResponse::success(payment)))
}

/// POST /payments/{booking_id}/complete — apply proration on job completion.
///
/// Actor gate: admin OR a service caller drives this (a customer cannot prorate their own
/// payment). For now we gate to `admin` via the user JWT; a system/service actor path is a
/// tracked follow-up (the booking-completion event consumer will call this). The proration
/// math is pure ([`compute_proration`]); the refund event is enqueued in the same tx.
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

    let payment = repo::get_payment_for_booking_amount(state.db(), booking_id).await?;
    let proration = compute_proration(payment.amount, booking.hours, req.actual_seconds);

    let updated = repo::apply_proration(state.db(), booking_id, proration, Uuid::new_v4()).await?;
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
    let items = repo::list_payments(state.db(), user.user_id).await?;
    Ok(Json(ApiResponse::success(items)))
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
    /// requires a real `redis::aio::MultiplexedConnection` (the jti blocklist), which can't
    /// be constructed without connecting. So these router tests are hermetic by default and
    /// only run when a test Redis is provided via `TEST_REDIS_URL` (falling back to
    /// `REDIS_CACHE_URL`). Returns `None` → the caller SKIPs. The auth-reject paths never
    /// query Redis (they fail at token parse first), so a reachable Redis is enough.
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
}
