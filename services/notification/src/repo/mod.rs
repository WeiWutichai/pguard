//! Repository layer — the ONLY place that touches the `notification` schema.
//!
//! Uses runtime `sqlx::query`/`query_as` (not the compile-time `query!` macro): the
//! scaffold has no DATABASE_URL / offline `.sqlx` cache at build time, and v1 used
//! runtime queries here too.

use sqlx::PgPool;
use uuid::Uuid;

use shared::error::AppError;

use crate::domain::NotificationPlan;
use crate::models::{ListNotificationsQuery, NotificationLogResponse};

const LOG_COLUMNS: &str = "id, user_id, title, body, notification_type::text AS notification_type, payload, is_read, sent_at, read_at";

// ----- FCM tokens -----

pub async fn register_token(
    db: &PgPool,
    user_id: Uuid,
    token: &str,
    device_type: &str,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        INSERT INTO notification.fcm_tokens (user_id, token, device_type)
        VALUES ($1, $2, $3)
        ON CONFLICT (user_id, token)
        DO UPDATE SET device_type = $3, updated_at = now()
        "#,
    )
    .bind(user_id)
    .bind(token)
    .bind(device_type)
    .execute(db)
    .await?;
    Ok(())
}

pub async fn unregister_token(db: &PgPool, user_id: Uuid, token: &str) -> Result<(), AppError> {
    sqlx::query("DELETE FROM notification.fcm_tokens WHERE user_id = $1 AND token = $2")
        .bind(user_id)
        .bind(token)
        .execute(db)
        .await?;
    Ok(())
}

pub async fn user_tokens(db: &PgPool, user_id: Uuid) -> Result<Vec<String>, AppError> {
    let rows: Vec<(String,)> =
        sqlx::query_as("SELECT token FROM notification.fcm_tokens WHERE user_id = $1")
            .bind(user_id)
            .fetch_all(db)
            .await?;
    Ok(rows.into_iter().map(|r| r.0).collect())
}

// ----- Notification reads -----

pub async fn list_notifications(
    db: &PgPool,
    user_id: Uuid,
    query: &ListNotificationsQuery,
) -> Result<Vec<NotificationLogResponse>, AppError> {
    let limit = query.limit.unwrap_or(20).clamp(1, 100);
    let offset = query.offset.unwrap_or(0).max(0);
    let unread_only = query.unread_only.unwrap_or(false);

    let sql = format!(
        r#"
        SELECT {LOG_COLUMNS}
        FROM notification.notification_logs
        WHERE user_id = $1
          AND ($4::text IS NULL OR payload->>'target_role' = $4 OR payload->>'target_role' IS NULL)
          AND (NOT $5 OR is_read = false)
        ORDER BY sent_at DESC
        LIMIT $2 OFFSET $3
        "#
    );

    let rows = sqlx::query_as::<_, NotificationLogResponse>(&sql)
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .bind(query.role.as_deref())
        .bind(unread_only)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

pub async fn unread_count(db: &PgPool, user_id: Uuid, role: Option<&str>) -> Result<i64, AppError> {
    let row: (i64,) = sqlx::query_as(
        r#"
        SELECT COUNT(*) FROM notification.notification_logs
        WHERE user_id = $1 AND is_read = false
          AND ($2::text IS NULL OR payload->>'target_role' = $2 OR payload->>'target_role' IS NULL)
        "#,
    )
    .bind(user_id)
    .bind(role)
    .fetch_one(db)
    .await?;
    Ok(row.0)
}

// ----- Notification writes -----

pub async fn mark_as_read(
    db: &PgPool,
    notification_id: Uuid,
    user_id: Uuid,
) -> Result<NotificationLogResponse, AppError> {
    let sql = format!(
        r#"
        UPDATE notification.notification_logs
        SET is_read = true, read_at = now()
        WHERE id = $1 AND user_id = $2
        RETURNING {LOG_COLUMNS}
        "#
    );
    sqlx::query_as::<_, NotificationLogResponse>(&sql)
        .bind(notification_id)
        .bind(user_id)
        .fetch_optional(db)
        .await?
        .ok_or_else(|| AppError::NotFound("Notification not found".to_string()))
}

/// Mark all of a user's unread notifications (optionally role-filtered) as read.
/// Returns the number marked.
pub async fn mark_all_as_read(
    db: &PgPool,
    user_id: Uuid,
    role: Option<&str>,
) -> Result<i64, AppError> {
    let result = sqlx::query(
        r#"
        UPDATE notification.notification_logs
        SET is_read = true, read_at = now()
        WHERE user_id = $1 AND is_read = false
          AND ($2::text IS NULL OR payload->>'target_role' = $2 OR payload->>'target_role' IS NULL)
        "#,
    )
    .bind(user_id)
    .bind(role)
    .execute(db)
    .await?;
    Ok(result.rows_affected() as i64)
}

/// Insert a notification log row (used by the admin send + internal push paths).
pub async fn insert_log(
    db: &PgPool,
    user_id: Uuid,
    title: &str,
    body: &str,
    notification_type: &str,
    payload: &Option<serde_json::Value>,
) -> Result<NotificationLogResponse, AppError> {
    let sql = format!(
        r#"
        INSERT INTO notification.notification_logs (user_id, title, body, notification_type, payload)
        VALUES ($1, $2, $3, $4::notification.notification_type, $5)
        RETURNING {LOG_COLUMNS}
        "#
    );
    sqlx::query_as::<_, NotificationLogResponse>(&sql)
        .bind(user_id)
        .bind(title)
        .bind(body)
        .bind(notification_type)
        .bind(payload)
        .fetch_one(db)
        .await
        .map_err(AppError::from)
}

// ----- Event consumer (atomic claim + log) -----

/// Outcome of processing one inbound event.
#[derive(Debug, PartialEq, Eq)]
pub enum Processed {
    /// A new notification was created for this recipient (caller should push).
    Created(Uuid),
    /// Event recognised but produces no notification; still marked processed.
    Ignored,
    /// Event was already processed (at-least-once redelivery) — skipped.
    Duplicate,
}

/// Atomically claim `event_id` and, if newly claimed and `plan` is `Some`, insert the
/// notification log — both in one transaction. Idempotent: a redelivered `event_id`
/// returns [`Processed::Duplicate`] and writes nothing.
pub async fn process_event(
    db: &PgPool,
    event_id: Uuid,
    event_type: &str,
    plan: Option<&NotificationPlan>,
) -> Result<Processed, AppError> {
    let mut tx = db.begin().await?;

    let claim = sqlx::query(
        r#"
        INSERT INTO notification.processed_events (event_id, event_type)
        VALUES ($1, $2)
        ON CONFLICT (event_id) DO NOTHING
        "#,
    )
    .bind(event_id)
    .bind(event_type)
    .execute(&mut *tx)
    .await?;

    if claim.rows_affected() == 0 {
        tx.rollback().await?;
        return Ok(Processed::Duplicate);
    }

    let outcome = match plan {
        Some(p) => {
            sqlx::query(
                r#"
                INSERT INTO notification.notification_logs (user_id, title, body, notification_type, payload)
                VALUES ($1, $2, $3, $4::notification.notification_type, $5)
                "#,
            )
            .bind(p.recipient_id)
            .bind(&p.title)
            .bind(&p.body)
            .bind(p.notification_type.as_db_str())
            .bind(&p.data)
            .execute(&mut *tx)
            .await?;
            Processed::Created(p.recipient_id)
        }
        None => Processed::Ignored,
    };

    tx.commit().await?;
    Ok(outcome)
}
