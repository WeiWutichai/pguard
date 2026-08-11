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
    /// Whether ALL FIVE credential documents (id card, security license, training cert,
    /// criminal check, driver license — passbook is banking, not a credential) are on file.
    /// A derived boolean only — the documents themselves stay owner/admin-only; this powers the
    /// customer-facing "มีเอกสาร / ไม่มีเอกสาร" indicator on the guard-selection card.
    pub has_documents: bool,
    /// Per-credential PRESENCE (has / doesn't have), so the customer can see WHICH credential
    /// types the guard has on file — never the documents themselves (those stay owner/admin-only,
    /// behind the presigned owner GET). Booleans only; the file bytes never leave profile.
    pub documents: GuardDocumentPresence,
}

/// Per-credential presence flags (has/doesn't-have) for the five customer-relevant credential
/// documents. Booleans ONLY — a "true" means the key column is non-null (the file is on record),
/// never the file itself. Passbook is deliberately excluded (banking, not a vetting credential).
#[derive(Debug, Clone, Serialize)]
pub struct GuardDocumentPresence {
    pub id_card: bool,
    pub security_license: bool,
    pub training_cert: bool,
    pub criminal_check: bool,
    pub driver_license: bool,
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
    /// Derived in SQL: all five credential `*_key` columns non-null (see `list_approved_guards`).
    pub has_documents: bool,
    /// Per-credential presence, each derived in SQL as `<name>_key IS NOT NULL`.
    pub has_id_card: bool,
    pub has_security_license: bool,
    pub has_training_cert: bool,
    pub has_criminal_check: bool,
    pub has_driver_license: bool,
}

/// The lean, customer-facing guard mini-profile for the live-tracking map
/// (`GET /guards/{id}/public`). Deliberately NARROW — only what the tracking card needs to
/// identify the assigned guard: name + experience. NEVER bank/address/DOB/emergency-contact PII
/// (least-privilege; those stay owner/admin-only). `full_name` is the new exposure — reachable
/// ONLY by a customer with an ACTIVE booking with this guard (or the guard themselves / an admin),
/// and ONLY for an `approved` guard (the repo filters; un-approved → 404). `avatar_url` is the
/// guard's self-uploaded photo: a short-lived presigned GET URL (the raw `avatar_key` never crosses
/// the wire — the handler presigns it, one place), `None` when the guard set no photo — the same
/// exposure discovery already makes of the chosen guard, mirrored onto the live-tracking card.
#[derive(Debug, Serialize)]
pub struct PublicGuardProfile {
    pub user_id: Uuid,
    pub full_name: Option<String>,
    pub years_of_experience: Option<i32>,
    pub avatar_url: Option<String>,
}

/// FromRow projection for [`PublicGuardProfile`] — carries the raw `avatar_key` the handler presigns
/// into `avatar_url` (the key never leaves the service), mirroring [`PublicCustomerProfileRow`].
#[derive(Debug, sqlx::FromRow)]
pub struct PublicGuardProfileRow {
    pub user_id: Uuid,
    pub full_name: Option<String>,
    pub years_of_experience: Option<i32>,
    pub avatar_key: Option<String>,
}

/// The lean, GUARD-facing customer mini-profile (`GET /customers/{id}/public`) — the mirror of
/// [`PublicGuardProfile`] for the OTHER direction. The assigned guard's job sheet needs to address
/// the customer by name (not a raw id) + show their photo, so this exposes ONLY
/// `{ user_id, full_name, avatar_url }`. NEVER the address / company / email / phone
/// (least-privilege; those stay owner/admin-only). `full_name` is PII reachable by any GUARD-role
/// caller (product decision 2026-07-11: the name shows from the job OFFER onwards, so the old
/// active-booking gate was dropped for this direction). `avatar_url` is a short-lived presigned
/// GET URL (the raw S3 key is never on the wire — the handler presigns the `avatar_key`), `None`
/// when the customer has not set an avatar — the same exposure the customer makes of the guard's
/// avatar via `GET /guards/{id}/public` / discovery, mirrored.
#[derive(Debug, Serialize)]
pub struct PublicCustomerProfile {
    pub user_id: Uuid,
    pub full_name: Option<String>,
    pub avatar_url: Option<String>,
}

