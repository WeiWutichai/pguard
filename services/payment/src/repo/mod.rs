//! Repository layer — the ONLY place that touches the `payment` schema. THE MONEY PATH.
//!
//! Uses runtime `sqlx::query`/`query_as` (not the compile-time `query!` macro): the
//! scaffold has no DATABASE_URL / offline `.sqlx` cache at build time (mirrors booking).
//!
//! Two atomic writes anchor this slice:
//!  - [`charge_idempotent`] — insert a completed payment AND its `payment.completed` outbox
//!    event in ONE transaction, idempotently (the UNIQUE partial index + ON CONFLICT means
//!    a retried charge returns the existing row and emits nothing — no double-charge).
//!  - [`apply_proration`] — update the payment with the prorated final/refund/hours AND, if
//!    a refund is owed, enqueue `payment.refund_processed` in the SAME transaction.

use rust_decimal::Decimal;
use serde_json::Value;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::topics;
use shared_events::EventEnvelope;

use crate::domain::Proration;
use crate::models::PaymentResponse;

const PAYMENT_COLUMNS: &str = "id, booking_id, customer_id, guard_id, amount, payment_method, \
     status::text AS status, final_amount, refund_amount, actual_hours, paid_at, created_at, updated_at";

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

/// Read the completed/refunded payment for a booking so the completion path can prorate
/// against the original `amount`. Errors `NotFound` if the booking was never paid.
pub async fn get_payment_for_booking_amount(
    db: &sqlx::PgPool,
    booking_id: Uuid,
) -> Result<PaymentResponse, AppError> {
    let sql = format!(
        "SELECT {PAYMENT_COLUMNS} FROM payment.payments \
         WHERE booking_id = $1 AND status IN ('completed', 'refunded') \
         ORDER BY created_at DESC LIMIT 1"
    );
    sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(booking_id)
        .fetch_optional(db)
        .await?
        .ok_or_else(|| AppError::NotFound("No payment for this booking".to_string()))
}

// ----- Writes -----

