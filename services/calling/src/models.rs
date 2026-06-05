//! DTOs for the calling service (transport shapes). Pure data — no I/O.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ----- Requests -----

/// Initiate a call. The `callee` is DERIVED from the booking (the other participant), never
/// supplied by the client — so a caller can't dial a stranger (CLAUDE.md authz / IDOR).
#[derive(Debug, Deserialize)]
pub struct InitiateCallRequest {
    pub booking_id: Uuid,
    /// `audio` (default) or `video`; validated by the domain.
    #[serde(default)]
    pub call_type: Option<String>,
}

/// Optional reason carried on `end` (e.g. "hangup", "cancelled"). Free text, audit-only.
#[derive(Debug, Default, Deserialize)]
pub struct EndCallRequest {
    #[serde(default)]
    pub reason: Option<String>,
}

// ----- Responses -----

/// A call row as returned to clients. `status`/`call_type` are read as text (the DB enums
/// cast to text) so the read path needs no enum decoding — mirrors the booking slice.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct CallResponse {
    pub id: Uuid,
    pub caller_id: Uuid,
    pub callee_id: Uuid,
    pub booking_id: Uuid,
    pub call_type: String,
    pub status: String,
    pub started_at: DateTime<Utc>,
    pub answered_at: Option<DateTime<Utc>>,
    pub ended_at: Option<DateTime<Utc>>,
    pub duration_seconds: Option<i32>,
    pub end_reason: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

// ----- booking internal read (deserialized from booking's /internal/bookings/{id}) -----

/// The authoritative booking fields the calling service verifies participation against.
/// Mirrors the subset of booking's `InternalBooking` we need; serde ignores extra fields.
#[derive(Debug, Clone, Deserialize)]
pub struct InternalBooking {
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub status: String,
}
