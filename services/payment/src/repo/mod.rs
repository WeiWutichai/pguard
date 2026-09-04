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
//!
//! MONEY-COLUMN INVARIANT every write path here maintains (relied on by the revenue/spend reports
//! and by the tax invoice): `subtotal + vat_amount = COALESCE(final_amount, amount)`, i.e. the VAT
//! split always describes the CURRENTLY SETTLED bill — the estimate at pre-pay, the prorated bill
//! after the completion reconcile, the retained cancellation fee after a cancel. Rows written
//! before VAT existed have a NULL split and are read with `COALESCE(..., 0)`.

use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde_json::Value;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::topics;
use shared_events::EventEnvelope;

use crate::domain::payout::PayoutSelection;
use crate::domain::ChargeTerms;
use crate::models::{
    CustomerSpend, NewPayoutBatch, PaymentResponse, PayoutConfigRow, RefundQueueItem, RevenuePoint,
    UnpaidPayoutRow, UpdatePayoutConfigRequest,
};

/// The payment row as clients see it. `grand_total` is DERIVED, not stored: the VAT split
/// (`subtotal + vat_amount`) always equals the currently-settled bill, and pre-VAT rows (both
/// columns NULL) fall back to the charged `amount` — so the field is never NULL and is always
/// "the payable figure", whatever era the row is from.
const PAYMENT_COLUMNS: &str = "id, booking_id, customer_id, guard_id, amount, expected_total, \
     subtotal, vat_amount, COALESCE(subtotal + vat_amount, amount) AS grand_total, \
     cancellation_fee_charged, overpaid_amount, payment_method, status::text AS status, \
     final_amount, refund_amount, actual_hours, refund_status, paid_at, created_at, updated_at";

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
/// `actual_hours` worked (persisted at reconcile) and the `commission_percent` deducted from that
/// job's pay (snapshotted from the booking at charge time). A `refunded` row (a cancelled/withdrawn
/// job — including one where the platform retained a cancellation fee) is excluded: the guard
/// earned nothing there, and it is not a `completed` job on their side either.
///
/// NB `status = 'completed'` is the PAYMENT status (stamped at pre-pay), not the booking's — a job
/// still in progress is already `completed` here. That is pre-existing behaviour and deliberately
/// left alone; this query only carries the new column.
///
/// The client pairs each `booking_id` with the `base_fee` from its own booking feed and pays
/// `base_fee × actual_hours` (falling back to booked hours when `actual_hours` is NULL) minus
/// `commission_percent`, so the guard's earnings reflect hours ACTUALLY worked — matching the
/// customer's reconciled net — and show what the platform took.
pub async fn guard_earnings(
    db: &sqlx::PgPool,
    guard_id: Uuid,
) -> Result<Vec<crate::models::GuardEarningRow>, AppError> {
    let rows = sqlx::query_as::<_, crate::models::GuardEarningRow>(
        "SELECT booking_id, actual_hours, commission_percent FROM payment.payments \
         WHERE guard_id = $1 AND status = 'completed' ORDER BY created_at DESC LIMIT 100",
    )
    .bind(guard_id)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// The UNPAID guard-payout backlog: every reconciled, guard-assigned, `completed` payment whose
/// `booking_id` is NOT yet in `payout_batch_items` (the paid-marker). `actual_hours IS NOT NULL` is
/// the "job finished + reconciled" signal (it is stamped at completion reconcile) — a payment is
/// `completed` at PRE-PAY, so that status alone would include in-progress jobs. Ordered by guard so
/// the aggregator can group.
///
/// `sel` narrows the run (see [`PayoutSelection`]): to the guards the admin ticked, and/or to jobs
/// finished within a day window. An all-`None` selection is the default whole-backlog run (NO
/// limit — one file pays every payable guard). The window is compared in **Thai local days**
/// (`Asia/Bangkok`), inclusive on both ends, against `updated_at` — the timestamp the completion
/// reconcile stamps when it writes `actual_hours`, i.e. when the job became payable.
pub async fn unpaid_payout_rows(
    db: &sqlx::PgPool,
    sel: &PayoutSelection,
) -> Result<Vec<UnpaidPayoutRow>, AppError> {
    let rows = sqlx::query_as::<_, UnpaidPayoutRow>(
        "SELECT p.booking_id, p.guard_id, p.actual_hours, p.commission_percent \
         FROM payment.payments p \
         WHERE p.status = 'completed' \
           AND p.guard_id IS NOT NULL \
           AND p.actual_hours IS NOT NULL \
           AND ($1::uuid[] IS NULL OR p.guard_id = ANY($1)) \
           AND ($2::date IS NULL OR (p.updated_at AT TIME ZONE 'Asia/Bangkok')::date >= $2) \
           AND ($3::date IS NULL OR (p.updated_at AT TIME ZONE 'Asia/Bangkok')::date <= $3) \
           AND NOT EXISTS ( \
               SELECT 1 FROM payment.payout_batch_items i WHERE i.booking_id = p.booking_id) \
         ORDER BY p.guard_id, p.created_at",
    )
    .bind(sel.guard_ids.as_deref())
    .bind(sel.from)
    .bind(sel.to)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Read the single-row payout config (`GET /admin/payouts/config`); the "unset" default (blank
/// debit accounts + the standard ภ.ง.ด.53 terms) when no row exists yet, so the GET never 404s.
pub async fn get_payout_config(db: &sqlx::PgPool) -> Result<PayoutConfigRow, AppError> {
    let row: Option<PayoutConfigRow> = sqlx::query_as(
        "SELECT debit_account, fee_debit_account, wht_form_type_code, wht_pay_type_code, \
                wht_income_type_code, wht_income_desc, wht_rate_percent, product_code, updated_at \
         FROM payment.payout_config WHERE id = TRUE",
    )
    .fetch_optional(db)
    .await?;
    Ok(row.unwrap_or_else(PayoutConfigRow::unset))
}

/// Upsert the single-row payout config (`PUT`). `id = TRUE` + the singleton CHECK pin it to one row;
/// each field COALESCEs to the sent value or KEEPS the stored one (`None` → unchanged), so an admin
/// can save incrementally. On first write the unset `NOT NULL DEFAULT` columns take the schema
/// defaults. `updated_by` records the acting admin; `updated_at = now()`.
pub async fn upsert_payout_config(
    db: &sqlx::PgPool,
    req: &UpdatePayoutConfigRequest,
    admin_id: Uuid,
) -> Result<PayoutConfigRow, AppError> {
    let row: PayoutConfigRow = sqlx::query_as(
        "INSERT INTO payment.payout_config \
             (id, debit_account, fee_debit_account, wht_form_type_code, wht_pay_type_code, \
              wht_income_type_code, wht_income_desc, wht_rate_percent, updated_by, updated_at) \
         VALUES (TRUE, $1, $2, \
                 COALESCE($3, '53'), COALESCE($4, '1'), COALESCE($5, '5'), \
                 COALESCE($6, 'ค่าบริการรักษาความปลอดภัย'), COALESCE($7, 3), $8, now()) \
         ON CONFLICT (id) DO UPDATE SET \
             debit_account        = COALESCE($1, payment.payout_config.debit_account), \
             fee_debit_account    = COALESCE($2, payment.payout_config.fee_debit_account), \
             wht_form_type_code   = COALESCE($3, payment.payout_config.wht_form_type_code), \
             wht_pay_type_code    = COALESCE($4, payment.payout_config.wht_pay_type_code), \
             wht_income_type_code = COALESCE($5, payment.payout_config.wht_income_type_code), \
             wht_income_desc      = COALESCE($6, payment.payout_config.wht_income_desc), \
             wht_rate_percent     = COALESCE($7, payment.payout_config.wht_rate_percent), \
             updated_by           = $8, \
             updated_at           = now() \
         RETURNING debit_account, fee_debit_account, wht_form_type_code, wht_pay_type_code, \
                   wht_income_type_code, wht_income_desc, wht_rate_percent, product_code, updated_at",
    )
    .bind(req.debit_account.as_deref())
    .bind(req.fee_debit_account.as_deref())
    .bind(req.wht_form_type_code.as_deref())
    .bind(req.wht_pay_type_code.as_deref())
    .bind(req.wht_income_type_code.as_deref())
    .bind(req.wht_income_desc.as_deref())
    .bind(req.wht_rate_percent)
    .bind(admin_id)
    .fetch_one(db)
    .await?;
    Ok(row)
}

/// Persist a generated payout batch: the `payout_batches` header + all `payout_batch_items` in ONE
/// transaction. The `UNIQUE(booking_id)` on the items is the atomic paid-marker — if any booking in
/// this batch was ALREADY paid (a concurrent export won the race), the item insert violates the
/// unique, the whole tx ROLLS BACK, and a typed 409 is returned so nothing is double-paid. Returns
/// the new batch id.
pub async fn insert_payout_batch(
    db: &sqlx::PgPool,
    batch: &NewPayoutBatch,
) -> Result<Uuid, AppError> {
    let mut tx = db.begin().await?;
    let batch_id: Uuid = sqlx::query_scalar(
        "INSERT INTO payment.payout_batches \
             (file_ref, system_ref, batch_ref, value_date, total_amount, recipient_count, created_by) \
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id",
    )
    .bind(&batch.file_ref)
    .bind(&batch.system_ref)
    .bind(&batch.batch_ref)
    .bind(batch.value_date)
    .bind(batch.total_amount)
    .bind(batch.items.len() as i32)
    .bind(batch.created_by)
    .fetch_one(&mut *tx)
    .await?;

    for item in &batch.items {
        let res = sqlx::query(
            "INSERT INTO payment.payout_batch_items \
                 (batch_id, booking_id, guard_id, income, wht, transfer_amount) \
             VALUES ($1, $2, $3, $4, $5, $6)",
        )
        .bind(batch_id)
        .bind(item.booking_id)
        .bind(item.guard_id)
        .bind(item.income)
        .bind(item.wht)
        .bind(item.transfer_amount)
        .execute(&mut *tx)
        .await;
        if let Err(e) = res {
            tx.rollback().await?;
            // A unique violation means the booking was paid out by a concurrent export — refuse the
            // whole batch rather than pay anyone twice; the admin re-previews the (now smaller) backlog.
            if let sqlx::Error::Database(db_err) = &e {
                if db_err.is_unique_violation() {
                    return Err(AppError::ConflictCode {
                        code: "PAYOUT_ALREADY_PAID",
                        message: "One or more jobs were already paid out; re-run the preview."
                            .to_string(),
                    });
                }
            }
            return Err(e.into());
        }
    }
    tx.commit().await?;
    Ok(batch_id)
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

/// Net revenue expression shared by the series + total queries. Kept as ONE constant so the
/// per-day chart and the MoM total can never disagree.
///
/// DECISION (2026-08-10): platform revenue is **VAT-EXCLUSIVE**. The 7% is collected FOR the
/// Revenue Department — it is a liability the moment we take it, not income — so counting it as
/// revenue would inflate every chart by 7% and make the number useless for deciding anything
/// (margin, runway, commission policy). We therefore subtract `vat_amount` from each row.
///
/// Per row we count what the platform ULTIMATELY KEPT, VAT-inclusive, then strip its VAT:
///  - `COALESCE(final_amount, amount)` — `final_amount` is the SETTLED bill and is ALREADY net of
///    any refund (reconcile sets `final = paid − refund`; a cancellation sets it to the retained
///    cancellation fee, or 0 for a full refund). `amount` is the fallback for a charge that has
///    not been settled yet. A separate `− refund_amount` term would therefore subtract the same
///    money twice: the old expression netted a half-worked 2000-job (final 1000, refund 1000) to
///    ZERO instead of 1000. Refunds are still fully reflected — through `final_amount`.
///  - `− COALESCE(vat_amount, 0)` — the VAT inside that kept amount. Every write path keeps the
///    split in step with `final_amount` (INVARIANT: `subtotal + vat_amount = COALESCE(final_amount,
///    amount)`), so this term is exactly the settled row's `subtotal`. Pre-VAT rows have a NULL
///    split → COALESCE 0 → they count in full, which is correct: no VAT was ever charged on them.
///  - `status <> 'pending'` — a reserved-but-uncaptured charge is not money. `refunded` rows are
///    now INCLUDED (they contribute their `final_amount`: 0 for a full refund, the retained
///    cancellation fee otherwise) — a fee we keep on a cancellation IS revenue, and the old
///    blanket exclusion would have silently dropped it.
const NET_REVENUE_EXPR: &str = "COALESCE(SUM(CASE WHEN status <> 'pending' \
     THEN COALESCE(final_amount, amount) - COALESCE(vat_amount, 0) ELSE 0 END), 0)";

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

/// Per-customer lifetime spend: what each customer is ultimately OUT OF POCKET, summed over their
/// settled payments. Powers the web-admin customers page's spend column. No owner filter — the
/// admin-role gate is the API layer's job.
///
/// Same per-row "what was kept" basis as [`NET_REVENUE_EXPR`] (`final_amount` is already net of any
/// refund; no second `− refund_amount` term, which used to net a half-worked job to zero) — but
/// deliberately VAT-INCLUSIVE: the customer really did pay the VAT, even though it is not the
/// platform's revenue. `pending` (never captured) is excluded; a `refunded` row contributes its
/// `final_amount`, i.e. 0 for a full refund and the retained cancellation fee otherwise. The status
/// enum cast mirrors `admin_list_payments`' `::payment.payment_status`.
pub async fn customer_spend(db: &sqlx::PgPool) -> Result<Vec<CustomerSpend>, AppError> {
    let rows = sqlx::query_as::<_, CustomerSpend>(
        "SELECT customer_id, \
                COALESCE(SUM(COALESCE(final_amount, amount)), 0)::numeric AS total \
         FROM payment.payments \
         WHERE status <> 'pending'::payment.payment_status \
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

/// Read the existing completed payment for a booking INSIDE the caller's transaction (so the
/// second-slip decision sees a consistent view with the ON CONFLICT probe above it).
async fn completed_for_booking_tx(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    booking_id: Uuid,
) -> Result<Option<PaymentResponse>, AppError> {
    let sql = format!(
        "SELECT {PAYMENT_COLUMNS} FROM payment.payments \
         WHERE booking_id = $1 AND status = 'completed' LIMIT 1"
    );
    Ok(sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(booking_id)
        .fetch_optional(&mut **tx)
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
/// v2 is PRE-PAY: the customer pays the ESTIMATE (`base_fee × hours × guard_count + tip`, **plus
/// 7% VAT**) once a guard has accepted; that payment GATES the booking's `en_route` transition
/// (booking learns it is paid by consuming `payment.completed`). A repeat POST cannot double-charge:
/// on conflict the INSERT returns no row, we roll the (empty) tx back, and return
/// [`PrePayOutcome::AlreadyPaid`] (no second event emitted). `amount == expected_total ==
/// terms.breakdown.grand_total` — all server-computed from booking's authoritative read, never a
/// client value — and the VAT split behind it is persisted alongside for the tax invoice. The
/// booking's commission / cancellation-fee snapshot rides along on the row so the guard's earnings
/// ledger and the (HTTP-less) cancellation consumer never need a cross-service read. The
/// completion-time SETTLE ([`reconcile_on_completion`]) later refunds/charges the difference vs the
/// actual hours.
#[tracing::instrument(skip(db, terms), fields(booking_id = %booking_id, customer_id = %customer_id))]
pub async fn prepay_idempotent(
    db: &sqlx::PgPool,
    booking_id: Uuid,
    customer_id: Uuid,
    guard_id: Option<Uuid>,
    terms: &ChargeTerms,
    payment_method: &str,
    correlation_id: Uuid,
) -> Result<PrePayOutcome, AppError> {
    let amount = terms.breakdown.grand_total;
    let mut tx = db.begin().await?;

    // 1) the business change — idempotent insert. ON CONFLICT (the UNIQUE partial index)
    //    DO NOTHING means a concurrent/repeat pre-pay inserts nothing. `amount` == `expected_total`
    //    == the PRE-PAY estimate (VAT included); the actual-hours SETTLE happens later in
    //    reconcile_on_completion, which rewrites subtotal/vat_amount to the settled figures.
    let sql = format!(
        "INSERT INTO payment.payments \
           (booking_id, customer_id, guard_id, amount, expected_total, subtotal, vat_amount, \
            commission_percent, cancellation_fee, payment_method, status, paid_at) \
         VALUES ($1, $2, $3, $4, $4, $5, $6, $7, $8, $9, 'completed'::payment.payment_status, now()) \
         ON CONFLICT (booking_id) WHERE status = 'completed' DO NOTHING \
         RETURNING {PAYMENT_COLUMNS}"
    );
    let inserted = sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(booking_id)
        .bind(customer_id)
        .bind(guard_id)
        .bind(amount)
        .bind(terms.breakdown.subtotal)
        .bind(terms.breakdown.vat)
        .bind(terms.commission_percent)
        .bind(terms.cancellation_fee)
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
    /// Idempotent no-op: this booking was already paid and the SAME accepted slip was re-submitted.
    /// The existing payment is returned; nothing re-charged.
    AlreadyPaid(PaymentResponse),
    /// A SECOND, DIFFERENT verified transfer arrived for an already-paid booking (a customer
    /// double-pay). The extra transfer was RECORDED as an unapplied, refundable slip (the money is
    /// not lost) — the caller surfaces a typed conflict and KEEPS the uploaded image as evidence.
    /// The existing (applied) payment is carried for the response.
    ExtraTransferRecorded(PaymentResponse),
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
#[tracing::instrument(skip(db, terms), fields(booking_id = %booking_id, customer_id = %customer_id))]
#[allow(clippy::too_many_arguments)]
pub async fn pay_with_slip(
    db: &sqlx::PgPool,
    booking_id: Uuid,
    customer_id: Uuid,
    guard_id: Option<Uuid>,
    terms: &ChargeTerms,
    reference_id: &str,
    trans_ref: &str,
    slip_amount: Decimal,
    slip_key: &str,
    correlation_id: Uuid,
) -> Result<SlipPayOutcome, AppError> {
    let amount = terms.breakdown.grand_total;
    // OVERPAY: the customer may transfer MORE than the estimate (the re-validation accepts
    // `slip_amount >= estimate`). We persist that excess so every refund path returns what was
    // ACTUALLY transferred (`amount + overpaid_amount`), not just the estimate. `slip_amount` is
    // rounded to the column scale; a slip below the estimate never reaches here (the handler rejects
    // it as SLIP_AMOUNT_TOO_LOW), so this is `>= 0`.
    let overpaid = (slip_amount.round_dp(2) - amount).max(Decimal::ZERO);
    let mut tx = db.begin().await?;

    // 1) idempotent payment insert. ON CONFLICT (one completed per booking) DO NOTHING. Identical
    //    money shape to the simulated pre-pay: `amount` = `expected_total` = the VAT-INCLUSIVE
    //    grand total, with its split + the booking's commission/cancellation snapshot alongside,
    //    plus the `overpaid_amount` rider (the excess above the estimate — always refundable).
    let sql = format!(
        "INSERT INTO payment.payments \
           (booking_id, customer_id, guard_id, amount, expected_total, subtotal, vat_amount, \
            commission_percent, cancellation_fee, overpaid_amount, payment_method, status, paid_at) \
         VALUES ($1, $2, $3, $4, $4, $5, $6, $7, $8, $9, $10, 'completed'::payment.payment_status, now()) \
         ON CONFLICT (booking_id) WHERE status = 'completed' DO NOTHING \
         RETURNING {PAYMENT_COLUMNS}"
    );
    let inserted = sqlx::query_as::<_, PaymentResponse>(&sql)
        .bind(booking_id)
        .bind(customer_id)
        .bind(guard_id)
        .bind(amount)
        .bind(terms.breakdown.subtotal)
        .bind(terms.breakdown.vat)
        .bind(terms.commission_percent)
        .bind(terms.cancellation_fee)
        .bind(overpaid)
        .bind(SLIP_PAYMENT_METHOD)
        .fetch_optional(&mut *tx)
        .await?;

    let Some(payment) = inserted else {
        // The booking already has a completed payment. Two cases, distinguished by the incoming
        // trans_ref vs. the slip ALREADY APPLIED to this booking:
        //  - SAME trans_ref → a benign re-submit of the accepted slip → AlreadyPaid (no re-charge).
        //  - DIFFERENT trans_ref → a SECOND, REAL transfer for an already-paid booking (a double-pay).
        //    Returning 200 here (the old behaviour) silently LOST that transfer. Instead record it as
        //    an UNAPPLIED slip (`applied=false`, `refund_status='pending'`) so the money is tracked +
        //    refundable and its transRef/referenceId are reserved against reuse, then surface a typed
        //    conflict. The UNIQUE(trans_ref)/(reference_id) still guards cross-booking reuse.
        let existing = completed_for_booking_tx(&mut tx, booking_id)
            .await?
            .ok_or_else(|| {
                AppError::Conflict("Payment already exists for this booking".to_string())
            })?;

        let same_slip: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM payment.payment_slips \
             WHERE booking_id = $1 AND applied = TRUE AND trans_ref = $2)",
        )
        .bind(booking_id)
        .bind(trans_ref)
        .fetch_one(&mut *tx)
        .await?;

        if same_slip {
            // Benign idempotent re-submit of the SAME accepted slip — no new money.
            tx.rollback().await?;
            return Ok(SlipPayOutcome::AlreadyPaid(existing));
        }

        // A DIFFERENT verified transfer — a real second payment. Record it as unapplied (refundable).
        let extra_insert = sqlx::query(
            "INSERT INTO payment.payment_slips \
               (payment_id, booking_id, reference_id, trans_ref, amount, slip_key, applied, refund_status) \
             VALUES ($1, $2, $3, $4, $5, $6, FALSE, 'pending')",
        )
        .bind(existing.id)
        .bind(booking_id)
        .bind(reference_id)
        .bind(trans_ref)
        .bind(slip_amount.round_dp(2))
        .bind(slip_key)
        .execute(&mut *tx)
        .await;

        return match extra_insert {
            Ok(_) => {
                tx.commit().await?;
                tracing::warn!(
                    %booking_id, %trans_ref, %slip_amount,
                    "second DIFFERENT verified transfer for an already-paid booking — recorded as an unapplied (refundable) slip"
                );
                Ok(SlipPayOutcome::ExtraTransferRecorded(existing))
            }
            // The extra slip's transRef/referenceId already exists (this exact slip already settled
            // ANOTHER booking, or was already recorded here) → reject as a duplicate rather than
            // silently keep a second copy. The tx aborts on the failed INSERT and rolls back on drop.
            Err(e) if is_unique_violation(&e) => {
                tracing::warn!(%trans_ref, "extra-transfer slip already recorded/used (dedupe reject)");
                Err(AppError::ConflictCode {
                    code: crate::slip2go_client::SLIP_DUPLICATE_CODE,
                    message: "This slip has already been used for a payment".to_string(),
                })
            }
            Err(e) => Err(e.into()),
        };
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
/// the actual-hours bill ([`crate::domain::reconcile`]) against what the customer ACTUALLY
/// transferred — `amount + overpaid_amount` (the estimate PLUS any slip overpay, so the excess above
/// the estimate is folded straight into the refund and never silently kept):
///  - `actual < received` → REFUND the difference (base overpay + slip overpay): set
///    `final_amount`/`refund_amount` + `refund_status='pending'` and emit
///    `pguard.events.payment.refund_processed`.
///  - `actual > received` → record the shortfall: set `final_amount` (the extra charge owed). The
///    base is NEVER re-charged — only the delta is recorded.
///  - equal → record `final_amount` only.
///
/// EVERY arm also rewrites `subtotal`/`vat_amount` to the SETTLED split (the prorated subtotal and
/// the VAT recomputed on it), keeping the row invariant `subtotal + vat_amount = final_amount`.
/// That is what the tax invoice must print — VAT on the hours actually worked, not on the original
/// estimate — and it is what makes the VAT-exclusive revenue expression exact.
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

    // Settle against what the customer ACTUALLY transferred = the estimate + any slip overpay. This
    // folds the overpay into the diff: a normal full-hours completion still refunds the overpay
    // (received > settled), and a proration refund returns the base overpay AND the slip overpay.
    let received = payment.amount + payment.overpaid_amount;
    let outcome = crate::domain::reconcile(
        received,
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
    // falls back to booked hours. Priced off the VAT-EXCLUSIVE subtotal — only the hours ratio is
    // read out, but VAT has no business in an hours calculation.
    let actual_hours: Option<Decimal> = actual_seconds.map(|secs| {
        let booked_base =
            crate::domain::pricing::subtotal(base_fee, booked_hours, guard_count, Decimal::ZERO);
        crate::domain::proration::compute_proration(booked_base, booked_hours, secs).actual_hours
    });

    let settle = match outcome {
        Reconciliation::Even { settled } => {
            // Record the (matching) final bill for the ledger; no money moves, no event. The split
            // is still written: `amount` alone cannot tell the tax invoice how much of it was VAT.
            // `final_amount = settled.grand_total` (the settled bill == `received`), NOT the bare
            // `amount` column — with an overpay `received` exceeds `amount`, and the invariant
            // `subtotal + vat_amount = final_amount` must hold against the settled split.
            sqlx::query(
                "UPDATE payment.payments \
                   SET final_amount = $2, subtotal = $3, vat_amount = $4, actual_hours = $5, \
                       updated_at = now() \
                 WHERE id = $1",
            )
            .bind(payment.id)
            .bind(settled.grand_total)
            .bind(settled.subtotal)
            .bind(settled.vat)
            .bind(actual_hours)
            .execute(&mut *tx)
            .await?;
            SettleOutcome::NoOp
        }
        Reconciliation::Refund { settled, refund } => {
            // The base is NOT re-charged — only the overpay is returned (including the VAT on the
            // hours that were never worked). refund_status='pending' (an admin/real-gateway marks
            // 'processed'); the row stays 'completed' (a PARTIAL refund) and `final_amount` — now
            // net of the refund — is what the revenue report counts.
            let final_amount = settled.grand_total;
            sqlx::query(
                "UPDATE payment.payments \
                   SET final_amount = $2, refund_amount = $3, refund_status = 'pending', \
                       subtotal = $4, vat_amount = $5, actual_hours = $6, updated_at = now() \
                 WHERE id = $1",
            )
            .bind(payment.id)
            .bind(final_amount)
            .bind(refund)
            .bind(settled.subtotal)
            .bind(settled.vat)
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
        Reconciliation::Extra { settled, extra } => {
            // Customer owes more than pre-paid (e.g. a tip bump — and the VAT on it). Record the
            // higher final_amount + its split; the delta is owed. No refund event. (A real gateway
            // would capture the extra here.)
            let final_amount = settled.grand_total;
            sqlx::query(
                "UPDATE payment.payments \
                   SET final_amount = $2, subtotal = $3, vat_amount = $4, actual_hours = $5, \
                       updated_at = now() \
                 WHERE id = $1",
            )
            .bind(payment.id)
            .bind(final_amount)
            .bind(settled.subtotal)
            .bind(settled.vat)
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

/// The outcome of settling a pre-pay when the job was cancelled before it ran.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CancelRefundOutcome {
    /// Nothing to settle (no PAID pre-pay on file, or the event was already processed).
    NoOp,
    /// The pre-pay was unwound: `fee_charged` was retained (always 0 when the GUARD withdrew) and
    /// `refund` returned to the customer. The row is `refunded`; `refund_status='pending'` and a
    /// `payment.refund_processed` event were only produced when `refund > 0`.
    Refunded {
        refund: Decimal,
        fee_charged: Decimal,
    },
}

/// The few columns the cancellation settle needs off the paid pre-pay (no `SELECT *` on the money
/// path). `cancellation_fee` is the booking's SNAPSHOT, copied onto the row at charge time — which
/// is why this consumer needs no cross-service read, and why editing the catalog later cannot
/// change the terms of a booking that is already paid for.
#[derive(Debug, sqlx::FromRow)]
struct CancelSettleRow {
    id: Uuid,
    customer_id: Uuid,
    guard_id: Option<Uuid>,
    amount: Decimal,
    /// Excess transferred above the estimate (slip overpay); always refunded on top of the base.
    overpaid_amount: Decimal,
    cancellation_fee: Option<Decimal>,
}

/// REFUND a pre-paid booking whose job was CANCELLED or DECLINED before it ran, in ONE transaction.
/// No work was done, so nothing is charged for labour — but WHO backed out (and whether the booking
/// was still active) decides whether a cancellation fee is retained. That is decided by the CALLER
/// from GROUND TRUTH — the `charge_cancel_fee` flag booking stamps on the event — NOT by the event
/// TYPE or by which of two events settles first:
///  - `charge_cancel_fee == true` — booking marked this a genuine CUSTOMER cancel of a still-active
///    booking BEFORE arrival. Retain `min(cancellation_fee, amount_paid)`
///    ([`crate::domain::cancellation_fee_charged`] — "take what is there, never leave a debt":
///    nothing paid → nothing charged, and the fee can never exceed the estimate) and refund the rest.
///  - `charge_cancel_fee == false` (the DEFAULT, incl. an old event missing the field) — no fee, FULL
///    refund. This covers a GUARD decline/withdraw, the customer's cancel-after-decline ACK, and an
///    ADMIN-initiated cancel — none of which may charge the customer. Fail-open toward the customer.
///
/// This closes three prior money bugs at once: (a) admin cancel charging the customer, (b) the
/// decline→ack event reordering charging a fee on a guard withdrawal, and (c) the fee being decided
/// by event type / arrival order under the shared durable consumer's redelivery.
///
/// The row always ends `refunded` (the booking is dead; this also keeps a cancelled job out of the
/// guard's `completed` earnings ledger). `final_amount` = the retained fee, `refund_amount` = what
/// went back (`amount − fee` PLUS any slip `overpaid_amount` — the overpay is never the platform's),
/// `cancellation_fee_charged` = the fee for the audit trail, and `subtotal`/`vat_amount` are
/// rewritten to the fee's own VAT split — the fee is carved out of VAT-INCLUSIVE money, so the
/// platform keeps `fee − VAT`, not the whole fee. `refund_status='pending'` + the
/// `payment.refund_processed` event are produced ONLY when money actually goes back: a fee that
/// absorbs the entire payment must not queue a ฿0 refund or push "you were refunded ฿0".
///
/// Idempotent via the `processed_events` ledger: the event_id is claimed in the same tx, so a
/// JetStream redelivery is a NoOp (the refund is never applied twice). NoOp when there is no PAID
/// pre-pay on file — an UNPAID cancel (e.g. cancelled at `accepted`, before the pre-pay) has
/// nothing to return and, per the rule above, nothing to charge either. `status = 'completed'` in
/// the lookup already excludes an already-`refunded` row, so a double-refund is impossible even
/// independent of the event-id claim.
#[tracing::instrument(skip(db), fields(booking_id = %booking_id, event_id = %event_id, charge_cancel_fee))]
pub async fn refund_on_cancellation(
    db: &sqlx::PgPool,
    event_id: Uuid,
    event_type: &str,
    booking_id: Uuid,
    charge_cancel_fee: bool,
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

    // 2) the PAID pre-pay to settle (FOR UPDATE locks it for the write).
    let Some(payment) = sqlx::query_as::<_, CancelSettleRow>(
        "SELECT id, customer_id, guard_id, amount, overpaid_amount, cancellation_fee \
         FROM payment.payments \
         WHERE booking_id = $1 AND status = 'completed' LIMIT 1 FOR UPDATE",
    )
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

    // 3) The CALLER decided (from booking's ground-truth `charge_cancel_fee` flag) whether a fee is
    //    due. Only a genuine customer cancel of a still-active booking carries one; a guard
    //    decline/withdraw, the cancel-after-decline ACK, and an admin cancel do NOT. The fee is
    //    clamped to the ESTIMATE (`amount`), never the overpay — the overpay is always returned.
    let fee_charged = if charge_cancel_fee {
        crate::domain::cancellation_fee_charged(
            payment.cancellation_fee.unwrap_or(Decimal::ZERO),
            payment.amount,
        )
    } else {
        Decimal::ZERO
    };
    // Refund = the estimate minus the retained fee, PLUS any slip overpay (the excess above the
    // estimate is never the platform's, whatever the cancellation reason).
    let refund = (payment.amount - fee_charged).max(Decimal::ZERO) + payment.overpaid_amount;
    // What we keep is VAT-INCLUSIVE money, so split the VAT back out of it (a fully-refunded
    // cancellation keeps nothing → the all-zero split).
    let kept = crate::domain::PriceBreakdown::from_gross(fee_charged);
    // Only queue the refund workflow when money is actually going back.
    let refund_status = if refund > Decimal::ZERO {
        Some("pending")
    } else {
        None
    };

    sqlx::query(
        "UPDATE payment.payments \
           SET status = 'refunded'::payment.payment_status, final_amount = $2, \
               refund_amount = $3, refund_status = $4, cancellation_fee_charged = $5, \
               subtotal = $6, vat_amount = $7, updated_at = now() \
         WHERE id = $1",
    )
    .bind(payment.id)
    .bind(fee_charged)
    .bind(refund)
    .bind(refund_status)
    .bind(fee_charged)
    .bind(kept.subtotal)
    .bind(kept.vat)
    .execute(&mut *tx)
    .await?;

    if refund > Decimal::ZERO {
        // customer_id/guard_id carried so notification can route the refund push to the payer.
        // `final_amount` is the retained fee, so the customer can be told what was kept and why.
        let payload = serde_json::json!({
            "payment_id": payment.id,
            "booking_id": booking_id,
            "customer_id": payment.customer_id,
            "guard_id": payment.guard_id,
            "refund_amount": refund,
            "final_amount": fee_charged,
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
    tracing::info!(
        booking_id = %booking_id, %refund, %fee_charged, event_type,
        "settled pre-pay on cancellation/decline"
    );
    Ok(CancelRefundOutcome::Refunded {
        refund,
        fee_charged,
    })
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
///
/// NO cancellation fee is ever retained here, even when the terminal status is the customer's own
/// `cancelled`: this charge landed on a booking that was ALREADY dead, so the customer never had a
/// live booking to cancel — the fee belongs to the cancel-consumer's path, which prices the real
/// cancellation. Charging here would double-dip (the consumer's settle already ran, or will).
#[tracing::instrument(skip(db), fields(booking_id = %booking_id))]
pub async fn refund_race_lost_prepay(
    db: &sqlx::PgPool,
    booking_id: Uuid,
    correlation_id: Uuid,
) -> Result<CancelRefundOutcome, AppError> {
    let mut tx = db.begin().await?;
    let Some(payment) = sqlx::query_as::<_, CancelSettleRow>(
        "SELECT id, customer_id, guard_id, amount, overpaid_amount, cancellation_fee \
         FROM payment.payments \
         WHERE booking_id = $1 AND status = 'completed' LIMIT 1 FOR UPDATE",
    )
    .bind(booking_id)
    .fetch_optional(&mut *tx)
    .await?
    else {
        // Already refunded (the cancel-consumer got there first, or a concurrent compensator) → NoOp.
        tx.rollback().await?;
        return Ok(CancelRefundOutcome::NoOp);
    };

    // Full refund of everything the customer transferred — the estimate AND any slip overpay.
    let refund = payment.amount + payment.overpaid_amount;
    sqlx::query(
        "UPDATE payment.payments \
           SET status = 'refunded'::payment.payment_status, final_amount = 0, \
               refund_amount = $2, refund_status = 'pending', cancellation_fee_charged = 0, \
               subtotal = 0, vat_amount = 0, updated_at = now() \
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
    Ok(CancelRefundOutcome::Refunded {
        refund,
        fee_charged: Decimal::ZERO,
    })
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

    use crate::domain::PriceBreakdown;

    fn dec(s: &str) -> Decimal {
        s.parse().unwrap()
    }

    /// Charge terms for a VAT-EXCLUSIVE `subtotal` with no commission and no cancellation fee —
    /// what the API layer assembles from a booking that carries neither snapshot. The charged
    /// `amount` is the GRAND TOTAL (`subtotal` + 7%), e.g. `terms_of("2000.00")` charges 2140.00.
    fn terms_of(subtotal: &str) -> ChargeTerms {
        ChargeTerms::new(
            PriceBreakdown::from_subtotal(dec(subtotal)),
            Decimal::ZERO,
            Decimal::ZERO,
        )
    }

    /// Charge terms carrying the booking's commission % + cancellation-fee snapshot.
    fn terms_with(subtotal: &str, commission_percent: &str, cancellation_fee: &str) -> ChargeTerms {
        ChargeTerms::new(
            PriceBreakdown::from_subtotal(dec(subtotal)),
            dec(commission_percent),
            dec(cancellation_fee),
        )
    }

    /// The money columns a settle/cancel assertion reads back off the row (a named struct rather
    /// than an 8-wide tuple, so the assertions say what they mean).
    #[derive(Debug, sqlx::FromRow)]
    struct SettledRow {
        status: String,
        amount: Decimal,
        final_amount: Option<Decimal>,
        refund_amount: Option<Decimal>,
        refund_status: Option<String>,
        cancellation_fee_charged: Option<Decimal>,
        subtotal: Option<Decimal>,
        vat_amount: Option<Decimal>,
    }

    /// Read the settled money state of one payment row.
    async fn settled_row(pool: &sqlx::PgPool, payment_id: Uuid) -> SettledRow {
        sqlx::query_as::<_, SettledRow>(
            "SELECT status::text AS status, amount, final_amount, refund_amount, refund_status, \
                    cancellation_fee_charged, subtotal, vat_amount \
             FROM payment.payments WHERE id = $1",
        )
        .bind(payment_id)
        .fetch_one(pool)
        .await
        .expect("read settled row")
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
            &terms_of("400.00"),
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
        // The customer is charged the GRAND TOTAL (400.00 + 7% VAT), with the split persisted.
        assert_eq!(first.amount, dec("428.00"));
        assert_eq!(first.expected_total, Some(dec("428.00")));
        assert_eq!(first.subtotal, Some(dec("400.00")));
        assert_eq!(first.vat_amount, Some(dec("28.00")));
        assert_eq!(
            first.grand_total,
            dec("428.00"),
            "grand_total is derived from the split"
        );
        assert_eq!(first.guard_id, guard_id);

        // Retry — must be AlreadyPaid with the SAME payment, not a new one.
        let second_out = prepay_idempotent(
            &pool,
            booking_id,
            customer_id,
            guard_id,
            &terms_of("400.00"),
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

    /// The guard-payout backlog + double-pay guard: a reconciled completed payment appears in
    /// `unpaid_payout_rows`; once a batch pays it, it is EXCLUDED; a second batch for the same
    /// booking is refused `PAYOUT_ALREADY_PAID` (the UNIQUE booking marker). Plus config round-trip.
    /// DATABASE_URL-gated.
    #[tokio::test]
    async fn payout_backlog_and_double_pay_guard() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();

        // A completed, guard-assigned payment; then RECONCILE it (stamp actual_hours) so it counts
        // as a finished job payable to the guard.
        prepay_idempotent(
            &pool,
            booking_id,
            Uuid::new_v4(),
            Some(guard_id),
            &terms_of("400.00"),
            "promptpay",
            Uuid::new_v4(),
        )
        .await
        .expect("pre-pay");
        sqlx::query(
            "UPDATE payment.payments SET actual_hours = 4, commission_percent = 10 WHERE booking_id = $1",
        )
        .bind(booking_id)
        .execute(&pool)
        .await
        .expect("reconcile");

        // config round-trips (upsert then read).
        let cfg = upsert_payout_config(
            &pool,
            &UpdatePayoutConfigRequest {
                debit_account: Some("1234567890".to_string()),
                fee_debit_account: None,
                wht_form_type_code: None,
                wht_pay_type_code: None,
                wht_income_type_code: None,
                wht_income_desc: None,
                wht_rate_percent: Some(dec("3")),
            },
            Uuid::new_v4(),
        )
        .await
        .expect("upsert config");
        assert_eq!(cfg.debit_account.as_deref(), Some("1234567890"));
        assert_eq!(cfg.wht_rate_percent, dec("3"));
        assert_eq!(cfg.wht_form_type_code, "53", "default kept");

        // the reconciled job is in the unpaid backlog.
        let all = PayoutSelection::default();
        let rows = unpaid_payout_rows(&pool, &all).await.expect("backlog");
        assert!(
            rows.iter().any(|r| r.booking_id == booking_id),
            "reconciled completed job is payable"
        );

        // ----- selection: WHO gets paid + WHICH days -----
        let today = chrono::Utc::now()
            .with_timezone(&chrono::FixedOffset::east_opt(7 * 3600).unwrap())
            .date_naive();
        let picked = |sel: &PayoutSelection| {
            let pool = pool.clone();
            let sel = sel.clone();
            async move {
                unpaid_payout_rows(&pool, &sel)
                    .await
                    .expect("filtered backlog")
                    .iter()
                    .any(|r| r.booking_id == booking_id)
            }
        };

        // ticking THIS guard includes the job; ticking only someone else excludes it.
        assert!(
            picked(&PayoutSelection {
                guard_ids: Some(vec![guard_id, Uuid::new_v4()]),
                ..Default::default()
            })
            .await,
            "a selection naming the guard (among others) pays them"
        );
        assert!(
            !picked(&PayoutSelection {
                guard_ids: Some(vec![Uuid::new_v4()]),
                ..Default::default()
            })
            .await,
            "an unselected guard's job is NOT in the run"
        );

        // the day window is inclusive on both ends, in Thai local days.
        assert!(
            picked(&PayoutSelection {
                guard_ids: None,
                from: Some(today),
                to: Some(today),
            })
            .await,
            "a job reconciled today is inside today's window"
        );
        assert!(
            !picked(&PayoutSelection {
                guard_ids: None,
                from: Some(today + chrono::Duration::days(1)),
                to: None,
            })
            .await,
            "a window starting tomorrow excludes today's job"
        );
        assert!(
            !picked(&PayoutSelection {
                guard_ids: None,
                from: None,
                to: Some(today - chrono::Duration::days(1)),
            })
            .await,
            "a window ending yesterday excludes today's job"
        );

        // pay it — insert the batch + paid-marker item.
        let batch = NewPayoutBatch {
            file_ref: "SCB_file_reference_x".to_string(),
            system_ref: "PGUARD-PAYOUT".to_string(),
            batch_ref: "010926120000PPY".to_string(),
            value_date: chrono::NaiveDate::from_ymd_opt(2026, 9, 1).unwrap(),
            total_amount: dec("349.20"),
            created_by: Some(Uuid::new_v4()),
            items: vec![crate::models::NewPayoutItem {
                booking_id,
                guard_id,
                income: dec("360.00"),
                wht: dec("10.80"),
                transfer_amount: dec("349.20"),
            }],
        };
        insert_payout_batch(&pool, &batch).await.expect("pay");

        // now it is NO LONGER in the backlog (paid-marker excludes it).
        let after = unpaid_payout_rows(&pool, &all).await.expect("backlog 2");
        assert!(
            !after.iter().any(|r| r.booking_id == booking_id),
            "a paid job drops out of the backlog"
        );

        // a SECOND batch for the same booking is refused — never pay twice.
        let err = insert_payout_batch(&pool, &batch)
            .await
            .expect_err("double pay refused");
        assert!(
            matches!(&err, AppError::ConflictCode { code, .. } if *code == "PAYOUT_ALREADY_PAID"),
            "double-pay is a typed conflict, got {err:?}"
        );

        // cleanup (items cascade with the batch).
        let _ = sqlx::query("DELETE FROM payment.payout_batches WHERE id IN (SELECT batch_id FROM payment.payout_batch_items WHERE booking_id = $1)")
            .bind(booking_id).execute(&pool).await;
        let _ = sqlx::query("DELETE FROM payment.payout_batch_items WHERE booking_id = $1")
            .bind(booking_id)
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

    /// Unwrap the payment out of a [`SlipPayOutcome`] (tests don't care which arm here).
    fn slip_payment_of(o: SlipPayOutcome) -> PaymentResponse {
        match o {
            SlipPayOutcome::Created(p)
            | SlipPayOutcome::AlreadyPaid(p)
            | SlipPayOutcome::ExtraTransferRecorded(p) => p,
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
                &terms_of("2000.00"),
                &reference_id,
                &trans_ref,
                dec("2140.00"),
                "payment/x/slips/a.jpg",
                Uuid::new_v4(),
            )
            .await
            .expect("first slip pay"),
        );
        assert_eq!(first.status, "completed");
        assert_eq!(first.payment_method.as_deref(), Some("promptpay_slip"));
        // The real money path charges the same VAT-inclusive grand total as the simulated one.
        assert_eq!(first.amount, dec("2140.00"));
        assert_eq!(first.subtotal, Some(dec("2000.00")));
        assert_eq!(first.vat_amount, Some(dec("140.00")));

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
            &terms_of("2000.00"),
            &reference_id,
            &trans_ref,
            dec("2140.00"),
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
                &terms_of("2000.00"),
                &ref_a,
                &trans_ref,
                dec("2140.00"),
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
            &terms_of("2000.00"),
            &ref_b,
            &trans_ref, // REUSED
            dec("2140.00"),
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
            &terms_of("2000.00"),
            &ref_a, // REUSED reference_id
            &format!("TR-{}", Uuid::new_v4()),
            dec("2140.00"),
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
                &terms_of("400.00"),
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
                &terms_of("250.00"),
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
        // Booking A: pre-pay 2140.00 (2000 + VAT), work 2h of 4h → settled 1070.00 → refund
        // 1070.00 owed (refund_status='pending').
        let booking_a = Uuid::new_v4();
        let event_a = Uuid::new_v4();
        let pay_a = payment_of(
            prepay_idempotent(
                &pool,
                booking_a,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                &terms_of("2000.00"),
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

        // Booking B: pre-pay 2140.00, work the full 4h → no refund (must NOT appear in the queue).
        let booking_b = Uuid::new_v4();
        let event_b = Uuid::new_v4();
        let pay_b = payment_of(
            prepay_idempotent(
                &pool,
                booking_b,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                &terms_of("2000.00"),
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
        assert_eq!(row_a.amount, dec("1070.00"), "amount = the refund owed");
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

        // Pre-pay the estimate 500×4×1 + 0 = 2000.00 subtotal → 2140.00 charged with VAT.
        let paid = payment_of(
            prepay_idempotent(
                &pool,
                booking_id,
                customer_id,
                Some(Uuid::new_v4()),
                &terms_of("2000.00"),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );

        // Complete after working only 2h of 4h → settled subtotal 1000.00 + VAT 70.00 = 1070.00
        // → refund 1070.00 (the unused VAT goes back with the unused base).
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
                final_amount: dec("1070.00"),
                refund: dec("1070.00"),
            }
        );

        // The row reflects the refund; the base was never re-charged (amount unchanged). The VAT
        // split is REWRITTEN to the settled bill and still reconstructs it exactly.
        let row = settled_row(&pool, paid.id).await;
        assert_eq!(row.amount, dec("2140.00"), "amount (pre-paid) unchanged");
        assert_eq!(
            row.final_amount,
            Some(dec("1070.00")),
            "final_amount = actual bill"
        );
        assert_eq!(
            row.refund_amount,
            Some(dec("1070.00")),
            "refund_amount = overpay"
        );
        assert_eq!(row.refund_status.as_deref(), Some("pending"));
        assert_eq!(
            row.subtotal,
            Some(dec("1000.00")),
            "subtotal = prorated base"
        );
        assert_eq!(
            row.vat_amount,
            Some(dec("70.00")),
            "VAT recomputed on the prorated subtotal"
        );
        assert_eq!(
            row.subtotal.unwrap() + row.vat_amount.unwrap(),
            row.final_amount.unwrap(),
            "the persisted split must reconstruct final_amount exactly"
        );

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
                &terms_with("2000.00", "10.00", "300.00"),
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

        // The guard's earnings ledger surfaces the booking, its actual worked hours AND the
        // commission % snapshotted from the booking, so the app can show what was deducted
        // (500 × 2.00 = 1000.00 gross → 10% = 100.00 commission → 900.00 net).
        let earnings = guard_earnings(&pool, guard_id).await.expect("earnings");
        let row = earnings
            .iter()
            .find(|e| e.booking_id == booking_id)
            .expect("the completed job appears in the guard's earnings");
        assert_eq!(row.actual_hours, Some(dec("2.00")));
        assert_eq!(
            row.commission_percent,
            Some(dec("10.00")),
            "the booking's commission snapshot rides along on the payment row"
        );

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

    /// Real-Postgres: PRE-PAY a booking, then the GUARD WITHDRAWS (`booking.declined`) before it
    /// ran → the WHOLE pre-pay is FULL-refunded with NO cancellation fee, even though the booking
    /// carries one: the customer did nothing wrong (status → refunded, refund_amount = the full
    /// amount, final_amount 0, cancellation_fee_charged 0, refund_status='pending', a
    /// `payment.refund_processed` emitted). Idempotent (a redelivery is a NoOp). An UNPAID booking
    /// (no pre-pay on file) → NoOp. DATABASE_URL-gated.
    #[tokio::test]
    async fn refund_on_cancellation_full_refunds_and_is_idempotent() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        // A paid pre-pay of 2140.00 (2000 + VAT) on a booking WITH a 300.00 cancellation fee.
        let paid = payment_of(
            prepay_idempotent(
                &pool,
                booking_id,
                customer_id,
                Some(Uuid::new_v4()),
                &terms_with("2000.00", "10.00", "300.00"),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );

        // Guard withdraws en_route (booking.declined) → the WHOLE pre-pay is refunded, fee-free
        // (charge_cancel_fee = false: a guard withdrawal never charges the customer).
        let out = refund_on_cancellation(
            &pool,
            event_id,
            topics::BOOKING_DECLINED,
            booking_id,
            false,
            Uuid::new_v4(),
        )
        .await
        .expect("refund");
        assert_eq!(
            out,
            CancelRefundOutcome::Refunded {
                refund: dec("2140.00"),
                fee_charged: Decimal::ZERO,
            },
            "a guard withdrawal never charges the customer a cancellation fee"
        );

        // The row: status refunded, full refund_amount, final_amount 0, pending refund workflow.
        let row = settled_row(&pool, paid.id).await;
        assert_eq!(
            row.status, "refunded",
            "a FULL refund flips status → refunded"
        );
        assert!(
            row.final_amount.expect("final_amount").is_zero(),
            "final_amount 0 (no work)"
        );
        assert_eq!(
            row.refund_amount,
            Some(dec("2140.00")),
            "refund_amount = the full pre-pay"
        );
        assert_eq!(row.refund_status.as_deref(), Some("pending"));
        assert_eq!(
            row.cancellation_fee_charged,
            Some(Decimal::ZERO),
            "no fee retained when the guard withdrew"
        );

        // Shows in the admin refund queue with amount = the full refund.
        let pending = admin_list_refund_queue(&pool, Some("pending"), 200, 0)
            .await
            .expect("queue");
        let qrow = pending
            .iter()
            .find(|r| r.payment_id == paid.id)
            .expect("in refund queue");
        assert_eq!(qrow.amount, dec("2140.00"));

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
            false,
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
            true,
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

        // Pre-pay 500×4×1 + 0 = 2000.00 subtotal → 2140.00 with VAT (no tip).
        let paid = payment_of(
            prepay_idempotent(
                &pool,
                booking_id,
                customer_id,
                Some(Uuid::new_v4()),
                &terms_of("2000.00"),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );

        // Complete the full 4h WITH a 300 tip → settled 2300.00 + 161.00 VAT = 2461.00, so
        // 321.00 is owed (the tip AND the VAT on it).
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
                final_amount: dec("2461.00"),
                extra: dec("321.00"),
            }
        );

        let row: (Decimal, Option<Decimal>, Option<Decimal>, Option<Decimal>) = sqlx::query_as(
            "SELECT amount, final_amount, refund_amount, vat_amount \
             FROM payment.payments WHERE id = $1",
        )
        .bind(paid.id)
        .fetch_one(&pool)
        .await
        .expect("read row");
        assert_eq!(row.0, dec("2140.00"), "amount (pre-paid base) unchanged");
        assert_eq!(
            row.1,
            Some(dec("2461.00")),
            "final_amount = actual + tip + VAT"
        );
        assert!(row.2.is_none(), "no refund on an under-payment");
        assert_eq!(
            row.3,
            Some(dec("161.00")),
            "VAT rewritten for the higher settled subtotal"
        );

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

    /// Real-Postgres: the CUSTOMER cancels a paid booking (`booking.cancelled`) → the booking's
    /// cancellation fee is RETAINED and the rest refunded. The row keeps the fee as `final_amount`
    /// + `cancellation_fee_charged`, splits the fee's own VAT out (the fee is carved from
    /// VAT-inclusive money), and still queues + emits the partial refund. DATABASE_URL-gated.
    #[tokio::test]
    async fn customer_cancellation_retains_the_fee_and_refunds_the_rest() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        // Paid 2140.00 on a booking whose cancellation fee is 300.00.
        let paid = payment_of(
            prepay_idempotent(
                &pool,
                booking_id,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                &terms_with("2000.00", "10.00", "300.00"),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );

        // charge_cancel_fee = true: booking marked this a genuine customer cancel of a live booking.
        let out = refund_on_cancellation(
            &pool,
            event_id,
            topics::BOOKING_CANCELLED,
            booking_id,
            true,
            Uuid::new_v4(),
        )
        .await
        .expect("cancel settle");
        assert_eq!(
            out,
            CancelRefundOutcome::Refunded {
                refund: dec("1840.00"),
                fee_charged: dec("300.00"),
            },
            "min(fee, paid) is kept; the remainder goes back"
        );

        let row = settled_row(&pool, paid.id).await;
        assert_eq!(row.status, "refunded", "the booking is dead either way");
        assert_eq!(
            row.final_amount,
            Some(dec("300.00")),
            "final_amount = the retained fee"
        );
        assert_eq!(
            row.refund_amount,
            Some(dec("1840.00")),
            "refund_amount = 2140 − 300"
        );
        assert_eq!(
            row.refund_status.as_deref(),
            Some("pending"),
            "a real refund is queued"
        );
        assert_eq!(
            row.cancellation_fee_charged,
            Some(dec("300.00")),
            "the fee is recorded for audit"
        );
        // The fee is VAT-INCLUSIVE money: 300.00 × 7/107 = 19.63 VAT, 280.37 actual revenue.
        assert_eq!(
            row.subtotal,
            Some(dec("280.37")),
            "fee subtotal (VAT carved out)"
        );
        assert_eq!(
            row.vat_amount,
            Some(dec("19.63")),
            "VAT inside the retained fee"
        );
        assert_eq!(
            row.subtotal.unwrap() + row.vat_amount.unwrap(),
            row.final_amount.unwrap(),
            "the split must still reconstruct final_amount"
        );

        // Exactly one refund_processed event (money DID go back).
        let refunds: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::PAYMENT_REFUND_PROCESSED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count refunds");
        assert_eq!(refunds, 1, "the partial refund is announced once");

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

    /// Real-Postgres: a cancellation fee LARGER than what the customer paid is clamped to the
    /// payment ("take what is there, never leave a debt") — nothing is refunded, and crucially no
    /// ฿0 refund is queued or announced (that would push "you were refunded ฿0" and pollute the
    /// admin refund queue). DATABASE_URL-gated.
    #[tokio::test]
    async fn cancellation_fee_is_clamped_to_the_payment_and_emits_no_zero_refund() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        // Paid only 107.00 (100.00 + VAT) against a 5000.00 cancellation fee.
        let paid = payment_of(
            prepay_idempotent(
                &pool,
                booking_id,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                &terms_with("100.00", "0", "5000.00"),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );

        // charge_cancel_fee = true: a genuine customer cancel — the fee applies but is clamped.
        let out = refund_on_cancellation(
            &pool,
            event_id,
            topics::BOOKING_CANCELLED,
            booking_id,
            true,
            Uuid::new_v4(),
        )
        .await
        .expect("cancel settle");
        assert_eq!(
            out,
            CancelRefundOutcome::Refunded {
                refund: Decimal::ZERO,
                fee_charged: dec("107.00"),
            },
            "the fee never exceeds what was actually paid"
        );

        let row = settled_row(&pool, paid.id).await;
        assert_eq!(row.status, "refunded");
        assert_eq!(
            row.refund_amount,
            Some(Decimal::ZERO),
            "nothing to give back"
        );
        assert_eq!(
            row.cancellation_fee_charged,
            Some(dec("107.00")),
            "the whole payment was retained"
        );
        assert!(
            row.refund_status.is_none(),
            "a ฿0 refund must NOT enter the admin refund queue"
        );

        // And no refund_processed event was emitted for a ฿0 refund.
        let refunds: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::PAYMENT_REFUND_PROCESSED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count refunds");
        assert_eq!(refunds, 0, "no ฿0 refund is announced to the customer");

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

    /// Real-Postgres: the revenue report is VAT-EXCLUSIVE and counts what was actually KEPT.
    /// A half-worked job that pre-paid 2140.00 and was refunded 1070.00 contributes its 1000.00
    /// settled SUBTOTAL — not 1070.00 (that would count the Revenue Department's VAT as income)
    /// and not 0.00 (the old double-subtraction of `final_amount − refund_amount`). The daily
    /// series and the window total must agree, since both use the same expression.
    /// DATABASE_URL-gated.
    #[tokio::test]
    async fn revenue_is_vat_exclusive_and_nets_refunds_once() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        payment_of(
            prepay_idempotent(
                &pool,
                booking_id,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                &terms_of("2000.00"),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );
        reconcile_on_completion(
            &pool,
            event_id,
            topics::BOOKING_COMPLETED,
            booking_id,
            dec("500"),
            4,
            1,
            Decimal::ZERO,
            Some(7200), // worked 2h of 4h → settled 1070.00, refunded 1070.00
            Uuid::new_v4(),
        )
        .await
        .expect("reconcile");

        // Park the row at a UNIQUE instant somewhere in 1970..2000 and aggregate a ±1s window
        // around it: `revenue_total` has no owner filter, so a "last 5 minutes" window would pick
        // up rows from tests running in parallel. This makes the assertion exact.
        let anchor = DateTime::from_timestamp((Uuid::new_v4().as_u128() % 946_684_800) as i64, 0)
            .expect("anchor timestamp");
        sqlx::query("UPDATE payment.payments SET paid_at = $2 WHERE booking_id = $1")
            .bind(booking_id)
            .bind(anchor)
            .execute(&pool)
            .await
            .expect("park the row in an isolated window");
        let from = anchor - chrono::TimeDelta::seconds(1);
        let to = anchor + chrono::TimeDelta::seconds(1);

        let total = revenue_total(&pool, from, to).await.expect("total");
        assert_eq!(
            total,
            dec("1000.00"),
            "revenue = the settled VAT-EXCLUSIVE subtotal, counted once"
        );

        // The chart must not disagree with the headline number.
        let series = revenue_series(&pool, from, to).await.expect("series");
        let series_total: Decimal = series.iter().map(|p| p.revenue).sum();
        assert_eq!(
            series_total, total,
            "the daily series must sum to the window total (one shared expression)"
        );

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

    /// Read one payment's `overpaid_amount` column.
    async fn overpaid_of(pool: &sqlx::PgPool, booking_id: Uuid) -> Decimal {
        sqlx::query_scalar("SELECT overpaid_amount FROM payment.payments WHERE booking_id = $1")
            .bind(booking_id)
            .fetch_one(pool)
            .await
            .expect("read overpaid_amount")
    }

    async fn cleanup(pool: &sqlx::PgPool, booking_id: Uuid, events: &[Uuid]) {
        let _ = sqlx::query(
            "DELETE FROM payment.payment_slips WHERE payment_id IN \
             (SELECT id FROM payment.payments WHERE booking_id = $1)",
        )
        .bind(booking_id)
        .execute(pool)
        .await;
        let _ = sqlx::query("DELETE FROM payment.processed_events WHERE event_id = ANY($1)")
            .bind(events)
            .execute(pool)
            .await;
        let _ =
            sqlx::query("DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(booking_id.to_string())
                .execute(pool)
                .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = $1")
            .bind(booking_id)
            .execute(pool)
            .await;
    }

    /// Real-Postgres: a slip OVERPAY (customer transferred MORE than the estimate) is LEDGERED on the
    /// payment row (`overpaid_amount`) and, on a GUARD withdrawal, FULLY refunded on top of the
    /// estimate — the excess is never silently kept. Estimate 2140.00, paid 2200.00 → overpaid 60.00
    /// → refund 2200.00 (not 2140.00). DATABASE_URL-gated.
    #[tokio::test]
    async fn slip_overpay_is_ledgered_and_fully_refunded_on_guard_decline() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        // Pay by slip for 2200.00 against a 2140.00 estimate → 60.00 overpay recorded.
        slip_payment_of(
            pay_with_slip(
                &pool,
                booking_id,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                &terms_of("2000.00"), // grand total 2140.00
                &Uuid::new_v4().to_string(),
                &format!("TR-{}", Uuid::new_v4()),
                dec("2200.00"), // OVERPAY by 60.00
                "payment/x/slips/over.jpg",
                Uuid::new_v4(),
            )
            .await
            .expect("slip pay with overpay"),
        );
        assert_eq!(
            overpaid_of(&pool, booking_id).await,
            dec("60.00"),
            "the slip overpay is ledgered on the payment row"
        );

        // Guard withdraws (declined, charge_cancel_fee=false) → the WHOLE transfer comes back.
        let out = refund_on_cancellation(
            &pool,
            event_id,
            topics::BOOKING_DECLINED,
            booking_id,
            false,
            Uuid::new_v4(),
        )
        .await
        .expect("refund");
        assert_eq!(
            out,
            CancelRefundOutcome::Refunded {
                refund: dec("2200.00"),
                fee_charged: Decimal::ZERO,
            },
            "refund = estimate 2140.00 + overpay 60.00 (never just the estimate)"
        );
        let row = {
            let id: Uuid =
                sqlx::query_scalar("SELECT id FROM payment.payments WHERE booking_id=$1")
                    .bind(booking_id)
                    .fetch_one(&pool)
                    .await
                    .unwrap();
            settled_row(&pool, id).await
        };
        assert_eq!(row.refund_amount, Some(dec("2200.00")));
        cleanup(&pool, booking_id, &[event_id]).await;
    }

    /// Real-Postgres: a CUSTOMER cancellation (charge_cancel_fee=true) keeps the fee but STILL
    /// returns the slip overpay: estimate 2140.00, paid 2200.00 (overpay 60.00), fee 300.00 →
    /// refund = (2140 − 300) + 60 = 1900.00, fee kept 300.00. DATABASE_URL-gated.
    #[tokio::test]
    async fn customer_cancel_with_fee_still_returns_the_slip_overpay() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        slip_payment_of(
            pay_with_slip(
                &pool,
                booking_id,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                &terms_with("2000.00", "10.00", "300.00"),
                &Uuid::new_v4().to_string(),
                &format!("TR-{}", Uuid::new_v4()),
                dec("2200.00"),
                "payment/x/slips/over2.jpg",
                Uuid::new_v4(),
            )
            .await
            .expect("slip pay with overpay"),
        );

        let out = refund_on_cancellation(
            &pool,
            event_id,
            topics::BOOKING_CANCELLED,
            booking_id,
            true, // genuine customer cancel of a live booking → the fee applies
            Uuid::new_v4(),
        )
        .await
        .expect("cancel settle");
        assert_eq!(
            out,
            CancelRefundOutcome::Refunded {
                refund: dec("1900.00"),
                fee_charged: dec("300.00"),
            },
            "the fee is kept out of the ESTIMATE; the overpay is always returned"
        );
        cleanup(&pool, booking_id, &[event_id]).await;
    }

    /// Real-Postgres: the cancellation fee is decided by `charge_cancel_fee`, NOT the event TYPE. A
    /// `booking.cancelled` with `charge_cancel_fee=false` (an ADMIN-initiated cancel, or the
    /// customer's cancel-after-decline ACK) FULL-refunds with NO fee, even though the booking carries
    /// a 300.00 fee. This is the fix for "admin cancel charges the customer" + the decline→ack fee
    /// reorder. DATABASE_URL-gated.
    #[tokio::test]
    async fn charge_cancel_fee_false_full_refunds_even_on_booking_cancelled() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        payment_of(
            prepay_idempotent(
                &pool,
                booking_id,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                &terms_with("2000.00", "10.00", "300.00"), // 2140.00 paid, 300.00 fee snapshot
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );

        // booking.cancelled BUT charge_cancel_fee=false (admin cancel / ack) → no fee, full refund.
        let out = refund_on_cancellation(
            &pool,
            event_id,
            topics::BOOKING_CANCELLED,
            booking_id,
            false,
            Uuid::new_v4(),
        )
        .await
        .expect("cancel settle");
        assert_eq!(
            out,
            CancelRefundOutcome::Refunded {
                refund: dec("2140.00"),
                fee_charged: Decimal::ZERO,
            },
            "a cancelled TOPIC does not charge a fee — only charge_cancel_fee=true does"
        );
        let id: Uuid = sqlx::query_scalar("SELECT id FROM payment.payments WHERE booking_id=$1")
            .bind(booking_id)
            .fetch_one(&pool)
            .await
            .unwrap();
        let row = settled_row(&pool, id).await;
        assert_eq!(
            row.cancellation_fee_charged,
            Some(Decimal::ZERO),
            "no fee retained on an admin cancel / decline ACK"
        );
        cleanup(&pool, booking_id, &[event_id]).await;
    }

    /// Real-Postgres: the slip overpay is refunded on COMPLETION reconcile too. Estimate 2140.00,
    /// paid 2200.00 (overpay 60.00); the guard works the FULL 4h so the settled bill == the estimate
    /// → the ONLY refund is the 60.00 overpay (received 2200 − settled 2140). DATABASE_URL-gated.
    #[tokio::test]
    async fn reconcile_refunds_the_slip_overpay_on_completion() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        slip_payment_of(
            pay_with_slip(
                &pool,
                booking_id,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                &terms_of("2000.00"),
                &Uuid::new_v4().to_string(),
                &format!("TR-{}", Uuid::new_v4()),
                dec("2200.00"), // overpay 60.00
                "payment/x/slips/over3.jpg",
                Uuid::new_v4(),
            )
            .await
            .expect("slip pay"),
        );

        // Full 4h worked → settled 2140.00; received 2200.00 → refund the 60.00 overpay only.
        let out = reconcile_on_completion(
            &pool,
            event_id,
            topics::BOOKING_COMPLETED,
            booking_id,
            dec("500"),
            4,
            1,
            Decimal::ZERO,
            Some(14400),
            Uuid::new_v4(),
        )
        .await
        .expect("reconcile");
        assert_eq!(
            out,
            SettleOutcome::Refunded {
                final_amount: dec("2140.00"),
                refund: dec("60.00"),
            },
            "a full-hours completion still refunds the slip overpay (received − settled)"
        );
        let id: Uuid = sqlx::query_scalar("SELECT id FROM payment.payments WHERE booking_id=$1")
            .bind(booking_id)
            .fetch_one(&pool)
            .await
            .unwrap();
        let row = settled_row(&pool, id).await;
        assert_eq!(row.final_amount, Some(dec("2140.00")));
        assert_eq!(row.refund_amount, Some(dec("60.00")));
        assert_eq!(
            row.subtotal.unwrap() + row.vat_amount.unwrap(),
            row.final_amount.unwrap(),
            "the settled split still reconstructs final_amount"
        );
        cleanup(&pool, booking_id, &[event_id]).await;
    }

    /// Real-Postgres: a SECOND, DIFFERENT verified transfer for an already-paid booking is NOT
    /// silently swallowed — it is recorded as an UNAPPLIED, refundable slip (`applied=false`,
    /// `refund_status='pending'`) and returns [`SlipPayOutcome::ExtraTransferRecorded`], while a
    /// re-submit of the SAME slip stays an idempotent no-op. The original payment is untouched.
    /// DATABASE_URL-gated.
    #[tokio::test]
    async fn second_different_slip_records_unapplied_extra_transfer() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let ref_a = Uuid::new_v4().to_string();
        let trans_a = format!("TR-{}", Uuid::new_v4());
        let ref_b = Uuid::new_v4().to_string();
        let trans_b = format!("TR-{}", Uuid::new_v4());

        // First transfer settles the booking.
        let first = slip_payment_of(
            pay_with_slip(
                &pool,
                booking_id,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                &terms_of("2000.00"),
                &ref_a,
                &trans_a,
                dec("2140.00"),
                "payment/x/slips/a.jpg",
                Uuid::new_v4(),
            )
            .await
            .expect("first slip"),
        );

        // A SECOND, DIFFERENT real transfer (distinct trans_ref) → recorded as unapplied + typed.
        let second = pay_with_slip(
            &pool,
            booking_id,
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            &terms_of("2000.00"),
            &ref_b,
            &trans_b,
            dec("2140.00"),
            "payment/x/slips/b.jpg",
            Uuid::new_v4(),
        )
        .await
        .expect("second slip");
        assert!(
            matches!(second, SlipPayOutcome::ExtraTransferRecorded(_)),
            "a second DIFFERENT transfer is recorded (not a silent AlreadyPaid 200)"
        );

        // The unapplied extra slip exists, is refundable, and carries the real transfer's refs.
        let extra: (bool, Option<String>, Decimal, String) = sqlx::query_as(
            "SELECT applied, refund_status, amount, trans_ref FROM payment.payment_slips \
             WHERE booking_id = $1 AND applied = FALSE",
        )
        .bind(booking_id)
        .fetch_one(&pool)
        .await
        .expect("the extra transfer is recorded as an unapplied slip");
        assert!(!extra.0, "the extra transfer is unapplied");
        assert_eq!(extra.1.as_deref(), Some("pending"), "queued for refund");
        assert_eq!(extra.2, dec("2140.00"));
        assert_eq!(extra.3, trans_b, "carries the SECOND transfer's trans_ref");

        // Still exactly ONE applied slip + ONE completed payment (the extra settled nothing).
        let applied_count: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.payment_slips WHERE booking_id = $1 AND applied = TRUE",
        )
        .bind(booking_id)
        .fetch_one(&pool)
        .await
        .expect("count applied slips");
        assert_eq!(
            applied_count, 1,
            "the extra transfer did not settle anything"
        );
        let pay_count: i64 =
            sqlx::query_scalar("SELECT count(*) FROM payment.payments WHERE booking_id = $1")
                .bind(booking_id)
                .fetch_one(&pool)
                .await
                .expect("count payments");
        assert_eq!(
            pay_count, 1,
            "one completed payment; nothing double-charged"
        );

        // Re-submitting the SAME accepted slip (trans_a) is still an idempotent no-op.
        let again = pay_with_slip(
            &pool,
            booking_id,
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
            &terms_of("2000.00"),
            &ref_a,
            &trans_a,
            dec("2140.00"),
            "payment/x/slips/a2.jpg",
            Uuid::new_v4(),
        )
        .await
        .expect("resubmit same slip");
        assert!(
            matches!(again, SlipPayOutcome::AlreadyPaid(p) if p.id == first.id),
            "the SAME slip re-submitted is a benign AlreadyPaid no-op"
        );

        cleanup(&pool, booking_id, &[]).await;
    }
}
