//! Repository layer — the ONLY place that touches the `payment` schema. THE MONEY PATH.
//!
//! Uses runtime `sqlx::query`/`query_as` (not the compile-time `query!` macro): the
//! scaffold has no DATABASE_URL / offline `.sqlx` cache at build time (mirrors booking).
//!
//! Two atomic writes anchor this slice (v2 is PRE-PAY then SETTLE):
//!  - [`prepay_idempotent`] — insert a completed payment AND its `payment.completed` outbox event
//!    in ONE transaction, idempotently (the UNIQUE partial index + ON CONFLICT means a repeat
//!    pre-pay returns the existing row and emits nothing — no double-charge). Called by the
//!    `createPayment` endpoint with the server-computed estimate.
//!  - [`reconcile_on_completion`] — on `booking.completed`, diff the actual-hours bill
//!    (`domain::reconcile`) against the pre-paid amount in ONE transaction and refund the overpay
//!    (`payment.refund_processed`) / record the shortfall. Idempotent via the `processed_events`
//!    event-id claim; the base is never double-charged.

use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde_json::Value;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::topics;
use shared_events::EventEnvelope;

use crate::models::{CustomerSpend, PaymentResponse, RefundQueueItem, RevenuePoint};

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

/// The assigned guard's earning basis: their COMPLETED (paid) jobs, newest first, with the clamped
/// `actual_hours` worked (persisted at reconcile). A `refunded` row (a cancelled/withdrawn job) is
/// excluded — the guard earned nothing there, and it is not a `completed` job on their side either.
/// The client pairs each `booking_id` with the `base_fee` from its own booking feed and pays
/// `base_fee × actual_hours` (falling back to booked hours when `actual_hours` is NULL), so the
/// guard's earnings reflect hours ACTUALLY worked — matching the customer's reconciled net.
pub async fn guard_earnings(
    db: &sqlx::PgPool,
    guard_id: Uuid,
) -> Result<Vec<crate::models::GuardEarningRow>, AppError> {
    let rows = sqlx::query_as::<_, crate::models::GuardEarningRow>(
        "SELECT booking_id, actual_hours FROM payment.payments \
         WHERE guard_id = $1 AND status = 'completed' ORDER BY created_at DESC LIMIT 100",
    )
    .bind(guard_id)
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

// ----- Refund queue (admin dashboard signal) -----

/// The refund-queue projection: a payment whose settle left a refund owed (`refund_status` set).
/// `amount` is the `refund_amount` (the money to return), `status` is the refund-workflow state.
/// SELECTs only the five columns the queue card needs (no SELECT *).
const REFUND_QUEUE_COLUMNS: &str = "id AS payment_id, booking_id, refund_amount AS amount, \
     refund_status AS status, created_at";

/// Admin refund queue — payments awaiting refund action / in progress (`refund_status` set),
/// newest first, with an optional refund-state filter (`pending`/`processed`) + limit/offset.
/// No owner filter — the admin-role gate is the API layer's job. `status` is validated against
/// the refund-state set in the handler and bound as a param (never interpolated). Index-backed
/// by `idx_payments_refund_queue (refund_status, created_at DESC) WHERE refund_status IS NOT NULL`.
pub async fn admin_list_refund_queue(
    db: &sqlx::PgPool,
    status: Option<&str>,
    limit: i64,
    offset: i64,
) -> Result<Vec<RefundQueueItem>, AppError> {
    let mut sql = format!(
        "SELECT {REFUND_QUEUE_COLUMNS} FROM payment.payments WHERE refund_status IS NOT NULL"
    );
    if status.is_some() {
        sql.push_str(" AND refund_status = $1");
    }
    sql.push_str(if status.is_some() {
        " ORDER BY created_at DESC LIMIT $2 OFFSET $3"
    } else {
        " ORDER BY created_at DESC LIMIT $1 OFFSET $2"
    });
    let mut query = sqlx::query_as::<_, RefundQueueItem>(&sql);
    if let Some(s) = status {
        query = query.bind(s);
    }
    let rows = query.bind(limit).bind(offset).fetch_all(db).await?;
    Ok(rows)
}

/// Total count of refund-queue rows matching the same `status` filter (independent of
/// limit/offset) — powers the dashboard "คิวคืนเงิน" badge. Same predicate as
/// [`admin_list_refund_queue`].
pub async fn admin_count_refund_queue(
    db: &sqlx::PgPool,
    status: Option<&str>,
) -> Result<i64, AppError> {
    let mut sql =
        "SELECT count(*)::bigint FROM payment.payments WHERE refund_status IS NOT NULL".to_string();
    if status.is_some() {
        sql.push_str(" AND refund_status = $1");
    }
    let mut query = sqlx::query_scalar::<_, i64>(&sql);
    if let Some(s) = status {
        query = query.bind(s);
    }
    Ok(query.fetch_one(db).await?)
}

// ----- Revenue report (admin analytics) -----

/// Net revenue expression shared by the series + total queries: completed charges' effective
/// amount (prorated `final_amount` when set, else `amount`) minus any refunds. Kept as one
/// constant so the per-day series and the MoM total compute identically.
///
/// BOTH terms are status-gated to `completed`: a PARTIAL refund stays `completed` (so its
/// `refund_amount` is subtracted here), but a FULL refund flips the row to `refunded` — its charge
/// already drops out of the positive term, so its `refund_amount` must NOT be subtracted too
/// (otherwise the row would net to −(pre-pay) instead of 0). Mirrors `customer_spend`'s exclusion.
const NET_REVENUE_EXPR: &str =
    "COALESCE(SUM(CASE WHEN status = 'completed' THEN COALESCE(final_amount, amount) ELSE 0 END), 0) \
     - COALESCE(SUM(CASE WHEN status = 'completed' THEN COALESCE(refund_amount, 0) ELSE 0 END), 0)";

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

/// Outcome of an idempotent PRE-PAY: a freshly-inserted payment (we emitted `payment.completed`)
/// or the already-existing one (a repeat pre-pay — a no-op, nothing emitted).
pub enum PrePayOutcome {
    /// First pre-pay for this booking — the row was inserted and `payment.completed` enqueued.
    Created(PaymentResponse),
    /// A pre-pay already exists — repeat request, no second charge and no second event.
    AlreadyPaid(PaymentResponse),
}

/// Idempotently PRE-PAY a booking: insert a `completed` payment AND its
/// `pguard.events.payment.completed` outbox event in ONE transaction. At most one completed
/// payment per booking — enforced by the UNIQUE partial index + `ON CONFLICT DO NOTHING`.
///
/// v2 is PRE-PAY: the customer pays the ESTIMATE (`base_fee × hours × guard_count + tip`) once a
/// guard has accepted; that payment GATES the booking's `en_route` transition (booking learns it
/// is paid by consuming `payment.completed`). A repeat POST cannot double-charge: on conflict the
/// INSERT returns no row, we roll the (empty) tx back, and return [`PrePayOutcome::AlreadyPaid`]
/// (no second event emitted). `amount == expected_total ==` the estimate — both server-computed
/// from booking's authoritative read, never a client value. The completion-time SETTLE
/// ([`reconcile_on_completion`]) later refunds/charges the difference vs the actual hours.
#[tracing::instrument(skip(db), fields(booking_id = %booking_id, customer_id = %customer_id))]
#[allow(clippy::too_many_arguments)]
pub async fn prepay_idempotent(
    db: &sqlx::PgPool,
    booking_id: Uuid,
    customer_id: Uuid,
    guard_id: Option<Uuid>,
    amount: Decimal,
    expected_total: Decimal,
    payment_method: &str,
    correlation_id: Uuid,
) -> Result<PrePayOutcome, AppError> {
    let mut tx = db.begin().await?;

    // 1) the business change — idempotent insert. ON CONFLICT (the UNIQUE partial index)
    //    DO NOTHING means a concurrent/repeat pre-pay inserts nothing. `amount` == `expected_total`
    //    == the PRE-PAY estimate; the actual-hours SETTLE happens later in reconcile_on_completion.
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
        // Already paid — no row inserted, nothing to emit. Return the existing payment.
        tx.rollback().await?;
        return completed_for_booking(db, booking_id)
            .await?
            .map(PrePayOutcome::AlreadyPaid)
            .ok_or_else(|| {
                AppError::Conflict("Payment already exists for this booking".to_string())
            });
    };

    // 2) the event — SAME transaction (transactional outbox). Carries the authoritative ids so
    //    booking can un-gate (set paid_at → allow en_route) and notification can push BOTH the
    //    customer ("ชำระเงินสำเร็จ") and the guard ("ลูกค้าชำระเงินแล้ว").
    let payload = serde_json::json!({
        "payment_id": payment.id,
        "booking_id": booking_id,
        "customer_id": customer_id,
        "guard_id": guard_id,
        "amount": amount,
    });
    enqueue_outbox(&mut tx, topics::PAYMENT_COMPLETED, payload, correlation_id).await?;

    tx.commit().await?;
    Ok(PrePayOutcome::Created(payment))
}