/// Idempotently charge a booking: insert a `completed` payment AND its
/// `pguard.events.payment.completed` outbox event in ONE transaction. At most one completed
/// payment per booking — enforced by the UNIQUE partial index + `ON CONFLICT DO NOTHING`.
///
/// A retried POST cannot double-charge: on conflict the INSERT returns no row, we roll the
/// (empty) tx back, and return the EXISTING completed payment (no second event emitted).
/// `guard_id`/`customer_id` come from the authoritative booking, never the client.
#[tracing::instrument(skip(db), fields(booking_id = %booking_id, customer_id = %customer_id))]
#[allow(clippy::too_many_arguments)]
pub async fn charge_idempotent(
    db: &sqlx::PgPool,
    booking_id: Uuid,
    customer_id: Uuid,
    guard_id: Option<Uuid>,
    amount: Decimal,
    payment_method: &str,
    correlation_id: Uuid,
) -> Result<PaymentResponse, AppError> {
    let mut tx = db.begin().await?;

    // 1) the business change — idempotent insert. ON CONFLICT (the UNIQUE partial index)
    //    DO NOTHING means a concurrent/retried charge inserts nothing.
    let sql = format!(
        "INSERT INTO payment.payments \
           (booking_id, customer_id, guard_id, amount, payment_method, status, paid_at) \
         VALUES ($1, $2, $3, $4, $5, 'completed'::payment.payment_status, now()) \
         ON CONFLICT (booking_id) WHERE status = 'completed' DO NOTHING \
         RETURNING {PAYMENT_COLUMNS}"
    );
    let inserted = sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(booking_id)
        .bind(customer_id)
        .bind(guard_id)
        .bind(amount)
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

/// Apply proration to a booking's completed payment: set `final_amount`, `refund_amount`,
/// `actual_hours`, and — if a refund is owed — enqueue `payment.refund_processed` in the
/// SAME transaction. When fully refunded the status flips to `refunded`.
///
/// Idempotency-friendly: if the payment is already refunded this is a no-op-return (the
/// proration values are already set); the caller gets the current row.
#[tracing::instrument(skip(db, proration), fields(booking_id = %booking_id))]
pub async fn apply_proration(
    db: &sqlx::PgPool,
    booking_id: Uuid,
    proration: Proration,
    correlation_id: Uuid,
) -> Result<PaymentResponse, AppError> {
    let mut tx = db.begin().await?;

    // Lock the completed payment row so concurrent completions serialize.
    let existing: Option<(Uuid, String)> = sqlx::query_as(
        "SELECT id, status::text FROM payment.payments \
         WHERE booking_id = $1 AND status IN ('completed', 'refunded') \
         ORDER BY created_at DESC LIMIT 1 FOR UPDATE",
    )
    .bind(booking_id)
    .fetch_optional(&mut *tx)
    .await?;

    let Some((payment_id, status)) = existing else {
        tx.rollback().await?;
        return Err(AppError::NotFound(
            "No completed payment for this booking".to_string(),
        ));
    };

    // Already refunded → the proration was applied; return as-is (idempotent).
    if status == "refunded" {
        tx.rollback().await?;
        return get_payment(db, payment_id).await;
    }

    let has_refund = proration.refund_amount > Decimal::ZERO;
    // Fully refunded (nothing left owed) → mark refunded; otherwise keep completed.
    let new_status = if proration.final_amount.is_zero() && has_refund {
        "refunded"
    } else {
        "completed"
    };

    let sql = format!(
        "UPDATE payment.payments \
         SET final_amount = $2, refund_amount = $3, actual_hours = $4, \
             status = $5::payment.payment_status, updated_at = now() \
         WHERE id = $1 \
         RETURNING {PAYMENT_COLUMNS}"
    );
    let updated = sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(payment_id)
        .bind(proration.final_amount)
        .bind(proration.refund_amount)
        .bind(proration.actual_hours)
        .bind(new_status)
        .fetch_one(&mut *tx)
        .await?;

    // Emit a refund event only when money is actually returned — same transaction.
    if has_refund {
        let payload = serde_json::json!({
            "payment_id": payment_id,
            "booking_id": booking_id,
            "refund_amount": proration.refund_amount,
            "final_amount": proration.final_amount,
        });
        enqueue_outbox(
            &mut tx,
            topics::PAYMENT_REFUND_PROCESSED,
            payload,
            correlation_id,
        )
        .await?;
    }

    tx.commit().await?;
    Ok(updated)
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
    use crate::domain::compute_proration;
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
            "promptpay",
            correlation,
        )
        .await
        .expect("first charge");
        assert_eq!(first.status, "completed");
        assert_eq!(first.amount, dec("400.00"));
        assert_eq!(first.guard_id, guard_id);

        // Retry — must return the SAME payment, not a new one.
        let second = charge_idempotent(
            &pool,
            booking_id,
            customer_id,
            guard_id,
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

    /// Proration on completion: a partial-hours completion sets final/refund/hours AND
    /// enqueues exactly one refund event. DATABASE_URL-gated.
    #[tokio::test]
    async fn proration_writes_refund_row_and_event() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        charge_idempotent(
            &pool,
            booking_id,
            customer_id,
            Some(Uuid::new_v4()),
            dec("400.00"),
            "promptpay",
            correlation,
        )
        .await
        .expect("charge");

        // booked 4h, worked 2h → final 200, refund 200.
        let proration = compute_proration(dec("400.00"), 4, 7200);
        let updated = apply_proration(&pool, booking_id, proration, correlation)
            .await
            .expect("apply proration");
        assert_eq!(updated.final_amount, Some(dec("200.00")));
        assert_eq!(updated.refund_amount, Some(dec("200.00")));
        assert_eq!(updated.actual_hours, Some(dec("2.00")));

        let events: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::PAYMENT_REFUND_PROCESSED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count refund events");
        assert_eq!(events, 1, "exactly one refund event");

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
}
