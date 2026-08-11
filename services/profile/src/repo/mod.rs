//! Repository layer — the ONLY place that touches the `profile` schema.
//!
//! Uses runtime `sqlx::query`/`query_as` (not the compile-time `query!` macro): the
//! scaffold has no DATABASE_URL / offline `.sqlx` cache at build time (mirrors the
//! identity + booking slices).
//!
//! `profile.approval_status` is a SCHEMA-QUALIFIED enum. The shared
//! [`ApprovalStatus`] sqlx type is declared `type_name = "approval_status"` (unqualified),
//! so to avoid any type-OID resolution ambiguity we read it via a `::text` cast (parsed in
//! Rust) and write it via an explicit `$n::profile.approval_status` cast. No raw user
//! input is ever interpolated — values are always bound parameters.

use std::str::FromStr;

use chrono::{DateTime, NaiveDate, Utc};
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

use shared::error::AppError;
use shared::models::ApprovalStatus;
use shared_events::{topics, EventEnvelope};

use crate::models::{
    AccessAuditRow, CustomerProfileAdminResponse, CustomerProfileResponse, DocumentExpiryRow,
    GuardProfileAdminResponse, GuardProfileResponse, InternalGuardRow, OrgSettingsResponse,
    PublicCustomerProfileRow, PublicGuardProfileRow, RecruitCandidate, ResolvedNameRow,
    UpdateOrgSettingsRequest, UpsertCustomerProfileRequest, UpsertGuardProfileRequest,
};

/// Valid pre-approval pipeline stages (matches the `profile.recruitment_stage` enum).
const RECRUITMENT_STAGES: &[&str] = &["sourcing", "screened", "docs_verified"];

