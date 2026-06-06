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

use crate::domain::{compute_proration, Proration};
use crate::models::PaymentResponse;

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

/// Read the completed/refunded payment for a booking. Used by the integration tests to
/// assert the finalized state by booking_id (the finalize paths read their own locked row);
/// `#[cfg(test)]` so it isn't dead code in the prod build.
#[cfg(test)]
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
    expected_total: Decimal,
    payment_method: &str,
    correlation_id: Uuid,
) -> Result<PaymentResponse, AppError> {
    let mut tx = db.begin().await?;

    // 1) the business change — idempotent insert. ON CONFLICT (the UNIQUE partial index)
    //    DO NOTHING means a concurrent/retried charge inserts nothing. `expected_total` is
    //    the server-computed authoritative total (the handler already verified amount covers
    //    it) — persisted so the completion proration has the authoritative basis on hand.
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

/// Raw locked-payment row used by both finalize paths: id, charged amount, the authoritative
/// `expected_total`, and the current `final_amount` (the idempotency guard). Aliased for
/// clippy `type_complexity`.
type LockedPayment = (Uuid, Decimal, Option<Decimal>, Option<Decimal>);

const LOCK_PAYMENT_SQL: &str = "SELECT id, amount, expected_total, final_amount \
     FROM payment.payments WHERE booking_id = $1 AND status IN ('completed', 'refunded') \
     ORDER BY created_at DESC LIMIT 1 FOR UPDATE";

/// Compute the **tip-protected** proration and persist it (final/refund/actual_hours/status/
/// refund_status) + enqueue `payment.refund_processed` — ALL inside the caller's transaction.
/// Returns whether a refund event was enqueued. The single source of truth both finalize
/// paths (event consumer + admin) call, so the persisted state + refund event can never drift.
///
/// Money rules:
///  - The refundable BASIS is `min(amount, expected_total)`: any surplus the customer paid
///    above the authoritative total is a NON-refundable tip, held out of the refund (mirrors
///    v1's separate `tip_amount`). When `amount == expected_total` (the common case) the basis
///    is the whole amount and behaviour is unchanged.
///  - `actual_seconds = None` → the guard never started; the full charge stands, zero worked
///    hours recorded (no factual basis to prorate — mirrors v1's missing-timestamps skip).
///  - Proration of the basis is [`compute_proration`] (ported verbatim from v1).
#[allow(clippy::too_many_arguments)]
async fn write_proration_tx(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    payment_id: Uuid,
    booking_id: Uuid,
    amount: Decimal,
    expected_total: Option<Decimal>,
    booked_hours: i32,
    actual_seconds: Option<i64>,
    correlation_id: Uuid,
) -> Result<bool, AppError> {
    // Hold any surplus tip out of the refundable basis.
    let basis = match expected_total {
        Some(exp) if exp < amount => exp,
        _ => amount,
    };
    let surplus = amount - basis; // non-refundable tip (>= 0)

    let prorated = match actual_seconds {
        Some(secs) => compute_proration(basis, booked_hours, secs),
        None => Proration {
            actual_hours: Decimal::ZERO,
            final_amount: basis,
            refund_amount: Decimal::ZERO,
        },
    };
    let final_amount = prorated.final_amount + surplus; // tip added back, never refunded
    let refund_amount = prorated.refund_amount; // = basis − prorated.final (tip excluded)
    let has_refund = refund_amount > Decimal::ZERO;
    // Fully refunded only when nothing is owed AND no tip keeps the payment alive.
    let new_status = if final_amount.is_zero() && has_refund {
        "refunded"
    } else {
        "completed"
    };

    sqlx::query(
        "UPDATE payment.payments \
         SET final_amount = $2, refund_amount = $3, actual_hours = $4, \
             status = $5::payment.payment_status, \
             refund_status = CASE WHEN $6 THEN 'pending' ELSE refund_status END, \
             updated_at = now() \
         WHERE id = $1",
    )
    .bind(payment_id)
    .bind(final_amount)
    .bind(refund_amount)
    .bind(prorated.actual_hours)
    .bind(new_status)
    .bind(has_refund)
    .execute(&mut **tx)
    .await?;

    if has_refund {
        let payload = serde_json::json!({
            "payment_id": payment_id,
            "booking_id": booking_id,
            "refund_amount": refund_amount,
            "final_amount": final_amount,
        });
        enqueue_outbox(
            tx,
            topics::PAYMENT_REFUND_PROCESSED,
            payload,
            correlation_id,
        )
        .await?;
    }
    Ok(has_refund)
}

/// Apply proration to a booking's completed payment (the ADMIN `/complete` override path).
/// Reads the booked hours from the caller; computes + persists the proration via
/// [`write_proration_tx`].
///
/// **Idempotent**: if the payment is already finalized (`final_amount` set — whether by the
/// event consumer or a prior admin call) this is a no-op-return of the current row, so the
/// admin path can never double-apply a refund on top of the event-driven finalization.
#[tracing::instrument(skip(db), fields(booking_id = %booking_id))]
pub async fn apply_proration(
    db: &sqlx::PgPool,
    booking_id: Uuid,
    booked_hours: i32,
    actual_seconds: i64,
    correlation_id: Uuid,
) -> Result<PaymentResponse, AppError> {
    let mut tx = db.begin().await?;

    // Lock the completed payment row so concurrent completions serialize.
    let existing: Option<LockedPayment> = sqlx::query_as(LOCK_PAYMENT_SQL)
        .bind(booking_id)
        .fetch_optional(&mut *tx)
        .await?;

    let Some((payment_id, amount, expected_total, existing_final)) = existing else {
        tx.rollback().await?;
        return Err(AppError::NotFound(
            "No completed payment for this booking".to_string(),
        ));
    };

    // Already finalized (event consumer or a prior admin call) → return as-is (idempotent;
    // no second refund event). This closes the admin-after-event double-refund window.
    if existing_final.is_some() {
        tx.rollback().await?;
        return get_payment(db, payment_id).await;
    }

    write_proration_tx(
        &mut tx,
        payment_id,
        booking_id,
        amount,
        expected_total,
        booked_hours,
        Some(actual_seconds),
        correlation_id,
    )
    .await?;

    tx.commit().await?;
    get_payment(db, payment_id).await
}

/// Outcome of finalizing a booking's payment on a `booking.completed` event.
#[derive(Debug, PartialEq, Eq)]
pub enum Finalized {
    /// Proration applied; `refunded` is true when a refund event was enqueued.
    Applied { refunded: bool },
    /// No completed payment for this booking (customer never paid) — nothing to finalize.
    NoPayment,
    /// This `event_id` was already processed (at-least-once redelivery) — no-op.
    Duplicate,
    /// The payment was already finalized (final_amount set) — no-op (belt-and-suspenders).
    AlreadyDone,
}

/// Finalize proration when a booking completes, driven by the `booking.completed` event.
/// **Idempotent by `event_id`**: the claim into `processed_events` + the payment update +
/// the refund outbox row all happen in ONE transaction, so a redelivered completion event
/// can never double-apply a refund. Persistence goes through [`write_proration_tx`] (shared
/// with the admin path) so the two finalizers cannot drift.
#[tracing::instrument(skip(db), fields(event_id = %event_id, booking_id = %booking_id))]
#[allow(clippy::too_many_arguments)]
pub async fn finalize_on_booking_completed(
    db: &sqlx::PgPool,
    event_id: Uuid,
    event_type: &str,
    booking_id: Uuid,
    booked_hours: i32,
    actual_seconds: Option<i64>,
    correlation_id: Uuid,
) -> Result<Finalized, AppError> {
    let mut tx = db.begin().await?;

    // 1) Claim the event_id — the idempotency anchor. A redelivery inserts nothing.
    let claim = sqlx::query(
        "INSERT INTO payment.processed_events (event_id, event_type) \
         VALUES ($1, $2) ON CONFLICT (event_id) DO NOTHING",
    )
    .bind(event_id)
    .bind(event_type)
    .execute(&mut *tx)
    .await?;
    if claim.rows_affected() == 0 {
        tx.rollback().await?;
        return Ok(Finalized::Duplicate);
    }

    // 2) Lock the completed payment for this booking (if any).
    let row: Option<LockedPayment> = sqlx::query_as(LOCK_PAYMENT_SQL)
        .bind(booking_id)
        .fetch_optional(&mut *tx)
        .await?;

    let Some((payment_id, amount, expected_total, existing_final)) = row else {
        // Customer never paid — nothing to finalize. The claim is committed, so a redelivery
        // of THIS completion event short-circuits as Duplicate. A pay-after-complete flow
        // (payment arriving after the completion) is a tracked follow-up and would need an
        // explicit reconciliation path — it is NOT handled by redelivery here.
        tx.commit().await?;
        return Ok(Finalized::NoPayment);
    };

    // Already finalized (a prior completion or the admin path) → no-op.
    if existing_final.is_some() {
        tx.commit().await?;
        return Ok(Finalized::AlreadyDone);
    }

    // 3) Prorate + persist (tip-protected) + enqueue any refund — shared with the admin path.
    let refunded = write_proration_tx(
        &mut tx,
        payment_id,
        booking_id,
        amount,
        expected_total,
        booked_hours,
        actual_seconds,
        correlation_id,
    )
    .await?;

    tx.commit().await?;
    Ok(Finalized::Applied { refunded })
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
            dec("400.00"),
            "promptpay",
            correlation,
        )
        .await
        .expect("charge");

        // booked 4h, worked 2h → final 200, refund 200, refund_status pending.
        let updated = apply_proration(&pool, booking_id, 4, 7200, correlation)
            .await
            .expect("apply proration");
        assert_eq!(updated.final_amount, Some(dec("200.00")));
        assert_eq!(updated.refund_amount, Some(dec("200.00")));
        assert_eq!(updated.actual_hours, Some(dec("2.00")));
        assert_eq!(updated.refund_status.as_deref(), Some("pending"));

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

        // Idempotent: a re-run of the admin path on an already-finalized payment is a no-op
        // (returns the current row, no SECOND refund event).
        let again = apply_proration(&pool, booking_id, 4, 7200, correlation)
            .await
            .expect("apply proration again");
        assert_eq!(again.final_amount, Some(dec("200.00")));
        let events_after: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::PAYMENT_REFUND_PROCESSED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count refund events after replay");
        assert_eq!(
            events_after, 1,
            "admin re-run must not emit a second refund"
        );

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

    /// THE double-refund regression (security HIGH): the event consumer finalizes first, then
    /// an admin invokes the manual /complete path. The admin path must be a no-op (it sees
    /// `final_amount` already set) — exactly ONE refund event total. DATABASE_URL-gated.
    #[tokio::test]
    async fn admin_complete_after_event_finalize_does_not_double_refund() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        charge_idempotent(
            &pool,
            booking_id,
            customer_id,
            Some(Uuid::new_v4()),
            dec("2000.00"),
            dec("2000.00"),
            "promptpay",
            correlation,
        )
        .await
        .expect("charge");

        // 1) event consumer finalizes (4h booked, 2h worked → refund 1000).
        let ev = finalize_on_booking_completed(
            &pool,
            event_id,
            topics::BOOKING_COMPLETED,
            booking_id,
            4,
            Some(7200),
            correlation,
        )
        .await
        .expect("event finalize");
        assert_eq!(ev, Finalized::Applied { refunded: true });

        // 2) admin manually re-runs /complete afterwards → MUST be a no-op (idempotent).
        let admin = apply_proration(&pool, booking_id, 4, 7200, correlation)
            .await
            .expect("admin complete");
        assert_eq!(admin.refund_amount, Some(dec("1000.00")));

        // Exactly ONE refund event despite both finalizers running.
        let events: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::PAYMENT_REFUND_PROCESSED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count refund events");
        assert_eq!(
            events, 1,
            "consumer + admin must yield exactly one refund event"
        );

        // cleanup
        let _ =
            sqlx::query("DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(booking_id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM payment.processed_events WHERE event_id = $1")
            .bind(event_id)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = $1")
            .bind(booking_id)
            .execute(&pool)
            .await;
    }

    /// Surplus tip (paid above expected_total) is NOT refunded on partial completion (#5):
    /// pay 2200 on a 2000 expected booking (200 tip); work 2h of 4h → refund 1000 (half the
    /// 2000 basis), final 1200 (1000 worked + 200 tip held out). DATABASE_URL-gated.
    #[tokio::test]
    async fn surplus_tip_is_not_refunded_on_partial_completion() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        charge_idempotent(
            &pool,
            booking_id,
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            dec("2200.00"), // 2000 expected + 200 tip
            dec("2000.00"),
            "promptpay",
            correlation,
        )
        .await
        .expect("charge");

        finalize_on_booking_completed(
            &pool,
            event_id,
            topics::BOOKING_COMPLETED,
            booking_id,
            4,
            Some(7200), // 2h of 4h
            correlation,
        )
        .await
        .expect("finalize");

        let p = get_payment_for_booking_amount(&pool, booking_id)
            .await
            .expect("read payment");
        assert_eq!(
            p.refund_amount,
            Some(dec("1000.00")),
            "only the basis is prorated"
        );
        assert_eq!(
            p.final_amount,
            Some(dec("1200.00")),
            "tip held out of the refund"
        );

        let _ =
            sqlx::query("DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(booking_id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM payment.processed_events WHERE event_id = $1")
            .bind(event_id)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = $1")
            .bind(booking_id)
            .execute(&pool)
            .await;
    }

    /// The booking.completed consumer's finalize is IDEMPOTENT by event_id: replaying the
    /// same completion event applies the refund exactly once (no double refund, one refund
    /// event). This is the core money-safety property of the event-driven path.
    /// DATABASE_URL-gated.
    #[tokio::test]
    async fn finalize_on_completion_is_idempotent() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        charge_idempotent(
            &pool,
            booking_id,
            customer_id,
            Some(Uuid::new_v4()),
            dec("400.00"),
            dec("400.00"),
            "promptpay",
            correlation,
        )
        .await
        .expect("charge");

        // booked 4h, worked 2h → final 200, refund 200.
        let first = finalize_on_booking_completed(
            &pool,
            event_id,
            topics::BOOKING_COMPLETED,
            booking_id,
            4,
            Some(7200),
            correlation,
        )
        .await
        .expect("finalize #1");
        assert_eq!(first, Finalized::Applied { refunded: true });

        // Redelivery of the SAME event_id → Duplicate, applies nothing more.
        let second = finalize_on_booking_completed(
            &pool,
            event_id,
            topics::BOOKING_COMPLETED,
            booking_id,
            4,
            Some(7200),
            correlation,
        )
        .await
        .expect("finalize #2 (replay)");
        assert_eq!(second, Finalized::Duplicate, "replay must be a no-op");

        // The payment shows the single proration result + refund_status pending.
        let p = get_payment_for_booking_amount(&pool, booking_id)
            .await
            .expect("read payment");
        assert_eq!(p.final_amount, Some(dec("200.00")));
        assert_eq!(p.refund_amount, Some(dec("200.00")));
        assert_eq!(p.refund_status.as_deref(), Some("pending"));

        // Exactly ONE refund event despite two deliveries.
        let events: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::PAYMENT_REFUND_PROCESSED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count refund events");
        assert_eq!(events, 1, "exactly one refund event (no double refund)");

        // cleanup
        let _ =
            sqlx::query("DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(booking_id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM payment.processed_events WHERE event_id = $1")
            .bind(event_id)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = $1")
            .bind(booking_id)
            .execute(&pool)
            .await;
    }
}
