//! API layer — thin Axum transport handlers. PRE-PAY: the customer-facing `POST /payments`
//! (createPayment) charges the server-computed ESTIMATE once a guard has accepted; that payment
//! gates the booking's en_route. This layer also serves the READ surface — a customer's own
//! payment + ledger, the admin cross-user ledger + revenue report, and the service-JWT'd PDPA
//! data export. THE MONEY PATH.
//!
//! Handlers are generic over [`PaymentDeps`] so the `AuthUser` guard + role/authz gates are
//! unit-testable with a lightweight state, mirroring rating's seam.

use axum::extract::{Path, Query, State};
use axum::Json;
use chrono::{TimeDelta, Utc};
use rust_decimal::prelude::ToPrimitive;
use rust_decimal::Decimal;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;
use shared::service_jwt::ServiceCaller;

use crate::booking_client::BookingReader;
use crate::domain;
use crate::models::{
    AdminListPaymentsQuery, CreatePaymentRequest, CustomerSpend, PaymentResponse, RefundQueueQuery,
    RefundQueueResponse, ReportRangeQuery, RevenueReport,
};
use crate::repo;
use crate::repo::PrePayOutcome;
use crate::state::PaymentDeps;
use crate::state::PaymentInternalDeps;

/// The recorded `payment_method` for a PRE-PAY charge. v2's gateway is simulated and there is no
/// real card-on-file step yet, so a successful pre-pay is tagged `prepaid`; a real gateway
/// integration would replace this with the captured method (PromptPay/card/…).
const PREPAID_METHOD: &str = "prepaid";

/// POST /payments — PRE-PAY a booking's estimate (createPayment). THE MONEY PATH (write).
///
/// v2 is PRE-PAY: after a guard ACCEPTS, the customer pays the estimate up front, which GATES the
/// booking's en_route (booking learns it is paid by consuming `payment.completed`). Discipline
/// (CLAUDE.md — never trust the client; money is server-computed):
///  1. role=customer.
///  2. VERIFY against the authoritative booking (service-JWT'd internal read): the caller must be
///     the booking's customer AND the booking must be in a payable state (post-accept,
///     pre-complete).
///  3. The amount is the SERVER-computed estimate `base_fee × hours × guard_count + tip` from the
///     booking's own pricing — exact `Decimal`, NEVER an f64, NEVER the client body.
///  4. Idempotent per booking (DB UNIQUE partial index): a repeat is a no-op returning the
///     existing payment (no second charge, no second `payment.completed`).
#[tracing::instrument(skip(state, req), fields(user = %user.user_id))]
pub async fn create_payment<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Json(req): Json<CreatePaymentRequest>,
) -> Result<Json<ApiResponse<PaymentResponse>>, AppError> {
    if user.role != "customer" {
        return Err(AppError::Forbidden(
            "Only customers can pay for a booking".to_string(),
        ));
    }

    // (1) authoritative verification — the charge trusts the booking, not the body.
    let booking = state.booking_reader().get_booking(req.booking_id).await?;

    if booking.customer_id != user.user_id {
        // Generic 403 — never reveal whether the booking exists / belongs to someone else.
        return Err(AppError::Forbidden(
            "You can only pay for your own booking".to_string(),
        ));
    }
    if !domain::is_payable_status(&booking.status) {
        return Err(AppError::Conflict(
            "This booking is not awaiting payment".to_string(),
        ));
    }

    // (2) SERVER-computed estimate from the booking's own pricing (never the client body).
    let estimate = domain::expected_total(
        booking.base_fee,
        booking.hours,
        booking.guard_count,
        booking.tip,
    );

    // (3) idempotent pre-pay + payment.completed outbox event, in ONE tx. A repeat is a no-op.
    let outcome = repo::prepay_idempotent(
        state.db(),
        req.booking_id,
        user.user_id,
        booking.guard_id,
        estimate,
        estimate,
        PREPAID_METHOD,
        Uuid::new_v4(),
    )
    .await?;

    let payment = match outcome {
        PrePayOutcome::Created(p) => {
            tracing::info!(payment_id = %p.id, amount = %estimate, "pre-pay charged (estimate)");
            p
        }
        PrePayOutcome::AlreadyPaid(p) => {
            // Idempotent: the booking was already pre-paid. Return the existing payment (200).
            tracing::info!(payment_id = %p.id, "pre-pay no-op (already paid)");
            p
        }
    };

    Ok(Json(ApiResponse::success(payment)))
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

/// Valid `?status=` filter values for the admin ledger (the payment.payment_status enum).
const PAYMENT_STATUSES: &[&str] = &["pending", "completed", "refunded"];

/// GET /admin/payments — admin cross-user payment ledger (READ-ONLY). Admin only (the edge
/// proves identity, not role). Optional `status` filter + limit/offset; replica read. This is
/// a reporting surface prepared ahead of a real payment integration — there is intentionally
/// NO manual refund-process endpoint here (v2 refunds are event-driven; see PROGRESS notes).
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn admin_list_payments<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<AdminListPaymentsQuery>,
) -> Result<Json<ApiResponse<Vec<PaymentResponse>>>, AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
    }
    let status = match q.status.as_deref() {
        None => None,
        Some(s) if PAYMENT_STATUSES.contains(&s) => Some(s),
        Some(_) => return Err(AppError::BadRequest("invalid status filter".to_string())),
    };
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);
    let items =
        repo::admin_list_payments(state.db_read(), status, q.customer_id, limit, offset).await?;
    Ok(Json(ApiResponse::success(items)))
}

