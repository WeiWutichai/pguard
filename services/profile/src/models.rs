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
/// discovery (`/available-guards`). Deliberately NARROW: only what the customer's
/// guard-selection card needs (name + photo + experience), NEVER bank/PII fields
/// (least-privilege over the wire; the PDPA-sensitive columns stay home). `full_name` and
/// `avatar_url` are the same exposure already made by `GET /guards/{id}/public` — the
/// approved guard the customer is choosing — so this is no NEW disclosure. `avatar_url` is a
/// short-lived presigned GET URL (the raw S3 key is never on the wire) and is `None` when the
/// guard has not set an avatar.
#[derive(Debug, Clone, Serialize)]
pub struct InternalGuard {
    pub user_id: Uuid,
    pub full_name: Option<String>,
    pub avatar_url: Option<String>,
    pub years_of_experience: Option<i32>,
}

/// The raw `list_approved_guards` repo row — DB columns only, including the unsigned
/// `avatar_key` (an S3 object key, NEVER serialized to a caller). The handler presigns
/// `avatar_key` into [`InternalGuard::avatar_url`]; keeping the raw key off the wire shape
/// means the presign decision lives in exactly one place (the handler), like the owner/admin
/// avatar path.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct InternalGuardRow {
    pub user_id: Uuid,
    pub full_name: Option<String>,
    pub avatar_key: Option<String>,
    pub years_of_experience: Option<i32>,
}

/// The lean, customer-facing guard mini-profile for the live-tracking map
/// (`GET /guards/{id}/public`). Deliberately NARROW — only what the tracking card needs to
/// identify the assigned guard: name + experience. NEVER bank/address/DOB/emergency-contact PII
/// (least-privilege; those stay owner/admin-only). `full_name` is the new exposure — reachable
/// ONLY by a customer with an ACTIVE booking with this guard (or the guard themselves / an admin),
/// and ONLY for an `approved` guard (the repo filters; un-approved → 404). Photo is deferred (no
/// avatar storage exists yet).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct PublicGuardProfile {
    pub user_id: Uuid,
    pub full_name: Option<String>,
    pub years_of_experience: Option<i32>,
}

/// The lean, GUARD-facing customer mini-profile (`GET /customers/{id}/public`) — the mirror of
/// [`PublicGuardProfile`] for the OTHER direction. The assigned guard's job sheet needs to address
/// the customer by name (not a raw id), so this exposes ONLY `{ user_id, full_name }`. NEVER the
/// address / company / email / phone (least-privilege; those stay owner/admin-only). `full_name`
/// is PII reachable by a non-owner ONLY under the same active-booking IDOR gate the guard-profile
/// read uses — here flipped so it is the ASSIGNED GUARD (not the customer) who may read it.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct PublicCustomerProfile {
    pub user_id: Uuid,
    pub full_name: Option<String>,
}

// ----- Admin batch name-resolver (POST /admin/users/resolve) -----

/// Request to resolve a batch of `user_id`s to display names (the admin lists render guard /
/// customer / admin ids — jobs, reviews, calls, activity log — as raw UUIDs without this).
/// Admin-only. Bounded by [`RESOLVE_NAMES_LIMIT`] so one page's worth of ids is one round-trip,
/// never an unbounded scan.
#[derive(Debug, Deserialize)]
pub struct ResolveNamesRequest {
    /// The ids to resolve. Duplicates are de-duplicated server-side; an empty list → empty map.
    pub ids: Vec<Uuid>,
}

/// Hard cap on a single resolve request (one admin page never references more ids than this).
/// A request beyond the cap is rejected (400) rather than silently truncated, so the caller
/// learns to page rather than getting a partial map it can't tell apart from "unknown ids".
pub const RESOLVE_NAMES_LIMIT: usize = 500;

