//! DTOs for the payment service (transport shapes). Pure data — no I/O.
//!
//! ALL money fields are [`rust_decimal::Decimal`] — never `f64` (CLAUDE.md money rules).

use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ----- Requests -----

/// Body of `POST /payments` (createPayment — PRE-PAY). The client sends ONLY the booking id;
/// the amount is computed SERVER-SIDE from the authoritative booking (`base_fee × hours ×
/// guard_count + tip`), never trusted from the client (CLAUDE.md money rules).
#[derive(Debug, Deserialize)]
pub struct CreatePaymentRequest {
    pub booking_id: Uuid,
}

/// Inclusive-from / exclusive-to date window for the analytics reports (RFC3339). Both
/// optional — the handler defaults to the last 30 days ending now.
#[derive(Debug, Deserialize)]
pub struct ReportRangeQuery {
    pub from: Option<DateTime<Utc>>,
    pub to: Option<DateTime<Utc>>,
}

/// Query params for `GET /admin/payments` (admin cross-user ledger). `status` is validated
/// against the payment status enum (unknown → 400); `customer_id` narrows to one customer's
/// payments (the customer-spend drill-down). House limit/offset pagination.
#[derive(Debug, Deserialize)]
pub struct AdminListPaymentsQuery {
    pub status: Option<String>,
    pub customer_id: Option<Uuid>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

// ----- Responses -----

/// A payment row as returned to clients. `status` is read as text (the DB enum cast to
/// text) so the read path needs no enum decoding — mirrors the booking/notification slices.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct PaymentResponse {
    pub id: Uuid,
    pub booking_id: Uuid,
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub amount: Decimal,
    /// Server-computed authoritative total at charge time (`base_fee × hours × guards + tip`).
    pub expected_total: Option<Decimal>,
    pub payment_method: Option<String>,
    pub status: String,
    pub final_amount: Option<Decimal>,
    pub refund_amount: Option<Decimal>,
    pub actual_hours: Option<Decimal>,
    /// `pending` once a refund is owed (admin marks `processed` later); else `None`.
    pub refund_status: Option<String>,
    pub paid_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

// ----- Revenue report (admin analytics) -----

/// One day's net revenue point. `revenue` is net of refunds (Decimal → JSON string, money
/// rule); `payments` counts completed charges that day.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct RevenuePoint {
    pub date: NaiveDate,
    pub revenue: Decimal,
    pub payments: i64,
}

/// Revenue-trend report. `mom_pct` compares the window's total to the immediately-preceding
/// equal-length window (`None` when the prior window had zero revenue — no baseline). It is a
/// display-only percentage (f64); the money totals stay Decimal-as-string on the wire.
#[derive(Debug, Serialize)]
pub struct RevenueReport {
    pub series: Vec<RevenuePoint>,
    pub total: Decimal,
    pub prev_total: Decimal,
    pub mom_pct: Option<f64>,
}

// ----- booking internal read (deserialized from booking's /internal/bookings/{id}) -----

/// The authoritative booking fields the PRE-PAY charge verifies + prices against. Mirrors the
/// relevant subset of booking's `InternalBooking`; serde ignores the extra fields (id/guard_id)
/// the charge does not need. The PRE-PAY estimate is `base_fee × hours × guard_count + tip`
/// computed from THESE server-owned values — never a client body. Money fields deserialize from
/// a JSON string (rust_decimal serde-str, workspace-wide).
#[derive(Debug, Clone, Deserialize)]
pub struct InternalBooking {
    pub customer_id: Uuid,
    /// The accepted guard (`Some` once a guard claimed the booking — always set in a payable
    /// state). Carried onto `payment.completed` so notification can push the guard
    /// "ลูกค้าชำระเงินแล้ว".
    pub guard_id: Option<Uuid>,
    pub status: String,
    pub hours: i32,
    /// ฿ per hour per guard (server-owned; the client never sets this).
    pub base_fee: Decimal,
    pub guard_count: i32,
    pub tip: Decimal,
}

// ----- Refund queue (admin dashboard signal) -----

/// Query params for `GET /admin/refunds/queue`. `status` optionally narrows to one refund-workflow
/// state (`pending` = awaiting action, `processed` = done); omitted → both. House limit/offset.
#[derive(Debug, Deserialize)]
pub struct RefundQueueQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// One refund-queue row — a payment whose settle left a refund owed. `amount` is the
/// `refund_amount` (the money to return, not the original charge); `status` is the refund-workflow
/// state (`pending`/`processed`), NOT the payment status (a partial refund stays `completed`).
/// Exact-decimal `amount` → JSON string (money rule).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct RefundQueueItem {
    pub payment_id: Uuid,
    pub booking_id: Uuid,
    pub amount: Decimal,
    pub status: String,
    pub created_at: DateTime<Utc>,
}

/// The admin refund-queue response: the matching refund rows (newest first) + the total `count`
/// of rows matching the same filter (the dashboard "คิวคืนเงิน" badge), independent of limit/offset.
#[derive(Debug, Serialize)]
pub struct RefundQueueResponse {
    pub refunds: Vec<RefundQueueItem>,
    pub count: i64,
}

// ----- Customer-spend report (admin analytics) -----

/// One customer's lifetime spend — the sum of their actually-charged (completed) payments'
/// effective amount (prorated `final_amount` when set, else `amount`). Powers the web-admin
/// customers page's spend column. `total` is exact-decimal → JSON string (money rule), mirroring
/// `RevenuePoint.revenue`.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct CustomerSpend {
    pub customer_id: Uuid,
    pub total: Decimal,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn money_serializes_as_string_not_float() {
        // Guards the rust_decimal `serde-str` wire format: money MUST be a JSON string
        // (matches the OpenAPI contract + never an f64), preserving 2dp scale.
        let epoch = DateTime::<Utc>::from_timestamp(0, 0).unwrap();
        let p = PaymentResponse {
            id: Uuid::nil(),
            booking_id: Uuid::nil(),
            customer_id: Uuid::nil(),
            guard_id: None,
            amount: "400.00".parse().unwrap(),
            expected_total: Some("400.00".parse().unwrap()),
            payment_method: Some("promptpay".to_string()),
            status: "completed".to_string(),
            final_amount: Some("333.33".parse().unwrap()),
            refund_amount: None,
            actual_hours: None,
            refund_status: None,
            paid_at: None,
            created_at: epoch,
            updated_at: epoch,
        };
        let v = serde_json::to_value(&p).unwrap();
        assert_eq!(
            v["amount"],
            serde_json::json!("400.00"),
            "amount must be a JSON string"
        );
        assert_eq!(v["expected_total"], serde_json::json!("400.00"));
        assert_eq!(v["final_amount"], serde_json::json!("333.33"));
        assert!(v["refund_amount"].is_null());
    }
}
