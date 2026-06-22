//! Repository layer — the ONLY place that touches the `notification` schema.
//!
//! Uses runtime `sqlx::query`/`query_as` (not the compile-time `query!` macro): the
//! scaffold has no DATABASE_URL / offline `.sqlx` cache at build time, and v1 used
//! runtime queries here too.

use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use shared::error::AppError;

use crate::domain::NotificationPlan;
use crate::models::{
    AutomationRule, BroadcastResponse, ListNotificationsQuery, NotificationLogResponse,
};

const LOG_COLUMNS: &str = "id, user_id, title, body, notification_type::text AS notification_type, payload, is_read, sent_at, read_at";

// ----- FCM tokens -----

pub async fn register_token(
    db: &PgPool,
    user_id: Uuid,
    token: &str,
    device_type: &str,
) -> Result<(), AppError> {
    // A device token belongs to AT MOST one user (UNIQUE(token), migration 0005): re-registering
    // a token that FCM rotated onto a new login RE-POINTS it to the current user instead of
    // leaving a duplicate row that would deliver the previous user's pushes to this device.
    sqlx::query(
        r#"
        INSERT INTO notification.fcm_tokens (user_id, token, device_type)
        VALUES ($1, $2, $3)
        ON CONFLICT (token)
        DO UPDATE SET user_id = EXCLUDED.user_id,
                      device_type = EXCLUDED.device_type,
                      updated_at = now()
        "#,
    )
    .bind(user_id)
    .bind(token)
    .bind(device_type)
    .execute(db)
    .await?;
    Ok(())
}

