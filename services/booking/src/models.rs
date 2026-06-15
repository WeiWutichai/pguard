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
    /// Optional site coordinates (both-or-neither; validated ranges) — feed open-job radius
    /// discovery. Coordinates are NOT money: f64 per the presence house style.
    #[serde(default)]
    pub lat: Option<f64>,
    #[serde(default)]
    pub lng: Option<f64>,
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
    /// Site coordinates — `None` when the customer did not provide them at create.
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

// ----- Progress reports (hourly check-in) -----

/// A `booking.progress_reports` row as stored. Only the S3 `photo_key` is persisted —
/// signed URLs are minted fresh per read (the chat-attachment pattern), never stored as
/// the source of truth.
#[derive(Debug, sqlx::FromRow)]
pub struct ProgressReportRow {
    pub id: Uuid,
    pub booking_id: Uuid,
    pub guard_id: Uuid,
    pub hour_number: i32,
    pub photo_key: String,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub accuracy_m: Option<f32>,
    pub note: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// The client view of a progress report: the row plus a FRESH presigned GET URL (TTL 1h)
/// signed from `photo_key` at response time.
#[derive(Debug, Serialize)]
pub struct ProgressReportResponse {
    pub id: Uuid,
    pub booking_id: Uuid,
    pub guard_id: Uuid,
    pub hour_number: i32,
    pub photo_key: String,
    pub photo_url: String,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub accuracy_m: Option<f32>,
    pub note: Option<String>,
    pub created_at: DateTime<Utc>,
}

impl ProgressReportResponse {
    /// Attach a freshly-signed download URL to a stored row.
    pub fn from_row(row: ProgressReportRow, photo_url: String) -> Self {
        Self {
            id: row.id,
            booking_id: row.booking_id,
            guard_id: row.guard_id,
            hour_number: row.hour_number,
            photo_key: row.photo_key,
            photo_url,
            lat: row.lat,
            lng: row.lng,
            accuracy_m: row.accuracy_m,
            note: row.note,
            created_at: row.created_at,
        }
    }
}

/// The validated, ready-to-persist check-in (built by the handler AFTER multipart parsing,
/// photo validation, and the S3 upload; the repo re-validates legality inside the row lock).
#[derive(Debug)]
pub struct NewProgressReport {
    pub hour_number: i32,
    pub photo_key: String,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub accuracy_m: Option<f32>,
    pub note: Option<String>,
}

/// Query params for `GET /bookings/{id}/progress-reports` (house limit/offset pagination).
#[derive(Debug, Deserialize)]
pub struct ListProgressReportsQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// Query params for `GET /bookings/open` (open-job discovery).
#[derive(Debug, Deserialize)]
pub struct OpenJobsQuery {
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub radius_km: Option<f64>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// Query params for `GET /admin/bookings` (admin cross-user list). `status` is validated
/// against `BookingStatus` (unknown → 400); `search` is a case-insensitive substring match on
/// the address. House limit/offset pagination.
#[derive(Debug, Deserialize)]
pub struct AdminListBookingsQuery {
    pub status: Option<String>,
    pub search: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// Body for `POST /admin/bookings/{id}/assign` — the admin's chosen guard for the booking.
#[derive(Debug, Deserialize)]
pub struct AssignGuardRequest {
    pub guard_id: Uuid,
}

// ----- Service catalog (admin-managed pricing; standalone, not wired to the charge path) -----

/// A service-catalog row as returned to the admin. `base_fee` is a Decimal serialized as a
/// string on the wire (money rule), like the booking response.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct ServiceCatalogItem {
    pub id: Uuid,
    pub name_th: String,
    pub name_en: String,
    /// ฿ per hour per guard.
    pub base_fee: Decimal,
    pub min_hours: i32,
    pub notes: Option<String>,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Create a catalog service (admin). Validated in the handler (non-empty names, fee ≥ 0,
/// min_hours 1..=24).
#[derive(Debug, Deserialize)]
pub struct CreateServiceRequest {
    pub name_th: String,
    pub name_en: String,
    pub base_fee: Decimal,
    pub min_hours: i32,
    pub notes: Option<String>,
}

/// Update a catalog service (admin) — full replace of the editable fields.
#[derive(Debug, Deserialize)]
pub struct UpdateServiceRequest {
    pub name_th: String,
    pub name_en: String,
    pub base_fee: Decimal,
    pub min_hours: i32,
    pub notes: Option<String>,
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
