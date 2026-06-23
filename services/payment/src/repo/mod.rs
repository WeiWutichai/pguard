//! Repository layer — the ONLY place that touches the `payment` schema. THE MONEY PATH.
//!
//! Uses runtime `sqlx::query`/`query_as` (not the compile-time `query!` macro): the
//! scaffold has no DATABASE_URL / offline `.sqlx` cache at build time (mirrors booking).
//!
//! One atomic write anchors this slice (v2 is POST-PAY — charge on completion, no refund):
//!  - [`charge_idempotent`] — insert a completed payment AND its `payment.completed` outbox
//!    event in ONE transaction, idempotently (the UNIQUE partial index + ON CONFLICT means
//!    a retried/redelivered charge returns the existing row and emits nothing — no double-charge).
//!    Called by the `booking.completed` consumer with the post-pay bill (`domain::post_pay_charge`).

use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde_json::Value;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::topics;
use shared_events::EventEnvelope;

use crate::models::{CustomerSpend, PaymentResponse, RevenuePoint};

const PAYMENT_COLUMNS: &str = "id, booking_id, customer_id, guard_id, amount, expected_total, \
     payment_method, status::text AS status, final_amount, refund_amount, actual_hours, \
     refund_status, paid_at, created_at, updated_at";

// ----- Outbox row (for the relay) -----

/// One unpublished outbox row, as the relay reads it.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct OutboxRow {
    pub id: Uuid,
    pub topic: String,
    /// The serialized `EventEnvelope` (JSONB).
    pub payload: Value,
}

// ----- Reads -----

/// Fetch one payment by id.
pub async fn get_payment(db: &sqlx::PgPool, id: Uuid) -> Result<PaymentResponse, AppError> {
    let sql = format!("SELECT {PAYMENT_COLUMNS} FROM payment.payments WHERE id = $1");
    sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(id)
        .fetch_optional(db)
        .await?
        .ok_or_else(|| AppError::NotFound("Payment not found".to_string()))
}

