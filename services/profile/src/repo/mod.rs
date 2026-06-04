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

use chrono::NaiveDate;
use sqlx::PgPool;
use uuid::Uuid;

use shared::error::AppError;
use shared::models::ApprovalStatus;

use crate::models::{
    CustomerProfileResponse, GuardProfileResponse, UpsertCustomerProfileRequest,
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

#[cfg(test)]
mod db_tests {
    use super::*;
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;

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

        // cleanup
        let _ = sqlx::query("DELETE FROM profile.guard_profiles WHERE user_id = $1")
            .bind(user_id)
            .execute(&pool)
            .await;
    }
}