/// The raw `get_public_customer_profile` repo row — DB columns only, including the unsigned
/// `avatar_key` (an S3 object key, NEVER serialized to a caller). The handler presigns `avatar_key`
/// into [`PublicCustomerProfile::avatar_url`]; keeping the raw key off the wire shape means the
/// presign decision lives in exactly one place (the handler), like the guard avatar path.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct PublicCustomerProfileRow {
    pub user_id: Uuid,
    pub full_name: Option<String>,
    pub avatar_key: Option<String>,
}

/// The result of a customer avatar upload/read: a short-lived (1h) presigned GET URL for the stored
/// profile picture. The raw S3 key is never exposed (only the signed URL). Mirrors
/// [`GuardAvatarResponse`].
#[derive(Debug, Serialize)]
pub struct CustomerAvatarResponse {
    pub avatar_url: String,
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

/// One guard-document expiry row (`GET /admin/documents/expiring`). `days_left` is computed in
/// SQL (`expiry_date - current_date`): NEGATIVE = already expired, 0 = due today, positive =
/// days until it lapses — so the client need not re-derive it from the date. Populated by the
/// guard profile submit (`POST /profile/guard`, which folds in the registration doc step's
/// expiry dates). Used both by the owner/admin per-guard list and the admin "expiring" surface.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct DocumentExpiryRow {
    pub id: Uuid,
    pub guard_id: Uuid,
    pub document_type: String,
    pub expiry_date: NaiveDate,
    /// `expiry_date - current_date` in days (negative = expired). Computed in SQL.
    pub days_left: i32,
    pub last_reminded_at: Option<DateTime<Utc>>,
}

/// Bucket counts for the admin "expiring documents" surface — how many credentials fall in each
/// urgency band, computed in ONE SQL pass over ALL recorded expiries (independent of the `window`
/// the list is filtered to). Bands are CUMULATIVE-by-meaning but reported DISJOINT: `expired`
/// (days_left < 0), `due_7` (0..=7), `due_30` (8..=30), `due_90` (31..=90). A document expiring
/// beyond 90 days is in none of these.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct ExpiringDocumentBuckets {
    pub expired: i64,
    pub due_7: i64,
    pub due_30: i64,
    pub due_90: i64,
}

/// The admin "expiring documents" response (`GET /admin/documents/expiring?window=`): the list
/// (filtered to the requested window, soonest first) PLUS the urgency-band `buckets` (over all
/// recorded expiries, so the dashboard pills are window-independent).
#[derive(Debug, Serialize)]
pub struct ExpiringDocumentsResponse {
    pub documents: Vec<DocumentExpiryRow>,
    pub buckets: ExpiringDocumentBuckets,
}

/// New-applicants count for the admin dashboard notification card + the ผู้สมัคร page (#132):
/// how many guards AND customers are awaiting admin approval (`approval_status = 'pending'`).
/// Both roles now go through the SAME admin-review gate (customers are no longer auto-approved),
/// so the page's "ผู้เรียก รปภ." (customer) tab is populated from `customers`. `total` is the
/// dashboard badge; the per-role split drives the two tabs. Computed in ONE SQL round-trip.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct PendingApplicantsCount {
    pub guards: i64,
    pub customers: i64,
    pub total: i64,
}

