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
///
/// TAX-INVOICE FIELDS (`subtotal` / `vat_amount` / `grand_total`): catalog prices are
/// VAT-EXCLUSIVE and 7% VAT is added on top, so `amount` (what was charged) is a GRAND TOTAL and
/// these three describe how it was reached. They always describe the CURRENTLY SETTLED bill: the
/// completion reconcile rewrites `subtotal`/`vat_amount` from the prorated hours, and a
/// cancellation rewrites them to the retained fee. `subtotal`/`vat_amount` are `None` only on rows
/// charged BEFORE VAT was introduced (those were never VAT'd — do not infer zero VAT-exclusive
/// pricing from a missing split).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct PaymentResponse {
    pub id: Uuid,
    pub booking_id: Uuid,
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub amount: Decimal,
    /// Server-computed authoritative total at charge time (`base_fee × hours × guards + tip`,
    /// VAT included) — the figure the customer was required to cover.
    pub expected_total: Option<Decimal>,
    /// VAT-EXCLUSIVE service cost of the settled bill. `None` on pre-VAT rows.
    pub subtotal: Option<Decimal>,
    /// 7% VAT charged on `subtotal`. `None` on pre-VAT rows.
    pub vat_amount: Option<Decimal>,
    /// `subtotal + vat_amount` — what the customer owes in total (falls back to `amount` on
    /// pre-VAT rows, so this field is always present and always the payable figure).
    pub grand_total: Decimal,
    /// Cancellation fee RETAINED when the customer cancelled (`min(fee, amount paid)`); `0` when
    /// the guard withdrew (no fault of the customer) and `None` when the booking was not cancelled.
    pub cancellation_fee_charged: Option<Decimal>,
    /// Excess the customer transferred ABOVE the estimate on a slip payment
    /// (`max(0, slip_amount − amount)`); `0` for simulated/exact payments. Always refundable ON TOP
    /// of the settled bill (never platform revenue), so every refund path returns
    /// `amount + overpaid_amount`. NOT NULL (default 0) — present on every row.
    pub overpaid_amount: Decimal,
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

// ----- PromptPay QR (customer payment screen) -----

