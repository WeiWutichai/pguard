//! DTOs for the payment service (transport shapes). Pure data — no I/O.
//!
//! ALL money fields are [`rust_decimal::Decimal`] — never `f64` (CLAUDE.md money rules).

use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ----- Requests -----

/// A customer pays for a booking. `amount` is validated against the SERVER-computed
/// `expected_total` (`base_fee × hours × guard_count + tip`, all from the authoritative
/// booking read) — the client can never pay less than the authoritative total; the surplus,
/// if any, is treated as an extra tip. The customer/guard/status also come from the booking
/// read, never the client (CLAUDE.md money rules — no client-trusted authoritative fields).
#[derive(Debug, Deserialize)]
pub struct CreatePaymentRequest {
    pub booking_id: Uuid,
    pub amount: Decimal,
    pub payment_method: String,
}

/// Apply proration to a completed booking. `actual_seconds` is the seconds the guard
/// actually worked (read from the booking in a later slice; supplied explicitly for now).
#[derive(Debug, Deserialize)]
pub struct CompletePaymentRequest {
    pub actual_seconds: i64,
}

/// Query params for `GET /admin/payments` (admin cross-user ledger). `status` is validated
/// against the payment status enum (unknown → 400). House limit/offset pagination.
#[derive(Debug, Deserialize)]
pub struct AdminListPaymentsQuery {
    pub status: Option<String>,
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

// ----- booking internal read (deserialized from booking's /internal/bookings/{id}) -----

/// The authoritative booking fields the booking service returns to the payment service.
/// Mirrors booking's `InternalBooking`. We deserialize the `{ success, data }` envelope's
/// `data` into this. `base_fee`/`guard_count`/`tip` are the server-owned pricing inputs the
/// money path uses to compute the expected total (never trusting the client).
#[derive(Debug, Clone, Deserialize)]
pub struct InternalBooking {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub status: String,
    pub hours: i32,
    pub base_fee: Decimal,
    pub guard_count: i32,
    pub tip: Decimal,
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