/// List the caller's payments (as the paying customer), newest first.
pub async fn list_payments(
    db: &sqlx::PgPool,
    customer_id: Uuid,
) -> Result<Vec<PaymentResponse>, AppError> {
    let sql = format!(
        "SELECT {PAYMENT_COLUMNS} FROM payment.payments \
         WHERE customer_id = $1 ORDER BY created_at DESC LIMIT 100"
    );
    let rows = sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(customer_id)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

/// Admin cross-user payment ledger — every payment (NO owner filter; the admin-role gate is
/// the API layer's job), newest first, with optional `status` and `customer_id` (drill into one
/// customer's spend) filters + limit/offset. Diverges from [`list_payments`] by dropping the
/// implicit `WHERE customer_id = $1` scope — here `customer_id` is an explicit, optional filter
/// (index-backed by `idx_payments_customer (customer_id, created_at DESC)`). `$n` placeholders
/// are built from a controlled counter; every value is a BOUND param (`status` validated against
/// the enum in the handler) — no user input is interpolated. READ-ONLY: a manual refund-process
/// step is deliberately out of scope (v2 refunds are event-driven).
pub async fn admin_list_payments(
    db: &sqlx::PgPool,
    status: Option<&str>,
    customer_id: Option<Uuid>,
    limit: i64,
    offset: i64,
) -> Result<Vec<PaymentResponse>, AppError> {
    let mut sql = format!("SELECT {PAYMENT_COLUMNS} FROM payment.payments");
    let mut conds: Vec<String> = Vec::new();
    let mut idx = 1;
    if status.is_some() {
        conds.push(format!("status = ${idx}::payment.payment_status"));
        idx += 1;
    }
    if customer_id.is_some() {
        conds.push(format!("customer_id = ${idx}"));
        idx += 1;
    }
    if !conds.is_empty() {
        sql.push_str(" WHERE ");
        sql.push_str(&conds.join(" AND "));
    }
    sql.push_str(&format!(
        " ORDER BY created_at DESC LIMIT ${} OFFSET ${}",
        idx,
        idx + 1
    ));
    let mut query = sqlx::query_as::<_, PaymentResponse>(&sql);
    if let Some(s) = status {
        query = query.bind(s);
    }
    if let Some(c) = customer_id {
        query = query.bind(c);
    }
    let rows = query.bind(limit).bind(offset).fetch_all(db).await?;
    Ok(rows)
}

// ----- Revenue report (admin analytics) -----

/// Net revenue expression shared by the series + total queries: completed charges' effective
/// amount (prorated `final_amount` when set, else `amount`) minus any refunds. Kept as one
/// constant so the per-day series and the MoM total compute identically.
const NET_REVENUE_EXPR: &str =
    "COALESCE(SUM(CASE WHEN status = 'completed' THEN COALESCE(final_amount, amount) ELSE 0 END), 0) \
     - COALESCE(SUM(COALESCE(refund_amount, 0)), 0)";

/// Daily net revenue over `[from, to)`, grouped by the day the money landed
/// (`paid_at`, falling back to `created_at`). `payments` = completed charges that day. Newest
/// day last (ascending) so the chart plots left→right.
pub async fn revenue_series(
    db: &sqlx::PgPool,
    from: DateTime<Utc>,
    to: DateTime<Utc>,
) -> Result<Vec<RevenuePoint>, AppError> {
    let sql = format!(
        r#"
        SELECT date_trunc('day', COALESCE(paid_at, created_at))::date AS date,
               {NET_REVENUE_EXPR} AS revenue,
               COUNT(*) FILTER (WHERE status = 'completed') AS payments
        FROM payment.payments
        WHERE COALESCE(paid_at, created_at) >= $1 AND COALESCE(paid_at, created_at) < $2
        GROUP BY 1
        ORDER BY 1
        "#
    );
    let rows = sqlx::query_as::<_, RevenuePoint>(&sql)
        .bind(from)
        .bind(to)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

/// Net revenue total over `[from, to)` — the MoM comparison uses it on the prior window.
pub async fn revenue_total(
    db: &sqlx::PgPool,
    from: DateTime<Utc>,
    to: DateTime<Utc>,
) -> Result<Decimal, AppError> {
    let sql = format!(
        r#"
        SELECT {NET_REVENUE_EXPR} AS total
        FROM payment.payments
        WHERE COALESCE(paid_at, created_at) >= $1 AND COALESCE(paid_at, created_at) < $2
        "#
    );
    let row: (Decimal,) = sqlx::query_as(&sql)
        .bind(from)
        .bind(to)
        .fetch_one(db)
        .await?;
    Ok(row.0)
}

// ----- Customer-spend report (admin analytics) -----

/// Per-customer lifetime spend: the summed effective amount of each customer's actually-charged
/// (completed) payments (prorated `final_amount` when set, else `amount`). Powers the web-admin
/// customers page's spend column. Only `completed` rows count (pending/refunded excluded); the
/// status enum cast mirrors `admin_list_payments`' `::payment.payment_status`. No owner filter —
/// the admin-role gate is the API layer's job. Customers with no completed payment do not appear.
pub async fn customer_spend(db: &sqlx::PgPool) -> Result<Vec<CustomerSpend>, AppError> {
    let rows = sqlx::query_as::<_, CustomerSpend>(
        // Net of refunds, mirroring NET_REVENUE_EXPR: a PARTIAL refund stays `completed` with
        // refund_amount set, so subtract it; a FULL refund flips the row to `refunded` (excluded).
        "SELECT customer_id, \
                (COALESCE(SUM(COALESCE(final_amount, amount)), 0) \
                 - COALESCE(SUM(COALESCE(refund_amount, 0)), 0))::numeric AS total \
         FROM payment.payments \
         WHERE status = 'completed'::payment.payment_status \
         GROUP BY customer_id",
    )
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// PDPA §19/§32 data export: ALL of the user's OWN payments (as the paying customer), no
/// pagination limit. Reuses `PaymentResponse` so money serializes as exact-decimal strings
/// (CLAUDE.md money rule). Scoped strictly to `customer_id`.
pub async fn export_user_payments(db: &sqlx::PgPool, customer_id: Uuid) -> Result<Value, AppError> {
    let sql = format!(
        "SELECT {PAYMENT_COLUMNS} FROM payment.payments \
         WHERE customer_id = $1 ORDER BY created_at DESC"
    );
    let rows = sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(customer_id)
        .fetch_all(db)
        .await?;
    serde_json::to_value(rows)
        .map_err(|e| AppError::Internal(format!("serialize payments export: {e}")))
}

/// Read the existing completed payment for a booking (the idempotency target).
async fn completed_for_booking(
    db: &sqlx::PgPool,
    booking_id: Uuid,
) -> Result<Option<PaymentResponse>, AppError> {
    let sql = format!(
        "SELECT {PAYMENT_COLUMNS} FROM payment.payments \
         WHERE booking_id = $1 AND status = 'completed' LIMIT 1"
    );
    Ok(sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(booking_id)
        .fetch_optional(db)
        .await?)
}

// ----- Writes -----

/// Idempotently charge a booking: insert a `completed` payment AND its
/// `pguard.events.payment.completed` outbox event in ONE transaction. At most one completed
/// payment per booking — enforced by the UNIQUE partial index + `ON CONFLICT DO NOTHING`.
///
/// Called by the `booking.completed` consumer with the post-pay bill. A redelivered completion
/// event cannot double-charge: on conflict the INSERT returns no row, we roll the (empty) tx back,
/// and return the EXISTING completed payment (no second event emitted). `guard_id`/`customer_id`/
/// the pricing come from booking's server-owned columns carried on the signed event, never a client.
#[tracing::instrument(skip(db), fields(booking_id = %booking_id, customer_id = %customer_id))]
#[allow(clippy::too_many_arguments)]
pub async fn charge_idempotent(
    db: &sqlx::PgPool,
    booking_id: Uuid,
    customer_id: Uuid,
    guard_id: Option<Uuid>,
    amount: Decimal,
    expected_total: Decimal,
    payment_method: &str,
    correlation_id: Uuid,
) -> Result<PaymentResponse, AppError> {
    let mut tx = db.begin().await?;

    // 1) the business change — idempotent insert. ON CONFLICT (the UNIQUE partial index)
    //    DO NOTHING means a concurrent/redelivered completion inserts nothing. Under post-pay
    //    `expected_total` == `amount` == the final bill (post_pay_charge: base prorated to worked
    //    hours + flat tip) — persisted alongside `amount`; there is no separate downstream proration.
    let sql = format!(
        "INSERT INTO payment.payments \
           (booking_id, customer_id, guard_id, amount, expected_total, payment_method, status, paid_at) \
         VALUES ($1, $2, $3, $4, $5, $6, 'completed'::payment.payment_status, now()) \
         ON CONFLICT (booking_id) WHERE status = 'completed' DO NOTHING \
         RETURNING {PAYMENT_COLUMNS}"
    );
    let inserted = sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(booking_id)
        .bind(customer_id)
        .bind(guard_id)
        .bind(amount)
        .bind(expected_total)
        .bind(payment_method)
        .fetch_optional(&mut *tx)
        .await?;

    let Some(payment) = inserted else {
        // Already charged — no row inserted, nothing to emit. Return the existing payment.
        tx.rollback().await?;
        return completed_for_booking(db, booking_id).await?.ok_or_else(|| {
            AppError::Conflict("Payment already exists for this booking".to_string())
        });
    };

    // 2) the event — SAME transaction (transactional outbox). Carries the authoritative ids.
    let payload = serde_json::json!({
        "payment_id": payment.id,
        "booking_id": booking_id,
        "guard_id": guard_id,
        "amount": amount,
    });
    enqueue_outbox(&mut tx, topics::PAYMENT_COMPLETED, payload, correlation_id).await?;

    tx.commit().await?;
    Ok(payment)
}

/// Insert one outbox row (a fully-formed EventEnvelope) inside the caller's transaction.
async fn enqueue_outbox(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    topic: &str,
    payload: Value,
    correlation_id: Uuid,
) -> Result<(), AppError> {
    let envelope = EventEnvelope::new(topic, correlation_id, payload);
    let envelope_json = serde_json::to_value(&envelope)
        .map_err(|e| AppError::Internal(format!("serialize event envelope: {e}")))?;
    sqlx::query("INSERT INTO payment.outbox (topic, payload) VALUES ($1, $2)")
        .bind(topic)
        .bind(&envelope_json)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

// ----- Outbox relay support -----

/// Fetch up to `limit` unpublished outbox rows, oldest first.
pub async fn fetch_unpublished(db: &sqlx::PgPool, limit: i64) -> Result<Vec<OutboxRow>, AppError> {
    let rows = sqlx::query_as::<_, OutboxRow>(
        "SELECT id, topic, payload FROM payment.outbox \
         WHERE published_at IS NULL ORDER BY created_at LIMIT $1",
    )
    .bind(limit)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Stamp one outbox row published (called only after a successful NATS publish).
pub async fn mark_published(db: &sqlx::PgPool, id: Uuid) -> Result<(), AppError> {
    sqlx::query("UPDATE payment.outbox SET published_at = now() WHERE id = $1")
        .bind(id)
        .execute(db)
        .await?;
    Ok(())
}

#[cfg(test)]
mod db_tests {
    use super::*;
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;

    fn dec(s: &str) -> Decimal {
        s.parse().unwrap()
    }

    async fn pool() -> Option<sqlx::PgPool> {
        let url = std::env::var("DATABASE_URL").ok()?;
        PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .ok()
    }

    /// Real-Postgres integration test: a retried charge does NOT double-charge — two POSTs
    /// for the same booking yield exactly ONE completed payment row and ONE outbox event,
    /// and the second call returns the same payment id. DATABASE_URL-gated (hermetic when
    /// unset). Run against a migrated DB:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-payment -- charge_is_idempotent --nocapture
    #[tokio::test]
    async fn charge_is_idempotent() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let guard_id = Some(Uuid::new_v4());
        let correlation = Uuid::new_v4();

        let first = charge_idempotent(
            &pool,
            booking_id,
            customer_id,
            guard_id,
            dec("400.00"),
            dec("400.00"),
            "promptpay",
            correlation,
        )
        .await
        .expect("first charge");
        assert_eq!(first.status, "completed");
        assert_eq!(first.amount, dec("400.00"));
        assert_eq!(first.expected_total, Some(dec("400.00")));
        assert_eq!(first.guard_id, guard_id);

        // Retry — must return the SAME payment, not a new one.
        let second = charge_idempotent(
            &pool,
            booking_id,
            customer_id,
            guard_id,
            dec("400.00"),
            dec("400.00"),
            "promptpay",
            Uuid::new_v4(),
        )
        .await
        .expect("retry charge");
        assert_eq!(
            second.id, first.id,
            "retry must return the existing payment"
        );

        // exactly one row
        let count: i64 =
            sqlx::query_scalar("SELECT count(*) FROM payment.payments WHERE booking_id = $1")
                .bind(booking_id)
                .fetch_one(&pool)
                .await
                .expect("count rows");
        assert_eq!(count, 1, "exactly one payment row per booking");

        // exactly one payment.completed event
        let events: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::PAYMENT_COMPLETED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count events");
        assert_eq!(events, 1, "exactly one completed event (no double-emit)");

        // cleanup
        let _ =
            sqlx::query("DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(booking_id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = $1")
            .bind(booking_id)
            .execute(&pool)
            .await;
    }

    /// `admin_list_payments(customer_id=…)` narrows the cross-user ledger to one customer's
    /// payments (the customer-spend drill-down), and ANDs with `status`. Fresh per-run UUIDs →
    /// exact id-set assertions even against a shared DB. DATABASE_URL-gated. Run:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-payment -- admin_list_payments_filters_by_customer --nocapture
    #[tokio::test]
    async fn admin_list_payments_filters_by_customer() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let customer_a = Uuid::new_v4();
        let customer_b = Uuid::new_v4();
        let booking_a = Uuid::new_v4();
        let booking_b = Uuid::new_v4();
        let pay_a = charge_idempotent(
            &pool,
            booking_a,
            customer_a,
            Some(Uuid::new_v4()),
            dec("400.00"),
            dec("400.00"),
            "promptpay",
            Uuid::new_v4(),
        )
        .await
        .expect("charge A");
        let pay_b = charge_idempotent(
            &pool,
            booking_b,
            customer_b,
            Some(Uuid::new_v4()),
            dec("250.00"),
            dec("250.00"),
            "promptpay",
            Uuid::new_v4(),
        )
        .await
        .expect("charge B");

        // customer_id=A → exactly A's payment (fresh UUID → no other rows match).
        let only_a = admin_list_payments(&pool, None, Some(customer_a), 200, 0)
            .await
            .expect("list A");
        assert_eq!(
            only_a.iter().map(|p| p.id).collect::<Vec<_>>(),
            vec![pay_a.id],
            "customer_id filter must return only that customer's payment"
        );

        // status-only (no customer filter) — the post-refactor status-only placeholder path:
        // both fresh completed charges (newest-first) appear in the unscoped completed ledger.
        let completed = admin_list_payments(&pool, Some("completed"), None, 200, 0)
            .await
            .expect("list completed");
        let completed_ids = completed.iter().map(|p| p.id).collect::<Vec<_>>();
        assert!(
            completed_ids.contains(&pay_a.id) && completed_ids.contains(&pay_b.id),
            "status-only filter must still return completed payments after the refactor"
        );

        // status=completed AND customer_id=B → exactly B's one completed payment.
        let b_completed = admin_list_payments(&pool, Some("completed"), Some(customer_b), 200, 0)
            .await
            .expect("list B completed");
        assert_eq!(
            b_completed.iter().map(|p| p.id).collect::<Vec<_>>(),
            vec![pay_b.id],
            "status+customer_id AND-filter narrows to exactly B's completed payment"
        );

        // A mismatched status excludes it (proves the AND, not an OR).
        let b_refunded = admin_list_payments(&pool, Some("refunded"), Some(customer_b), 200, 0)
            .await
            .expect("list B refunded");
        assert!(b_refunded.is_empty(), "B has no refunded payment");

        // cleanup
        let _ = sqlx::query(
            "DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = ANY($1)",
        )
        .bind(vec![booking_a.to_string(), booking_b.to_string()])
        .execute(&pool)
        .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = ANY($1)")
            .bind(vec![booking_a, booking_b])
            .execute(&pool)
            .await;
    }
}
