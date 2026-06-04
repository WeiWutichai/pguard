//! Repository layer — the ONLY place that touches the `otp` schema.
//!
//! Uses runtime `sqlx::query`/`query_as` (not the compile-time `query!` macro): the
//! scaffold has no DATABASE_URL / offline `.sqlx` cache at build time, and v1 used
//! runtime queries here too (CLAUDE.md: runtime sqlx for cross-crate/no-offline-cache).

use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use shared::error::AppError;

/// A row from `otp.otp_codes`, fetched atomically with the attempts increment.
#[derive(Debug, sqlx::FromRow)]
pub struct OtpRow {
    pub id: Uuid,
    pub code_hash: String,
    pub attempts: i32,
    #[allow(dead_code)]
    pub expires_at: DateTime<Utc>,
}

const PURPOSE_REGISTER: &str = "register";

/// Invalidate any previous unused OTP for this phone+purpose, then insert the new hashed
/// code — both in one transaction so a request can never leave two live codes.
#[tracing::instrument(skip(db, code_hash))]
pub async fn store_code(
    db: &PgPool,
    phone: &str,
    code_hash: &str,
    expires_at: DateTime<Utc>,
) -> Result<(), AppError> {
    let mut tx = db.begin().await?;

    sqlx::query(
        "UPDATE otp.otp_codes SET is_used = true \
         WHERE phone = $1 AND purpose = $2 AND is_used = false",
    )
    .bind(phone)
    .bind(PURPOSE_REGISTER)
    .execute(&mut *tx)
    .await?;

    sqlx::query(
        "INSERT INTO otp.otp_codes (phone, code_hash, purpose, expires_at) \
         VALUES ($1, $2, $3, $4)",
    )
    .bind(phone)
    .bind(code_hash)
    .bind(PURPOSE_REGISTER)
    .bind(expires_at)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(())
}

/// Atomically find the latest valid unused OTP for `phone`, increment its attempts, and
/// return it. The `FOR UPDATE` subquery serialises concurrent verify attempts so the
/// attempts counter can never be lost (security-reviewer §3: "Attempts counter atomic").
/// Returns `None` when there is no valid (unused, unexpired) code.
#[tracing::instrument(skip(db))]
pub async fn claim_for_verify(db: &PgPool, phone: &str) -> Result<Option<OtpRow>, AppError> {
    let row = sqlx::query_as::<_, OtpRow>(
        r#"
        UPDATE otp.otp_codes
        SET attempts = attempts + 1
        WHERE id = (
            SELECT id FROM otp.otp_codes
            WHERE phone = $1 AND purpose = $2 AND is_used = false AND expires_at > now()
            ORDER BY created_at DESC
            LIMIT 1
            FOR UPDATE
        )
        RETURNING id, code_hash, attempts, expires_at
        "#,
    )
    .bind(phone)
    .bind(PURPOSE_REGISTER)
    .fetch_optional(db)
    .await?;
    Ok(row)
}

/// Mark a specific OTP row as used (after success, or after exceeding max attempts).
#[tracing::instrument(skip(db))]
pub async fn mark_used(db: &PgPool, id: Uuid) -> Result<(), AppError> {
    sqlx::query("UPDATE otp.otp_codes SET is_used = true WHERE id = $1")
        .bind(id)
        .execute(db)
        .await?;
    Ok(())
}

#[cfg(test)]
mod db_tests {
    use super::*;
    use crate::domain::sha256_hex;
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;

    /// Real-Postgres integration test: proves the store → atomic claim → mark-used
    /// lifecycle (runtime sqlx + `FOR UPDATE` attempts increment + single-live-code
    /// invariant). No-op unless `DATABASE_URL` is set, so `cargo test` stays hermetic.
    /// Run against a migrated DB:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-otp -- otp_lifecycle_against_real_db --nocapture
    #[tokio::test]
    async fn otp_lifecycle_against_real_db() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        // Unique phone per run so parallel/repeat runs don't collide.
        let phone = format!("099{:07}", rand_suffix());
        let code = "424242";
        let hash = sha256_hex(code);
        let expires = Utc::now() + chrono::TimeDelta::minutes(5);

        store_code(&pool, &phone, &hash, expires)
            .await
            .expect("store #1");

        // Store again: the previous unused code must be invalidated (single live code).
        let hash2 = sha256_hex("131313");
        store_code(&pool, &phone, &hash2, expires)
            .await
            .expect("store #2");

        let (live,): (i64,) = sqlx::query_as(
            "SELECT count(*) FROM otp.otp_codes WHERE phone = $1 AND is_used = false",
        )
        .bind(&phone)
        .fetch_one(&pool)
        .await
        .expect("count live");
        assert_eq!(live, 1, "exactly one live code after re-store");

        // Claim increments attempts atomically.
        let r1 = claim_for_verify(&pool, &phone)
            .await
            .expect("claim #1")
            .expect("a live code exists");
        assert_eq!(r1.attempts, 1, "first claim sets attempts=1");
        assert_eq!(r1.code_hash, hash2, "latest code is returned");

        let r2 = claim_for_verify(&pool, &phone)
            .await
            .expect("claim #2")
            .expect("still live");
        assert_eq!(r2.attempts, 2, "second claim increments");

        // Mark used → no more live codes to claim.
        mark_used(&pool, r2.id).await.expect("mark used");
        assert!(
            claim_for_verify(&pool, &phone)
                .await
                .expect("claim #3")
                .is_none(),
            "no live code after mark_used"
        );

        // Dev-DB hygiene.
        let _ = sqlx::query("DELETE FROM otp.otp_codes WHERE phone = $1")
            .bind(&phone)
            .execute(&pool)
            .await;
    }

    fn rand_suffix() -> u32 {
        use rand::Rng;
        rand::thread_rng().gen_range(0..10_000_000)
    }
}