/// List every guard as a recruitment-pipeline candidate (lean projection — no PII), newest
/// first. The kanban groups them: pending guards by `recruitment_stage`, finalized ones by
/// `approval_status`. Bounded (mirrors the admin guard list's cap).
pub async fn list_recruitment_candidates(db: &PgPool) -> Result<Vec<RecruitCandidate>, AppError> {
    let rows = sqlx::query_as::<_, RecruitCandidate>(
        "SELECT user_id, years_of_experience, approval_status::text AS approval_status, \
                recruitment_stage::text AS recruitment_stage \
         FROM profile.guard_profiles ORDER BY created_at DESC LIMIT 200",
    )
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Move a PENDING guard to a pre-approval pipeline stage. Only `pending` applicants have a
/// meaningful pipeline position — a finalized (approved/rejected) guard returns 409 (they left
/// the pipeline via `approval_status`). An unknown stage → 400. Returns the updated candidate.
pub async fn set_recruitment_stage(
    db: &PgPool,
    user_id: Uuid,
    stage: &str,
) -> Result<RecruitCandidate, AppError> {
    if !RECRUITMENT_STAGES.contains(&stage) {
        return Err(AppError::BadRequest(format!(
            "invalid stage: {stage} (expected sourcing|screened|docs_verified)"
        )));
    }
    let row: Option<RecruitCandidate> = sqlx::query_as(
        "UPDATE profile.guard_profiles \
         SET recruitment_stage = $2::profile.recruitment_stage, updated_at = now() \
         WHERE user_id = $1 AND approval_status = 'pending'::profile.approval_status \
         RETURNING user_id, years_of_experience, approval_status::text AS approval_status, \
                   recruitment_stage::text AS recruitment_stage",
    )
    .bind(user_id)
    .bind(stage)
    .fetch_optional(db)
    .await?;
    match row {
        Some(c) => Ok(c),
        None => {
            // Distinguish missing vs already-finalized for a useful error.
            let exists: Option<(String,)> = sqlx::query_as(
                "SELECT approval_status::text FROM profile.guard_profiles WHERE user_id = $1",
            )
            .bind(user_id)
            .fetch_optional(db)
            .await?;
            match exists {
                Some(_) => Err(AppError::Conflict(
                    "recruitment stage only applies to pending applicants".to_string(),
                )),
                None => Err(AppError::NotFound("Guard profile not found".to_string())),
            }
        }
    }
}

/// List guard documents expiring within `window_days` (INCLUDING already-expired), soonest
/// first, each carrying its SQL-computed `days_left` (`expiry_date - current_date`; negative =
/// expired). Bounded. Reads the `document_expiry` table (empty until the doc-upload+expiry-
/// capture follow-up populates it). The companion [`expiring_document_buckets`] gives the
/// window-independent urgency counts.
pub async fn list_expiring_documents(
    db: &PgPool,
    window_days: i64,
) -> Result<Vec<DocumentExpiryRow>, AppError> {
    let rows = sqlx::query_as::<_, DocumentExpiryRow>(
        "SELECT id, guard_id, document_type, expiry_date, \
                (expiry_date - current_date)::int AS days_left, last_reminded_at \
         FROM profile.document_expiry \
         WHERE expiry_date <= current_date + make_interval(days => $1) \
         ORDER BY expiry_date ASC LIMIT 500",
    )
    .bind(window_days as i32)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Urgency-band counts for the admin "expiring documents" pills — ONE pass over ALL recorded
/// expiries (window-independent, so the dashboard pills don't change when the list filter does).
/// Disjoint bands by `days_left = expiry_date - current_date`: expired (<0), 0..=7, 8..=30,
/// 31..=90. Mirrors booking's `count(*) FILTER (...)` aggregate pattern.
pub async fn expiring_document_buckets(
    db: &PgPool,
) -> Result<crate::models::ExpiringDocumentBuckets, AppError> {
    let row = sqlx::query_as::<_, crate::models::ExpiringDocumentBuckets>(
        "SELECT \
            count(*) FILTER (WHERE expiry_date <  current_date)::bigint AS expired, \
            count(*) FILTER (WHERE expiry_date >= current_date \
                               AND expiry_date <= current_date + 7)::bigint  AS due_7, \
            count(*) FILTER (WHERE expiry_date >  current_date + 7 \
                               AND expiry_date <= current_date + 30)::bigint AS due_30, \
            count(*) FILTER (WHERE expiry_date >  current_date + 30 \
                               AND expiry_date <= current_date + 90)::bigint AS due_90 \
         FROM profile.document_expiry",
    )
    .fetch_one(db)
    .await?;
    Ok(row)
}

/// Count guards AND customers awaiting admin approval (`approval_status = 'pending'`) for the
/// dashboard new-applicants card + the ผู้สมัคร page tabs. ONE round-trip via two scalar
/// subqueries; the `idx_*_approval_status` partial-friendly indexes cover both predicates.
pub async fn count_pending_applicants(
    db: &PgPool,
) -> Result<crate::models::PendingApplicantsCount, AppError> {
    let (guards, customers): (i64, i64) = sqlx::query_as(
        "SELECT \
            (SELECT count(*) FROM profile.guard_profiles \
                WHERE approval_status = 'pending'::profile.approval_status)::bigint, \
            (SELECT count(*) FROM profile.customer_profiles \
                WHERE approval_status = 'pending'::profile.approval_status)::bigint",
    )
    .fetch_one(db)
    .await?;
    Ok(crate::models::PendingApplicantsCount {
        guards,
        customers,
        total: guards + customers,
    })
}

/// Average guard approval turnaround = mean(`reviewed_at - created_at`) over APPROVED guards.
/// Returns the average in seconds + the sample size. NULL average (None) when no guard has been
/// approved yet — the handler surfaces that as an honest empty state, not a fake 0. `reviewed_at`
/// is the dedicated decision timestamp (migration 0010), never clobbered by a guard self-edit.
pub async fn avg_approval_time_seconds(db: &PgPool) -> Result<(Option<i64>, i64), AppError> {
    // EXTRACT(EPOCH FROM avg(interval)) → double precision; round + cast to bigint in Rust to
    // keep the wire shape integral. count(*) over the same filtered set is the sample size.
    let (avg_secs, sample): (Option<f64>, i64) = sqlx::query_as(
        "SELECT \
            extract(epoch FROM avg(reviewed_at - created_at)), \
            count(*)::bigint \
         FROM profile.guard_profiles \
         WHERE approval_status = 'approved'::profile.approval_status \
           AND reviewed_at IS NOT NULL",
    )
    .fetch_one(db)
    .await?;
    Ok((avg_secs.map(|s| s.round() as i64), sample))
}

/// All recorded document expiries for ONE guard (the owner/admin view + edit). Ordered by type for
/// a stable list.
pub async fn list_document_expiries(
    db: &PgPool,
    guard_id: Uuid,
) -> Result<Vec<DocumentExpiryRow>, AppError> {
    let rows = sqlx::query_as::<_, DocumentExpiryRow>(
        "SELECT id, guard_id, document_type, expiry_date, \
                (expiry_date - current_date)::int AS days_left, last_reminded_at \
         FROM profile.document_expiry WHERE guard_id = $1 ORDER BY document_type",
    )
    .bind(guard_id)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Upsert one guard document's expiry date — one row per (guard, document_type), keyed on the
/// table's UNIQUE constraint so a later re-capture overwrites the date. Writes the PRIMARY (not
/// the replica). Returns the resulting row for the response.
pub async fn upsert_document_expiry(
    db: &PgPool,
    guard_id: Uuid,
    document_type: &str,
    expiry_date: NaiveDate,
) -> Result<DocumentExpiryRow, AppError> {
    let row = sqlx::query_as::<_, DocumentExpiryRow>(
        "INSERT INTO profile.document_expiry (guard_id, document_type, expiry_date) \
         VALUES ($1, $2, $3) \
         ON CONFLICT (guard_id, document_type) \
         DO UPDATE SET expiry_date = EXCLUDED.expiry_date, updated_at = now() \
         RETURNING id, guard_id, document_type, expiry_date, \
                   (expiry_date - current_date)::int AS days_left, last_reminded_at",
    )
    .bind(guard_id)
    .bind(document_type)
    .bind(expiry_date)
    .fetch_one(db)
    .await?;
    Ok(row)
}

/// Resolve the recipient `user_id`s for a broadcast audience. notification's bulk-send calls
/// this over the service-JWT'd internal endpoint because notification owns no user/role
/// registry; profile reads its OWN tables (NOT a cross-schema read for notification):
///   - `guards`    → every `profile.guard_profiles` row
///   - `customers` → every `profile.customer_profiles` row
///   - `all`       → the UNION of both (a user is one or the other, so the union just merges)
///
/// Bounded by `limit` (no unbounded service-to-service payload); truncation is the caller's to
/// log. Newest-first for the per-role lists; the UNION is unordered (set semantics). The
/// `audience` string is matched against a fixed set — never interpolated as raw SQL.
pub async fn recipient_ids(db: &PgPool, audience: &str, limit: i64) -> Result<Vec<Uuid>, AppError> {
    let sql = match audience {
        "guards" => "SELECT user_id FROM profile.guard_profiles ORDER BY created_at DESC LIMIT $1",
        "customers" => {
            "SELECT user_id FROM profile.customer_profiles ORDER BY created_at DESC LIMIT $1"
        }
        "all" => {
            "SELECT user_id FROM profile.guard_profiles \
             UNION \
             SELECT user_id FROM profile.customer_profiles \
             LIMIT $1"
        }
        other => {
            return Err(AppError::BadRequest(format!(
                "unknown audience: {other} (expected all|guards|customers)"
            )))
        }
    };
    let rows: Vec<(Uuid,)> = sqlx::query_as(sql)
        .bind(limit.clamp(1, 10_000))
        .fetch_all(db)
        .await?;
    Ok(rows.into_iter().map(|r| r.0).collect())
}

/// Raw guard-profile row (approval_status read as text, parsed below). `account_number` is
/// the UNMASKED stored value — masking is the handler's job, never the repo's.
struct GuardRow {
    user_id: Uuid,
    full_name: Option<String>,
    gender: Option<String>,
    date_of_birth: Option<NaiveDate>,
    years_of_experience: Option<i32>,
    previous_workplace: Option<String>,
    bank_name: Option<String>,
    account_number: Option<String>,
    account_name: Option<String>,
    address: Option<String>,
    emergency_contact_name: Option<String>,
    emergency_contact_phone: Option<String>,
    emergency_contact_relationship: Option<String>,
    approval_status: String,
}

impl GuardRow {
    /// Build the API response with the FULL (unmasked) account number. The owner-facing
    /// `GET /profile/me` masks it afterwards via [`crate::domain::mask`].
    fn into_response(self) -> Result<GuardProfileResponse, AppError> {
        let approval_status = ApprovalStatus::from_str(&self.approval_status)
            .map_err(|e| AppError::Internal(format!("unknown approval_status in db: {e}")))?;
        Ok(GuardProfileResponse {
            user_id: self.user_id,
            full_name: self.full_name,
            gender: self.gender,
            date_of_birth: self.date_of_birth,
            years_of_experience: self.years_of_experience,
            previous_workplace: self.previous_workplace,
            bank_name: self.bank_name,
            account_number: self.account_number,
            account_name: self.account_name,
            address: self.address,
            emergency_contact_name: self.emergency_contact_name,
            emergency_contact_phone: self.emergency_contact_phone,
            emergency_contact_relationship: self.emergency_contact_relationship,
            approval_status,
        })
    }
}

/// Columns selected for a guard profile (approval_status cast to text for decoding). Order is
/// positional — it MUST match `GuardTuple` + `guard_row_from_tuple`.
const GUARD_COLUMNS: &str = "user_id, full_name, gender, date_of_birth, years_of_experience, \
     previous_workplace, bank_name, account_number, account_name, address, \
     emergency_contact_name, emergency_contact_phone, emergency_contact_relationship, \
     approval_status::text";

type GuardTuple = (
    Uuid,
    Option<String>, // full_name
    Option<String>, // gender
    Option<NaiveDate>,
    Option<i32>,
    Option<String>, // previous_workplace
    Option<String>, // bank_name
    Option<String>, // account_number
    Option<String>, // account_name
    Option<String>, // address
    Option<String>, // emergency_contact_name
    Option<String>, // emergency_contact_phone
    Option<String>, // emergency_contact_relationship
    String,         // approval_status
);

/// [`GuardTuple`] + the admin queue's `created_at` (appended LAST — see [`list_guard_profiles`]).
type GuardAdminTuple = (
    Uuid,
    Option<String>, // full_name
    Option<String>, // gender
    Option<NaiveDate>,
    Option<i32>,
    Option<String>, // previous_workplace
    Option<String>, // bank_name
    Option<String>, // account_number
    Option<String>, // account_name
    Option<String>, // address
    Option<String>, // emergency_contact_name
    Option<String>, // emergency_contact_phone
    Option<String>, // emergency_contact_relationship
    String,         // approval_status
    DateTime<Utc>,  // created_at
);

fn guard_row_from_tuple(t: GuardTuple) -> GuardRow {
    GuardRow {
        user_id: t.0,
        full_name: t.1,
        gender: t.2,
        date_of_birth: t.3,
        years_of_experience: t.4,
        previous_workplace: t.5,
        bank_name: t.6,
        account_number: t.7,
        account_name: t.8,
        address: t.9,
        emergency_contact_name: t.10,
        emergency_contact_phone: t.11,
        emergency_contact_relationship: t.12,
        approval_status: t.13,
    }
}

// ----- Guard profile -----

/// Upsert the caller's guard profile. First insert sets `approval_status = 'pending'`
/// (the column default); a later upsert by the SAME guard updates the editable fields but
/// MUST NOT silently change the approval decision — so the `ON CONFLICT` clause leaves
/// `approval_status` untouched (only an admin moves it via [`set_approval_status`]).
pub async fn upsert_guard_profile(
    db: &PgPool,
    user_id: Uuid,
    req: &UpsertGuardProfileRequest,
) -> Result<GuardProfileResponse, AppError> {
    let sql = format!(
        r#"
        INSERT INTO profile.guard_profiles
            (user_id, full_name, gender, date_of_birth, years_of_experience, previous_workplace,
             bank_name, account_number, account_name, address,
             emergency_contact_name, emergency_contact_phone, emergency_contact_relationship)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
        ON CONFLICT (user_id) DO UPDATE SET
            full_name                      = EXCLUDED.full_name,
            gender                         = EXCLUDED.gender,
            date_of_birth                  = EXCLUDED.date_of_birth,
            years_of_experience            = EXCLUDED.years_of_experience,
            previous_workplace             = EXCLUDED.previous_workplace,
            bank_name                      = EXCLUDED.bank_name,
            account_number                 = EXCLUDED.account_number,
            account_name                   = EXCLUDED.account_name,
            address                        = EXCLUDED.address,
            emergency_contact_name         = EXCLUDED.emergency_contact_name,
            emergency_contact_phone        = EXCLUDED.emergency_contact_phone,
            emergency_contact_relationship = EXCLUDED.emergency_contact_relationship,
            updated_at                     = now()
        RETURNING {GUARD_COLUMNS}
        "#
    );
    let row: GuardTuple = sqlx::query_as(&sql)
        .bind(user_id)
        .bind(&req.full_name)
        .bind(&req.gender)
        .bind(req.date_of_birth)
        .bind(req.years_of_experience)
        .bind(&req.previous_workplace)
        .bind(&req.bank_name)
        .bind(&req.account_number)
        .bind(&req.account_name)
        .bind(&req.address)
        .bind(&req.emergency_contact_name)
        .bind(&req.emergency_contact_phone)
        .bind(&req.emergency_contact_relationship)
        .fetch_one(db)
        .await?;
    guard_row_from_tuple(row).into_response()
}

/// Update an EXISTING guard profile's editable fields (PUT). Unlike the upsert this never
/// inserts: a missing profile is a 404 (the guard must create it first).
pub async fn update_guard_profile(
    db: &PgPool,
    user_id: Uuid,
    req: &UpsertGuardProfileRequest,
) -> Result<GuardProfileResponse, AppError> {
    let sql = format!(
        r#"
        UPDATE profile.guard_profiles SET
            full_name                      = $2,
            gender                         = $3,
            date_of_birth                  = $4,
            years_of_experience            = $5,
            previous_workplace             = $6,
            bank_name                      = $7,
            account_number                 = $8,
            account_name                   = $9,
            address                        = $10,
            emergency_contact_name         = $11,
            emergency_contact_phone        = $12,
            emergency_contact_relationship = $13,
            updated_at                     = now()
        WHERE user_id = $1
        RETURNING {GUARD_COLUMNS}
        "#
    );
    let row: Option<GuardTuple> = sqlx::query_as(&sql)
        .bind(user_id)
        .bind(&req.full_name)
        .bind(&req.gender)
        .bind(req.date_of_birth)
        .bind(req.years_of_experience)
        .bind(&req.previous_workplace)
        .bind(&req.bank_name)
        .bind(&req.account_number)
        .bind(&req.account_name)
        .bind(&req.address)
        .bind(&req.emergency_contact_name)
        .bind(&req.emergency_contact_phone)
        .bind(&req.emergency_contact_relationship)
        .fetch_optional(db)
        .await?;
    row.map(guard_row_from_tuple)
        .ok_or_else(|| AppError::NotFound("Guard profile not found".to_string()))?
        .into_response()
}

/// Fetch the caller's guard profile (FULL account number — caller masks if needed).
pub async fn get_guard_profile(
    db: &PgPool,
    user_id: Uuid,
) -> Result<Option<GuardProfileResponse>, AppError> {
    let sql = format!("SELECT {GUARD_COLUMNS} FROM profile.guard_profiles WHERE user_id = $1");
    let row: Option<GuardTuple> = sqlx::query_as(&sql)
        .bind(user_id)
        .fetch_optional(db)
        .await?;
    row.map(guard_row_from_tuple)
        .map(GuardRow::into_response)
        .transpose()
}

/// Fetch the customer-facing guard MINI-profile for the live-tracking map
/// (`GET /guards/{id}/public`). Returns `None` (→ 404) unless the guard exists AND is
/// `approved` — so an un-approved/unknown guard's existence is never revealed, and only vetted
/// guards' names are ever exposed. Lean projection (user_id + full_name + experience) — NEVER
/// the bank/address/DOB/emergency-contact PII columns (least-privilege). The IDOR gate
/// (customer must have an ACTIVE booking with this guard) is the handler's job; this is the
/// post-authz read.
pub async fn get_public_guard_profile(
    db: &PgPool,
    guard_id: Uuid,
) -> Result<Option<PublicGuardProfileRow>, AppError> {
    // Lean projection incl. the raw `avatar_key` (the handler presigns it into `avatar_url`; the key
    // never crosses the wire) — mirrors the customer-public read.
    let row = sqlx::query_as::<_, PublicGuardProfileRow>(
        "SELECT user_id, full_name, years_of_experience, avatar_key FROM profile.guard_profiles \
         WHERE user_id = $1 AND approval_status = 'approved'::profile.approval_status",
    )
    .bind(guard_id)
    .fetch_optional(db)
    .await?;
    Ok(row)
}

/// Fetch the guard-facing customer MINI-profile for the assigned guard's job sheet
/// (`GET /customers/{id}/public`). The mirror of [`get_public_guard_profile`] for the other
/// direction. Returns `None` (→ 404) when the customer has no profile row. Lean projection
/// (user_id + full_name + the raw `avatar_key`, which the handler presigns) — NEVER the
/// address/company/email/phone PII. UNLIKE the guard read,
/// there is NO approval filter: a customer's name must be visible to their guard regardless of
/// the customer's own admin-approval state (a booking only exists for an approved customer
/// anyway). The IDOR gate (the caller must be the guard ASSIGNED to an active booking with this
/// customer) is the handler's job; this is the post-authz read.
pub async fn get_public_customer_profile(
    db: &PgPool,
    customer_id: Uuid,
) -> Result<Option<PublicCustomerProfileRow>, AppError> {
    let row = sqlx::query_as::<_, PublicCustomerProfileRow>(
        "SELECT user_id, full_name, avatar_key FROM profile.customer_profiles WHERE user_id = $1",
    )
    .bind(customer_id)
    .fetch_optional(db)
    .await?;
    Ok(row)
}

/// Resolve a batch of `user_id`s to `{ user_id, full_name, role }` for the admin name-resolver
/// (`POST /admin/users/resolve`). UNIONs the two profile tables profile OWNS — a hit in
/// `guard_profiles` is role `guard`, a hit in `customer_profiles` is role `customer` (a user is
/// exactly one, so no id collides across the two). Ids with NO row (admins — who have no profile
/// row / stored name — and genuinely-unknown/deleted ids) simply DON'T come back: the handler
/// omits them, which is null-safe (the client falls back to id/role-label). Lean projection —
/// only the name + the derived role, NEVER bank/address/phone PII (least-privilege). `role` is
/// a SQL literal, not user input; the ids are a single bound array (`= ANY($1)`), never
/// interpolated. NO approval filter (UNLIKE the customer-facing `get_public_guard_profile`): an
/// admin must see the name of a guard on a job even before the guard is approved.
pub async fn resolve_names(db: &PgPool, ids: &[Uuid]) -> Result<Vec<ResolvedNameRow>, AppError> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }
    let rows = sqlx::query_as::<_, ResolvedNameRow>(
        "SELECT user_id, full_name, 'guard' AS role \
           FROM profile.guard_profiles WHERE user_id = ANY($1) \
         UNION ALL \
         SELECT user_id, full_name, 'customer' AS role \
           FROM profile.customer_profiles WHERE user_id = ANY($1)",
    )
    .bind(ids)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

// ----- Guard document image keys (S3 object paths) -----

/// Write the S3 object key for ONE guard document into its `*_key` column. `column` MUST be a
/// value from the closed `domain::documents::key_column_for` allowlist (never user input) — it is
/// the one justified dynamic-column `format!`; the key is a bound parameter. 404 when the guard
/// has no profile row yet (they must submit their profile first, like `update_guard_profile`).
pub async fn update_document_key(
    db: &PgPool,
    user_id: Uuid,
    column: &'static str,
    key: &str,
) -> Result<(), AppError> {
    let sql = format!(
        "UPDATE profile.guard_profiles SET {column} = $2, updated_at = now() WHERE user_id = $1"
    );
    let n = sqlx::query(&sql)
        .bind(user_id)
        .bind(key)
        .execute(db)
        .await?
        .rows_affected();
    if n == 0 {
        return Err(AppError::NotFound("Guard profile not found".to_string()));
    }
    Ok(())
}

/// Read the S3 object key stored in ONE guard document's `*_key` column. `column` MUST be from the
/// `key_column_for` allowlist. `None` when the column is NULL (not uploaded) or no profile exists.
pub async fn get_document_key(
    db: &PgPool,
    user_id: Uuid,
    column: &'static str,
) -> Result<Option<String>, AppError> {
    let sql = format!("SELECT {column} FROM profile.guard_profiles WHERE user_id = $1");
    let row: Option<(Option<String>,)> = sqlx::query_as(&sql)
        .bind(user_id)
        .fetch_optional(db)
        .await?;
    Ok(row.and_then(|(key,)| key))
}

// ----- Customer avatar image key (S3 object path) -----
//
// The customer side mirrors the guard `update_document_key`/`get_document_key` pair but targets
// `profile.customer_profiles`. A customer has exactly ONE image column (`avatar_key`) — no
// credential docs — so there is no `key_column_for` allowlist here: the handler passes the fixed
// `AVATAR_KEY_COLUMN` `&'static str` (never client-controlled), the only dynamic-column `format!`.

/// Write the S3 object key for the customer's avatar into its `avatar_key` column. `column` MUST be
/// the fixed `AVATAR_KEY_COLUMN` `&'static str` (never user input); the key is a bound parameter.
/// 404 when the customer has no profile row yet (they must submit their profile first).
pub async fn update_customer_document_key(
    db: &PgPool,
    user_id: Uuid,
    column: &'static str,
    key: &str,
) -> Result<(), AppError> {
    let sql = format!(
        "UPDATE profile.customer_profiles SET {column} = $2, updated_at = now() WHERE user_id = $1"
    );
    let n = sqlx::query(&sql)
        .bind(user_id)
        .bind(key)
        .execute(db)
        .await?
        .rows_affected();
    if n == 0 {
        return Err(AppError::NotFound("Customer profile not found".to_string()));
    }
    Ok(())
}

/// Read the S3 object key stored in the customer's `avatar_key` column. `column` MUST be the fixed
/// `AVATAR_KEY_COLUMN`. `None` when the column is NULL (not uploaded) or no profile exists.
pub async fn get_customer_document_key(
    db: &PgPool,
    user_id: Uuid,
    column: &'static str,
) -> Result<Option<String>, AppError> {
    let sql = format!("SELECT {column} FROM profile.customer_profiles WHERE user_id = $1");
    let row: Option<(Option<String>,)> = sqlx::query_as(&sql)
        .bind(user_id)
        .fetch_optional(db)
        .await?;
    Ok(row.and_then(|(key,)| key))
}

// ----- Event-derived IDOR read-model (guard_assignments) -----

/// The IDOR read: does `customer_id` have an ACTIVE booking with `guard_id`? Reads the
/// event-derived `profile.guard_assignments` read-model (projected from `pguard.events.booking.*`
/// by the booking-links consumer). NO cross-schema read of booking's tables, NO cross-service FK.
pub async fn has_active_booking(
    db: &PgPool,
    customer_id: Uuid,
    guard_id: Uuid,
) -> Result<bool, AppError> {
    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS( \
            SELECT 1 FROM profile.guard_assignments \
            WHERE customer_id = $1 AND guard_id = $2 AND active \
         )",
    )
    .bind(customer_id)
    .bind(guard_id)
    .fetch_one(db)
    .await?;
    Ok(exists)
}

/// Project one booking event onto the read-model: upsert the (booking_id) link's `active` flag.
/// Idempotent + LAST-WRITER-WINS by `occurred_at` — the `WHERE EXCLUDED.updated_at >
/// profile.guard_assignments.updated_at` guard means a redelivered/reordered OLDER event never
/// reactivates a finished booking (at-least-once JetStream delivery is safe). `customer_id`/
/// `guard_id` are COALESCEd so a terminal event that omits them keeps the ids from the accept.
pub async fn upsert_assignment(
    db: &PgPool,
    booking_id: Uuid,
    customer_id: Option<Uuid>,
    guard_id: Option<Uuid>,
    active: bool,
    occurred_at: DateTime<Utc>,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO profile.guard_assignments \
             (booking_id, customer_id, guard_id, active, updated_at) \
         VALUES ($1, $2, $3, $4, $5) \
         ON CONFLICT (booking_id) DO UPDATE SET \
             customer_id = COALESCE(EXCLUDED.customer_id, profile.guard_assignments.customer_id), \
             guard_id    = COALESCE(EXCLUDED.guard_id, profile.guard_assignments.guard_id), \
             active      = EXCLUDED.active, \
             updated_at  = EXCLUDED.updated_at \
         WHERE EXCLUDED.updated_at > profile.guard_assignments.updated_at",
    )
    .bind(booking_id)
    .bind(customer_id)
    .bind(guard_id)
    .bind(active)
    .bind(occurred_at)
    .execute(db)
    .await?;
    Ok(())
}

