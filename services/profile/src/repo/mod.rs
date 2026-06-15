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
    AccessAuditRow, CustomerProfileAdminResponse, CustomerProfileResponse, GuardProfileResponse,
    InternalGuard, UpsertCustomerProfileRequest, UpsertGuardProfileRequest,
};

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
    gender: Option<String>,
    date_of_birth: Option<NaiveDate>,
    years_of_experience: Option<i32>,
    previous_workplace: Option<String>,
    bank_name: Option<String>,
    account_number: Option<String>,
    account_name: Option<String>,
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
            gender: self.gender,
            date_of_birth: self.date_of_birth,
            years_of_experience: self.years_of_experience,
            previous_workplace: self.previous_workplace,
            bank_name: self.bank_name,
            account_number: self.account_number,
            account_name: self.account_name,
            approval_status,
        })
    }
}

/// Columns selected for a guard profile (approval_status cast to text for decoding).
const GUARD_COLUMNS: &str = "user_id, gender, date_of_birth, years_of_experience, \
     previous_workplace, bank_name, account_number, account_name, approval_status::text";

type GuardTuple = (
    Uuid,
    Option<String>,
    Option<NaiveDate>,
    Option<i32>,
    Option<String>,
    Option<String>,
    Option<String>,
    Option<String>,
    String,
);

fn guard_row_from_tuple(t: GuardTuple) -> GuardRow {
    GuardRow {
        user_id: t.0,
        gender: t.1,
        date_of_birth: t.2,
        years_of_experience: t.3,
        previous_workplace: t.4,
        bank_name: t.5,
        account_number: t.6,
        account_name: t.7,
        approval_status: t.8,
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
            (user_id, gender, date_of_birth, years_of_experience, previous_workplace,
             bank_name, account_number, account_name)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (user_id) DO UPDATE SET
            gender              = EXCLUDED.gender,
            date_of_birth       = EXCLUDED.date_of_birth,
            years_of_experience = EXCLUDED.years_of_experience,
            previous_workplace  = EXCLUDED.previous_workplace,
            bank_name           = EXCLUDED.bank_name,
            account_number      = EXCLUDED.account_number,
            account_name        = EXCLUDED.account_name,
            updated_at          = now()
        RETURNING {GUARD_COLUMNS}
        "#
    );
    let row: GuardTuple = sqlx::query_as(&sql)
        .bind(user_id)
        .bind(&req.gender)
        .bind(req.date_of_birth)
        .bind(req.years_of_experience)
        .bind(&req.previous_workplace)
        .bind(&req.bank_name)
        .bind(&req.account_number)
        .bind(&req.account_name)
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
            gender              = $2,
            date_of_birth       = $3,
            years_of_experience = $4,
            previous_workplace  = $5,
            bank_name           = $6,
            account_number      = $7,
            account_name        = $8,
            updated_at          = now()
        WHERE user_id = $1
        RETURNING {GUARD_COLUMNS}
        "#
    );
    let row: Option<GuardTuple> = sqlx::query_as(&sql)
        .bind(user_id)
        .bind(&req.gender)
        .bind(req.date_of_birth)
        .bind(req.years_of_experience)
        .bind(&req.previous_workplace)
        .bind(&req.bank_name)
        .bind(&req.account_number)
        .bind(&req.account_name)
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

/// List guard profiles for the admin onboarding queue, newest first. An optional
/// `status` filters by approval_status (compared as text against the enum cast).
pub async fn list_guard_profiles(
    db: &PgPool,
    status: Option<ApprovalStatus>,
) -> Result<Vec<GuardProfileResponse>, AppError> {
    let mut sql = format!("SELECT {GUARD_COLUMNS} FROM profile.guard_profiles");
    if status.is_some() {
        sql.push_str(" WHERE approval_status = $1::profile.approval_status");
    }
    sql.push_str(" ORDER BY created_at DESC LIMIT 200");

    let mut query = sqlx::query_as::<_, GuardTuple>(&sql);
    if let Some(s) = &status {
        query = query.bind(s.to_string());
    }
    let rows = query.fetch_all(db).await?;
    rows.into_iter()
        .map(guard_row_from_tuple)
        .map(GuardRow::into_response)
        .collect()
}

