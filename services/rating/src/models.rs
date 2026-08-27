//! DTOs for the rating service (transport shapes). Pure data — no I/O.
//!
//! Ratings are whole-star `1..=5`. The DB columns are `SMALLINT`, so the row structs use
//! `i16`; the request DTO uses `i32` (JSON integers) and is validated + narrowed before bind.

use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ----- Requests -----

/// A customer submits a review for a completed assignment (= booking). `overall_rating` is
/// required (`1..=5`); categories are optional (`1..=5` when present). The reviewed guard,
/// the customer, and the completed-status are taken from the AUTHORITATIVE booking read —
/// never the request body (CLAUDE.md money/authz rules).
#[derive(Debug, Deserialize)]
pub struct CreateReviewRequest {
    pub overall_rating: i32,
    #[serde(default)]
    pub punctuality: Option<i32>,
    #[serde(default)]
    pub professionalism: Option<i32>,
    #[serde(default)]
    pub communication: Option<i32>,
    #[serde(default)]
    pub appearance: Option<i32>,
    #[serde(default)]
    pub review_text: Option<String>,
}

/// Admin visibility toggle body.
#[derive(Debug, Deserialize)]
pub struct SetVisibilityRequest {
    pub is_visible: bool,
}

/// Batch rating-summaries request (service-to-service): the guard ids booking's discovery wants
/// summaries for in ONE call, collapsing the per-guard N+1. Ids with no visible reviews are
/// simply omitted from the response (the caller defaults them), so duplicate/unknown ids are
/// harmless — no dedup required.
#[derive(Debug, Deserialize)]
pub struct BatchRatingSummariesRequest {
    pub ids: Vec<Uuid>,
}

/// Admin-reviews list filters (all optional). `rating` filters on the whole-star overall.
#[derive(Debug, Default, Deserialize)]
pub struct AdminReviewsQuery {
    pub guard_id: Option<Uuid>,
    pub rating: Option<i32>,
    pub is_visible: Option<bool>,
    pub search: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

// ----- Responses -----

/// A single review as returned on public discovery (`is_visible = true` only). No customer
/// identity is exposed publicly — only the reviewed guard + the ratings + text.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct ReviewResponse {
    pub id: Uuid,
    pub guard_id: Uuid,
    pub overall_rating: i16,
    pub punctuality: Option<i16>,
    pub professionalism: Option<i16>,
    pub communication: Option<i16>,
    pub appearance: Option<i16>,
    pub review_text: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// A guard's public ratings page: the visible reviews + the aggregate summary.
#[derive(Debug, Serialize)]
pub struct GuardRatingsResponse {
    pub guard_id: Uuid,
    /// AVG of visible overall ratings (`None` if there are none). Decimal-as-number on wire.
    pub average: Option<Decimal>,
    pub count: i64,
    pub reviews: Vec<ReviewResponse>,
}

/// A review as the admin moderation list shows it. Carries the customer/guard IDs (not names
/// — those live in the profile service; cross-service name enrichment is a noted follow-up)
/// + the visibility flag.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct AdminReviewResponse {
    pub id: Uuid,
    pub assignment_id: Uuid,
    pub customer_id: Uuid,
    pub guard_id: Uuid,
    pub overall_rating: i16,
    pub punctuality: Option<i16>,
    pub professionalism: Option<i16>,
    pub communication: Option<i16>,
    pub appearance: Option<i16>,
    pub review_text: Option<String>,
    pub is_visible: bool,
    pub created_at: DateTime<Utc>,
}

/// Global review stats for the admin dashboard cards — computed on the UNFILTERED dataset
/// (v1 rule: the cards reflect the whole dataset, not the current filter).
#[derive(Debug, Serialize)]
pub struct AdminReviewStats {
    pub total: i64,
    pub visible: i64,
    pub average: Option<Decimal>,
    /// Reviews created in the current calendar month (server tz, UTC) — the รีวิวเดือนนี้ card.
    pub this_month: i64,
}

/// Paginated admin-reviews response (list + total + unfiltered stats).
#[derive(Debug, Serialize)]
pub struct AdminReviewsResponse {
    pub data: Vec<AdminReviewResponse>,
    pub total: i64,
    pub limit: i64,
    pub offset: i64,
    pub stats: AdminReviewStats,
}

/// The summary other services (booking's available-guards) consume via the internal read.
#[derive(Debug, Serialize)]
pub struct RatingSummaryResponse {
    pub guard_id: Uuid,
    pub average: Option<Decimal>,
    pub count: i64,
}

/// One guard's summary in the BATCH internal response. Field names (`average_rating`,
/// `review_count`) match the shared discovery contract consumed by booking's `discovery_client`
/// (deliberately distinct from the single-endpoint `RatingSummaryResponse`). Only guards with at
/// least one visible review are returned; the caller defaults the rest to `{ null, 0 }`.
#[derive(Debug, Serialize)]
pub struct RatingSummaryBatchItem {
    pub guard_id: Uuid,
    /// AVG of visible overall ratings, rounded to 2 dp (Decimal-as-string on wire, matching the
    /// single endpoint). Always present in a returned row (a returned guard has ≥1 visible review).
    pub average_rating: Option<Decimal>,
    pub review_count: i64,
}

/// The submit-review result.
#[derive(Debug, Serialize)]
pub struct SubmitReviewResponse {
    pub id: Uuid,
}

// ----- booking internal read (deserialized from booking's /internal/bookings/{id}) -----

/// The authoritative booking fields the rating service verifies a review against. Mirrors
/// the relevant subset of booking's `InternalBooking`; serde ignores the extra fields
/// (id/hours/pricing) we don't need here.
#[derive(Debug, Clone, Deserialize)]
pub struct InternalBooking {
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub status: String,
}