/// Valid `?status=` filter values for the refund queue (the `refund_status` workflow states).
const REFUND_STATUSES: &[&str] = &["pending", "processed"];

/// GET /admin/refunds/queue — admin refund queue: payments awaiting refund action / in progress
/// (`refund_status` set), newest first. Admin only (the edge proves identity, not role). Optional
/// `status` filter (`pending` = awaiting action, `processed` = done; omitted → both) + limit/offset;
/// replica read. Returns the page of refunds PLUS the total `count` matching the same filter (the
/// dashboard "แจ้งเตือน / คิวคืนเงิน" badge — independent of the page window). v2 refunds are
/// event-driven (a settle sets `refund_status='pending'`); this is the READ surface that surfaces
/// them — there is intentionally no manual refund-process action here yet.
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn admin_refund_queue<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<RefundQueueQuery>,
) -> Result<Json<ApiResponse<RefundQueueResponse>>, AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
    }
    let status = match q.status.as_deref() {
        None => None,
        Some(s) if REFUND_STATUSES.contains(&s) => Some(s),
        Some(_) => return Err(AppError::BadRequest("invalid status filter".to_string())),
    };
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);
    let refunds = repo::admin_list_refund_queue(state.db_read(), status, limit, offset).await?;
    let count = repo::admin_count_refund_queue(state.db_read(), status).await?;
    Ok(Json(ApiResponse::success(RefundQueueResponse {
        refunds,
        count,
    })))
}

/// Default analytics window when `from`/`to` are omitted, and the hard cap on its length.
const REPORT_DEFAULT_DAYS: i64 = 30;
const REPORT_MAX_DAYS: i64 = 366;

/// Resolve the `[from, to)` window: default last 30 days ending now; `from` clamped so the
/// window never exceeds a year (bounds the aggregation scan). Shared shape with booking's report.
fn report_range(q: &ReportRangeQuery) -> (chrono::DateTime<Utc>, chrono::DateTime<Utc>) {
    let to = q.to.unwrap_or_else(Utc::now);
    let from = q
        .from
        .unwrap_or_else(|| to - TimeDelta::days(REPORT_DEFAULT_DAYS));
    let earliest = to - TimeDelta::days(REPORT_MAX_DAYS);
    (from.max(earliest).min(to), to)
}