/// List guard profiles for the admin onboarding queue, newest first. An optional
/// `status` filters by approval_status (compared as text against the enum cast).
///
/// Selects `created_at` ON TOP of [`GUARD_COLUMNS`] (the shared projection the owner-facing
/// reads reuse) so the queue can show HOW LONG an applicant has been waiting — the customer
/// admin list already returned it, the guard one didn't. Hence the `+ 1` tuple element; the
/// order stays positional, so the extra column is appended LAST, after `approval_status`.
pub async fn list_guard_profiles(
    db: &PgPool,
    status: Option<ApprovalStatus>,
) -> Result<Vec<GuardProfileAdminResponse>, AppError> {
    let mut sql = format!("SELECT {GUARD_COLUMNS}, created_at FROM profile.guard_profiles");
    if status.is_some() {
        sql.push_str(" WHERE approval_status = $1::profile.approval_status");
    }
    sql.push_str(" ORDER BY created_at DESC LIMIT 200");

    let mut query = sqlx::query_as::<_, GuardAdminTuple>(&sql);
    if let Some(s) = &status {
        query = query.bind(s.to_string());
    }
    let rows = query.fetch_all(db).await?;
    rows.into_iter()
        .map(|row| {
            let created_at = row.14;
            let base: GuardTuple = (
                row.0, row.1, row.2, row.3, row.4, row.5, row.6, row.7, row.8, row.9, row.10,
                row.11, row.12, row.13,
            );
            Ok(GuardProfileAdminResponse {
                profile: guard_row_from_tuple(base).into_response()?,
                created_at,
            })
        })
        .collect()
}