/// One resolved identity: a display name (PII reachable ONLY by an admin here) + the role it
/// was resolved as. NEVER any other PII (phone / bank / address / email). `display_name` is
/// `None` when the profile row exists but carries no name yet (mid-onboarding); the role is
/// still authoritative. Keyed by the id in the response map, so the id is not repeated here.
#[derive(Debug, Serialize)]
pub struct ResolvedName {
    /// `guard` | `customer`. (`admin` is never produced here — admins have no profile row /
    /// stored name; see the handler's fallback + the OpenAPI note.)
    pub role: String,
    /// The user's full name, or `null` if the profile row has no name set yet.
    pub display_name: Option<String>,
}

/// Raw resolver row (a guard or customer profile, with the role derived from which table the
/// row came from). `role` is a literal from the UNION query, never user input.
#[derive(Debug, sqlx::FromRow)]
pub struct ResolvedNameRow {
    pub user_id: Uuid,
    pub full_name: Option<String>,
    pub role: String,
}

/// Response for a guard-document upload / read: the canonical type + a short-lived presigned GET
/// URL (1h) for the stored image. The raw S3 key is never exposed (only the signed URL).
#[derive(Debug, Serialize)]
pub struct GuardDocumentResponse {
    pub document_type: String,
    pub download_url: String,
}

/// The result of a guard avatar upload/read: a short-lived (1h) presigned GET URL for the stored
/// profile picture. The raw S3 key is never exposed (only the signed URL).
#[derive(Debug, Serialize)]
pub struct GuardAvatarResponse {
    pub avatar_url: String,
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
    /// Guard's full name (v2 stores it on the profile, not on identity.users — v1 parity).
    pub full_name: Option<String>,
    pub gender: Option<String>,
    /// ISO `YYYY-MM-DD`. Parsed by serde into a `NaiveDate` (a malformed date → 422).
    pub date_of_birth: Option<NaiveDate>,
    pub years_of_experience: Option<i32>,
    pub previous_workplace: Option<String>,
    pub bank_name: Option<String>,
    pub account_number: Option<String>,
    pub account_name: Option<String>,
    /// Home address (v1 parity).
    pub address: Option<String>,
    /// Emergency contact (v1 parity — PII; not masked, v1 doesn't mask it either).
    pub emergency_contact_name: Option<String>,
    pub emergency_contact_phone: Option<String>,
    pub emergency_contact_relationship: Option<String>,
    /// OPTIONAL per-document expiry dates from the registration doc step (the single-use
    /// profile_token authorizes one write, so they ride the profile submit). Captured
    /// best-effort into `document_expiry`; the guard_profiles columns are unaffected. Absent on
    /// a non-guard or pre-doc-step submit.
    pub document_expiries: Option<Vec<DocumentExpiryInput>>,
}

/// Upsert the caller's customer profile (v1-parity fields).
#[derive(Debug, Default, Deserialize)]
pub struct UpsertCustomerProfileRequest {
    pub full_name: Option<String>,
    pub address: Option<String>,
    /// Optional company (v1 parity).
    pub company_name: Option<String>,
    /// Optional email (validated `@`+`.`+len≥5; v1 parity).
    pub email: Option<String>,
    /// Optional contact phone (Thai national format; v1 parity).
    pub contact_phone: Option<String>,
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

/// The guard document types that carry an expiry date — matches the `document_expiry` CHECK
/// constraint (the bank passbook is excluded: it's a bank doc, not an expiring credential).
pub const EXPIRING_DOCUMENT_TYPES: [&str; 5] = [
    "id_card",
    "security_license",
    "training_cert",
    "criminal_check",
    "driver_license",
];

/// One document's expiry as the OWNER (or an admin) sees/edits it — the slim public shape (no
/// internal id / reminder bookkeeping). `GET /profile/guard/{id}/document-expiries`.
#[derive(Debug, Serialize)]
pub struct GuardDocumentExpiry {
    pub document_type: String,
    pub expiry_date: NaiveDate,
}

/// Body for `PUT /profile/guard/{id}/document-expiry` — set/replace ONE document's expiry. The
/// `document_type` must be an [`EXPIRING_DOCUMENT_TYPES`] credential (the passbook has no expiry).
#[derive(Debug, Deserialize)]
pub struct SetDocumentExpiryRequest {
    pub document_type: String,
    pub expiry_date: NaiveDate,
}

/// One guard-document expiry row (`GET /admin/documents/expiring`). The web-admin client buckets
/// by `expiry_date` (expired / 7 / 30 / 90 days). Populated by the guard profile submit
/// (`POST /profile/guard`, which folds in the registration doc step's expiry dates).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct DocumentExpiryRow {
    pub id: Uuid,
    pub guard_id: Uuid,
    pub document_type: String,
    pub expiry_date: NaiveDate,
    pub last_reminded_at: Option<DateTime<Utc>>,
}