/// Outcome of an idempotent SLIP pay: a freshly-verified slip stamped the booking paid (we emitted
/// `payment.completed`), the SAME accepted slip was re-submitted (a no-op returning paid), or the
/// slip was already used for ANOTHER booking (rejected — one slip cannot pay two bookings).
#[derive(Debug)]
pub enum SlipPayOutcome {
    /// First slip for this booking — the payment was stamped paid + the slip recorded + the
    /// `payment.completed` event enqueued.
    Created(PaymentResponse),
    /// Idempotent no-op: this booking was already paid (the SAME slip re-submitted, or any later
    /// slip for an already-paid booking). The existing payment is returned; nothing re-charged.
    AlreadyPaid(PaymentResponse),
}

/// Atomically pay a booking with a VERIFIED slip — the REAL money path's write. THE MONEY PATH.
///
/// In ONE transaction: (1) idempotently insert the `completed` payment (UNIQUE partial index +
/// ON CONFLICT — at most one completed payment per booking, like the simulated pre-pay), (2) record
/// the verified slip with its `trans_ref` / `reference_id` under a UNIQUE constraint (the atomic
/// our-side dedupe), and (3) enqueue the EXISTING `payment.completed` outbox event (gates en_route
/// — no new event type).
///
/// DEDUPE GUARANTEE (anti-fraud, the core value): a slip's `trans_ref`/`reference_id` is UNIQUE
/// across ALL bookings. The slip INSERT is the atomic guard — if this exact slip already settled a
/// DIFFERENT booking, the unique-violation aborts the tx and we return an [`AppError::ConflictCode`]
/// (`SLIP_DUPLICATE`). One real transfer can therefore settle at most one booking, independent of
/// Slip2Go's own `checkDuplicate`.
///
/// IDEMPOTENCY: re-submitting the SAME accepted slip for the SAME (already-paid) booking is a no-op
/// returning the existing payment (no double-charge, no second event) — distinguished from the
/// cross-booking reuse above by checking, on a payment conflict, whether the already-recorded slip
/// for THIS booking carries the same `trans_ref`.
#[tracing::instrument(skip(db), fields(booking_id = %booking_id, customer_id = %customer_id))]
#[allow(clippy::too_many_arguments)]
pub async fn pay_with_slip(
    db: &sqlx::PgPool,
    booking_id: Uuid,
    customer_id: Uuid,
    guard_id: Option<Uuid>,
    amount: Decimal,
    expected_total: Decimal,
    reference_id: &str,
    trans_ref: &str,
    slip_amount: Decimal,
    slip_key: &str,
    correlation_id: Uuid,
) -> Result<SlipPayOutcome, AppError> {
    let mut tx = db.begin().await?;

    // 1) idempotent payment insert. ON CONFLICT (one completed per booking) DO NOTHING.
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
        .bind(SLIP_PAYMENT_METHOD)
        .fetch_optional(&mut *tx)
        .await?;

    let Some(payment) = inserted else {
        // The booking already has a completed payment. Idempotent re-submit: if the recorded slip
        // for THIS booking is the SAME slip (same trans_ref), this is a benign retry → AlreadyPaid.
        // Otherwise the booking was paid by a DIFFERENT slip already → still AlreadyPaid (we never
        // re-charge a paid booking; the new slip is simply not consumed). We do NOT insert the new
        // slip row in either case (the booking-level idempotency wins). The cross-booking reuse of
        // THIS slip is caught below at the slip INSERT for the FIRST-pay path.
        tx.rollback().await?;
        return completed_for_booking(db, booking_id)
            .await?
            .map(SlipPayOutcome::AlreadyPaid)
            .ok_or_else(|| {
                AppError::Conflict("Payment already exists for this booking".to_string())
            });
    };

    // 2) record the verified slip — the UNIQUE (trans_ref) / (reference_id) is the atomic dedupe.
    //    A unique-violation means this slip already settled ANOTHER booking → reject the whole tx
    //    (the payment insert rolls back with it; nothing is charged).
    let slip_insert = sqlx::query(
        "INSERT INTO payment.payment_slips \
           (payment_id, booking_id, reference_id, trans_ref, amount, slip_key) \
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(payment.id)
    .bind(booking_id)
    .bind(reference_id)
    .bind(trans_ref)
    .bind(slip_amount)
    .bind(slip_key)
    .execute(&mut *tx)
    .await;

    if let Err(e) = slip_insert {
        // The payment insert in THIS tx rolls back on drop, so no orphan payment is created.
        if is_unique_violation(&e) {
            tracing::warn!(%trans_ref, "slip already used for another booking (dedupe reject)");
            return Err(AppError::ConflictCode {
                code: crate::slip2go_client::SLIP_DUPLICATE_CODE,
                message: "This slip has already been used for a payment".to_string(),
            });
        }
        return Err(e.into());
    }

    // 3) the event — SAME transaction (transactional outbox). Identical payload to the simulated
    //    pre-pay so booking un-gates (en_route) and notification pushes both parties.
    let payload = serde_json::json!({
        "payment_id": payment.id,
        "booking_id": booking_id,
        "customer_id": customer_id,
        "guard_id": guard_id,
        "amount": amount,
    });
    enqueue_outbox(&mut tx, topics::PAYMENT_COMPLETED, payload, correlation_id).await?;

    tx.commit().await?;
    Ok(SlipPayOutcome::Created(payment))
}

/// `payment_method` for a REAL Slip2Go-verified transfer (vs the simulated path's `prepaid`).
const SLIP_PAYMENT_METHOD: &str = "promptpay_slip";

/// Is this sqlx error a Postgres UNIQUE constraint violation (SQLSTATE 23505)? Used to turn the
/// slip dedupe's unique-violation into a typed `SLIP_DUPLICATE` rejection.
fn is_unique_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505")
    )
}