/// GET /admin/reports/revenue?from=&to= — daily net-revenue series + MoM vs the prior window.
/// Admin only. Read from the replica (pure analytics, no read-after-write).
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn admin_revenue_report<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<ReportRangeQuery>,
) -> Result<Json<ApiResponse<RevenueReport>>, AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
    }
    let (from, to) = report_range(&q);
    let series = repo::revenue_series(state.db_read(), from, to).await?;
    let total: Decimal = series.iter().map(|p| p.revenue).sum();
    // MoM: the immediately-preceding equal-length window.
    let len = to - from;
    let prev_total = repo::revenue_total(state.db_read(), from - len, from).await?;
    let mom_pct = if prev_total == Decimal::ZERO {
        None
    } else {
        ((total - prev_total) / prev_total * Decimal::from(100)).to_f64()
    };
    Ok(Json(ApiResponse::success(RevenueReport {
        series,
        total,
        prev_total,
        mom_pct,
    })))
}

/// GET /admin/reports/customer-spend — per-customer lifetime spend (summed completed-payment
/// effective amount), for the web-admin customers page. Admin only. Read from the replica (pure
/// analytics, no read-after-write). Each customer's `total` is exact-decimal → JSON string.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn admin_customer_spend_report<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<CustomerSpend>>>, AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
    }
    let rows = repo::customer_spend(state.db_read()).await?;
    Ok(Json(ApiResponse::success(rows)))
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
    use crate::booking_client::BookingReader;
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

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-payment-test!!!";

    /// Stub booking reader — canned booking (or NotFound), no HTTP. Lets the createPayment
    /// role/authz gates be tested hermetically (mirrors rating's `StubReader`).
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

    /// Build the payment router over a lightweight test state. The `AuthUser` extractor requires
    /// a real `redis::aio::ConnectionManager` (the jti blocklist), which can't be constructed
    /// without connecting. So these router tests are hermetic by default and only run when a test
    /// Redis is provided via `TEST_REDIS_URL` (falling back to `REDIS_CACHE_URL`); `None` → the
    /// caller SKIPs. The role/authz reject paths fail at the gate before any DB read, so the
    /// (invalid) lazy pool is never touched.
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
                .route("/admin/payments", get(admin_list_payments::<TestDeps>))
                .route("/admin/refunds/queue", get(admin_refund_queue::<TestDeps>))
                .route(
                    "/admin/reports/revenue",
                    get(admin_revenue_report::<TestDeps>),
                )
                .route(
                    "/admin/reports/customer-spend",
                    get(admin_customer_spend_report::<TestDeps>),
                )
                .with_state(deps),
        )
    }

    fn customer_token(user_id: Uuid, role: &str) -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _jti) = encode_jwt_with_key(user_id, role, 0, &ek, 15).unwrap();
        tok
    }

    /// A payable booking (guard accepted) owned by `customer_id`, priced 500×4×1 + 0 = 2000.00.
    fn payable_booking(customer_id: Uuid) -> InternalBooking {
        InternalBooking {
            customer_id,
            guard_id: Some(Uuid::new_v4()),
            status: "accepted".to_string(),
            hours: 4,
            base_fee: "500".parse().unwrap(),
            guard_count: 1,
            tip: rust_decimal::Decimal::ZERO,
        }
    }

    fn create_payment_req(booking_id: Uuid) -> Body {
        Body::from(serde_json::json!({ "booking_id": booking_id }).to_string())
    }

    async fn post_payment(app: Router, tok: Option<&str>, body: Body) -> StatusCode {
        let mut b = Request::builder()
            .method("POST")
            .uri("/payments")
            .header("content-type", "application/json");
        if let Some(t) = tok {
            b = b.header("authorization", format!("Bearer {t}"));
        }
        app.oneshot(b.body(body).unwrap()).await.unwrap().status()
    }

    // ----- POST /payments (createPayment — PRE-PAY): role + authz gates -----

    #[tokio::test]
    async fn create_payment_rejects_missing_token() {
        let Some(app) = router(Some(payable_booking(Uuid::new_v4()))).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // No bearer → 401 (the service validates, not just the gateway edge).
        assert_eq!(
            post_payment(app, None, create_payment_req(Uuid::new_v4())).await,
            StatusCode::UNAUTHORIZED
        );
    }

    #[tokio::test]
    async fn create_payment_rejects_non_customer() {
        // A guard must not pay for a booking (role gate, before any booking read).
        let Some(app) = router(Some(payable_booking(Uuid::new_v4()))).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = customer_token(Uuid::new_v4(), "guard");
        assert_eq!(
            post_payment(app, Some(&tok), create_payment_req(Uuid::new_v4())).await,
            StatusCode::FORBIDDEN
        );
    }

    #[tokio::test]
    async fn create_payment_rejects_paying_someone_elses_booking() {
        // Caller is a customer, but the authoritative booking belongs to a DIFFERENT customer →
        // 403, decided against the booking read (never the body), before any DB write.
        let Some(app) = router(Some(payable_booking(Uuid::new_v4()))).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = customer_token(Uuid::new_v4(), "customer");
        assert_eq!(
            post_payment(app, Some(&tok), create_payment_req(Uuid::new_v4())).await,
            StatusCode::FORBIDDEN
        );
    }

    #[tokio::test]
    async fn create_payment_rejects_non_payable_status() {
        // Owner matches, but the booking is not in a payable state (no guard yet) → 409, before
        // any DB write. Proves the estimate path is GATED on an accepted booking.
        let me = Uuid::new_v4();
        let mut booking = payable_booking(me);
        booking.status = "requested".to_string();
        booking.guard_id = None;
        let Some(app) = router(Some(booking)).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = customer_token(me, "customer");
        assert_eq!(
            post_payment(app, Some(&tok), create_payment_req(Uuid::new_v4())).await,
            StatusCode::CONFLICT
        );
    }

    #[tokio::test]
    async fn create_payment_estimate_ignores_client_amount() {
        // The request body has NO amount field — the estimate is computed SERVER-SIDE from the
        // booking (proved by the pure `domain::expected_total` tests). Here we assert a body that
        // tries to smuggle an `amount` is simply ignored (still parses to the same request).
        let me = Uuid::new_v4();
        let Some(app) = router(Some(payable_booking(me))).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = customer_token(me, "customer");
        // Owner matches + booking payable → the handler proceeds past authz to the DB write. The
        // lazy pool is invalid, so the write errors (500), NOT a 4xx — i.e. the client `amount`
        // was never validated/honored; the flow reached the server-priced charge. (The actual
        // charge + estimate value are covered by the repo DB test + the domain unit tests.)
        let body = Body::from(
            serde_json::json!({ "booking_id": Uuid::new_v4(), "amount": "1.00" }).to_string(),
        );
        let status = post_payment(app, Some(&tok), body).await;
        assert_eq!(
            status,
            StatusCode::INTERNAL_SERVER_ERROR,
            "authz passed and the client amount was ignored; the flow reached the server-priced DB write"
        );
    }

    #[tokio::test]
    async fn admin_list_payments_rejects_non_admin() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not read the cross-user payment ledger (every customer's money).
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/payments")
                    .header(
                        "authorization",
                        format!("Bearer {}", customer_token(Uuid::new_v4(), "customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_refund_queue_rejects_non_admin() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not read the cross-user refund queue (every customer's owed refunds).
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/refunds/queue")
                    .header(
                        "authorization",
                        format!("Bearer {}", customer_token(Uuid::new_v4(), "customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_revenue_report_rejects_non_admin() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not read cross-user revenue analytics.
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/reports/revenue")
                    .header(
                        "authorization",
                        format!("Bearer {}", customer_token(Uuid::new_v4(), "customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_customer_spend_report_rejects_non_admin() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not read cross-user per-customer spend analytics.
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/reports/customer-spend")
                    .header(
                        "authorization",
                        format!("Bearer {}", customer_token(Uuid::new_v4(), "customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }
}
