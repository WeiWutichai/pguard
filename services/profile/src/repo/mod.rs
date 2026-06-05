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
use sqlx::PgPool;
use uuid::Uuid;

use shared::error::AppError;
use shared::models::ApprovalStatus;

use crate::models::{
    CustomerProfileResponse, GuardProfileResponse, InternalGuard, UpsertCustomerProfileRequest,
    UpsertGuardProfileRequest,
};

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

/// Admin: set a guard profile's approval status (row-locked + transition-checked).
///
/// Reads the current status under `FOR UPDATE`, applies the pure
/// [`crate::domain::approval::can_transition`] gate, and writes only if legal — so two
/// concurrent admins cannot both finalize the same pending profile into conflicting
/// states. Returns the updated profile (FULL account number; admin endpoints don't mask).
#[tracing::instrument(skip(db), fields(user_id = %user_id, target = %target))]
pub async fn set_approval_status(
    db: &PgPool,
    user_id: Uuid,
    target: ApprovalStatus,
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

    tx.commit().await?;
    guard_row_from_tuple(row).into_response()
}

// ----- Customer profile -----

/// Upsert the caller's customer profile (minimal in this slice).
pub async fn upsert_customer_profile(
    db: &PgPool,
    user_id: Uuid,
    req: &UpsertCustomerProfileRequest,
) -> Result<CustomerProfileResponse, AppError> {
    let row: (Uuid, Option<String>, Option<String>) = sqlx::query_as(
        r#"
        INSERT INTO profile.customer_profiles (user_id, full_name, address)
        VALUES ($1, $2, $3)
        ON CONFLICT (user_id) DO UPDATE SET
            full_name  = EXCLUDED.full_name,
            address    = EXCLUDED.address,
            updated_at = now()
        RETURNING user_id, full_name, address
        "#,
    )
    .bind(user_id)
    .bind(&req.full_name)
    .bind(&req.address)
    .fetch_one(db)
    .await?;
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

/// Record an admin read of personal data (PDPA §30 — who accessed what). Runs on the same
/// pool as the read it accompanies, so it propagates errors rather than swallowing them: a
/// healthy read path is a healthy audit-write path, and an unrecorded access should fail
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
        let approved = set_approval_status(&pool, user_id, ApprovalStatus::Approved)
            .await
            .expect("approve");
        assert_eq!(approved.approval_status, ApprovalStatus::Approved);

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
        let err = set_approval_status(&pool, user_id, ApprovalStatus::Rejected)
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
}