/// Delete a device token across ALL users. Called when FCM reports it UNREGISTERED /
/// NOT_FOUND / INVALID_ARGUMENT on send: the token is dead/rotated, so leaving the row would
/// keep mis-delivering (a reassigned token would push user A's notifications to user B's device).
pub async fn delete_token(db: &PgPool, token: &str) -> Result<(), AppError> {
    sqlx::query("DELETE FROM notification.fcm_tokens WHERE token = $1")
        .bind(token)
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

// ----- Broadcast campaigns (admin bulk-send) -----

const BROADCAST_COLUMNS: &str = "id, audience::text AS audience, title, body, \
    notification_type::text AS notification_type, status::text AS status, scheduled_at, \
    recipient_count, created_by, created_at, sent_at";

/// Insert a broadcast campaign row in the given lifecycle `status`. Enum columns are written
/// via explicit `::` casts (the values are a fixed in-code set, never raw user SQL).
#[allow(clippy::too_many_arguments)]
pub async fn create_broadcast(
    db: &PgPool,
    created_by: Uuid,
    audience: &str,
    title: &str,
    body: &str,
    notification_type: &str,
    status: &str,
    scheduled_at: Option<DateTime<Utc>>,
) -> Result<BroadcastResponse, AppError> {
    let sql = format!(
        r#"
        INSERT INTO notification.broadcasts
            (audience, title, body, notification_type, status, scheduled_at, created_by)
        VALUES ($1::notification.broadcast_audience, $2, $3,
                $4::notification.notification_type, $5::notification.broadcast_status, $6, $7)
        RETURNING {BROADCAST_COLUMNS}
        "#
    );
    sqlx::query_as::<_, BroadcastResponse>(&sql)
        .bind(audience)
        .bind(title)
        .bind(body)
        .bind(notification_type)
        .bind(status)
        .bind(scheduled_at)
        .bind(created_by)
        .fetch_one(db)
        .await
        .map_err(AppError::from)
}

/// List broadcast campaigns, newest first (history: drafts + scheduled + sent).
pub async fn list_broadcasts(
    db: &PgPool,
    limit: i64,
    offset: i64,
) -> Result<Vec<BroadcastResponse>, AppError> {
    let sql = format!(
        "SELECT {BROADCAST_COLUMNS} FROM notification.broadcasts \
         ORDER BY created_at DESC LIMIT $1 OFFSET $2"
    );
    let rows = sqlx::query_as::<_, BroadcastResponse>(&sql)
        .bind(limit)
        .bind(offset)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

/// Fetch one broadcast campaign.
pub async fn get_broadcast(db: &PgPool, id: Uuid) -> Result<Option<BroadcastResponse>, AppError> {
    let sql = format!("SELECT {BROADCAST_COLUMNS} FROM notification.broadcasts WHERE id = $1");
    let row = sqlx::query_as::<_, BroadcastResponse>(&sql)
        .bind(id)
        .fetch_optional(db)
        .await?;
    Ok(row)
}

/// Edit a DRAFT broadcast (COALESCE — only provided fields change). Returns the updated row,
/// or `None` if the id doesn't exist OR the broadcast is no longer a draft (the handler maps
/// that to a 409 — a sent/scheduled broadcast is immutable here).
pub async fn update_draft_broadcast(
    db: &PgPool,
    id: Uuid,
    audience: Option<&str>,
    title: Option<&str>,
    body: Option<&str>,
    notification_type: Option<&str>,
    scheduled_at: Option<DateTime<Utc>>,
) -> Result<Option<BroadcastResponse>, AppError> {
    let sql = format!(
        r#"
        UPDATE notification.broadcasts SET
            audience          = COALESCE($2::notification.broadcast_audience, audience),
            title             = COALESCE($3, title),
            body              = COALESCE($4, body),
            notification_type = COALESCE($5::notification.notification_type, notification_type),
            scheduled_at      = COALESCE($6, scheduled_at),
            updated_at        = now()
        WHERE id = $1 AND status = 'draft'::notification.broadcast_status
        RETURNING {BROADCAST_COLUMNS}
        "#
    );
    let row = sqlx::query_as::<_, BroadcastResponse>(&sql)
        .bind(id)
        .bind(audience)
        .bind(title)
        .bind(body)
        .bind(notification_type)
        .bind(scheduled_at)
        .fetch_optional(db)
        .await?;
    Ok(row)
}

/// ATOMIC CLAIM for a send. Flip a still-unsent broadcast (`draft`/`scheduled`) to `sent` in a
/// single UPDATE and return the row — but ONLY if THIS call won the transition. A second
/// concurrent `/send` (or the scheduler racing a manual send) sees `status = 'sent'` already and
/// the `WHERE` matches nothing, so it gets `None` and MUST NOT fan out. This is the guard against
/// double-fan-out: claim first, fan out only on `Some`, then `mark_broadcast_sent` records the
/// final recipient count. `recipient_count`/`sent_at` are stamped provisionally here.
pub async fn claim_broadcast_for_send(
    db: &PgPool,
    id: Uuid,
) -> Result<Option<BroadcastResponse>, AppError> {
    let sql = format!(
        r#"
        UPDATE notification.broadcasts
        SET status = 'sent'::notification.broadcast_status,
            sent_at = now(),
            updated_at = now()
        WHERE id = $1
          AND status IN ('draft'::notification.broadcast_status,
                         'scheduled'::notification.broadcast_status)
        RETURNING {BROADCAST_COLUMNS}
        "#
    );
    let row = sqlx::query_as::<_, BroadcastResponse>(&sql)
        .bind(id)
        .fetch_optional(db)
        .await?;
    Ok(row)
}

/// Release a claim taken by [`claim_broadcast_for_send`] when the fan-out failed BEFORE any
/// recipient was notified (the roster lookup errored — `fan_out` is per-recipient best-effort,
/// so an `Err` means zero pushes went out). Reverts `sent` → the prior lifecycle so the row can
/// be retried, restoring the scheduler's retry-ledger semantics without risking a double-send
/// (the claim still serialised the attempt). `scheduled_at IS NOT NULL` → it was a scheduled
/// broadcast; otherwise it was sent from a draft.
pub async fn release_broadcast_claim(db: &PgPool, id: Uuid) -> Result<(), AppError> {
    sqlx::query(
        r#"
        UPDATE notification.broadcasts
        SET status = CASE
                WHEN scheduled_at IS NOT NULL
                    THEN 'scheduled'::notification.broadcast_status
                ELSE 'draft'::notification.broadcast_status
            END,
            sent_at = NULL,
            updated_at = now()
        WHERE id = $1 AND status = 'sent'::notification.broadcast_status AND recipient_count = 0
        "#,
    )
    .bind(id)
    .execute(db)
    .await?;
    Ok(())
}

/// Mark a broadcast sent (status → sent, set `recipient_count` + `sent_at`). Used by the
/// immediate-send path AND the scheduler after a successful fan-out.
pub async fn mark_broadcast_sent(
    db: &PgPool,
    id: Uuid,
    recipient_count: i64,
) -> Result<Option<BroadcastResponse>, AppError> {
    let sql = format!(
        r#"
        UPDATE notification.broadcasts
        SET status = 'sent'::notification.broadcast_status,
            recipient_count = $2,
            sent_at = now(),
            updated_at = now()
        WHERE id = $1
        RETURNING {BROADCAST_COLUMNS}
        "#
    );
    let row = sqlx::query_as::<_, BroadcastResponse>(&sql)
        .bind(id)
        .bind(recipient_count as i32)
        .fetch_optional(db)
        .await?;
    Ok(row)
}

/// Claim due scheduled broadcasts (their `scheduled_at` has passed). A single notification
/// instance runs the scheduler, so a plain bounded SELECT is sufficient; a row stays
/// `scheduled` until a fan-out succeeds and flips it to `sent` (the retry ledger).
pub async fn due_broadcasts(db: &PgPool, limit: i64) -> Result<Vec<BroadcastResponse>, AppError> {
    let sql = format!(
        r#"
        SELECT {BROADCAST_COLUMNS} FROM notification.broadcasts
        WHERE status = 'scheduled'::notification.broadcast_status
          AND scheduled_at <= now()
        ORDER BY scheduled_at
        LIMIT $1
        "#
    );
    let rows = sqlx::query_as::<_, BroadcastResponse>(&sql)
        .bind(limit)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

// ----- Automation rules (admin authoring; live execution is a follow-up) -----

const RULE_COLUMNS: &str =
    "id, trigger_key, condition_text, action_key, is_enabled, created_by, created_at, updated_at";

/// List automation rules, newest first.
pub async fn list_rules(db: &PgPool) -> Result<Vec<AutomationRule>, AppError> {
    let sql = format!(
        "SELECT {RULE_COLUMNS} FROM notification.automation_rules ORDER BY created_at DESC"
    );
    let rows = sqlx::query_as::<_, AutomationRule>(&sql)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

/// Insert an automation rule.
pub async fn create_rule(
    db: &PgPool,
    created_by: Uuid,
    trigger_key: &str,
    condition_text: Option<&str>,
    action_key: &str,
    is_enabled: bool,
) -> Result<AutomationRule, AppError> {
    let sql = format!(
        r#"
        INSERT INTO notification.automation_rules
            (trigger_key, condition_text, action_key, is_enabled, created_by)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING {RULE_COLUMNS}
        "#
    );
    sqlx::query_as::<_, AutomationRule>(&sql)
        .bind(trigger_key)
        .bind(condition_text)
        .bind(action_key)
        .bind(is_enabled)
        .bind(created_by)
        .fetch_one(db)
        .await
        .map_err(AppError::from)
}

/// Update an automation rule (COALESCE — only provided fields change; the common edit is the
/// enable toggle). Returns `None` if the rule doesn't exist.
pub async fn update_rule(
    db: &PgPool,
    id: Uuid,
    trigger_key: Option<&str>,
    condition_text: Option<&str>,
    action_key: Option<&str>,
    is_enabled: Option<bool>,
) -> Result<Option<AutomationRule>, AppError> {
    let sql = format!(
        r#"
        UPDATE notification.automation_rules SET
            trigger_key    = COALESCE($2, trigger_key),
            condition_text = COALESCE($3, condition_text),
            action_key     = COALESCE($4, action_key),
            is_enabled     = COALESCE($5, is_enabled),
            updated_at     = now()
        WHERE id = $1
        RETURNING {RULE_COLUMNS}
        "#
    );
    let row = sqlx::query_as::<_, AutomationRule>(&sql)
        .bind(id)
        .bind(trigger_key)
        .bind(condition_text)
        .bind(action_key)
        .bind(is_enabled)
        .fetch_optional(db)
        .await?;
    Ok(row)
}

/// Delete an automation rule. Returns `true` if a row was removed.
pub async fn delete_rule(db: &PgPool, id: Uuid) -> Result<bool, AppError> {
    let result = sqlx::query("DELETE FROM notification.automation_rules WHERE id = $1")
        .bind(id)
        .execute(db)
        .await?;
    Ok(result.rows_affected() > 0)
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
#[tracing::instrument(skip(db, plan), fields(event_id = %event_id, event_type = %event_type))]
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

// ----- Dispatch fan-out (booking.requested → all online guards) -----

/// Atomically claim ONE (event_id, recipient) dispatch and, if newly claimed, insert the guard's
/// `notification_logs` row — both in one transaction. Returns `true` if THIS call won the claim
/// (caller should push the FCM dispatch alert), `false` if this guard was already notified for this
/// event (a JetStream redelivery, or a retry that already covered this guard) — so the fan-out is
/// IDEMPOTENT per-(booking, guard): no double-push, no double-log.
///
/// Distinct from [`process_event`] (which claims the event_id ALONE for single-recipient events):
/// one booking.requested fans out to MANY guards, so the dedupe granularity is per recipient here.
#[tracing::instrument(skip(db, plan), fields(event_id = %event_id, recipient = %recipient_id))]
pub async fn claim_dispatch_recipient(
    db: &PgPool,
    event_id: Uuid,
    booking_id: Uuid,
    recipient_id: Uuid,
    plan: &NotificationPlan,
) -> Result<bool, AppError> {
    let mut tx = db.begin().await?;

    let claim = sqlx::query(
        r#"
        INSERT INTO notification.dispatch_recipients (event_id, recipient_id, booking_id)
        VALUES ($1, $2, $3)
        ON CONFLICT (event_id, recipient_id) DO NOTHING
        "#,
    )
    .bind(event_id)
    .bind(recipient_id)
    .bind(booking_id)
    .execute(&mut *tx)
    .await?;

    if claim.rows_affected() == 0 {
        tx.rollback().await?;
        return Ok(false); // already notified this guard for this event → skip (idempotent)
    }

    sqlx::query(
        r#"
        INSERT INTO notification.notification_logs (user_id, title, body, notification_type, payload)
        VALUES ($1, $2, $3, $4::notification.notification_type, $5)
        "#,
    )
    .bind(plan.recipient_id)
    .bind(&plan.title)
    .bind(&plan.body)
    .bind(plan.notification_type.as_db_str())
    .bind(&plan.data)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(true)
}

#[cfg(test)]
mod db_tests {
    use super::*;
    use crate::domain;
    use serde_json::json;
    use shared_events::topics;
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;
    use uuid::Uuid;

    /// Real-Postgres integration test: proves the consumer's atomic dedupe end-to-end
    /// (runtime sqlx + `processed_events` PK + same-tx insert). No-op unless
    /// `DATABASE_URL` is set, so `cargo test` stays hermetic. Run against a migrated DB:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-notification --  process_event_is_idempotent_against_real_db --nocapture
    #[tokio::test]
    async fn process_event_is_idempotent_against_real_db() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let event_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let payload = json!({
            "customer_id": customer_id,
            "guard_id": Uuid::new_v4(),
            "booking_id": Uuid::new_v4(),
        });
        let plan = domain::plan_for_event(topics::BOOKING_JOB_ACCEPTED, &payload).expect("maps");

        // First delivery → Created.
        let first = process_event(&pool, event_id, topics::BOOKING_JOB_ACCEPTED, Some(&plan))
            .await
            .expect("process #1");
        assert_eq!(
            first,
            Processed::Created(customer_id),
            "first delivery creates"
        );

        // Redelivery (same event_id) → Duplicate, writes nothing.
        let second = process_event(&pool, event_id, topics::BOOKING_JOB_ACCEPTED, Some(&plan))
            .await
            .expect("process #2");
        assert_eq!(second, Processed::Duplicate, "redelivery deduped");

        // Exactly one log row + one ledger row despite two deliveries.
        let (logs,): (i64,) = sqlx::query_as(
            "SELECT count(*) FROM notification.notification_logs WHERE user_id = $1",
        )
        .bind(customer_id)
        .fetch_one(&pool)
        .await
        .expect("count logs");
        let (claims,): (i64,) = sqlx::query_as(
            "SELECT count(*) FROM notification.processed_events WHERE event_id = $1",
        )
        .bind(event_id)
        .fetch_one(&pool)
        .await
        .expect("count claims");
        assert_eq!(
            logs, 1,
            "exactly one notification logged for two deliveries"
        );
        assert_eq!(claims, 1, "event claimed exactly once");

        // Dev-DB hygiene: remove what this test inserted.
        let _ = sqlx::query("DELETE FROM notification.notification_logs WHERE user_id = $1")
            .bind(customer_id)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM notification.processed_events WHERE event_id = $1")
            .bind(event_id)
            .execute(&pool)
            .await;
    }

    /// Real-Postgres integration test for the fan-out dedupe: the SAME (event_id, guard) claim
    /// wins once and is a no-op on redelivery, and exactly one notification row is logged. No-op
    /// unless `DATABASE_URL` is set (hermetic default). Run against a migrated DB:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-notification -- claim_dispatch_recipient_is_idempotent_against_real_db --nocapture
    #[tokio::test]
    async fn claim_dispatch_recipient_is_idempotent_against_real_db() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let event_id = Uuid::new_v4();
        let booking_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let plan = domain::dispatch_plan_for_guard(guard_id, booking_id);

        // First delivery → won the claim.
        let first = claim_dispatch_recipient(&pool, event_id, booking_id, guard_id, &plan)
            .await
            .expect("claim #1");
        assert!(first, "first dispatch claims the guard");

        // Redelivery (same event_id + guard) → claim is a no-op (idempotent).
        let second = claim_dispatch_recipient(&pool, event_id, booking_id, guard_id, &plan)
            .await
            .expect("claim #2");
        assert!(!second, "redelivery does not re-claim the guard");

        // Exactly one log row + one claim row despite two deliveries.
        let (logs,): (i64,) = sqlx::query_as(
            "SELECT count(*) FROM notification.notification_logs WHERE user_id = $1",
        )
        .bind(guard_id)
        .fetch_one(&pool)
        .await
        .expect("count logs");
        let (claims,): (i64,) = sqlx::query_as(
            "SELECT count(*) FROM notification.dispatch_recipients WHERE event_id = $1 AND recipient_id = $2",
        )
        .bind(event_id)
        .bind(guard_id)
        .fetch_one(&pool)
        .await
        .expect("count claims");
        assert_eq!(logs, 1, "exactly one dispatch logged for two deliveries");
        assert_eq!(claims, 1, "guard claimed exactly once");

        // Dev-DB hygiene.
        let _ = sqlx::query("DELETE FROM notification.notification_logs WHERE user_id = $1")
            .bind(guard_id)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM notification.dispatch_recipients WHERE event_id = $1")
            .bind(event_id)
            .execute(&pool)
            .await;
    }
}
