//! DTOs for the profile service (transport shapes). Pure data — no I/O.
//!
//! The `account_number` on read responses is ALWAYS the value produced by the masking /
//! admin logic in the handler — the type itself carries no "is this masked?" flag, so the
//! masking decision lives in exactly one place (the handler), never duplicated.

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use shared::models::ApprovalStatus;
use uuid::Uuid;

// ----- Internal (service-to-service) -----

/// The lean guard-catalog row exposed to internal (service-JWT'd) callers — booking's
/// discovery (`/available-guards`). Deliberately NARROW: only what discovery needs, NEVER
/// bank/PII fields (least-privilege over the wire; the PDPA-sensitive columns stay home).
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct InternalGuard {
    pub user_id: Uuid,
    pub years_of_experience: Option<i32>,
}

/// Query for `GET /internal/profiles/recipients` — the broadcast audience selector
/// (notification's bulk-send asks profile to resolve `user_id`s by role).
#[derive(Debug, Deserialize)]
pub struct RecipientsQuery {
    /// `all` | `guards` | `customers`.
    pub audience: String,
}

/// The resolved recipient set for a broadcast audience, returned over the service-JWT'd
/// `/internal/profiles/recipients`. Least-privilege — only `user_id`s (no names/PII).
/// `user_ids` is bounded (the repo caps it); a roster beyond the cap is truncated (logged).
#[derive(Debug, Serialize)]
pub struct RecipientsResponse {
    pub audience: String,
    pub count: i64,
    pub user_ids: Vec<Uuid>,
}

// ----- Requests -----

/// Upsert the caller's guard profile. All fields optional except where a guard would
/// reasonably leave them blank during a multi-step onboarding; the repo upserts whatever
/// is provided.
#[derive(Debug, Default, Deserialize)]
pub struct UpsertGuardProfileRequest {
    pub gender: Option<String>,
    /// ISO `YYYY-MM-DD`. Parsed by serde into a `NaiveDate` (a malformed date → 422).
    pub date_of_birth: Option<NaiveDate>,
    pub years_of_experience: Option<i32>,
    pub previous_workplace: Option<String>,
    pub bank_name: Option<String>,
    pub account_number: Option<String>,
    pub account_name: Option<String>,
}

/// Upsert the caller's customer profile (minimal in this slice).
#[derive(Debug, Default, Deserialize)]
pub struct UpsertCustomerProfileRequest {
    pub full_name: Option<String>,
    pub address: Option<String>,
}

/// Optional reason carried on an admin rejection (stored is a follow-up; for now it is
/// logged + echoed so the reviewer can supply context).
#[derive(Debug, Default, Deserialize)]
pub struct RejectRequest {
    pub reason: Option<String>,
}

// ----- Recruitment pipeline (admin "recruit" surface) -----

/// One candidate in the recruitment pipeline (`GET /admin/recruitment/candidates`). Lean — only
/// what the kanban needs: who, experience, the authoritative `approval_status` (the final
/// columns), and the pre-approval `recruitment_stage` (the workflow columns). No name/bank/PII.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct RecruitCandidate {
    pub user_id: Uuid,
    pub years_of_experience: Option<i32>,
    pub approval_status: String,
    pub recruitment_stage: String,
}

/// Move a pending candidate to a pipeline stage (`PUT .../candidates/{id}/stage`).
#[derive(Debug, Deserialize)]
pub struct StageRequest {
    /// `sourcing` | `screened` | `docs_verified`.
    pub stage: String,
}

// ----- Document expiry (admin "expiring" surface) -----

/// One guard-document expiry row (`GET /admin/documents/expiring`). `days_remaining` is derived
/// in the handler from `expiry_date` (negative = already expired). The doc-upload + expiry
/// CAPTURE flow is a deferred follow-up, so this set is empty until that lands.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct DocumentExpiryRow {
    pub id: Uuid,
    pub guard_id: Uuid,
    pub document_type: String,
    pub expiry_date: NaiveDate,
    pub last_reminded_at: Option<DateTime<Utc>>,
}

// ----- Responses -----

/// A guard profile as returned to the OWNER or an admin. `account_number` is masked for
/// the owner's own read (`GET /profile/me`) and full for the admin endpoints — the caller
/// decides which by choosing the constructor.
#[derive(Debug, Serialize)]
pub struct GuardProfileResponse {
    pub user_id: Uuid,
    pub gender: Option<String>,
    pub date_of_birth: Option<NaiveDate>,
    pub years_of_experience: Option<i32>,
    pub previous_workplace: Option<String>,
    pub bank_name: Option<String>,
    /// Masked (last-4) on owner reads; full on admin reads. See the constructors.
    pub account_number: Option<String>,
    pub account_name: Option<String>,
    pub approval_status: ApprovalStatus,
}

/// A customer profile as returned to the owner.
#[derive(Debug, Serialize)]
pub struct CustomerProfileResponse {
    pub user_id: Uuid,
    pub full_name: Option<String>,
    pub address: Option<String>,
}

/// A customer profile row as returned to an ADMIN list (`GET /admin/customer-profiles`).
/// A SEPARATE shape from [`CustomerProfileResponse`] so the owner-facing read stays
/// additive-only — this one adds `created_at` (the signup time the admin UI shows + the
/// list's order-by key). No `approval_status`: customer approval lives in identity, not
/// profile (customers auto-approve on first profile insert), and profile must not read
/// across the service boundary — every customer with a profile row is approved by construction.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct CustomerProfileAdminResponse {
    pub user_id: Uuid,
    pub full_name: Option<String>,
    pub address: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// One PDPA §30 data-access audit row (`GET /admin/access-audit`). Records WHO (an admin)
/// accessed WHAT (the `action`, e.g. `admin_list_guard_profiles`) and WHEN. This is a
/// data-access trail, NOT a full business-action feed (the design's broader "activity" intent).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct AccessAuditRow {
    pub id: i64,
    pub accessed_by: Uuid,
    pub action: String,
    pub target: Option<String>,
    pub accessed_at: DateTime<Utc>,
}

/// Query params for `GET /admin/access-audit` — optional `action` filter + limit/offset.
#[derive(Debug, Deserialize)]
pub struct AdminListAccessAuditQuery {
    pub action: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// Either profile shape, tagged so `GET /profile/me` can return whichever the caller has
/// without the client guessing. (`#[serde(tag = "kind")]` keeps the wire shape explicit.)
#[derive(Debug, Serialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum MyProfile {
    Guard(GuardProfileResponse),
    Customer(CustomerProfileResponse),
}