/// `GET /payments/{id}/promptpay` response — everything the mobile needs to render the PromptPay
/// transfer screen. The `qr_payload` is the authoritative EMVCo string built SERVER-SIDE from our
/// `RECEIVING_ACCOUNT` + the server estimate (one place — the client never composes its own), so
/// the amount + receiver can never drift. Only meaningful under `PAYMENT_PROVIDER=slip2go`.
///
/// `amount` is the same exact-decimal estimate (`base_fee × hours × guards + tip`) the slip /
/// prepay handlers charge → JSON string (money rule). `amount_satang` is that amount in the
/// smallest unit (×100, integer) as a convenience for clients that price in satang — derived
/// from the same Decimal, never an f64.
#[derive(Debug, Serialize)]
pub struct PromptPayResponse {
    /// The server-side estimate the customer must transfer (exact decimal → JSON string).
    pub amount: Decimal,
    /// The estimate in satang (the smallest THB unit, ×100) as an integer — a convenience field.
    pub amount_satang: i64,
    /// OUR receiving PromptPay account, formatted for human display (e.g. `081-234-5678`).
    pub receiving_account: String,
    /// The authoritative EMVCo PromptPay QR string — render this as a QR; do NOT rebuild it.
    pub qr_payload: String,
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

/// One completed job's earning basis for the assigned guard. `actual_hours` is the clamped hours
/// ACTUALLY worked (persisted at reconcile); NULL for an even-match / not-yet-reconciled row, where
/// the client falls back to the booked hours. The client multiplies `base_fee` (from its own
/// booking feed) × these hours to show the guard's pay for hours actually worked — so the guard's
/// figure tracks what the customer was actually charged (net of the overpay refund), instead of the
/// full booked estimate that used to overstate it.
///
/// `commission_percent` is the per-service commission SNAPSHOT taken from the booking at charge
/// time, so the app can show what was deducted:
///   `gross = base_fee × actual_hours` · `commission = gross × commission_percent / 100` ·
///   `net = gross − commission`
/// (no `guard_count`, no tip — this is ONE guard's share). Commission comes out of the GUARD's pay,
/// never off the customer's bill, and VAT is not part of it: the guard is paid on the VAT-exclusive
/// service price. `None` on a job booked before commissions existed → treat as 0%.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct GuardEarningRow {
    pub booking_id: Uuid,
    pub actual_hours: Option<Decimal>,
    pub commission_percent: Option<Decimal>,
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
    /// ฿ per hour per guard (server-owned; the client never sets this). VAT-EXCLUSIVE — VAT is
    /// added on top by [`crate::domain::price_breakdown`], never baked into the catalog price.
    pub base_fee: Decimal,
    pub guard_count: i32,
    pub tip: Decimal,
    /// Per-service commission %, SNAPSHOT on the booking at creation. `None` when booking has not
    /// deployed the field yet, or the booking predates commissions → treat as 0 (see
    /// [`crate::domain::ChargeTerms::new`], which also clamps it to `0..=100`).
    #[serde(default)]
    pub commission_percent: Option<Decimal>,
    /// What a CUSTOMER cancellation of this booking costs, SNAPSHOT on the booking at creation.
    /// `None`/absent → 0 (no fee). Payment copies it onto the payment row so the refund path —
    /// an event consumer with no HTTP — can price a cancellation without a cross-service read.
    #[serde(default)]
    pub cancellation_fee: Option<Decimal>,
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
        // (matches the OpenAPI contract + never an f64), preserving 2dp scale. The tax-invoice
        // fields (subtotal/vat_amount/grand_total) follow the same rule.
        let epoch = DateTime::<Utc>::from_timestamp(0, 0).unwrap();
        let p = PaymentResponse {
            id: Uuid::nil(),
            booking_id: Uuid::nil(),
            customer_id: Uuid::nil(),
            guard_id: None,
            amount: "428.00".parse().unwrap(),
            expected_total: Some("428.00".parse().unwrap()),
            subtotal: Some("400.00".parse().unwrap()),
            vat_amount: Some("28.00".parse().unwrap()),
            grand_total: "428.00".parse().unwrap(),
            cancellation_fee_charged: None,
            overpaid_amount: Decimal::ZERO,
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
            serde_json::json!("428.00"),
            "amount must be a JSON string"
        );
        assert_eq!(v["expected_total"], serde_json::json!("428.00"));
        assert_eq!(v["final_amount"], serde_json::json!("333.33"));
        assert!(v["refund_amount"].is_null());
        // The VAT split is exact-decimal strings too, and reconstructs the grand total.
        assert_eq!(v["subtotal"], serde_json::json!("400.00"));
        assert_eq!(v["vat_amount"], serde_json::json!("28.00"));
        assert_eq!(v["grand_total"], serde_json::json!("428.00"));
        assert!(v["cancellation_fee_charged"].is_null());
        // The overpay rider is exact-decimal too (never an f64) and present on every row.
        assert_eq!(v["overpaid_amount"], serde_json::json!("0"));
    }

    #[test]
    fn guard_earning_row_carries_the_commission_snapshot() {
        // The guard app needs the % that was deducted, per job — a NULL (pre-commission booking)
        // stays NULL on the wire so the client can distinguish "0%" from "unknown".
        let row = GuardEarningRow {
            booking_id: Uuid::nil(),
            actual_hours: Some("2.00".parse().unwrap()),
            commission_percent: Some("12.50".parse().unwrap()),
        };
        let v = serde_json::to_value(&row).unwrap();
        assert_eq!(v["actual_hours"], serde_json::json!("2.00"));
        assert_eq!(v["commission_percent"], serde_json::json!("12.50"));
    }

    #[test]
    fn internal_booking_defaults_the_missing_snapshot_fields() {
        // A booking service that has not deployed the commission/cancellation columns yet sends
        // neither field — the pre-pay must still parse (and treat both as absent → 0), instead of
        // failing the authoritative read and blocking every payment.
        let b: InternalBooking = serde_json::from_value(serde_json::json!({
            "customer_id": Uuid::nil(),
            "guard_id": null,
            "status": "accepted",
            "hours": 4,
            "base_fee": "500.00",
            "guard_count": 1,
            "tip": "0.00",
        }))
        .expect("old-shape booking still parses");
        assert!(b.commission_percent.is_none());
        assert!(b.cancellation_fee.is_none());
    }
}