/// List APPROVED guards for the internal discovery catalog (booking's `/available-guards`).
/// Narrow projection (user_id + name + avatar key + experience + a derived documents boolean) —
/// NEVER the bank/PII columns; least-privilege over the service-to-service wire. `full_name` +
/// `avatar_key` enrich the customer's guard-selection card (the handler presigns `avatar_key`);
/// both are the same approved-guard exposure as `GET /guards/{id}/public`. `has_documents` is
/// derived HERE (all five credential `*_key` columns non-null — passbook excluded, it's banking
/// not a credential) so only a boolean ever crosses the wire, never the keys. Bounded (`LIMIT`),
/// newest first; NOT paginated yet, so a roster beyond the cap is truncated (the handler logs
/// it). The `user_id` tiebreaker makes the order deterministic when `created_at` ties (stable
/// across calls).
pub async fn list_approved_guards(
    db: &PgPool,
    limit: i64,
) -> Result<Vec<InternalGuardRow>, AppError> {
    let rows = sqlx::query_as::<_, InternalGuardRow>(
        "SELECT user_id, full_name, avatar_key, years_of_experience, \
         (id_card_key IS NOT NULL AND security_license_key IS NOT NULL \
          AND training_cert_key IS NOT NULL AND criminal_check_key IS NOT NULL \
          AND driver_license_key IS NOT NULL) AS has_documents, \
         (id_card_key IS NOT NULL) AS has_id_card, \
         (security_license_key IS NOT NULL) AS has_security_license, \
         (training_cert_key IS NOT NULL) AS has_training_cert, \
         (criminal_check_key IS NOT NULL) AS has_criminal_check, \
         (driver_license_key IS NOT NULL) AS has_driver_license \
         FROM profile.guard_profiles \
         WHERE approval_status = 'approved'::profile.approval_status \
         ORDER BY created_at DESC, user_id DESC LIMIT $1",
    )
    .bind(limit.clamp(1, 200))
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Admin: set a guard profile's approval status (row-locked + transition-checked) AND emit
/// the matching account event into the outbox — IN ONE TRANSACTION.
///
/// Reads the current status under `FOR UPDATE`, applies the pure
/// [`crate::domain::approval::can_transition`] gate, and writes only if legal — so two
/// concurrent admins cannot both finalize the same pending profile into conflicting states.
///
/// The status flip and the outbox row are **atomic**: an `Approved` transition writes a
/// `user.approved` event (and `Rejected` → `user.rejected`) in the same tx, so the event is
/// emitted iff the flip commits — never one without the other. identity consumes
/// `user.approved` and flips ITS OWN `users.approval_status` (no cross-schema write here;
/// profile only ever touches `profile.*` + its outbox). `role` is informational metadata for
/// the consumer (the route already determines it — `guard`). Returns the updated profile
/// (FULL account number; admin endpoints don't mask).
#[tracing::instrument(skip(db), fields(user_id = %user_id, target = %target, role = %role))]
pub async fn set_approval_status(
    db: &PgPool,
    user_id: Uuid,
    target: ApprovalStatus,
    role: &str,
) -> Result<GuardProfileResponse, AppError> {
    let mut tx = db.begin().await?;

    let current: Option<(String,)> = sqlx::query_as(
        "SELECT approval_status::text FROM profile.guard_profiles WHERE user_id = $1 FOR UPDATE",
    )
    .bind(user_id)
    .fetch_optional(&mut *tx)
    .await?;

    let current = match current {
        Some((s,)) => ApprovalStatus::from_str(&s)
            .map_err(|e| AppError::Internal(format!("unknown approval_status in db: {e}")))?,
        None => {
            tx.rollback().await?;
            return Err(AppError::NotFound("Guard profile not found".to_string()));
        }
    };

    if !crate::domain::approval::can_transition(current.clone(), target.clone()) {
        tx.rollback().await?;
        return Err(AppError::Conflict(format!(
            "illegal approval transition {current} → {target}"
        )));
    }

    // Stamp `reviewed_at` (the dedicated decision timestamp the avg-approval-time metric reads)
    // in the SAME write that flips the status — a guard self-edit never touches it, so
    // `reviewed_at - created_at` stays a faithful approval duration (unlike the generic
    // `updated_at`). Stamped on reject too (for a future review-SLA), even though the metric
    // averages only approvals.
    let sql = format!(
        r#"
        UPDATE profile.guard_profiles
        SET approval_status = $2::profile.approval_status, reviewed_at = now(), updated_at = now()
        WHERE user_id = $1
        RETURNING {GUARD_COLUMNS}
        "#
    );
    let row: GuardTuple = sqlx::query_as(&sql)
        .bind(user_id)
        .bind(target.to_string())
        .fetch_one(&mut *tx)
        .await?;

    // Atomic with the flip: enqueue the account event for identity to consume. APPROVAL unblocks
    // login; REJECTION now also emits `user.rejected` so identity flips ITS OWN approval_status to
    // 'rejected' — the applicant can then be shown a distinct rejected state (instead of "pending
    // forever") and a rejected phone can be re-registered (deep-review).
    if let Some(topic) = approval_event_topic(&target) {
        let now = Utc::now();
        let envelope = EventEnvelope::new(
            topic,
            Uuid::new_v4(),
            serde_json::json!({ "user_id": user_id, "role": role, "approved_at": now }),
        );
        let payload = serde_json::to_value(&envelope)
            .map_err(|e| AppError::Internal(format!("serialize outbox envelope: {e}")))?;
        enqueue_outbox(&mut tx, topic, &payload).await?;
    }

    tx.commit().await?;
    guard_row_from_tuple(row).into_response()
}

/// The account-event topic to emit for an approval transition. `Approved` → `user.approved` (the
/// login unblocker); `Rejected` → `user.rejected` (identity flips its own status so the applicant
/// sees a distinct rejected state + can re-apply). `Pending` emits nothing.
fn approval_event_topic(target: &ApprovalStatus) -> Option<&'static str> {
    match target {
        ApprovalStatus::Approved => Some(topics::USER_APPROVED),
        ApprovalStatus::Rejected => Some(topics::USER_REJECTED),
        ApprovalStatus::Pending => None,
    }
}

