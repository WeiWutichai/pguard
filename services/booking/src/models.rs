//! DTOs for the booking service (transport shapes). Pure data — no I/O.
//!
//! Money fields (`base_fee`, `tip`) are [`rust_decimal::Decimal`] — never `f64` (CLAUDE.md
//! money rules); they serialize as JSON strings via the workspace `serde-str` feature.

use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ----- Requests -----

/// Customer creates a booking request. `guard_count` and `tip` are part of the request but
/// become authoritative once persisted (the money path reads them from the booking, never
/// from the payment request body). `base_fee` is NOT client-settable — it is a server-owned
/// rate (DB default), so the customer can never undercut the price.
#[derive(Debug, Deserialize)]
pub struct CreateBookingRequest {
    pub address: String,
    pub scheduled_at: DateTime<Utc>,
    pub hours: i32,
    /// Number of guards requested (default 1; validated 1..=20).
    #[serde(default)]
    pub guard_count: Option<i32>,
    /// Optional tip the customer adds up front (default 0; folded into the expected total).
    #[serde(default)]
    pub tip: Option<Decimal>,
}

/// Customer's verdict on a guard's completion request (`pending_completion`).
#[derive(Debug, Deserialize)]
pub struct ReviewCompletionRequest {
    /// `"approve"` → completed; `"reject"` → back to arrived.
    pub action: String,
}

// ----- Responses -----

/// A booking row as returned to clients. `status` is read as text (the DB enum cast to
/// text) so the read path needs no enum decoding — mirrors the notification slice.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct BookingResponse {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub status: String,
    pub address: String,
    pub scheduled_at: DateTime<Utc>,
    pub hours: i32,
    /// ฿ per hour per guard (server-owned rate).
    pub base_fee: Decimal,
    pub guard_count: i32,
    pub tip: Decimal,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// One entry in the `/available-guards` discovery list: an approved guard (from profile's
/// catalog) enriched with their live rating summary (from rating). `average_rating` is `None`
/// when the guard has no visible reviews (or rating was unreachable — best-effort).
#[derive(Debug, Serialize)]
pub struct AvailableGuard {
    pub guard_id: Uuid,
    pub years_of_experience: Option<i32>,
    pub average_rating: Option<Decimal>,
    pub review_count: i64,
}

/// The authoritative subset of a booking exposed to internal callers (service-JWT'd),
/// e.g. the payment service deciding whether a charge is legitimate and computing the
/// expected total. Deliberately narrow: ownership/payability + the pricing inputs the money
/// path needs (`base_fee × hours × guard_count + tip`). NOT the address/timestamps a
/// participant sees — internal callers get the minimum they need (least-privilege).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct InternalBooking {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub status: String,
    pub hours: i32,
    /// ฿ per hour per guard (server-owned; the client never sets this).
    pub base_fee: Decimal,
    pub guard_count: i32,
    pub tip: Decimal,
}