/// The outcome of the completion-time SETTLE against the PRE-PAID amount.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SettleOutcome {
    /// Nothing to do (no pre-pay found, the event was already processed, or actual == paid).
    NoOp,
    /// A refund of `refund` was owed (we set final_amount/refund_amount/refund_status='pending'
    /// and emitted `payment.refund_processed`).
    Refunded {
        final_amount: Decimal,
        refund: Decimal,
    },
    /// The customer owed `extra` above the pre-paid amount (recorded as `final_amount`, no event).
    ExtraCharged {
        final_amount: Decimal,
        extra: Decimal,
    },
}

/// RECONCILE the actual-hours bill against the PRE-PAID amount on `booking.completed`, in ONE
/// transaction (idempotent via the `processed_events` ledger — JetStream is at-least-once).
///
/// v2 PRE-PAY then SETTLE: the customer already paid the estimate up front. On completion we diff
/// the actual-hours bill ([`crate::domain::reconcile`]) against the pre-paid `amount`:
///  - `actual < paid` → REFUND the difference: set `final_amount`/`refund_amount` +
///    `refund_status='pending'` and emit `pguard.events.payment.refund_processed`.
///  - `actual > paid` → record the shortfall: set `final_amount` (the extra charge owed). The base
///    is NEVER re-charged — only the delta is recorded.
///  - equal → record `final_amount` only.
///
/// Dedup: the event_id is claimed in `processed_events` inside the same tx; a redelivery finds it
/// claimed and is a NoOp (the refund is never double-applied). If no pre-pay row exists (defensive
/// — the en_route gate means a completed booking was paid), this is a NoOp: there is nothing to
/// settle against, and we never raise a base charge here (that would risk a double-charge).
#[tracing::instrument(skip(db), fields(booking_id = %booking_id, event_id = %event_id))]
#[allow(clippy::too_many_arguments)]
pub async fn reconcile_on_completion(
    db: &sqlx::PgPool,
    event_id: Uuid,
    event_type: &str,
    booking_id: Uuid,
    base_fee: Decimal,
    booked_hours: i32,
    guard_count: i32,
    tip: Decimal,
    actual_seconds: Option<i64>,
    correlation_id: Uuid,
) -> Result<SettleOutcome, AppError> {
    use crate::domain::Reconciliation;

    let mut tx = db.begin().await?;

    // 1) claim the event_id (at-least-once dedup). A redelivery inserts nothing → NoOp.
    let claimed = sqlx::query(
        "INSERT INTO payment.processed_events (event_id, event_type) VALUES ($1, $2) \
         ON CONFLICT (event_id) DO NOTHING",
    )
    .bind(event_id)
    .bind(event_type)
    .execute(&mut *tx)
    .await?;
    if claimed.rows_affected() == 0 {
        tx.rollback().await?;
        tracing::debug!("booking.completed already reconciled (idempotent NoOp)");
        return Ok(SettleOutcome::NoOp);
    }

    // 2) read the PRE-PAID amount (the settle basis). FOR UPDATE locks the row for the diff write.
    let sql = format!(
        "SELECT {PAYMENT_COLUMNS} FROM payment.payments \
         WHERE booking_id = $1 AND status = 'completed' LIMIT 1 FOR UPDATE"
    );
    let Some(payment) = sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(booking_id)
        .fetch_optional(&mut *tx)
        .await?
    else {
        // No pre-pay on file — nothing to settle against. Commit the claim (so a replay stays a
        // NoOp) and return. We do NOT raise a base charge here (avoids any double-charge risk).
        tx.commit().await?;
        tracing::warn!("booking.completed with no pre-pay on file; nothing to reconcile");
        return Ok(SettleOutcome::NoOp);
    };

    let outcome = crate::domain::reconcile(
        payment.amount,
        base_fee,
        booked_hours,
        guard_count,
        tip,
        actual_seconds,
    );

    // The clamped hours ACTUALLY worked (min(worked, booked), ≥0) — persisted on the row so the
    // guard-earnings endpoint can pay for actual, not booked, hours. This column existed but was
    // never written; leaving it NULL is why the guard's earnings screen (base × BOOKED hours) showed
    // more than the customer's reconciled net. `None` only when the guard never started (defensive —
    // requesting completion requires a start), in which case the column stays NULL and the client
    // falls back to booked hours.
    let actual_hours: Option<Decimal> = actual_seconds.map(|secs| {
        let booked_base =
            crate::domain::expected_total(base_fee, booked_hours, guard_count, Decimal::ZERO);
        crate::domain::proration::compute_proration(booked_base, booked_hours, secs).actual_hours
    });

    let settle = match outcome {
        Reconciliation::Even => {
            // Record the (matching) final bill for the ledger; no money moves, no event.
            sqlx::query(
                "UPDATE payment.payments SET final_amount = amount, actual_hours = $2, updated_at = now() WHERE id = $1",
            )
            .bind(payment.id)
            .bind(actual_hours)
            .execute(&mut *tx)
            .await?;
            SettleOutcome::NoOp
        }
        Reconciliation::Refund {
            final_amount,
            refund,
        } => {
            // The base is NOT re-charged — only the overpay is returned. refund_status='pending'
            // (an admin/real-gateway marks 'processed'); the row stays 'completed' (a PARTIAL
            // refund) so the revenue report nets it out.
            sqlx::query(
                "UPDATE payment.payments \
                   SET final_amount = $2, refund_amount = $3, refund_status = 'pending', \
                       actual_hours = $4, updated_at = now() \
                 WHERE id = $1",
            )
            .bind(payment.id)
            .bind(final_amount)
            .bind(refund)
            .bind(actual_hours)
            .execute(&mut *tx)
            .await?;

            // emit refund_processed (booking un-gates on payment.completed, NOT this).
            // customer_id/guard_id carried so the notification consumer can ROUTE the "you were
            // refunded" push to the payer (the payload formerly had no recipient — deep-review HIGH).
            let payload = serde_json::json!({
                "payment_id": payment.id,
                "booking_id": booking_id,
                "customer_id": payment.customer_id,
                "guard_id": payment.guard_id,
                "refund_amount": refund,
                "final_amount": final_amount,
            });
            enqueue_outbox(
                &mut tx,
                topics::PAYMENT_REFUND_PROCESSED,
                payload,
                correlation_id,
            )
            .await?;
            SettleOutcome::Refunded {
                final_amount,
                refund,
            }
        }
        Reconciliation::Extra {
            final_amount,
            extra,
        } => {
            // Customer owes more than pre-paid (e.g. a tip bump). Record the higher final_amount;
            // the delta is owed. No refund event. (A real gateway would capture the extra here.)
            sqlx::query(
                "UPDATE payment.payments SET final_amount = $2, actual_hours = $3, updated_at = now() WHERE id = $1",
            )
            .bind(payment.id)
            .bind(final_amount)
            .bind(actual_hours)
            .execute(&mut *tx)
            .await?;
            SettleOutcome::ExtraCharged {
                final_amount,
                extra,
            }
        }
    };

    tx.commit().await?;
    Ok(settle)
}