/// Admin: set a CUSTOMER profile's approval status (row-locked + transition-checked) AND emit
/// the matching account event into the outbox — IN ONE TRANSACTION. The customer mirror of
/// [`set_approval_status`]: customers are now vetted exactly like guards (no longer
/// auto-approved on first profile insert).
///
/// Reads the current status under `FOR UPDATE`, applies the same pure
/// [`crate::domain::approval::can_transition`] gate, and writes only if legal — so two
/// concurrent admins cannot both finalize the same pending customer into conflicting states.
///
/// The status flip and the outbox row are **atomic** (shared [`approval_event_topic`] helper):
/// an `Approved` transition writes a `user.approved` event in the same tx (and `Rejected` →
/// none, since login already blocks every non-`approved` account), so the event is emitted iff
/// the flip commits. identity's `user.approved` consumer is role-agnostic (flips ITS OWN
/// `users.approval_status` by `user_id`), so the existing approval→login loop closes unchanged;
/// `role = "customer"` is informational metadata for the consumer (the route determines it). No
/// cross-schema write here — profile only ever touches `profile.*` + its outbox. Returns the
/// updated customer profile.
#[allow(clippy::type_complexity)]
#[tracing::instrument(skip(db), fields(user_id = %user_id, target = %target, role = %role))]
pub async fn set_customer_approval(
    db: &PgPool,
    user_id: Uuid,
    target: ApprovalStatus,
    role: &str,
) -> Result<CustomerProfileResponse, AppError> {
    let mut tx = db.begin().await?;

    let current: Option<(String,)> = sqlx::query_as(
        "SELECT approval_status::text FROM profile.customer_profiles WHERE user_id = $1 FOR UPDATE",
    )
    .bind(user_id)
    .fetch_optional(&mut *tx)
    .await?;

    let current = match current {
        Some((s,)) => ApprovalStatus::from_str(&s)
            .map_err(|e| AppError::Internal(format!("unknown approval_status in db: {e}")))?,
        None => {
            tx.rollback().await?;
            return Err(AppError::NotFound("Customer profile not found".to_string()));
        }
    };

    if !crate::domain::approval::can_transition(current.clone(), target.clone()) {
        tx.rollback().await?;
        return Err(AppError::Conflict(format!(
            "illegal approval transition {current} → {target}"
        )));
    }

    let row: (
        Uuid,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    ) = sqlx::query_as(
        "UPDATE profile.customer_profiles \
         SET approval_status = $2::profile.approval_status, updated_at = now() \
         WHERE user_id = $1 \
         RETURNING user_id, full_name, address, company_name, email, contact_phone",
    )
    .bind(user_id)
    .bind(target.to_string())
    .fetch_one(&mut *tx)
    .await?;

    // Atomic with the flip: enqueue the account event for identity to consume. Only an
    // APPROVAL needs an event — it's the login UNBLOCKER identity must react to (a rejection
    // needs none: login already blocks every non-`approved` account). Shares the guard helper.
    if let Some(topic) = approval_event_topic(&target) {
        let now = Utc::now();
        let envelope = EventEnvelope::new(
            topic,
            Uuid::new_v4(),
            serde_json::json!({ "user_id": user_id, "role": role, "approved_at": now }),
        );
        let payload = serde_json::to_value(&envelope)
            .map_err(|e| AppError::Internal(format!("serialize outbox envelope: {e}")))?;
        enqueue_outbox(&mut tx, topic, &payload).await?;
    }

    tx.commit().await?;
    Ok(CustomerProfileResponse {
        user_id: row.0,
        full_name: row.1,
        address: row.2,
        company_name: row.3,
        email: row.4,
        contact_phone: row.5,
    })
}

// ----- Transactional outbox (producer + relay support) -----

/// One unpublished outbox row, as the relay reads it.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct OutboxRow {
    pub id: Uuid,
    pub topic: String,
    /// The serialized `EventEnvelope` (JSONB).
    pub payload: Value,
}

