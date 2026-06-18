//! API layer — thin Axum transport handlers. POST-PAY: there is NO customer-initiated charge
//! endpoint (the bill is raised by the `booking.completed` consumer). This layer serves the
//! READ surface — a customer's own payment + ledger, the admin cross-user ledger + revenue
//! report, and the service-JWT'd PDPA data export. THE MONEY PATH (reads).
//!
//! Handlers are generic over [`PaymentDeps`] so the `AuthUser` guard + role gates are
//! unit-testable with a lightweight state, mirroring booking's seam.

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

use crate::models::{AdminListPaymentsQuery, PaymentResponse, ReportRangeQuery, RevenueReport};
use crate::repo;
use crate::state::PaymentDeps;
use crate::state::PaymentInternalDeps;

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
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::get;
    use axum::Router;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use shared::auth::{encode_jwt_with_key, HasJwtSecret};
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;
    use std::time::Duration;
    use tower::ServiceExt;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-payment-test!!!";

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
        redis: redis::aio::ConnectionManager,
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
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
    }

    /// Build the payment READ router over a lightweight test state. The `AuthUser` extractor
    /// requires a real `redis::aio::ConnectionManager` (the jti blocklist), which can't be
    /// constructed without connecting. So these router tests are hermetic by default and only
    /// run when a test Redis is provided via `TEST_REDIS_URL` (falling back to `REDIS_CACHE_URL`);
    /// `None` → the caller SKIPs. The role-reject paths fail at the role gate before any DB read,
    /// so the (invalid) lazy pool is never touched.
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
        };
        Some(
            Router::new()
                .route("/admin/payments", get(admin_list_payments::<TestDeps>))
                .route(
                    "/admin/reports/revenue",
                    get(admin_revenue_report::<TestDeps>),
                )
                .with_state(deps),
        )
    }

    fn customer_token(user_id: Uuid, role: &str) -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _jti) = encode_jwt_with_key(user_id, role, 0, &ek, 15).unwrap();
        tok
    }

    #[tokio::test]
    async fn admin_list_payments_rejects_non_admin() {
        let Some(app) = router().await else {
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
    async fn admin_revenue_report_rejects_non_admin() {
        let Some(app) = router().await else {
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
}
