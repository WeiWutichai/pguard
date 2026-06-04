//! DTOs for the booking service (transport shapes). Pure data — no I/O.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ----- Requests -----

/// Customer creates a booking request.
#[derive(Debug, Deserialize)]
pub struct CreateBookingRequest {
    pub address: String,
    pub scheduled_at: DateTime<Utc>,
    pub hours: i32,
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
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