/// The outcome of a cancellation/decline FULL refund against the pre-paid amount.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CancelRefundOutcome {
    /// Nothing to refund (no PAID pre-pay on file, or the event was already processed).
    NoOp,
    /// The whole pre-paid `refund` was returned (status → `refunded`, refund_status = 'pending',
    /// emitted `payment.refund_processed`).
    Refunded { refund: Decimal },
}

/// FULL-REFUND a pre-paid booking whose job was CANCELLED or DECLINED before it ran — a guard
/// withdrawing en_route, or a customer cancelling after paying — in ONE transaction. No work was
/// done, so the ENTIRE pre-pay is returned: the payment row flips `status → refunded`,
/// `final_amount → 0`, `refund_amount → the whole paid amount`, `refund_status → 'pending'` (an
/// admin / real gateway later marks it 'processed'), and a `payment.refund_processed` event is
/// enqueued. Excluding the `refunded` row from revenue nets the booking to zero.
///
/// Idempotent via the `processed_events` ledger: the event_id is claimed in the same tx, so a
/// JetStream redelivery is a NoOp (the refund is never applied twice). NoOp when there is no PAID
/// pre-pay on file — an UNPAID cancel (e.g. cancelled at `accepted`, before the pre-pay) has
/// nothing to return. `status = 'completed'` in the lookup already excludes an already-`refunded`
/// row, so a double-refund is impossible even independent of the event-id claim.
#[tracing::instrument(skip(db), fields(booking_id = %booking_id, event_id = %event_id))]
pub async fn refund_on_cancellation(
    db: &sqlx::PgPool,
    event_id: Uuid,
    event_type: &str,
    booking_id: Uuid,
    correlation_id: Uuid,
) -> Result<CancelRefundOutcome, AppError> {
    let mut tx = db.begin().await?;

    // 1) claim the event_id (at-least-once dedup). A redelivery inserts nothing → NoOp.
    let claimed = sqlx::query(
        "INSERT INTO payment.processed_events (event_id, event_type) VALUES ($1, $2) \
         ON CONFLICT (event_id) DO NOTHING",
    )
    .bind(event_id)
    .bind(event_type)
    .execute(&mut *tx)
    .await?;
    if claimed.rows_affected() == 0 {
        tx.rollback().await?;
        tracing::debug!("cancellation refund already processed (idempotent NoOp)");
        return Ok(CancelRefundOutcome::NoOp);
    }

    // 2) the PAID pre-pay to return (FOR UPDATE locks it for the write).
    let sql = format!(
        "SELECT {PAYMENT_COLUMNS} FROM payment.payments \
         WHERE booking_id = $1 AND status = 'completed' LIMIT 1 FOR UPDATE"
    );
    let Some(payment) = sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(booking_id)
        .fetch_optional(&mut *tx)
        .await?
    else {
        // No paid pre-pay — an unpaid cancel (nothing to return). Commit the claim so a replay
        // stays a NoOp.
        tx.commit().await?;
        tracing::info!("cancellation/decline with no paid pre-pay; nothing to refund");
        return Ok(CancelRefundOutcome::NoOp);
    };

    // FULL refund — no work was done. Flip to `refunded` (excluded from revenue → nets to 0),
    // return the whole amount, and queue it for the refund workflow.
    let refund = payment.amount;
    sqlx::query(
        "UPDATE payment.payments \
           SET status = 'refunded'::payment.payment_status, final_amount = 0, \
               refund_amount = $2, refund_status = 'pending', updated_at = now() \
         WHERE id = $1",
    )
    .bind(payment.id)
    .bind(refund)
    .execute(&mut *tx)
    .await?;

    // customer_id/guard_id carried so notification can route the refund push to the payer.
    let payload = serde_json::json!({
        "payment_id": payment.id,
        "booking_id": booking_id,
        "customer_id": payment.customer_id,
        "guard_id": payment.guard_id,
        "refund_amount": refund,
        "final_amount": Decimal::ZERO,
    });
    enqueue_outbox(
        &mut tx,
        topics::PAYMENT_REFUND_PROCESSED,
        payload,
        correlation_id,
    )
    .await?;

    tx.commit().await?;
    tracing::info!(booking_id = %booking_id, %refund, "full-refunded pre-pay on cancellation/decline");
    Ok(CancelRefundOutcome::Refunded { refund })
}

