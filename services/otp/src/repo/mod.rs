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
/// `purpose` is the FLOW the code was requested for ([`PURPOSE_REGISTER`] /
/// [`PURPOSE_PIN_RESET`]) — the verify step mints the token from THIS stored value,
/// never from what the verify request asks for (purpose is bound at request time).
#[derive(Debug, sqlx::FromRow)]
pub struct OtpRow {
    pub id: Uuid,
    pub code_hash: String,
    pub attempts: i32,
    pub purpose: String,
    #[allow(dead_code)]
    pub expires_at: DateTime<Utc>,
}

/// Row purpose for a REGISTRATION code (mints a `phone_verify` token). The legacy
/// spelling — every pre-split row holds this value, so it stays the stored form.
pub const PURPOSE_REGISTER: &str = "register";
/// Row purpose for a FORGOT-PIN RESET code (mints a `pin_reset` token).
pub const PURPOSE_PIN_RESET: &str = "pin_reset";
/// Row purpose for a CHANGE-LOGIN-PHONE code (mints a `phone_change` token). The verified phone
/// is the NEW number; identity's `PATCH /auth/phone` step-ups on the current PIN before writing.
pub const PURPOSE_PHONE_CHANGE: &str = "phone_change";

/// Invalidate any previous unused OTP for this phone (ANY purpose), then insert the new
/// hashed code — both in one transaction so a phone can never hold two live codes. The
/// any-purpose invalidation matters for the purpose binding: if a register code could
/// stay live next to a newer reset code, verify's latest-row claim would be ambiguous.
#[tracing::instrument(skip(db, code_hash, phone))]
pub async fn store_code(
    db: &PgPool,
    phone: &str,
    code_hash: &str,
    purpose: &str,
    expires_at: DateTime<Utc>,
) -> Result<(), AppError> {
    let mut tx = db.begin().await?;

    sqlx::query("UPDATE otp.otp_codes SET is_used = true WHERE phone = $1 AND is_used = false")
        .bind(phone)
        .execute(&mut *tx)
        .await?;

    sqlx::query(
        "INSERT INTO otp.otp_codes (phone, code_hash, purpose, expires_at) \
         VALUES ($1, $2, $3, $4)",
    )
    .bind(phone)
    .bind(code_hash)
    .bind(purpose)
    .bind(expires_at)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(())
}

/// Atomically find the latest valid unused OTP for `phone` (any purpose — a phone has at
/// most ONE live code, see [`store_code`]), increment its attempts, and return it. The
/// `FOR UPDATE` subquery serialises concurrent verify attempts so the attempts counter
/// can never be lost (security-reviewer §3: "Attempts counter atomic").
/// Returns `None` when there is no valid (unused, unexpired) code.
#[tracing::instrument(skip(db, phone))]
pub async fn claim_for_verify(db: &PgPool, phone: &str) -> Result<Option<OtpRow>, AppError> {
    let row = sqlx::query_as::<_, OtpRow>(
        r#"
        UPDATE otp.otp_codes
        SET attempts = attempts + 1
        WHERE id = (
            SELECT id FROM otp.otp_codes
            WHERE phone = $1 AND is_used = false AND expires_at > now()
            ORDER BY created_at DESC
            LIMIT 1
            FOR UPDATE
        )
        RETURNING id, code_hash, attempts, purpose, expires_at
        "#,
    )
    .bind(phone)
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

        store_code(&pool, &phone, &hash, PURPOSE_REGISTER, expires)
            .await
            .expect("store #1");

        // Store again with the OTHER purpose: the previous unused code must be invalidated
        // (single live code per phone across purposes — verify's latest-row claim relies on it).
        let hash2 = sha256_hex("131313");
        store_code(&pool, &phone, &hash2, PURPOSE_PIN_RESET, expires)
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
        assert_eq!(
            r1.purpose, PURPOSE_PIN_RESET,
            "the stored purpose rides back on the claim (token purpose binds to it)"
        );

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