/// Average guard approval turnaround for the admin dashboard (เวลาอนุมัติเฉลี่ย, #132): the mean
/// of `reviewed_at - created_at` over APPROVED guards, in seconds + a pre-rounded hours value for
/// display. `sample_size` is how many approved guards the average is over — `null` average + 0
/// sample when none have been approved yet (honest empty state, not a fake 0h).
#[derive(Debug, Serialize)]
pub struct AvgApprovalTime {
    /// Mean approval duration in seconds (`null` when no guard has been approved yet).
    pub avg_seconds: Option<i64>,
    /// The same value in hours, rounded to 1 decimal (`null` when no sample). Convenience for UI.
    pub avg_hours: Option<f64>,
    /// Number of approved guards the average is computed over.
    pub sample_size: i64,
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

/// A guard profile row as returned to an ADMIN list (`GET /admin/guard-profiles` — the onboarding
/// review queue): the owner-facing [`GuardProfileResponse`] (with the FULL account number) PLUS
/// `created_at`, the signup time. Flattened, so the JSON is the profile's own fields with
/// `created_at` alongside.
///
/// A SEPARATE shape from the owner read for the same reason [`CustomerProfileAdminResponse`] is:
/// queue metadata has no business on `GET /profile/me`. The customer admin list already carried
/// `created_at`; the guard one did not — so the reviewer had no idea how long an applicant had
/// been waiting (and the admin UI's "สมัครเมื่อ" column had nothing to render).
#[derive(Debug, Serialize)]
pub struct GuardProfileAdminResponse {
    #[serde(flatten)]
    pub profile: GuardProfileResponse,
    /// When the applicant signed up (`guard_profiles.created_at`) — also the list's order-by key.
    pub created_at: DateTime<Utc>,
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

/// An admin-list row PLUS the applicant's **login phone** — `identity.users.phone`, the number
/// they signed up and log in with. Wraps [`GuardProfileResponse`] / [`CustomerProfileAdminResponse`]
/// with `#[serde(flatten)]`, so the JSON is the profile's own fields with `login_phone` alongside
/// (same trick as [`GuardProfileSubmitResponse`]). Wrapping rather than adding the field to the
/// profile structs keeps it OFF the owner-facing reads (`GET /profile/me`, the submit response),
/// which have no business carrying an identity-owned column.
///
/// WHY: profile's own `contact_phone` is an OPTIONAL extra a customer may never fill in, and
/// `full_name` is optional too — so the approval queue was showing `#5680b50f` / "—" for real
/// applicants and admins were approving blind. The login phone is the one contact detail every
/// account is guaranteed to have (it IS the account), and profile does not store it — hence the
/// cross-service resolve.
///
/// `login_phone` is `Option` for exactly one reason: the lookup is **best-effort**. `null` means
/// identity was unreachable (or the account is gone), NOT that the person has no phone — a healthy
/// row always carries one. An approval queue that 500s because a name lookup failed is strictly
/// worse than one that renders with a blank phone column.
#[derive(Debug, Serialize)]
pub struct WithLoginPhone<T> {
    #[serde(flatten)]
    pub profile: T,
    /// The account's login phone from identity, or `null` when the resolve did not answer.
    pub login_phone: Option<String>,
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

// ----- Organization (company) profile settings (#143, Admin Settings → "บริษัท") -----

/// `PUT /admin/org-settings` body — the company profile shown on receipts + in-app. All fields
/// OPTIONAL (the admin saves incrementally); the handler validates lengths + a lenient `tax_id`
/// format before the single-row upsert.
#[derive(Debug, Deserialize)]
pub struct UpdateOrgSettingsRequest {
    pub company_name: Option<String>,
    pub tax_id: Option<String>,
    pub address: Option<String>,
}

/// The org (company) profile as returned to an admin (`GET`/`PUT /admin/org-settings`). When no
/// row has been saved yet every field is `null` and `updated_at` is `null` (honest "unset" state
/// — the admin UI shows blank inputs), so the GET never 404s.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct OrgSettingsResponse {
    pub company_name: Option<String>,
    pub tax_id: Option<String>,
    pub address: Option<String>,
    /// When the company profile was last saved (`null` until first written).
    pub updated_at: Option<DateTime<Utc>>,
}

impl OrgSettingsResponse {
    /// The "never saved yet" default — all fields blank. Returned by GET when the single row
    /// does not exist, so the admin UI renders empty inputs instead of an error.
    pub fn unset() -> Self {
        Self {
            company_name: None,
            tax_id: None,
            address: None,
            updated_at: None,
        }
    }
}