/// Insert one outbox row inside the caller's transaction (atomic with the business write).
async fn enqueue_outbox(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    topic: &str,
    envelope_json: &Value,
) -> Result<(), AppError> {
    sqlx::query("INSERT INTO profile.outbox (topic, payload) VALUES ($1, $2)")
        .bind(topic)
        .bind(envelope_json)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

/// Fetch up to `limit` unpublished outbox rows, oldest first (relay drain).
pub async fn fetch_unpublished(db: &PgPool, limit: i64) -> Result<Vec<OutboxRow>, AppError> {
    let rows = sqlx::query_as::<_, OutboxRow>(
        "SELECT id, topic, payload FROM profile.outbox \
         WHERE published_at IS NULL ORDER BY created_at LIMIT $1",
    )
    .bind(limit)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Stamp one outbox row published (called only after a successful NATS publish).
pub async fn mark_published(db: &PgPool, id: Uuid) -> Result<(), AppError> {
    sqlx::query("UPDATE profile.outbox SET published_at = now() WHERE id = $1")
        .bind(id)
        .execute(db)
        .await?;
    Ok(())
}

// ----- Customer profile -----

/// Upsert the caller's customer profile (minimal in this slice).
///
/// First insert sets `approval_status = 'pending'` (the column default): customers are now
/// **admin-approved**, NOT auto-approved — they are vetted by an admin via
/// [`set_customer_approval`] exactly like guards (`set_approval_status`), and stay `pending`
/// (login-blocked in identity) until that approval emits `user.approved`. This upsert therefore
/// emits NO event — the INSERT relies on the column default and the `ON CONFLICT` (self-edit)
/// path deliberately leaves `approval_status` untouched (only an admin moves it), so a customer
/// re-saving their profile can never silently re-approve themselves.
#[allow(clippy::type_complexity)]
pub async fn upsert_customer_profile(
    db: &PgPool,
    user_id: Uuid,
    req: &UpsertCustomerProfileRequest,
) -> Result<CustomerProfileResponse, AppError> {
    let row: (
        Uuid,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    ) = sqlx::query_as(
        r#"
        INSERT INTO profile.customer_profiles
            (user_id, full_name, address, company_name, email, contact_phone)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (user_id) DO UPDATE SET
            full_name     = EXCLUDED.full_name,
            address       = EXCLUDED.address,
            company_name  = EXCLUDED.company_name,
            email         = EXCLUDED.email,
            contact_phone = EXCLUDED.contact_phone,
            updated_at    = now()
        RETURNING user_id, full_name, address, company_name, email, contact_phone
        "#,
    )
    .bind(user_id)
    .bind(&req.full_name)
    .bind(&req.address)
    .bind(&req.company_name)
    .bind(&req.email)
    .bind(&req.contact_phone)
    .fetch_one(db)
    .await?;
    Ok(CustomerProfileResponse {
        user_id: row.0,
        full_name: row.1,
        address: row.2,
        company_name: row.3,
        email: row.4,
        contact_phone: row.5,
    })
}

/// Fetch the caller's customer profile.
#[allow(clippy::type_complexity)]
pub async fn get_customer_profile(
    db: &PgPool,
    user_id: Uuid,
) -> Result<Option<CustomerProfileResponse>, AppError> {
    let row: Option<(
        Uuid,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    )> = sqlx::query_as(
        "SELECT user_id, full_name, address, company_name, email, contact_phone \
             FROM profile.customer_profiles WHERE user_id = $1",
    )
    .bind(user_id)
    .fetch_optional(db)
    .await?;
    Ok(row.map(
        |(user_id, full_name, address, company_name, email, contact_phone)| {
            CustomerProfileResponse {
                user_id,
                full_name,
                address,
                company_name,
                email,
                contact_phone,
            }
        },
    ))
}

/// List customer profiles for the admin surface (`GET /admin/customer-profiles`), optionally
/// filtered by `approval_status` (mirrors the guard list — drives the ผู้สมัคร page's customer
/// pending tab). Cross-user (no owner filter) — the admin-role gate is the API layer's job.
/// Newest first, capped at 200 (NOT paginated — same documented limitation as the guard admin
/// list). Carries `approval_status` (read as `::text`) so the admin can see pending vs
/// approved/rejected customers — customers are now admin-approved (`set_customer_approval`),
/// no longer auto-approved.
pub async fn list_customer_profiles(
    db: &PgPool,
    status: Option<ApprovalStatus>,
) -> Result<Vec<CustomerProfileAdminResponse>, AppError> {
    // Columns match `CustomerProfileAdminResponse` field-for-field → decode via `FromRow`
    // (no intermediate tuple). `approval_status` is cast to text + aliased so FromRow binds it
    // by name. No transformation (unlike the guard list's mask step).
    let mut sql = String::from(
        "SELECT user_id, full_name, address, company_name, email, contact_phone, created_at, \
                approval_status::text AS approval_status \
         FROM profile.customer_profiles",
    );
    if status.is_some() {
        sql.push_str(" WHERE approval_status = $1::profile.approval_status");
    }
    sql.push_str(" ORDER BY created_at DESC LIMIT 200");

    let mut query = sqlx::query_as::<_, CustomerProfileAdminResponse>(&sql);
    if let Some(s) = &status {
        query = query.bind(s.to_string());
    }
    let rows = query.fetch_all(db).await?;
    Ok(rows)
}

/// Record an admin read of personal data (PDPA §30 — who accessed what). This is a WRITE, so
/// the caller runs it on the PRIMARY pool (the accompanying admin LIST reads from the replica,
/// C5.3). It propagates errors rather than swallowing them — an unrecorded access should fail
/// loudly rather than disclose PII silently.
pub async fn record_access(
    db: &PgPool,
    accessed_by: Uuid,
    action: &str,
    target: Option<&str>,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO profile.access_audit (accessed_by, action, target) VALUES ($1, $2, $3)",
    )
    .bind(accessed_by)
    .bind(action)
    .bind(target)
    .execute(db)
    .await?;
    Ok(())
}

/// List PDPA §30 data-access audit rows (admin), newest first, optional `action` filter +
/// limit/offset. Read from the replica. The `action` value is a BOUND parameter.
pub async fn list_access_audit(
    db: &PgPool,
    action: Option<&str>,
    limit: i64,
    offset: i64,
) -> Result<Vec<AccessAuditRow>, AppError> {
    let mut sql = String::from(
        "SELECT id, accessed_by, action, target, accessed_at FROM profile.access_audit",
    );
    if action.is_some() {
        sql.push_str(" WHERE action = $1");
    }
    let lim = if action.is_some() { 2 } else { 1 };
    sql.push_str(&format!(
        " ORDER BY accessed_at DESC LIMIT ${} OFFSET ${}",
        lim,
        lim + 1
    ));
    let mut query = sqlx::query_as::<_, AccessAuditRow>(&sql);
    if let Some(a) = action {
        query = query.bind(a);
    }
    let rows = query.bind(limit).bind(offset).fetch_all(db).await?;
    Ok(rows)
}

// ----- Organization (company) profile settings (#143) — single-row store -----

/// Read the single-row org (company) profile. Returns the "unset" default (all `null`) when no
/// row exists yet — so the admin GET never 404s. Read from the replica.
pub async fn get_org_settings(db: &PgPool) -> Result<OrgSettingsResponse, AppError> {
    let row: Option<OrgSettingsResponse> = sqlx::query_as(
        "SELECT company_name, tax_id, address, updated_at \
         FROM profile.org_settings WHERE id = TRUE",
    )
    .fetch_optional(db)
    .await?;
    Ok(row.unwrap_or_else(OrgSettingsResponse::unset))
}

/// Upsert the single-row org (company) profile (PUT). The fixed `id = TRUE` primary key plus
/// the `CHECK (id)` constraint pins the table to at most one row; `ON CONFLICT (id)` overwrites
/// it. `updated_by` records the acting admin (no cross-service FK), `updated_at = now()`. All
/// three business fields are written unconditionally (the handler sends the full object, like
/// the profile upsert) — returns the stored row for read-back.
pub async fn upsert_org_settings(
    db: &PgPool,
    updated_by: Uuid,
    req: &UpdateOrgSettingsRequest,
) -> Result<OrgSettingsResponse, AppError> {
    let row: OrgSettingsResponse = sqlx::query_as(
        "INSERT INTO profile.org_settings (id, company_name, tax_id, address, updated_by, updated_at) \
         VALUES (TRUE, $1, $2, $3, $4, now()) \
         ON CONFLICT (id) DO UPDATE SET \
             company_name = EXCLUDED.company_name, \
             tax_id       = EXCLUDED.tax_id, \
             address      = EXCLUDED.address, \
             updated_by   = EXCLUDED.updated_by, \
             updated_at   = now() \
         RETURNING company_name, tax_id, address, updated_at",
    )
    .bind(req.company_name.as_deref())
    .bind(req.tax_id.as_deref())
    .bind(req.address.as_deref())
    .bind(updated_by)
    .fetch_one(db)
    .await?;
    Ok(row)
}

/// The roles this user has a SUBMITTED-but-PENDING profile for (awaiting admin approval). Union of
/// the guard + customer profile tables filtered to `approval_status = 'pending'`. Identity calls
/// this (service-JWT) to enrich `/auth/me` with `pending_roles`, so the mobile mode-picker can show
/// a submitted role as "รอการยืนยัน / pending approval" instead of re-offering its blank form.
/// Read-only; returns `[]` when nothing is pending.
pub async fn pending_roles_for_user(db: &PgPool, user_id: Uuid) -> Result<Vec<String>, AppError> {
    let roles: Vec<String> = sqlx::query_scalar(
        "SELECT 'guard' FROM profile.guard_profiles \
              WHERE user_id = $1 AND approval_status = 'pending'::profile.approval_status \
         UNION \
         SELECT 'customer' FROM profile.customer_profiles \
              WHERE user_id = $1 AND approval_status = 'pending'::profile.approval_status",
    )
    .bind(user_id)
    .fetch_all(db)
    .await?;
    Ok(roles)
}

/// PDPA §19/§32 data export: the user's OWN profile rows (guard and/or customer). This is
/// the data subject reading their own data, so the FULL account number is returned;
/// documents are reported as presence flags (not raw S3 keys — signed-URL download is a
/// follow-up). Scoped strictly to `user_id`.
#[allow(clippy::type_complexity)]
pub async fn export_user_data(db: &PgPool, user_id: Uuid) -> Result<serde_json::Value, AppError> {
    // A named FromRow struct (not a tuple): the guard export is 20 columns, past sqlx's tuple
    // FromRow arity cap. Column names match field names (no aliases needed).
    #[derive(sqlx::FromRow)]
    struct GuardExportRow {
        gender: Option<String>,
        date_of_birth: Option<NaiveDate>,
        years_of_experience: Option<i32>,
        previous_workplace: Option<String>,
        bank_name: Option<String>,
        account_number: Option<String>,
        account_name: Option<String>,
        id_card_key: Option<String>,
        security_license_key: Option<String>,
        training_cert_key: Option<String>,
        criminal_check_key: Option<String>,
        driver_license_key: Option<String>,
        passbook_photo_key: Option<String>,
        full_name: Option<String>,
        address: Option<String>,
        emergency_contact_name: Option<String>,
        emergency_contact_phone: Option<String>,
        emergency_contact_relationship: Option<String>,
        created_at: DateTime<Utc>,
        updated_at: DateTime<Utc>,
    }
    let guard: Option<GuardExportRow> = sqlx::query_as(
        "SELECT gender, date_of_birth, years_of_experience, previous_workplace, \
                bank_name, account_number, account_name, \
                id_card_key, security_license_key, training_cert_key, criminal_check_key, \
                driver_license_key, passbook_photo_key, \
                full_name, address, emergency_contact_name, emergency_contact_phone, \
                emergency_contact_relationship, created_at, updated_at \
         FROM profile.guard_profiles WHERE user_id = $1",
    )
    .bind(user_id)
    .fetch_optional(db)
    .await?;

    let guard_json = guard.map(|g| {
        serde_json::json!({
            "full_name": g.full_name,
            "gender": g.gender,
            "date_of_birth": g.date_of_birth,
            "years_of_experience": g.years_of_experience,
            "previous_workplace": g.previous_workplace,
            "bank_name": g.bank_name,
            "account_number": g.account_number,
            "account_name": g.account_name,
            "address": g.address,
            "emergency_contact_name": g.emergency_contact_name,
            "emergency_contact_phone": g.emergency_contact_phone,
            "emergency_contact_relationship": g.emergency_contact_relationship,
            "documents": {
                "id_card": g.id_card_key.is_some(),
                "security_license": g.security_license_key.is_some(),
                "training_cert": g.training_cert_key.is_some(),
                "criminal_check": g.criminal_check_key.is_some(),
                "driver_license": g.driver_license_key.is_some(),
                "passbook_photo": g.passbook_photo_key.is_some(),
            },
            "created_at": g.created_at,
            "updated_at": g.updated_at,
        })
    });

    let customer: Option<(
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        DateTime<Utc>,
        DateTime<Utc>,
    )> = sqlx::query_as(
        "SELECT full_name, address, company_name, email, contact_phone, created_at, updated_at \
             FROM profile.customer_profiles WHERE user_id = $1",
    )
    .bind(user_id)
    .fetch_optional(db)
    .await?;
    let customer_json = customer.map(
        |(full_name, address, company_name, email, contact_phone, created_at, updated_at)| {
            serde_json::json!({
                "full_name": full_name,
                "address": address,
                "company_name": company_name,
                "email": email,
                "contact_phone": contact_phone,
                "created_at": created_at,
                "updated_at": updated_at,
            })
        },
    );

    Ok(serde_json::json!({
        "guard_profile": guard_json,
        "customer_profile": customer_json,
    }))
}

#[cfg(test)]
mod db_tests {
    use super::*;
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;

    /// PDPA §30 read-audit: `record_access` writes a row attributable to the admin. Gated on
    /// `DATABASE_URL` (migrated profile 0001+0002); hermetic SKIP otherwise.
    #[tokio::test]
    async fn record_access_writes_a_row() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let admin = Uuid::new_v4();
        record_access(&pool, admin, "admin_list_guard_profiles", Some("approved"))
            .await
            .expect("record_access");

        let (count, action, target): (i64, String, Option<String>) = sqlx::query_as(
            "SELECT count(*)::bigint, max(action), max(target) FROM profile.access_audit \
             WHERE accessed_by = $1",
        )
        .bind(admin)
        .fetch_one(&pool)
        .await
        .expect("read audit row");
        assert_eq!(count, 1, "one audit row written");
        assert_eq!(action, "admin_list_guard_profiles");
        assert_eq!(target.as_deref(), Some("approved"));

        let _ = sqlx::query("DELETE FROM profile.access_audit WHERE accessed_by = $1")
            .bind(admin)
            .execute(&pool)
            .await;
    }

    /// Real-Postgres integration test: upsert → get → approve, end-to-end. Proves the
    /// schema-qualified enum read/write round-trips and the approval transition writes.
    /// No-op unless `DATABASE_URL` is set, so `cargo test` stays hermetic. Run against a
    /// migrated DB:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-profile -- upsert_get_approve_roundtrip --nocapture
    #[tokio::test]
    async fn upsert_get_approve_roundtrip() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let user_id = Uuid::new_v4();

        // 1) upsert (create) — defaults to pending, stores the full account number.
        let req = UpsertGuardProfileRequest {
            full_name: Some("Somchai Jaidee".to_string()),
            gender: Some("male".to_string()),
            date_of_birth: NaiveDate::from_ymd_opt(1990, 1, 2),
            years_of_experience: Some(5),
            previous_workplace: Some("ACME Security".to_string()),
            bank_name: Some("SCB".to_string()),
            account_number: Some("1234567890".to_string()),
            account_name: Some("Somchai".to_string()),
            ..Default::default()
        };
        let created = upsert_guard_profile(&pool, user_id, &req)
            .await
            .expect("upsert create");
        assert_eq!(created.approval_status, ApprovalStatus::Pending);
        assert_eq!(created.account_number.as_deref(), Some("1234567890")); // repo never masks

        // 1a) pending_roles_for_user surfaces the submitted-but-unapproved guard role (feeds
        //     identity's /auth/me `pending_roles` → the mobile mode-picker's "pending" card).
        assert_eq!(
            pending_roles_for_user(&pool, user_id).await.unwrap(),
            vec!["guard".to_string()],
            "a pending guard profile → pending_roles = [guard]"
        );

        // 2) get — round-trips the row.
        let fetched = get_guard_profile(&pool, user_id)
            .await
            .expect("get")
            .expect("exists");
        assert_eq!(fetched.years_of_experience, Some(5));
        assert_eq!(fetched.approval_status, ApprovalStatus::Pending);

        // 3) approve — legal transition writes; the status moves to approved.
        let approved = set_approval_status(&pool, user_id, ApprovalStatus::Approved, "guard")
            .await
            .expect("approve");
        assert_eq!(approved.approval_status, ApprovalStatus::Approved);

        // 3b) …and once approved it is no longer pending (the mode-picker flips pending → enrolled).
        assert!(
            pending_roles_for_user(&pool, user_id)
                .await
                .unwrap()
                .is_empty(),
            "an approved guard is no longer in pending_roles"
        );

        // 3a) ATOMIC: a `user.approved` outbox row was written in the SAME tx as the flip,
        //     carrying this user_id — the only coupling to identity (no cross-schema write).
        let (evt_count,): (i64,) = sqlx::query_as(
            "SELECT count(*)::bigint FROM profile.outbox \
             WHERE topic = $1 AND payload->'payload'->>'user_id' = $2",
        )
        .bind(topics::USER_APPROVED)
        .bind(user_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count outbox");
        assert_eq!(
            evt_count, 1,
            "approve emits exactly one user.approved outbox row"
        );

        // 3b) a guard re-upserting their own profile must NOT reset the admin's decision
        //     (the ON CONFLICT clause deliberately omits approval_status).
        let re_upserted = upsert_guard_profile(&pool, user_id, &req)
            .await
            .expect("re-upsert after approve");
        assert_eq!(
            re_upserted.approval_status,
            ApprovalStatus::Approved,
            "re-upsert must preserve the admin approval decision"
        );

        // 4) re-reject after approve is illegal (terminal) → Conflict, status unchanged.
        let err = set_approval_status(&pool, user_id, ApprovalStatus::Rejected, "guard")
            .await
            .expect_err("approved is terminal");
        assert!(matches!(err, AppError::Conflict(_)), "got {err:?}");

        // 5) list with the approved filter includes our row — and the ADMIN queue row carries the
        //    signup time (the reviewer's "how long has this person been waiting?"), which the
        //    owner-facing shape does not.
        let listed = list_guard_profiles(&pool, Some(ApprovalStatus::Approved))
            .await
            .expect("list");
        let row = listed
            .iter()
            .find(|p| p.profile.user_id == user_id)
            .expect("approved guard is listed");
        assert!(
            row.created_at <= Utc::now(),
            "the admin queue row carries a real signup timestamp"
        );

        // 6) the internal catalog returns the approved guard (with experience + name for the
        //    customer's selection card) — and the projection carries no bank fields (it's
        //    `InternalGuardRow`, type-enforced; `avatar_key` is presigned by the handler, never
        //    re-sent raw). No avatar was set here, so `avatar_key` is None.
        let catalog = list_approved_guards(&pool, 100).await.expect("catalog");
        let row = catalog
            .iter()
            .find(|g| g.user_id == user_id)
            .expect("approved guard appears in the internal catalog");
        assert_eq!(row.years_of_experience, Some(5));
        assert_eq!(row.full_name.as_deref(), Some("Somchai Jaidee"));
        assert_eq!(row.avatar_key, None, "no avatar set → key is null");

        // cleanup
        let _ = sqlx::query("DELETE FROM profile.guard_profiles WHERE user_id = $1")
            .bind(user_id)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM profile.outbox WHERE payload->'payload'->>'user_id' = $1")
            .bind(user_id.to_string())
            .execute(&pool)
            .await;
    }

    /// A pending (un-approved) guard never appears in the internal discovery catalog.
    /// DATABASE_URL-gated.
    #[tokio::test]
    async fn internal_catalog_excludes_unapproved() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let user_id = Uuid::new_v4();
        let req = UpsertGuardProfileRequest {
            years_of_experience: Some(2),
            ..Default::default()
        };
        // Created → defaults to pending (never approved).
        upsert_guard_profile(&pool, user_id, &req)
            .await
            .expect("upsert pending");

        let catalog = list_approved_guards(&pool, 200).await.expect("catalog");
        assert!(
            !catalog.iter().any(|g| g.user_id == user_id),
            "a pending guard must NOT surface in the internal discovery catalog"
        );

        let _ = sqlx::query("DELETE FROM profile.guard_profiles WHERE user_id = $1")
            .bind(user_id)
            .execute(&pool)
            .await;
    }

    /// Customers are now ADMIN-approved (NOT auto-approved): the FIRST profile insert emits NO
    /// `user.approved` outbox row (the inverse of the old auto-approve behavior) and the new row
    /// starts `pending`; a re-upsert (self-edit) likewise emits nothing AND must not flip the
    /// approval decision. Only an admin's `set_customer_approval` unblocks login. DATABASE_URL-gated.
    #[tokio::test]
    async fn customer_first_insert_does_not_emit_user_approved() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let user_id = Uuid::new_v4();
        let outbox_count = |pool: PgPool, user_id: Uuid| async move {
            let (n,): (i64,) = sqlx::query_as(
                "SELECT count(*)::bigint FROM profile.outbox \
                 WHERE topic = $1 AND payload->'payload'->>'user_id' = $2",
            )
            .bind(topics::USER_APPROVED)
            .bind(user_id.to_string())
            .fetch_one(&pool)
            .await
            .expect("count outbox");
            n
        };
        let approval_status = |pool: PgPool, user_id: Uuid| async move {
            let (s,): (String,) = sqlx::query_as(
                "SELECT approval_status::text FROM profile.customer_profiles WHERE user_id = $1",
            )
            .bind(user_id)
            .fetch_one(&pool)
            .await
            .expect("read approval_status");
            s
        };

        // 1) FIRST insert → NO user.approved row, and the row starts pending (admin must approve).
        let req = UpsertCustomerProfileRequest {
            full_name: Some("สมหญิง ใจดี".to_string()),
            address: Some("กรุงเทพฯ".to_string()),
            ..Default::default()
        };
        upsert_customer_profile(&pool, user_id, &req)
            .await
            .expect("first upsert");
        assert_eq!(
            outbox_count(pool.clone(), user_id).await,
            0,
            "first customer-profile insert must NOT auto-approve (no user.approved)"
        );
        assert_eq!(
            approval_status(pool.clone(), user_id).await,
            "pending",
            "a new customer starts pending (admin-approval gate)"
        );

        // 2) Re-upsert (self-edit) → still no event; the edit applies; approval_status untouched.
        let edited = UpsertCustomerProfileRequest {
            full_name: Some("สมหญิง ใจดีมาก".to_string()),
            address: None,
            ..Default::default()
        };
        let profile = upsert_customer_profile(&pool, user_id, &edited)
            .await
            .expect("re-upsert");
        assert_eq!(profile.full_name.as_deref(), Some("สมหญิง ใจดีมาก"));
        assert_eq!(
            outbox_count(pool.clone(), user_id).await,
            0,
            "a re-upsert must NOT emit user.approved"
        );
        assert_eq!(
            approval_status(pool.clone(), user_id).await,
            "pending",
            "a self-edit must NOT change the approval decision"
        );

        let _ = sqlx::query("DELETE FROM profile.outbox WHERE payload->'payload'->>'user_id' = $1")
            .bind(user_id.to_string())
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM profile.customer_profiles WHERE user_id = $1")
            .bind(user_id)
            .execute(&pool)
            .await;
    }

    /// Admin customer approval, end-to-end: a pending customer is approved → `approval_status`
    /// moves to approved AND exactly one `user.approved` outbox row is written in the SAME tx
    /// (role=customer), the login UNBLOCKER identity consumes. Re-rejecting an approved customer
    /// is illegal (terminal) → Conflict, status unchanged. Mirrors the guard
    /// `upsert_get_approve_roundtrip`. DATABASE_URL-gated.
    #[tokio::test]
    async fn customer_admin_approve_emits_user_approved_once() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let user_id = Uuid::new_v4();

        // 1) Create (pending) — no event yet.
        let req = UpsertCustomerProfileRequest {
            full_name: Some("สมชาย มั่นคง".to_string()),
            ..Default::default()
        };
        upsert_customer_profile(&pool, user_id, &req)
            .await
            .expect("create pending customer");

        // 2) Admin approves → status approved, exactly one user.approved row (role=customer).
        let approved = set_customer_approval(&pool, user_id, ApprovalStatus::Approved, "customer")
            .await
            .expect("approve customer");
        assert_eq!(approved.user_id, user_id);

        let (evt_count,): (i64,) = sqlx::query_as(
            "SELECT count(*)::bigint FROM profile.outbox \
             WHERE topic = $1 AND payload->'payload'->>'user_id' = $2",
        )
        .bind(topics::USER_APPROVED)
        .bind(user_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count outbox");
        assert_eq!(
            evt_count, 1,
            "approve emits exactly one user.approved outbox row"
        );
        let (role,): (String,) = sqlx::query_as(
            "SELECT payload->'payload'->>'role' FROM profile.outbox \
             WHERE topic = $1 AND payload->'payload'->>'user_id' = $2",
        )
        .bind(topics::USER_APPROVED)
        .bind(user_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("read role");
        assert_eq!(role, "customer");

        // 2a) The status flip is visible to the admin list (now carries approval_status).
        let listed = list_customer_profiles(&pool, None).await.expect("list");
        let row = listed
            .iter()
            .find(|c| c.user_id == user_id)
            .expect("approved customer appears in the admin list");
        assert_eq!(row.approval_status, "approved");

        // 3) Re-reject after approve is illegal (terminal) → Conflict, no second event.
        let err = set_customer_approval(&pool, user_id, ApprovalStatus::Rejected, "customer")
            .await
            .expect_err("approved is terminal");
        assert!(matches!(err, AppError::Conflict(_)), "got {err:?}");

        // cleanup
        let _ = sqlx::query("DELETE FROM profile.customer_profiles WHERE user_id = $1")
            .bind(user_id)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM profile.outbox WHERE payload->'payload'->>'user_id' = $1")
            .bind(user_id.to_string())
            .execute(&pool)
            .await;
    }

    /// The customer-facing public read returns ONLY approved guards: a pending guard is invisible
    /// (→ None → 404, no existence leak); once approved, the lean shape (name + experience) is
    /// returned. DATABASE_URL-gated.
    #[tokio::test]
    async fn public_profile_only_returns_approved_guards() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        // A PENDING guard is NOT publicly readable.
        let pending = Uuid::new_v4();
        upsert_guard_profile(
            &pool,
            pending,
            &UpsertGuardProfileRequest {
                full_name: Some("Pending Pat".to_string()),
                years_of_experience: Some(2),
                ..Default::default()
            },
        )
        .await
        .expect("upsert pending");
        assert!(
            get_public_guard_profile(&pool, pending)
                .await
                .expect("get")
                .is_none(),
            "an un-approved guard must not be publicly readable"
        );

        // Once APPROVED, the lean public shape (name + experience only) is returned.
        let approved = Uuid::new_v4();
        upsert_guard_profile(
            &pool,
            approved,
            &UpsertGuardProfileRequest {
                full_name: Some("ณัฐพล วงศ์ดี".to_string()),
                years_of_experience: Some(7),
                account_number: Some("1234567890".to_string()),
                ..Default::default()
            },
        )
        .await
        .expect("upsert approved");
        set_approval_status(&pool, approved, ApprovalStatus::Approved, "guard")
            .await
            .expect("approve");

        let got = get_public_guard_profile(&pool, approved)
            .await
            .expect("get")
            .expect("approved guard is publicly visible");
        assert_eq!(got.user_id, approved);
        assert_eq!(got.full_name.as_deref(), Some("ณัฐพล วงศ์ดี"));
        assert_eq!(got.years_of_experience, Some(7));
        // (No bank/PII fields exist on PublicGuardProfile — least-privilege is type-enforced.)

        for id in [pending, approved] {
            let _ = sqlx::query("DELETE FROM profile.guard_profiles WHERE user_id = $1")
                .bind(id)
                .execute(&pool)
                .await;
        }
        let _ = sqlx::query("DELETE FROM profile.outbox WHERE payload->'payload'->>'user_id' = $1")
            .bind(approved.to_string())
            .execute(&pool)
            .await;
    }

    /// The IDOR read-model is idempotent + LAST-WRITER-WINS by `occurred_at`: a redelivered OLDER
    /// accept must never reactivate a finished booking (the `> updated_at` guard). This is the
    /// security-critical correctness property for at-least-once JetStream delivery. DATABASE_URL-gated.
    #[tokio::test]
    async fn assignment_read_model_is_lww_idempotent() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let booking = Uuid::new_v4();
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let t1 = DateTime::parse_from_rfc3339("2026-06-05T10:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let t2 = DateTime::parse_from_rfc3339("2026-06-05T12:00:00Z")
            .unwrap()
            .with_timezone(&Utc);

        // accept @ t1 → active link.
        upsert_assignment(&pool, booking, Some(customer), Some(guard), true, t1)
            .await
            .expect("project accept");
        assert!(
            has_active_booking(&pool, customer, guard)
                .await
                .expect("authz"),
            "accept activates the (customer, guard) link"
        );

        // completed @ t2 (later; ids omitted) → inactive. COALESCE keeps the known ids.
        upsert_assignment(&pool, booking, None, None, false, t2)
            .await
            .expect("project completion");
        assert!(
            !has_active_booking(&pool, customer, guard)
                .await
                .expect("authz"),
            "completion deactivates the link"
        );

        // REPLAY the older accept @ t1 → the LWW guard must NOT reactivate the finished booking.
        upsert_assignment(&pool, booking, Some(customer), Some(guard), true, t1)
            .await
            .expect("replay older accept");
        assert!(
            !has_active_booking(&pool, customer, guard)
                .await
                .expect("authz"),
            "a redelivered OLDER accept must NOT reactivate a finished booking (LWW by occurred_at)"
        );

        let _ = sqlx::query("DELETE FROM profile.guard_assignments WHERE booking_id = $1")
            .bind(booking)
            .execute(&pool)
            .await;
    }

    /// Document-key write/read round-trip: `update_document_key` writes ONE `*_key` column,
    /// `get_document_key` reads it back; an un-set column reads None; a missing profile → 404.
    /// DATABASE_URL-gated.
    #[tokio::test]
    async fn document_key_write_read_roundtrip() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        // Missing profile → 404.
        let missing = Uuid::new_v4();
        let err = update_document_key(&pool, missing, "id_card_key", "profile/x/documents/a.jpg")
            .await
            .expect_err("no profile row");
        assert!(matches!(err, AppError::NotFound(_)), "got {err:?}");

        // Seed a guard profile, then write + read its id_card key.
        let user_id = Uuid::new_v4();
        upsert_guard_profile(
            &pool,
            user_id,
            &UpsertGuardProfileRequest {
                years_of_experience: Some(1),
                ..Default::default()
            },
        )
        .await
        .expect("seed profile");

        // Un-set column reads None.
        assert_eq!(
            get_document_key(&pool, user_id, "id_card_key")
                .await
                .expect("get"),
            None,
        );

        let key = format!("profile/{user_id}/documents/abc.jpg");
        update_document_key(&pool, user_id, "id_card_key", &key)
            .await
            .expect("write id_card_key");
        assert_eq!(
            get_document_key(&pool, user_id, "id_card_key")
                .await
                .expect("get"),
            Some(key),
        );
        // A different column remains independently NULL (no clobber).
        assert_eq!(
            get_document_key(&pool, user_id, "security_license_key")
                .await
                .expect("get"),
            None,
        );

        let _ = sqlx::query("DELETE FROM profile.guard_profiles WHERE user_id = $1")
            .bind(user_id)
            .execute(&pool)
            .await;
    }

    /// An empty id set short-circuits BEFORE any query — so it's safe even with an unusable pool
    /// (the lazy pool to a closed port is never connected). Hermetic (no DATABASE_URL needed).
    #[tokio::test]
    async fn resolve_names_empty_ids_short_circuits() {
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let out = resolve_names(&pool, &[]).await.expect("empty resolve");
        assert!(out.is_empty(), "no ids → no rows, no query");
    }

    /// Real-Postgres roundtrip: seed one guard + one customer, resolve a batch that also contains
    /// an UNKNOWN id, and assert the derived role + name come back and the unknown id is OMITTED
    /// (null-safe). Proves the UNION-across-both-profile-tables query + role-derivation.
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-profile -- resolve_names_roundtrip --nocapture
    #[tokio::test]
    async fn resolve_names_roundtrip() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let guard_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let unknown_id = Uuid::new_v4();

        upsert_guard_profile(
            &pool,
            guard_id,
            &UpsertGuardProfileRequest {
                full_name: Some("Somchai Guard".to_string()),
                ..Default::default()
            },
        )
        .await
        .expect("seed guard");
        upsert_customer_profile(
            &pool,
            customer_id,
            &UpsertCustomerProfileRequest {
                full_name: Some("Malee Customer".to_string()),
                ..Default::default()
            },
        )
        .await
        .expect("seed customer");

        let rows = resolve_names(&pool, &[guard_id, customer_id, unknown_id])
            .await
            .expect("resolve");

        // The unknown id is omitted; exactly the two seeded ids come back.
        assert_eq!(rows.len(), 2, "unknown id is omitted (null-safe)");
        let g = rows
            .iter()
            .find(|r| r.user_id == guard_id)
            .expect("guard row");
        assert_eq!(g.role, "guard");
        assert_eq!(g.full_name.as_deref(), Some("Somchai Guard"));
        let c = rows
            .iter()
            .find(|r| r.user_id == customer_id)
            .expect("customer row");
        assert_eq!(c.role, "customer");
        assert_eq!(c.full_name.as_deref(), Some("Malee Customer"));

        let _ = sqlx::query("DELETE FROM profile.guard_profiles WHERE user_id = $1")
            .bind(guard_id)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM profile.customer_profiles WHERE user_id = $1")
            .bind(customer_id)
            .execute(&pool)
            .await;
    }
}