/// List APPROVED guards for the internal discovery catalog (booking's `/available-guards`).
/// Narrow projection (user_id + experience) — NEVER the bank/PII columns; least-privilege
/// over the service-to-service wire. Bounded (`LIMIT`), newest first; NOT paginated yet, so a
/// roster beyond the cap is truncated (the handler logs it). The `user_id` tiebreaker makes
/// the order deterministic when `created_at` ties (stable across calls).
pub async fn list_approved_guards(db: &PgPool, limit: i64) -> Result<Vec<InternalGuard>, AppError> {
    let rows = sqlx::query_as::<_, InternalGuard>(
        "SELECT user_id, years_of_experience FROM profile.guard_profiles \
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

    let sql = format!(
        r#"
        UPDATE profile.guard_profiles
        SET approval_status = $2::profile.approval_status, updated_at = now()
        WHERE user_id = $1
        RETURNING {GUARD_COLUMNS}
        "#
    );
    let row: GuardTuple = sqlx::query_as(&sql)
        .bind(user_id)
        .bind(target.to_string())
        .fetch_one(&mut *tx)
        .await?;

    // Atomic with the flip: enqueue the account event for identity to consume. Only an
    // APPROVAL needs an event — it's the login UNBLOCKER identity must react to. A rejection
    // needs none: login already blocks every non-`approved` account, so there is no consumer
    // (emitting a consumer-less `user.rejected` would just accrue orphan messages). The
    // `user.rejected` topic stays reserved in shared-events for a future audit/notify consumer.
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

/// The account-event topic to emit for an approval transition. Only `Approved` produces an
/// event (the login unblocker identity consumes); `Rejected`/`Pending` emit nothing (no
/// consumer — login already blocks them).
fn approval_event_topic(target: &ApprovalStatus) -> Option<&'static str> {
    match target {
        ApprovalStatus::Approved => Some(topics::USER_APPROVED),
        ApprovalStatus::Rejected | ApprovalStatus::Pending => None,
    }
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
/// The FIRST creation also enqueues `user.approved` (same tx, transactional outbox):
/// customers are **auto-approved on first profile submission**. Guards are vetted by an admin
/// (`set_approval_status`), but v2 has no admin customer-review surface at all — without
/// this event a registered customer stays `pending` in identity forever and can never log
/// in. identity's `user.approved` consumer is role-agnostic (flips by `user_id`), so the
/// existing approval→login loop closes unchanged. A re-upsert (self-edit) is detected via
/// `xmax = 0` and emits nothing — "approved" happens at most once per account here.
pub async fn upsert_customer_profile(
    db: &PgPool,
    user_id: Uuid,
    req: &UpsertCustomerProfileRequest,
) -> Result<CustomerProfileResponse, AppError> {
    let mut tx = db.begin().await?;
    let row: (Uuid, Option<String>, Option<String>, bool) = sqlx::query_as(
        r#"
        INSERT INTO profile.customer_profiles (user_id, full_name, address)
        VALUES ($1, $2, $3)
        ON CONFLICT (user_id) DO UPDATE SET
            full_name  = EXCLUDED.full_name,
            address    = EXCLUDED.address,
            updated_at = now()
        RETURNING user_id, full_name, address, (xmax = 0) AS inserted
        "#,
    )
    .bind(user_id)
    .bind(&req.full_name)
    .bind(&req.address)
    .fetch_one(&mut *tx)
    .await?;
    if row.3 {
        let envelope = EventEnvelope::new(
            topics::USER_APPROVED,
            Uuid::new_v4(),
            serde_json::json!({
                "user_id": user_id,
                "role": "customer",
                "approved_at": Utc::now(),
            }),
        );
        let payload = serde_json::to_value(&envelope)
            .map_err(|e| AppError::Internal(format!("serialize outbox envelope: {e}")))?;
        enqueue_outbox(&mut tx, topics::USER_APPROVED, &payload).await?;
    }
    tx.commit().await?;
    Ok(CustomerProfileResponse {
        user_id: row.0,
        full_name: row.1,
        address: row.2,
    })
}

/// Fetch the caller's customer profile.
pub async fn get_customer_profile(
    db: &PgPool,
    user_id: Uuid,
) -> Result<Option<CustomerProfileResponse>, AppError> {
    let row: Option<(Uuid, Option<String>, Option<String>)> = sqlx::query_as(
        "SELECT user_id, full_name, address FROM profile.customer_profiles WHERE user_id = $1",
    )
    .bind(user_id)
    .fetch_optional(db)
    .await?;
    Ok(
        row.map(|(user_id, full_name, address)| CustomerProfileResponse {
            user_id,
            full_name,
            address,
        }),
    )
}

/// List ALL customer profiles for the admin surface (`GET /admin/customer-profiles`).
/// Cross-user (no owner filter) — the admin-role gate is the API layer's job. Newest first,
/// capped at 200 (NOT paginated — same documented limitation as the guard admin list). No
/// `approval_status` filter: that column does not exist on `profile.customer_profiles`
/// (customer approval lives in identity), and profile must not read across the boundary.
pub async fn list_customer_profiles(
    db: &PgPool,
) -> Result<Vec<CustomerProfileAdminResponse>, AppError> {
    // Columns match `CustomerProfileAdminResponse` field-for-field → decode via `FromRow`
    // (no intermediate tuple). No transformation (unlike the guard list's mask step).
    let rows = sqlx::query_as::<_, CustomerProfileAdminResponse>(
        "SELECT user_id, full_name, address, created_at FROM profile.customer_profiles \
         ORDER BY created_at DESC LIMIT 200",
    )
    .fetch_all(db)
    .await?;
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

/// PDPA §19/§32 data export: the user's OWN profile rows (guard and/or customer). This is
/// the data subject reading their own data, so the FULL account number is returned;
/// documents are reported as presence flags (not raw S3 keys — signed-URL download is a
/// follow-up). Scoped strictly to `user_id`.
#[allow(clippy::type_complexity)]
pub async fn export_user_data(db: &PgPool, user_id: Uuid) -> Result<serde_json::Value, AppError> {
    let guard: Option<(
        Option<String>,
        Option<NaiveDate>,
        Option<i32>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        DateTime<Utc>,
        DateTime<Utc>,
    )> = sqlx::query_as(
        "SELECT gender, date_of_birth, years_of_experience, previous_workplace, \
                bank_name, account_number, account_name, \
                id_card_key, security_license_key, training_cert_key, criminal_check_key, \
                driver_license_key, passbook_photo_key, created_at, updated_at \
         FROM profile.guard_profiles WHERE user_id = $1",
    )
    .bind(user_id)
    .fetch_optional(db)
    .await?;

    let guard_json = guard.map(|g| {
        let (
            gender,
            dob,
            yoe,
            prev,
            bank_name,
            account_number,
            account_name,
            id_card,
            sec_lic,
            train,
            crim,
            driver,
            passbook,
            created_at,
            updated_at,
        ) = g;
        serde_json::json!({
            "gender": gender,
            "date_of_birth": dob,
            "years_of_experience": yoe,
            "previous_workplace": prev,
            "bank_name": bank_name,
            "account_number": account_number,
            "account_name": account_name,
            "documents": {
                "id_card": id_card.is_some(),
                "security_license": sec_lic.is_some(),
                "training_cert": train.is_some(),
                "criminal_check": crim.is_some(),
                "driver_license": driver.is_some(),
                "passbook_photo": passbook.is_some(),
            },
            "created_at": created_at,
            "updated_at": updated_at,
        })
    });

    let customer: Option<(Option<String>, Option<String>, DateTime<Utc>, DateTime<Utc>)> =
        sqlx::query_as(
            "SELECT full_name, address, created_at, updated_at \
             FROM profile.customer_profiles WHERE user_id = $1",
        )
        .bind(user_id)
        .fetch_optional(db)
        .await?;
    let customer_json = customer.map(|(full_name, address, created_at, updated_at)| {
        serde_json::json!({
            "full_name": full_name,
            "address": address,
            "created_at": created_at,
            "updated_at": updated_at,
        })
    });

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
            gender: Some("male".to_string()),
            date_of_birth: NaiveDate::from_ymd_opt(1990, 1, 2),
            years_of_experience: Some(5),
            previous_workplace: Some("ACME Security".to_string()),
            bank_name: Some("SCB".to_string()),
            account_number: Some("1234567890".to_string()),
            account_name: Some("Somchai".to_string()),
        };
        let created = upsert_guard_profile(&pool, user_id, &req)
            .await
            .expect("upsert create");
        assert_eq!(created.approval_status, ApprovalStatus::Pending);
        assert_eq!(created.account_number.as_deref(), Some("1234567890")); // repo never masks

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

        // 5) list with the approved filter includes our row.
        let listed = list_guard_profiles(&pool, Some(ApprovalStatus::Approved))
            .await
            .expect("list");
        assert!(listed.iter().any(|p| p.user_id == user_id));

        // 6) the internal catalog returns the approved guard (with experience) — and the
        //    projection carries no bank fields (it's `InternalGuard`, type-enforced).
        let catalog = list_approved_guards(&pool, 100).await.expect("catalog");
        let row = catalog
            .iter()
            .find(|g| g.user_id == user_id)
            .expect("approved guard appears in the internal catalog");
        assert_eq!(row.years_of_experience, Some(5));

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
            gender: None,
            date_of_birth: None,
            years_of_experience: Some(2),
            previous_workplace: None,
            bank_name: None,
            account_number: None,
            account_name: None,
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

    /// Customer auto-approval: the FIRST profile insert enqueues exactly one `user.approved`
    /// outbox row (atomic with the insert); a re-upsert (self-edit) emits nothing. Without
    /// this event a customer account stays `pending` forever (v2 has no admin
    /// customer-approval surface) and could never log in. DATABASE_URL-gated.
    #[tokio::test]
    async fn customer_first_insert_emits_user_approved_once() {
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

        // 1) FIRST insert → exactly one user.approved row, carrying role=customer.
        let req = UpsertCustomerProfileRequest {
            full_name: Some("สมหญิง ใจดี".to_string()),
            address: Some("กรุงเทพฯ".to_string()),
        };
        upsert_customer_profile(&pool, user_id, &req)
            .await
            .expect("first upsert");
        assert_eq!(
            outbox_count(pool.clone(), user_id).await,
            1,
            "first customer-profile insert emits exactly one user.approved"
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

        // 2) Re-upsert (self-edit) → no second event; the edit itself still applies.
        let edited = UpsertCustomerProfileRequest {
            full_name: Some("สมหญิง ใจดีมาก".to_string()),
            address: None,
        };
        let profile = upsert_customer_profile(&pool, user_id, &edited)
            .await
            .expect("re-upsert");
        assert_eq!(profile.full_name.as_deref(), Some("สมหญิง ใจดีมาก"));
        assert_eq!(
            outbox_count(pool.clone(), user_id).await,
            1,
            "a re-upsert must NOT re-emit user.approved"
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
}