/// One document's expiry date, folded into the guard-profile submit (the registration doc step).
/// Metadata only — no image. Upserted on (guard_id, document_type).
#[derive(Debug, Deserialize)]
pub struct DocumentExpiryInput {
    pub document_type: String,
    pub expiry_date: NaiveDate,
}

// ----- Responses -----

/// A guard profile as returned to the OWNER or an admin. `account_number` is masked for
/// the owner's own read (`GET /profile/me`) and full for the admin endpoints — the caller
/// decides which by choosing the constructor.
#[derive(Debug, Serialize)]
pub struct GuardProfileResponse {
    pub user_id: Uuid,
    /// Guard's full name (v1 parity — stored on the profile in v2).
    pub full_name: Option<String>,
    pub gender: Option<String>,
    pub date_of_birth: Option<NaiveDate>,
    pub years_of_experience: Option<i32>,
    pub previous_workplace: Option<String>,
    pub bank_name: Option<String>,
    /// Masked (last-4) on owner reads; full on admin reads. See the constructors.
    pub account_number: Option<String>,
    pub account_name: Option<String>,
    pub address: Option<String>,
    pub emergency_contact_name: Option<String>,
    pub emergency_contact_phone: Option<String>,
    pub emergency_contact_relationship: Option<String>,
    pub approval_status: ApprovalStatus,
}

/// The `POST /profile/guard` (registration) response: the masked profile PLUS a short-lived,
/// MULTI-use `doc_upload_token` the client uses to upload credential images immediately after — so
/// an admin can review them BEFORE approving. Flattened: the JSON carries the profile fields with
/// `doc_upload_token` alongside (the read endpoints keep returning the bare profile, no token).
#[derive(Debug, Serialize)]
pub struct GuardProfileSubmitResponse {
    #[serde(flatten)]
    pub profile: GuardProfileResponse,
    pub doc_upload_token: String,
}

/// A customer profile as returned to the owner.
#[derive(Debug, Serialize)]
pub struct CustomerProfileResponse {
    pub user_id: Uuid,
    pub full_name: Option<String>,
    pub address: Option<String>,
    pub company_name: Option<String>,
    pub email: Option<String>,
    pub contact_phone: Option<String>,
}

/// A customer profile row as returned to an ADMIN list (`GET /admin/customer-profiles`).
/// A SEPARATE shape from [`CustomerProfileResponse`] so the owner-facing read stays
/// additive-only — this one adds `created_at` (the signup time the admin UI shows + the
/// list's order-by key) and `approval_status` (the customer review queue's pending/approved
/// filter). Customers are now admin-approved exactly like guards (no longer auto-approved on
/// first profile insert); `approval_status` is owned on `profile.customer_profiles` and read
/// as `::text` (mirrors the guard list), so the admin can see who is still pending.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct CustomerProfileAdminResponse {
    pub user_id: Uuid,
    pub full_name: Option<String>,
    pub address: Option<String>,
    pub company_name: Option<String>,
    pub email: Option<String>,
    pub contact_phone: Option<String>,
    pub created_at: DateTime<Utc>,
    /// `pending` | `approved` | `rejected` (read as text from the schema-qualified enum).
    pub approval_status: String,
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
