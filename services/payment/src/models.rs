//! DTOs for the payment service (transport shapes). Pure data — no I/O.
//!
//! ALL money fields are [`rust_decimal::Decimal`] — never `f64` (CLAUDE.md money rules).

use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ----- Requests -----

/// A customer pays for a booking. `amount` is client-supplied + validated (`> 0`,
/// `<= cap`); the authoritative customer/guard/status come from booking's internal read,
/// never the client (CLAUDE.md money rules — no client-trusted authoritative fields).
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
    pub payment_method: Option<String>,
    pub status: String,
    pub final_amount: Option<Decimal>,
    pub refund_amount: Option<Decimal>,
    pub actual_hours: Option<Decimal>,
    pub paid_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

// ----- booking internal read (deserialized from booking's /internal/bookings/{id}) -----

/// The authoritative booking fields the booking service returns to the payment service.
/// Mirrors booking's `InternalBooking`. We deserialize the `{ success, data }` envelope's
/// `data` into this.
#[derive(Debug, Clone, Deserialize)]
pub struct InternalBooking {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub status: String,
    pub hours: i32,
}
