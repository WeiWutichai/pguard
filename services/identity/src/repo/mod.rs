//! Repository layer — the ONLY place that touches the `identity` schema.
//!
//! Runtime `sqlx::query`/`query_as` (not the compile-time `query!` macro): the scaffold
//! has no DATABASE_URL / offline `.sqlx` cache at build time. Argon2 work (CPU-bound) is
//! offloaded to `spawn_blocking` here — the scheduling is an I/O concern, so it lives in
//! `repo`, while the pure hash/verify functions stay in `domain::password`.

use chrono::{DateTime, TimeDelta, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use shared::error::AppError;

use crate::domain::rotation::StoredRefresh;
use crate::domain::{password, revocation};
use crate::models::AuthUserRow;

/// Refresh-token lifetime (RFC 6749 §6 rotation; 7 days mirrors v1).
const REFRESH_TOKEN_DAYS: i64 = 7;

/// A pre-computed Argon2id hash of a throwaway value. Verified against on the no-such-
/// user path so login takes ~the same time whether or not the account exists
/// (anti-enumeration; ported from v1 auth `service.rs`).
const DUMMY_HASH: &str =
    "$argon2id$v=19$m=19456,t=2,p=1$dW5rbm93bg$aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

/// Row returned by the login lookup (password hash stays inside repo).
struct UserAuthRow {
    id: Uuid,
    role: String,
    password_hash: String,
    is_active: bool,
}

/// Look up a user by phone OR email. Returns `None` if absent (inactive users still
/// return so the caller can run the dummy-verify path uniformly).
async fn find_user_by_identifier(
    db: &PgPool,
    identifier: &str,
) -> Result<Option<UserAuthRow>, AppError> {
    let row: Option<(Uuid, String, String, bool)> = sqlx::query_as(
        r#"
        SELECT id, role::text AS role, password_hash, is_active
        FROM identity.users
        WHERE phone = $1 OR email = $1
        "#,
    )
    .bind(identifier)
    .fetch_optional(db)
    .await?;

    Ok(row.map(|(id, role, password_hash, is_active)| UserAuthRow {
        id,
        role,
        password_hash,
        is_active,
    }))
}

/// Verify credentials. Always returns a generic `Unauthorized` on any failure (no
/// user-enumeration); runs the Argon2 verify even when the user is missing so timing
/// does not leak existence. Returns the minimal user identity on success.
pub async fn verify_credentials(
    db: &PgPool,
    identifier: &str,
    password: &str,
) -> Result<AuthUserRow, AppError> {
    let user = find_user_by_identifier(db, identifier).await?;

    // Pick the hash to verify against: the real one, or a constant dummy. Either way we
    // spend the same Argon2 time.
    let (hash, active, identity) = match &user {
        Some(u) if u.is_active => (
            u.password_hash.clone(),
            true,
            Some(AuthUserRow {
                id: u.id,
                role: u.role.clone(),
            }),
        ),
        _ => (DUMMY_HASH.to_string(), false, None),
    };

    let password = password.to_string();
    let ok = tokio::task::spawn_blocking(move || password::verify_secret(&password, &hash))
        .await
        .map_err(|e| AppError::Internal(format!("verify task failed: {e}")))??;

    match (ok, active, identity) {
        (true, true, Some(id)) => Ok(id),
        _ => Err(AppError::Unauthorized("Invalid credentials".to_string())),
    }
}

/// Persist a freshly-issued refresh token (new family on login). Returns the opaque
/// token the client receives (`{rotation_id}.{secret}`).
pub async fn create_refresh_family(db: &PgPool, user_id: Uuid) -> Result<String, AppError> {
    let family_id = Uuid::new_v4();
    issue_refresh(db, user_id, family_id).await
}

/// Insert one refresh-token row in `family_id` and return its opaque token. Used for the
/// initial login token (rotation uses its own in-tx insert).
async fn issue_refresh(db: &PgPool, user_id: Uuid, family_id: Uuid) -> Result<String, AppError> {
    let rotation_id = Uuid::new_v4();
    let jti = Uuid::new_v4();
    let secret = Uuid::new_v4().to_string();
    let expires_at: DateTime<Utc> = Utc::now() + TimeDelta::days(REFRESH_TOKEN_DAYS);

    let secret_for_hash = secret.clone();
    let secret_hash = tokio::task::spawn_blocking(move || password::hash_secret(&secret_for_hash))
        .await
        .map_err(|e| AppError::Internal(format!("hash task failed: {e}")))??;

    sqlx::query(
        r#"
        INSERT INTO identity.refresh_tokens
            (user_id, family_id, rotation_id, jti, secret_hash, expires_at)
        VALUES ($1, $2, $3, $4, $5, $6)
        "#,
    )
    .bind(user_id)
    .bind(family_id)
    .bind(rotation_id)
    .bind(jti)
    .bind(&secret_hash)
    .bind(expires_at)
    .execute(db)
    .await?;

    Ok(crate::domain::token::assemble(rotation_id, &secret))
}

/// A refresh row located by its `rotation_id`, with everything the rotation decision +
/// secret check need.
pub struct LocatedRefresh {
    pub user_id: Uuid,
    pub family_id: Uuid,
    pub stored: StoredRefresh,
    secret_hash: String,
}

impl LocatedRefresh {
    /// Argon2-verify the presented secret against the stored hash (constant-time).
    pub async fn secret_matches(&self, secret: &str) -> Result<bool, AppError> {
        let secret = secret.to_string();
        let hash = self.secret_hash.clone();
        tokio::task::spawn_blocking(move || password::verify_secret(&secret, &hash))
            .await
            .map_err(|e| AppError::Internal(format!("verify task failed: {e}")))?
    }
}

/// Locate a refresh-token row by its public `rotation_id`.
pub async fn find_refresh_by_rotation(
    db: &PgPool,
    rotation_id: Uuid,
) -> Result<Option<LocatedRefresh>, AppError> {
    let row: Option<(Uuid, Uuid, bool, DateTime<Utc>, String)> = sqlx::query_as(
        r#"
        SELECT user_id, family_id, revoked, expires_at, secret_hash
        FROM identity.refresh_tokens
        WHERE rotation_id = $1
        "#,
    )
    .bind(rotation_id)
    .fetch_optional(db)
    .await?;

    Ok(row.map(
        |(user_id, family_id, revoked, expires_at, secret_hash)| LocatedRefresh {
            user_id,
            family_id,
            stored: StoredRefresh {
                revoked,
                expires_at,
            },
            secret_hash,
        },
    ))
}

/// Atomically revoke the presented rotation and mint its successor in the SAME family.
/// One transaction: prevents a window where the old token is dead but the new one is not
/// yet recorded (RFC 6749 §6 rotation).
pub async fn rotate(
    db: &PgPool,
    user_id: Uuid,
    family_id: Uuid,
    presented_rotation_id: Uuid,
) -> Result<String, AppError> {
    let mut tx = db.begin().await?;

    sqlx::query("UPDATE identity.refresh_tokens SET revoked = TRUE WHERE rotation_id = $1")
        .bind(presented_rotation_id)
        .execute(&mut *tx)
        .await?;

    // Re-issue inside the family. We hash + insert here rather than calling `issue_refresh`
    // so the whole rotate stays in one tx.
    let rotation_id = Uuid::new_v4();
    let jti = Uuid::new_v4();
    let secret = Uuid::new_v4().to_string();
    let expires_at: DateTime<Utc> = Utc::now() + TimeDelta::days(REFRESH_TOKEN_DAYS);
    let secret_for_hash = secret.clone();
    let secret_hash = tokio::task::spawn_blocking(move || password::hash_secret(&secret_for_hash))
        .await
        .map_err(|e| AppError::Internal(format!("hash task failed: {e}")))??;

    sqlx::query(
        r#"
        INSERT INTO identity.refresh_tokens
            (user_id, family_id, rotation_id, jti, secret_hash, expires_at)
        VALUES ($1, $2, $3, $4, $5, $6)
        "#,
    )
    .bind(user_id)
    .bind(family_id)
    .bind(rotation_id)
    .bind(jti)
    .bind(&secret_hash)
    .bind(expires_at)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    Ok(crate::domain::token::assemble(rotation_id, &secret))
}

/// Revoke every token in a family (logout, or reuse-detection kill-switch).
pub async fn revoke_family(db: &PgPool, family_id: Uuid) -> Result<u64, AppError> {
    let res = sqlx::query(
        "UPDATE identity.refresh_tokens SET revoked = TRUE WHERE family_id = $1 AND revoked = FALSE",
    )
    .bind(family_id)
    .execute(db)
    .await?;
    Ok(res.rows_affected())
}

/// The user's current role (re-read at rotation so a role change since login is honoured
/// in the freshly-issued access token). `None` if the user is gone or deactivated.
pub async fn user_auth_meta(db: &PgPool, user_id: Uuid) -> Result<Option<AuthUserRow>, AppError> {
    let row: Option<(String,)> = sqlx::query_as(
        r#"
        SELECT role::text AS role
        FROM identity.users
        WHERE id = $1 AND is_active = TRUE
        "#,
    )
    .bind(user_id)
    .fetch_optional(db)
    .await?;

    Ok(row.map(|(role,)| AuthUserRow { id: user_id, role }))
}

/// Force-revoke-all for a user: bump `token_revocation_version` AND revoke every
/// outstanding refresh family — in one transaction (CLAUDE.md "Token revocation").
/// Returns the new version. Idempotent enough for at-least-once event delivery.
#[tracing::instrument(skip(db), fields(user_id = %user_id))]
pub async fn revoke_all(db: &PgPool, user_id: Uuid) -> Result<i32, AppError> {
    let mut tx = db.begin().await?;

    // Read-modify-write under the tx (row locked) so the monotonic bump is computed by the
    // single domain helper rather than duplicated in SQL.
    let current: Option<(i32,)> = sqlx::query_as(
        "SELECT token_revocation_version FROM identity.users WHERE id = $1 FOR UPDATE",
    )
    .bind(user_id)
    .fetch_optional(&mut *tx)
    .await?;

    let current = match current {
        Some((v,)) => v,
        None => {
            tx.rollback().await?;
            return Err(AppError::NotFound("User not found".to_string()));
        }
    };
    let new_version = revocation::next_revocation_version(current);

    sqlx::query(
        r#"
        UPDATE identity.users
        SET token_revocation_version = $2, updated_at = now()
        WHERE id = $1
        "#,
    )
    .bind(user_id)
    .bind(new_version)
    .execute(&mut *tx)
    .await?;

    sqlx::query(
        "UPDATE identity.refresh_tokens SET revoked = TRUE WHERE user_id = $1 AND revoked = FALSE",
    )
    .bind(user_id)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    // Invariant: every access token stamped with the OLD version must now be rejected by a
    // version-checking validator. Cheap self-check on the security-critical path.
    debug_assert!(
        !revocation::token_version_is_current(current, new_version),
        "force-revoke-all must invalidate old-version tokens"
    );
    tracing::info!(new_version, "force-revoke-all applied");
    Ok(new_version)
}