/// Compensating FULL refund for a pre-pay that COMMITTED against a booking which had already gone
/// terminal (guard withdrew / customer cancelled) — the pay-vs-cancel RACE. When the cancellation
/// event is consumed BEFORE the payment row exists, `refund_on_cancellation` finds no row, NoOps,
/// and claims the event_id, so nothing ever refunds the late charge. The pay path re-reads the
/// booking after committing and calls THIS when it sees the booking terminal. Flips
/// `status 'completed' → 'refunded'` by booking_id (full refund, `refund_status='pending'`) and
/// emits `payment.refund_processed`. Idempotent via the `status='completed'` guard: if a concurrent
/// cancel-consumer (or a repeat) already refunded, the row is `refunded` and the lookup matches
/// nothing → NoOp, so no second refund_processed. NOT tied to an event_id (there is none — this is
/// triggered by the pay path's own re-read, not a cancel event).
#[tracing::instrument(skip(db), fields(booking_id = %booking_id))]
pub async fn refund_race_lost_prepay(
    db: &sqlx::PgPool,
    booking_id: Uuid,
    correlation_id: Uuid,
) -> Result<CancelRefundOutcome, AppError> {
    let mut tx = db.begin().await?;
    let sql = format!(
        "SELECT {PAYMENT_COLUMNS} FROM payment.payments \
         WHERE booking_id = $1 AND status = 'completed' LIMIT 1 FOR UPDATE"
    );
    let Some(payment) = sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(booking_id)
        .fetch_optional(&mut *tx)
        .await?
    else {
        // Already refunded (the cancel-consumer got there first, or a concurrent compensator) → NoOp.
        tx.rollback().await?;
        return Ok(CancelRefundOutcome::NoOp);
    };

    let refund = payment.amount;
    sqlx::query(
        "UPDATE payment.payments \
           SET status = 'refunded'::payment.payment_status, final_amount = 0, \
               refund_amount = $2, refund_status = 'pending', updated_at = now() \
         WHERE id = $1",
    )
    .bind(payment.id)
    .bind(refund)
    .execute(&mut *tx)
    .await?;

    let payload = serde_json::json!({
        "payment_id": payment.id,
        "booking_id": booking_id,
        "customer_id": payment.customer_id,
        "guard_id": payment.guard_id,
        "refund_amount": refund,
        "final_amount": Decimal::ZERO,
    });
    enqueue_outbox(
        &mut tx,
        topics::PAYMENT_REFUND_PROCESSED,
        payload,
        correlation_id,
    )
    .await?;

    tx.commit().await?;
    tracing::warn!(booking_id = %booking_id, %refund, "pay-vs-cancel race: compensating full-refund of a pre-pay that committed on a terminal booking");
    Ok(CancelRefundOutcome::Refunded { refund })
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

    /// Unwrap the payment out of a [`PrePayOutcome`] (tests don't care which arm here).
    fn payment_of(o: PrePayOutcome) -> PaymentResponse {
        match o {
            PrePayOutcome::Created(p) | PrePayOutcome::AlreadyPaid(p) => p,
        }
    }

    async fn pool() -> Option<sqlx::PgPool> {
        let url = std::env::var("DATABASE_URL").ok()?;
        PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .ok()
    }

    /// Real-Postgres integration test: a retried PRE-PAY does NOT double-charge — two POSTs
    /// for the same booking yield exactly ONE completed payment row and ONE outbox event, the
    /// first is `Created` and the second is `AlreadyPaid` with the same id. DATABASE_URL-gated
    /// (hermetic when unset). Run against a migrated DB:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-payment -- prepay_is_idempotent --nocapture
    #[tokio::test]
    async fn prepay_is_idempotent() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let guard_id = Some(Uuid::new_v4());
        let correlation = Uuid::new_v4();

        let first_out = prepay_idempotent(
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
        .expect("first pre-pay");
        assert!(
            matches!(first_out, PrePayOutcome::Created(_)),
            "first pre-pay is Created"
        );
        let first = payment_of(first_out);
        assert_eq!(first.status, "completed");
        assert_eq!(first.amount, dec("400.00"));
        assert_eq!(first.expected_total, Some(dec("400.00")));
        assert_eq!(first.guard_id, guard_id);

        // Retry — must be AlreadyPaid with the SAME payment, not a new one.
        let second_out = prepay_idempotent(
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
        .expect("retry pre-pay");
        assert!(
            matches!(second_out, PrePayOutcome::AlreadyPaid(_)),
            "repeat pre-pay is AlreadyPaid (no-op)"
        );
        let second = payment_of(second_out);
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

    /// Unwrap the payment out of a [`SlipPayOutcome`] (tests don't care which arm here).
    fn slip_payment_of(o: SlipPayOutcome) -> PaymentResponse {
        match o {
            SlipPayOutcome::Created(p) | SlipPayOutcome::AlreadyPaid(p) => p,
        }
    }

    /// Real-Postgres: a VERIFIED slip stamps the booking paid (method=promptpay_slip), records the
    /// slip + its trans_ref/reference_id, and emits exactly ONE `payment.completed`. Re-submitting
    /// the SAME accepted slip is an idempotent no-op (AlreadyPaid; same payment id; still one
    /// event). DATABASE_URL-gated. Run:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-payment -- slip_pay_is_idempotent --nocapture
    #[tokio::test]
    async fn slip_pay_settles_and_is_idempotent() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let guard_id = Some(Uuid::new_v4());
        let reference_id = Uuid::new_v4().to_string();
        let trans_ref = format!("TR-{}", Uuid::new_v4());

        let first = slip_payment_of(
            pay_with_slip(
                &pool,
                booking_id,
                customer_id,
                guard_id,
                dec("2000.00"),
                dec("2000.00"),
                &reference_id,
                &trans_ref,
                dec("2000.00"),
                "payment/x/slips/a.jpg",
                Uuid::new_v4(),
            )
            .await
            .expect("first slip pay"),
        );
        assert_eq!(first.status, "completed");
        assert_eq!(first.payment_method.as_deref(), Some("promptpay_slip"));
        assert_eq!(first.amount, dec("2000.00"));

        // The slip row was recorded with the trans_ref.
        let slip_count: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.payment_slips WHERE trans_ref = $1 AND payment_id = $2",
        )
        .bind(&trans_ref)
        .bind(first.id)
        .fetch_one(&pool)
        .await
        .expect("count slips");
        assert_eq!(slip_count, 1, "the verified slip is recorded once");

        // Re-submit the SAME accepted slip → AlreadyPaid, same payment, no second charge/event.
        let again = pay_with_slip(
            &pool,
            booking_id,
            customer_id,
            guard_id,
            dec("2000.00"),
            dec("2000.00"),
            &reference_id,
            &trans_ref,
            dec("2000.00"),
            "payment/x/slips/b.jpg",
            Uuid::new_v4(),
        )
        .await
        .expect("re-submit same slip");
        assert!(
            matches!(again, SlipPayOutcome::AlreadyPaid(_)),
            "re-submitting the same accepted slip is a no-op"
        );
        assert_eq!(slip_payment_of(again).id, first.id, "same payment returned");

        // exactly one payment.completed event for this booking.
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
        let _ = sqlx::query("DELETE FROM payment.payment_slips WHERE payment_id = $1")
            .bind(first.id)
            .execute(&pool)
            .await;
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

    /// Real-Postgres: the DEDUPE GUARANTEE — one slip can NEVER pay two bookings. The SAME
    /// trans_ref used for a SECOND, different booking is rejected by the UNIQUE constraint
    /// (typed SLIP_DUPLICATE), and that second booking ends up with NO payment row. DATABASE_URL-
    /// gated. Run:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-payment -- slip_dedupe_across_bookings --nocapture
    #[tokio::test]
    async fn slip_cannot_pay_two_bookings_dedupe() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_a = Uuid::new_v4();
        let booking_b = Uuid::new_v4();
        let trans_ref = format!("TR-{}", Uuid::new_v4());
        let ref_a = Uuid::new_v4().to_string();
        let ref_b = Uuid::new_v4().to_string();

        // Booking A pays with the slip — fine.
        let pay_a = slip_payment_of(
            pay_with_slip(
                &pool,
                booking_a,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                dec("2000.00"),
                dec("2000.00"),
                &ref_a,
                &trans_ref,
                dec("2000.00"),
                "payment/a/slips/a.jpg",
                Uuid::new_v4(),
            )
            .await
            .expect("A pays"),
        );

        // Booking B tries to reuse the SAME trans_ref (a different reference_id) → SLIP_DUPLICATE.
        let dup = pay_with_slip(
            &pool,
            booking_b,
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            dec("2000.00"),
            dec("2000.00"),
            &ref_b,
            &trans_ref, // REUSED
            dec("2000.00"),
            "payment/b/slips/b.jpg",
            Uuid::new_v4(),
        )
        .await;
        match dup {
            Err(AppError::ConflictCode { code, .. }) => {
                assert_eq!(code, crate::slip2go_client::SLIP_DUPLICATE_CODE)
            }
            other => panic!("expected SLIP_DUPLICATE, got {other:?}"),
        }

        // Booking B got NO payment row (the tx rolled back the payment insert too).
        let b_count: i64 =
            sqlx::query_scalar("SELECT count(*) FROM payment.payments WHERE booking_id = $1")
                .bind(booking_b)
                .fetch_one(&pool)
                .await
                .expect("count B");
        assert_eq!(
            b_count, 0,
            "the reused slip created NO payment for booking B"
        );

        // The reference_id UNIQUE is ALSO a guard: reusing ref_a on booking B (fresh trans_ref)
        // is likewise rejected.
        let dup_ref = pay_with_slip(
            &pool,
            booking_b,
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            dec("2000.00"),
            dec("2000.00"),
            &ref_a, // REUSED reference_id
            &format!("TR-{}", Uuid::new_v4()),
            dec("2000.00"),
            "payment/b/slips/c.jpg",
            Uuid::new_v4(),
        )
        .await;
        assert!(
            matches!(dup_ref, Err(AppError::ConflictCode { code, .. }) if code == crate::slip2go_client::SLIP_DUPLICATE_CODE),
            "a reused reference_id is also rejected"
        );

        // cleanup
        let _ = sqlx::query("DELETE FROM payment.payment_slips WHERE payment_id = $1")
            .bind(pay_a.id)
            .execute(&pool)
            .await;
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
        let pay_a = payment_of(
            prepay_idempotent(
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
            .expect("charge A"),
        );
        let pay_b = payment_of(
            prepay_idempotent(
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
            .expect("charge B"),
        );

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

    /// Real-Postgres: a settle that REFUNDS the overpay lands the payment in the admin refund
    /// queue (`refund_status='pending'`, `amount` = the refund owed), and the count matches the
    /// filter. A `status=processed` filter excludes the pending row (proves the filter), and a
    /// payment with no refund never appears. DATABASE_URL-gated. Run:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-payment -- refund_queue_surfaces_pending --nocapture
    #[tokio::test]
    async fn refund_queue_surfaces_pending_refunds() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        // Booking A: pre-pay 2000, work 2h of 4h → refund 1000 owed (refund_status='pending').
        let booking_a = Uuid::new_v4();
        let event_a = Uuid::new_v4();
        let pay_a = payment_of(
            prepay_idempotent(
                &pool,
                booking_a,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                dec("2000.00"),
                dec("2000.00"),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay A"),
        );
        reconcile_on_completion(
            &pool,
            event_a,
            topics::BOOKING_COMPLETED,
            booking_a,
            dec("500"),
            4,
            1,
            Decimal::ZERO,
            Some(7200),
            Uuid::new_v4(),
        )
        .await
        .expect("reconcile A");

        // Booking B: pre-pay 2000, work the full 4h → no refund (must NOT appear in the queue).
        let booking_b = Uuid::new_v4();
        let event_b = Uuid::new_v4();
        let pay_b = payment_of(
            prepay_idempotent(
                &pool,
                booking_b,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                dec("2000.00"),
                dec("2000.00"),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay B"),
        );
        reconcile_on_completion(
            &pool,
            event_b,
            topics::BOOKING_COMPLETED,
            booking_b,
            dec("500"),
            4,
            1,
            Decimal::ZERO,
            Some(14400),
            Uuid::new_v4(),
        )
        .await
        .expect("reconcile B");

        // pending queue includes A's refund (amount = the owed refund) but not B (no refund).
        let pending = admin_list_refund_queue(&pool, Some("pending"), 200, 0)
            .await
            .expect("list pending");
        let row_a = pending
            .iter()
            .find(|r| r.payment_id == pay_a.id)
            .expect("A in pending queue");
        assert_eq!(row_a.booking_id, booking_a);
        assert_eq!(row_a.amount, dec("1000.00"), "amount = the refund owed");
        assert_eq!(row_a.status, "pending");
        assert!(
            !pending.iter().any(|r| r.payment_id == pay_b.id),
            "B (no refund) must not be in the queue"
        );

        // processed filter excludes the pending row (proves the status filter narrows).
        let processed = admin_list_refund_queue(&pool, Some("processed"), 200, 0)
            .await
            .expect("list processed");
        assert!(
            !processed.iter().any(|r| r.payment_id == pay_a.id),
            "a pending refund must not appear under status=processed"
        );

        // count(pending) ≥ 1 and matches the same predicate as the list.
        let count = admin_count_refund_queue(&pool, Some("pending"))
            .await
            .expect("count pending");
        assert!(count >= 1, "pending count includes A");

        // cleanup
        let _ = sqlx::query("DELETE FROM payment.processed_events WHERE event_id = ANY($1)")
            .bind(vec![event_a, event_b])
            .execute(&pool)
            .await;
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

    /// Real-Postgres: PRE-PAY the full estimate, then RECONCILE on completion. Worked < booked →
    /// the overpay is REFUNDED (final_amount + refund_amount set, refund_status='pending', a
    /// `payment.refund_processed` event emitted) and the base is NOT re-charged. A redelivered
    /// completion is idempotent (the event is claimed once → second call is a NoOp, no second
    /// refund). DATABASE_URL-gated. Run:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-payment -- reconcile_refunds_overpay --nocapture
    #[tokio::test]
    async fn reconcile_refunds_overpay_and_is_idempotent() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        // Pre-pay the estimate 500×4×1 + 0 = 2000.00.
        let paid = payment_of(
            prepay_idempotent(
                &pool,
                booking_id,
                customer_id,
                Some(Uuid::new_v4()),
                dec("2000.00"),
                dec("2000.00"),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );

        // Complete after working only 2h of 4h → actual 1000.00 → refund 1000.00.
        let out = reconcile_on_completion(
            &pool,
            event_id,
            topics::BOOKING_COMPLETED,
            booking_id,
            dec("500"),
            4,
            1,
            Decimal::ZERO,
            Some(7200),
            Uuid::new_v4(),
        )
        .await
        .expect("reconcile");
        assert_eq!(
            out,
            SettleOutcome::Refunded {
                final_amount: dec("1000.00"),
                refund: dec("1000.00"),
            }
        );

        // The row reflects the refund; the base was never re-charged (amount unchanged).
        let row: (Decimal, Option<Decimal>, Option<Decimal>, Option<String>) = sqlx::query_as(
            "SELECT amount, final_amount, refund_amount, refund_status \
             FROM payment.payments WHERE id = $1",
        )
        .bind(paid.id)
        .fetch_one(&pool)
        .await
        .expect("read row");
        assert_eq!(row.0, dec("2000.00"), "amount (pre-paid) unchanged");
        assert_eq!(row.1, Some(dec("1000.00")), "final_amount = actual bill");
        assert_eq!(row.2, Some(dec("1000.00")), "refund_amount = overpay");
        assert_eq!(row.3.as_deref(), Some("pending"));

        // exactly ONE refund_processed event.
        let refunds: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::PAYMENT_REFUND_PROCESSED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count refunds");
        assert_eq!(refunds, 1, "exactly one refund event");

        // Replay the SAME completion event → idempotent NoOp (no second refund).
        let replay = reconcile_on_completion(
            &pool,
            event_id,
            topics::BOOKING_COMPLETED,
            booking_id,
            dec("500"),
            4,
            1,
            Decimal::ZERO,
            Some(7200),
            Uuid::new_v4(),
        )
        .await
        .expect("replay reconcile");
        assert_eq!(replay, SettleOutcome::NoOp, "replay is a NoOp");
        let refunds2: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::PAYMENT_REFUND_PROCESSED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count refunds after replay");
        assert_eq!(refunds2, 1, "still exactly one refund (idempotent)");

        // cleanup
        let _ = sqlx::query("DELETE FROM payment.processed_events WHERE event_id = $1")
            .bind(event_id)
            .execute(&pool)
            .await;
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

    /// Real-Postgres: reconcile PERSISTS `actual_hours` (the clamped worked hours) — the column was
    /// declared but never written, which is why the guard-earnings screen (base × BOOKED hours)
    /// overstated pay vs the customer's reconciled net. And `guard_earnings` returns exactly that
    /// row so the guard app can pay `base × actual_hours`. DATABASE_URL-gated.
    #[tokio::test]
    async fn reconcile_persists_actual_hours_and_guard_earnings_returns_it() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        payment_of(
            prepay_idempotent(
                &pool,
                booking_id,
                customer_id,
                Some(guard_id),
                dec("2000.00"),
                dec("2000.00"),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );

        // Worked 2h of 4h booked → actual_hours must persist as 2.00.
        reconcile_on_completion(
            &pool,
            event_id,
            topics::BOOKING_COMPLETED,
            booking_id,
            dec("500"),
            4,
            1,
            Decimal::ZERO,
            Some(7200),
            Uuid::new_v4(),
        )
        .await
        .expect("reconcile");

        let ah: Option<Decimal> =
            sqlx::query_scalar("SELECT actual_hours FROM payment.payments WHERE booking_id = $1")
                .bind(booking_id)
                .fetch_one(&pool)
                .await
                .expect("read actual_hours");
        assert_eq!(ah, Some(dec("2.00")), "actual_hours persisted at reconcile");

        // The guard's earnings ledger surfaces the booking + its actual worked hours.
        let earnings = guard_earnings(&pool, guard_id).await.expect("earnings");
        let row = earnings
            .iter()
            .find(|e| e.booking_id == booking_id)
            .expect("the completed job appears in the guard's earnings");
        assert_eq!(row.actual_hours, Some(dec("2.00")));

        // A DIFFERENT guard sees nothing for this booking (own-only scoping).
        let other = guard_earnings(&pool, Uuid::new_v4()).await.expect("other");
        assert!(!other.iter().any(|e| e.booking_id == booking_id));

        // cleanup
        let _ = sqlx::query("DELETE FROM payment.processed_events WHERE event_id = $1")
            .bind(event_id)
            .execute(&pool)
            .await;
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

    /// Real-Postgres: PRE-PAY a booking, then CANCEL/DECLINE it before it ran → the WHOLE pre-pay is
    /// FULL-refunded (status → refunded, refund_amount = the full amount, final_amount 0,
    /// refund_status='pending', a `payment.refund_processed` emitted). Idempotent (a redelivery is a
    /// NoOp). An UNPAID booking (no pre-pay on file) → NoOp. DATABASE_URL-gated.
    #[tokio::test]
    async fn refund_on_cancellation_full_refunds_and_is_idempotent() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        // A paid pre-pay of 2000.00.
        let paid = payment_of(
            prepay_idempotent(
                &pool,
                booking_id,
                customer_id,
                Some(Uuid::new_v4()),
                dec("2000.00"),
                dec("2000.00"),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );

        // Guard withdraws en_route (booking.declined) → the WHOLE pre-pay is refunded.
        let out = refund_on_cancellation(
            &pool,
            event_id,
            topics::BOOKING_DECLINED,
            booking_id,
            Uuid::new_v4(),
        )
        .await
        .expect("refund");
        assert_eq!(
            out,
            CancelRefundOutcome::Refunded {
                refund: dec("2000.00")
            }
        );

        // The row: status refunded, full refund_amount, final_amount 0, pending refund workflow.
        let row: (String, Option<Decimal>, Option<Decimal>, Option<String>) = sqlx::query_as(
            "SELECT status::text, final_amount, refund_amount, refund_status \
             FROM payment.payments WHERE id = $1",
        )
        .bind(paid.id)
        .fetch_one(&pool)
        .await
        .expect("read row");
        assert_eq!(row.0, "refunded", "a FULL refund flips status → refunded");
        assert!(
            row.1.expect("final_amount").is_zero(),
            "final_amount 0 (no work)"
        );
        assert_eq!(
            row.2,
            Some(dec("2000.00")),
            "refund_amount = the full pre-pay"
        );
        assert_eq!(row.3.as_deref(), Some("pending"));

        // Shows in the admin refund queue with amount = the full refund.
        let pending = admin_list_refund_queue(&pool, Some("pending"), 200, 0)
            .await
            .expect("queue");
        let qrow = pending
            .iter()
            .find(|r| r.payment_id == paid.id)
            .expect("in refund queue");
        assert_eq!(qrow.amount, dec("2000.00"));

        // exactly ONE refund_processed event.
        let refunds: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::PAYMENT_REFUND_PROCESSED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count refunds");
        assert_eq!(refunds, 1, "exactly one refund event");

        // Replay the SAME event → idempotent NoOp (no second refund).
        let replay = refund_on_cancellation(
            &pool,
            event_id,
            topics::BOOKING_DECLINED,
            booking_id,
            Uuid::new_v4(),
        )
        .await
        .expect("replay");
        assert_eq!(replay, CancelRefundOutcome::NoOp, "replay is a NoOp");
        let refunds2: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::PAYMENT_REFUND_PROCESSED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count refunds after replay");
        assert_eq!(refunds2, 1, "still exactly one refund (idempotent)");

        // An UNPAID booking (no pre-pay on file) → NoOp, nothing to refund.
        let unpaid_booking = Uuid::new_v4();
        let noop_event = Uuid::new_v4();
        let noop = refund_on_cancellation(
            &pool,
            noop_event,
            topics::BOOKING_CANCELLED,
            unpaid_booking,
            Uuid::new_v4(),
        )
        .await
        .expect("noop");
        assert_eq!(
            noop,
            CancelRefundOutcome::NoOp,
            "no pre-pay → nothing to refund"
        );

        // cleanup
        let _ = sqlx::query("DELETE FROM payment.processed_events WHERE event_id = ANY($1)")
            .bind(vec![event_id, noop_event])
            .execute(&pool)
            .await;
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

    /// Real-Postgres: PRE-PAY without a tip, then complete WITH a tip bump → actual > paid, so the
    /// shortfall is recorded as the higher final_amount (no refund event), and the base is never
    /// re-charged. DATABASE_URL-gated. Run:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-payment -- reconcile_records_extra --nocapture
    #[tokio::test]
    async fn reconcile_records_extra_when_actual_exceeds_paid() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        // Pre-pay 500×4×1 + 0 = 2000.00 (no tip).
        let paid = payment_of(
            prepay_idempotent(
                &pool,
                booking_id,
                customer_id,
                Some(Uuid::new_v4()),
                dec("2000.00"),
                dec("2000.00"),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );

        // Complete the full 4h WITH a 300 tip → actual 2300.00, extra 300.00 owed.
        let out = reconcile_on_completion(
            &pool,
            event_id,
            topics::BOOKING_COMPLETED,
            booking_id,
            dec("500"),
            4,
            1,
            dec("300"),
            Some(14400),
            Uuid::new_v4(),
        )
        .await
        .expect("reconcile");
        assert_eq!(
            out,
            SettleOutcome::ExtraCharged {
                final_amount: dec("2300.00"),
                extra: dec("300.00"),
            }
        );

        let row: (Decimal, Option<Decimal>, Option<Decimal>) = sqlx::query_as(
            "SELECT amount, final_amount, refund_amount FROM payment.payments WHERE id = $1",
        )
        .bind(paid.id)
        .fetch_one(&pool)
        .await
        .expect("read row");
        assert_eq!(row.0, dec("2000.00"), "amount (pre-paid base) unchanged");
        assert_eq!(row.1, Some(dec("2300.00")), "final_amount = actual + tip");
        assert!(row.2.is_none(), "no refund on an under-payment");

        // No refund event emitted.
        let refunds: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::PAYMENT_REFUND_PROCESSED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count refunds");
        assert_eq!(refunds, 0, "an extra charge emits no refund event");

        // cleanup
        let _ = sqlx::query("DELETE FROM payment.processed_events WHERE event_id = $1")
            .bind(event_id)
            .execute(&pool)
            .await;
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
