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

use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde_json::Value;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::topics;
use shared_events::EventEnvelope;

use crate::domain::batch_status::{self, BatchKind, BatchStatus};
use crate::domain::deduction::DeductionSelection;
use crate::domain::payout::PayoutSelection;
use crate::domain::refund_export::{RefundSelection, RefundSource, RefundSourceKind};
use crate::domain::ChargeTerms;
use crate::models::{
    CustomerSpend, DeductionBatchDetail, DeductionBatchItemRow, DeductionBatchList,
    DeductionBatchRow, ExportedBatchFile, NewDeductionBatch, NewPayoutBatch, NewRefundBatch,
    PaymentResponse, PayoutBatchDetail, PayoutBatchItemRow, PayoutBatchList, PayoutBatchRow,
    PayoutConfigRow, RefundBatchDetail, RefundBatchItemRow, RefundBatchList, RefundBatchRow,
    RefundQueueItem, RevenuePoint, SettledPaymentRow, UnpaidPayoutRow, UnpaidRefundRow,
    UpdatePayoutConfigRequest, VatRegisterRow, WhtPayeeTotals,
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
///
/// OPEN, KNOWN, AND OUT OF THIS CHANGE'S SCOPE: that `base_fee` is booking's CURRENT column, which is
/// the same mismatch B2 fixed on the payout side — [`unpaid_payout_rows`] now pays from
/// `payments.base_fee` (the migration-0013 snapshot), so a booking re-priced after completion would
/// make this SCREEN disagree with the file the guard is actually paid by. Closing it means adding
/// `base_fee` to [`crate::models::GuardEarningRow`] and having the mobile app read it from here
/// instead of from its booking feed — an API + client change, hence not folded in silently.
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
/// finished within a day window. An all-`None` selection is the default whole-backlog run. The
/// window is compared in **Thai local days** (`Asia/Bangkok`), inclusive on both ends, against
/// `updated_at` — the timestamp the completion reconcile stamps when it writes `actual_hours`, i.e.
/// when the job became payable.
///
/// IT SELECTS THE MIGRATION-0013 PRICING SNAPSHOT (`base_fee`, `booked_hours`), and that is the
/// point rather than an extra column: the guard's gross is `base_fee × hours`, and the sweep computes
/// the platform's cut from `payments.base_fee` — the SAME row. Reading the pay basis from booking's
/// live `base_fee` over HTTP instead meant a re-price after completion paid the guard off one number
/// while the sweep took `subtotal − guard_income` off another, and the difference silently landed in
/// (or leaked out of) the cut. See `api::payouts::aggregate`.
///
/// BOUNDED by [`MAX_PAYOUT_BACKLOG_ROWS`] + 1 so an unbounded default run cannot buffer the whole
/// table; the caller turns the overflow into a typed "narrow the window" 400.
///
/// A VOIDED item does not count as paid (`i.voided_at IS NULL`): voiding a batch exists to put its
/// work back in this backlog, and the item rows are kept as history rather than deleted — so
/// without this predicate a voided booking would stay filtered out and could never be paid at all.
pub async fn unpaid_payout_rows(
    db: &sqlx::PgPool,
    sel: &PayoutSelection,
) -> Result<Vec<UnpaidPayoutRow>, AppError> {
    let rows = sqlx::query_as::<_, UnpaidPayoutRow>(
        "SELECT p.booking_id, p.guard_id, p.actual_hours, p.commission_percent, \
                p.base_fee, p.booked_hours \
         FROM payment.payments p \
         WHERE p.status = 'completed' \
           AND p.guard_id IS NOT NULL \
           AND p.actual_hours IS NOT NULL \
           AND ($1::uuid[] IS NULL OR p.guard_id = ANY($1)) \
           AND ($2::date IS NULL OR (p.updated_at AT TIME ZONE 'Asia/Bangkok')::date >= $2) \
           AND ($3::date IS NULL OR (p.updated_at AT TIME ZONE 'Asia/Bangkok')::date <= $3) \
           AND NOT EXISTS ( \
               SELECT 1 FROM payment.payout_batch_items i \
               WHERE i.booking_id = p.booking_id AND i.voided_at IS NULL) \
         ORDER BY p.guard_id, p.created_at \
         LIMIT $4",
    )
    .bind(sel.guard_ids.as_deref())
    .bind(sel.from)
    .bind(sel.to)
    .bind(MAX_PAYOUT_BACKLOG_ROWS + 1)
    .fetch_all(db)
    .await?;
    if rows.len() as i64 > MAX_PAYOUT_BACKLOG_ROWS {
        return Err(too_many_rows(
            "งานที่รอจ่ายในช่วงที่เลือกมีมากเกินไป",
            MAX_PAYOUT_BACKLOG_ROWS,
        ));
    }
    Ok(rows)
}

/// How many rows ONE money query may return before it is refused.
///
/// EVERY money list in this file is `fetch_all`-ed into the heap on a SHARED pool, and three of them
/// were unbounded: the payout backlog and the sweep backlog both default to "the whole backlog"
/// (both ends `None`), and the two tax reports run over a whole calendar month. A year-end CSV or a
/// first-ever sweep therefore sized itself from the table, and one admin click could evict every
/// other request's connection budget.
///
/// A HARD CAP WITH A TYPED ERROR, never a silent `LIMIT`. Truncating a MONEY report produces a
/// smaller number that looks exactly like a correct one — a VAT total an accountant would file, or a
/// sweep an admin would reconcile against — so the honest answer is to refuse and say "narrow the
/// window", which is an action the admin can actually take. It also keeps the preview and the export
/// in lock-step: both go through the same aggregation, so an admin can never export a set of jobs
/// different from the one they previewed.
///
/// The numbers are generous on purpose — they are a runaway guard, not a business rule. At current
/// volumes a month of trading is a few thousand rows, so a cap that bites means either an unusually
/// large window or a genuinely huge backlog, and both want an explicit decision from a human.
pub const MAX_PAYOUT_BACKLOG_ROWS: i64 = 20_000;
/// The sweep's backlog cap — one row per SETTLED PAYMENT, the densest of the three (a payout row
/// needs a guard, a refund row needs an obligation; every settled job is sweepable).
pub const MAX_SWEEP_BACKLOG_ROWS: i64 = 20_000;
/// The refund backlog's cap. Same reasoning, and the same "narrow the window" remedy.
pub const MAX_REFUND_BACKLOG_ROWS: i64 = 20_000;
/// The output-VAT register's cap — one row per settled payment in the filing month.
pub const MAX_VAT_REGISTER_ROWS: i64 = 50_000;
/// The ภ.ง.ด.3/53 payee list's cap. It is GROUPED BY guard, so it is naturally bounded by how many
/// guards were paid in the month; the cap is a backstop rather than the real limit.
pub const MAX_WHT_PAYEE_ROWS: i64 = 20_000;

/// The typed 400 a capped money query returns. Thai, because an admin reads it, and it names both
/// the cap and the remedy — "too many rows" with no number is a dead end.
fn too_many_rows(what_th: &str, cap: i64) -> AppError {
    AppError::BadRequest(format!(
        "{what_th} (เกิน {cap} รายการ) — กรุณาแบ่งช่วงวันที่ให้สั้นลงแล้วทำทีละช่วง \
         ระบบไม่ตัดรายการทิ้งเอง เพราะยอดเงินที่ขาดไปจะดูเหมือนยอดที่ถูกต้อง"
    ))
}

/// Read the single-row payout config (`GET /admin/payouts/config`); the "unset" default (blank
/// debit accounts + the standard ภ.ง.ด.53 terms) when no row exists yet, so the GET never 404s.
pub async fn get_payout_config(db: &sqlx::PgPool) -> Result<PayoutConfigRow, AppError> {
    let row: Option<PayoutConfigRow> = sqlx::query_as(
        "SELECT debit_account, fee_debit_account, revenue_account, wht_form_type_code, \
                wht_pay_type_code, wht_income_type_code, wht_income_desc, wht_rate_percent, \
                product_code, fee_charge_code, sms_notify, max_transfer_per_txn, updated_at \
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
              wht_income_type_code, wht_income_desc, wht_rate_percent, max_transfer_per_txn, \
              fee_charge_code, sms_notify, revenue_account, updated_by, updated_at) \
         VALUES (TRUE, $1, $2, \
                 COALESCE($3, '53'), COALESCE($4, '1'), COALESCE($5, '5'), \
                 COALESCE($6, 'ค่าบริการรักษาความปลอดภัย'), COALESCE($7, 3), \
                 COALESCE($8, 2000000), COALESCE($9, 'OUR'), COALESCE($10, FALSE), $12, $11, now()) \
         ON CONFLICT (id) DO UPDATE SET \
             debit_account        = COALESCE($1, payment.payout_config.debit_account), \
             fee_debit_account    = COALESCE($2, payment.payout_config.fee_debit_account), \
             wht_form_type_code   = COALESCE($3, payment.payout_config.wht_form_type_code), \
             wht_pay_type_code    = COALESCE($4, payment.payout_config.wht_pay_type_code), \
             wht_income_type_code = COALESCE($5, payment.payout_config.wht_income_type_code), \
             wht_income_desc      = COALESCE($6, payment.payout_config.wht_income_desc), \
             wht_rate_percent     = COALESCE($7, payment.payout_config.wht_rate_percent), \
             max_transfer_per_txn = COALESCE($8, payment.payout_config.max_transfer_per_txn), \
             fee_charge_code      = COALESCE($9, payment.payout_config.fee_charge_code), \
             sms_notify           = COALESCE($10, payment.payout_config.sms_notify), \
             revenue_account      = COALESCE($12, payment.payout_config.revenue_account), \
             updated_by           = $11, \
             updated_at           = now() \
         RETURNING debit_account, fee_debit_account, revenue_account, wht_form_type_code, \
                   wht_pay_type_code, wht_income_type_code, wht_income_desc, wht_rate_percent, \
                   product_code, fee_charge_code, sms_notify, max_transfer_per_txn, updated_at",
    )
    .bind(req.debit_account.as_deref())
    .bind(req.fee_debit_account.as_deref())
    .bind(req.wht_form_type_code.as_deref())
    .bind(req.wht_pay_type_code.as_deref())
    .bind(req.wht_income_type_code.as_deref())
    .bind(req.wht_income_desc.as_deref())
    .bind(req.wht_rate_percent)
    .bind(req.max_transfer_per_txn)
    .bind(req.fee_charge_code.as_deref())
    .bind(req.sms_notify)
    .bind(admin_id)
    // $12 — the sweep destination (stream ②). COALESCE-merged like every other field, so an admin
    // saving only the ภ.ง.ด. codes cannot blank the account a money file credits.
    .bind(req.revenue_account.as_deref())
    .fetch_one(db)
    .await?;
    Ok(row)
}

// ----- the SHARED SCB reference space (migration 0012) -----
//
// Every stream that leaves over SCB Business Net derives its references from the same clock, and the
// two PromptPay streams stamp the same product code — so a payout and a refund committed in the same
// Bangkok second produce byte-identical HEADER field 1 and BCHDET field 1. The per-table uniques
// (`uq_payout_batches_file_ref`, `uq_refund_batches_file_ref`) live on different tables and cannot
// see each other, so only a SHARED reservation catches that. See migration 0012.

/// `payment.scb_file_refs.stream` — stream ③ *ยอดที่โอนให้ รปภ* (guard payout).
const SCB_STREAM_PAYOUT: &str = "payout";
/// `payment.scb_file_refs.stream` — stream ① *ยอดที่ต้องโอนคืนกับคนจ้าง* (customer refunds).
const SCB_STREAM_REFUND: &str = "refund";
/// `payment.scb_file_refs.stream` — stream ② *ยอดที่โดนหักเข้าระบบ* (the platform-cut sweep). Its
/// product differs (`OAT`, so a different `file_ref` suffix) but its BATCH ref comes off the same
/// one-second Bangkok clock as the other two, and that is the reference the bank de-dups a batch on.
const SCB_STREAM_DEDUCTION: &str = "deduction";

/// Claim `file_ref` + `batch_ref` for `stream` INSIDE the caller's transaction, so a collision rolls
/// the whole export back (nothing marked paid, nothing marked processed) instead of putting a second
/// file with the same bank references on an admin's disk.
///
/// The raw `sqlx::Error` is handed back deliberately: only the caller knows which stream's typed 409
/// to reuse, and mapping it here would either invent a second message for the same situation or lose
/// the non-unique errors that must still surface as a 500.
async fn reserve_scb_file_ref(
    tx: &mut sqlx::PgConnection,
    file_ref: &str,
    batch_ref: &str,
    stream: &str,
    batch_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO payment.scb_file_refs (file_ref, batch_ref, stream, batch_id) \
         VALUES ($1, $2, $3, $4)",
    )
    .bind(file_ref)
    .bind(batch_ref)
    .bind(stream)
    .bind(batch_id)
    .execute(tx)
    .await
    .map(|_| ())
}

// ----- how the three streams write their item rows -----
//
// ALL THREE USE ONE `UNNEST` STATEMENT PER BATCH, and it is worth saying why rather than leaving it
// as an obvious optimisation. Each export ran `INSERT … VALUES` in a LOOP inside the transaction that
// also holds the batch header, the `scb_file_refs` reservation and the audit row — so a 3,000-job
// sweep took 3,000 round trips while HOLDING the write locks on the paid-marker partial unique
// (`uq_deduction_batch_items_payment_live` and its two siblings). Every concurrent export, and every
// backlog read that touches those index pages, waits for the whole loop. One statement collapses that
// to a single round trip and the locks are taken for the width of one insert.
//
// `UNNEST` OVER `QueryBuilder::push_values`, deliberately: a builder emits one placeholder per COLUMN
// per ROW, so at 9 columns it hits Postgres's 65,535-parameter ceiling somewhere north of 7,000 rows
// — inside the range the backlog caps allow — and would need chunking, which puts the row count back
// into the transaction's round-trip count and adds a second failure mode to reason about. `UNNEST`
// binds one ARRAY per column: a fixed parameter count, one statement, any number of rows.
//
// THE TRANSACTIONAL SEMANTICS ARE UNCHANGED. It is still the same `&mut *tx`, the partial unique is
// still the atomic double-pay guard, and a unique violation still rolls the WHOLE export back and
// returns the SAME typed 409 — the only difference is that the violation is now reported by one
// statement instead of by whichever iteration happened to hit it.

/// The 409 a PAYOUT export returns when its batch reference is already taken — by another payout
/// (the per-table unique) or by a refund/sweep in the same Bangkok second (the shared reservation).
///
/// ONE function for both, because it is one situation with one remedy: the whole transaction rolled
/// back, nothing was marked paid, and the same click a second later succeeds with a fresh stamp.
/// Two different messages for it would only make the admin wonder which of the two they hit.
fn payout_batch_ref_taken() -> AppError {
    AppError::ConflictCode {
        code: "PAYOUT_BATCH_REF_TAKEN",
        message: "มีการสร้างไฟล์จ่ายเงินอีกไฟล์ในวินาทีเดียวกัน — ยังไม่มีรายการใดถูกทำเครื่องหมายว่าจ่ายแล้ว กรุณากดสร้างไฟล์อีกครั้ง".to_string(),
    }
}

/// The REFUND export's counterpart to [`payout_batch_ref_taken`] — same reasoning, same remedy.
fn refund_batch_ref_taken() -> AppError {
    AppError::ConflictCode {
        code: "REFUND_BATCH_REF_TAKEN",
        message: "มีการสร้างไฟล์คืนเงินอีกไฟล์ในวินาทีเดียวกัน — ยังไม่มีรายการใดถูกทำเครื่องหมายว่าคืนแล้ว กรุณากดสร้างไฟล์อีกครั้ง".to_string(),
    }
}

/// The SWEEP export's counterpart — same reasoning, same remedy. The sweep rides `OAT` rather than
/// `PPY`, so its FILE ref cannot collide with the other two; its BATCH ref (the bare 12-digit stamp,
/// which is what the bank de-dups on) collides exactly as theirs do, which is what the shared
/// `payment.scb_file_refs` reservation is for.
fn deduction_batch_ref_taken() -> AppError {
    AppError::ConflictCode {
        code: "DEDUCTION_BATCH_REF_TAKEN",
        message: "มีการสร้างไฟล์โอนอีกไฟล์ในวินาทีเดียวกัน — ยังไม่มีรายการใดถูกทำเครื่องหมายว่าหักเข้าระบบแล้ว กรุณากดสร้างไฟล์อีกครั้ง".to_string(),
    }
}

/// The batch-header columns every payout read returns. `has_file` is DERIVED, not stored: the list
/// and the drill-down must tell the screen whether the re-download will work (a batch generated
/// before `file_text` existed has no stored copy) without shipping the file text itself.
const PAYOUT_BATCH_COLUMNS: &str =
    "id, file_ref, system_ref, batch_ref, value_date, total_amount, \
     recipient_count, status, status_note, void_reason, (file_text IS NOT NULL) AS has_file, \
     created_by, created_at, uploaded_at, confirmed_at, rejected_at, voided_at, voided_by";

/// Persist a generated payout batch: the `payout_batches` header (INCLUDING the exact file text
/// handed to the admin), all `payout_batch_items`, and the `money_audit` row — in ONE transaction.
/// The partial `UNIQUE(booking_id) WHERE voided_at IS NULL` on the items is the atomic paid-marker:
/// if any booking in this batch is already claimed by a LIVE item (a concurrent export won the
/// race), the insert violates the unique, the whole tx ROLLS BACK, and a typed 409 is returned so
/// nothing is double-paid. Returns the new batch id.
///
/// Storing `file_text` here — in the same tx that marks the bookings paid — is what closes the
/// one-way door: the paid-markers and the only copy of the file that justifies them are committed
/// together, so the file can always be re-downloaded (and the batch voided) afterwards.
///
/// The batch reference is claimed in `payment.scb_file_refs` in the same tx — the SHARED space that
/// also catches a REFUND export stamped in the same Bangkok second (see [`reserve_scb_file_ref`]).
pub async fn insert_payout_batch(
    db: &sqlx::PgPool,
    batch: &NewPayoutBatch,
) -> Result<Uuid, AppError> {
    let mut tx = db.begin().await?;
    let inserted: Result<Uuid, sqlx::Error> = sqlx::query_scalar(
        "INSERT INTO payment.payout_batches \
             (file_ref, system_ref, batch_ref, value_date, total_amount, recipient_count, \
              file_text, status, created_by) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'generated', $8) RETURNING id",
    )
    .bind(&batch.file_ref)
    .bind(&batch.system_ref)
    .bind(&batch.batch_ref)
    .bind(batch.value_date)
    .bind(batch.total_amount)
    // GUARDS, not bookings (see `NewPayoutBatch::recipient_count`).
    .bind(batch.recipient_count as i32)
    .bind(&batch.file_text)
    .bind(batch.created_by)
    .fetch_one(&mut *tx)
    .await;
    // `uq_payout_batches_file_ref` (migration 0010). `file_ref` is `batch_ref || product`, and the
    // batch ref is a timestamp at ONE-SECOND resolution — so two exports committed in the same
    // Bangkok second collide here even when their guard selections are DISJOINT (nothing for the
    // per-booking paid-marker to catch). Colliding matters because the customer transaction refs are
    // derived from the same batch ref: two files would carry the refs SCB de-dups on.
    //
    // The honest answer is a typed 409 and NOT a silent retry loop sleeping in the request path: the
    // whole insert is one transaction, so the loser rolls back with NOTHING marked paid, and one
    // second later the same click succeeds with a fresh ref.
    let batch_id = match inserted {
        Ok(id) => id,
        Err(e) => {
            tx.rollback().await?;
            if is_unique_violation(&e) {
                return Err(payout_batch_ref_taken());
            }
            return Err(e.into());
        }
    };

    // …and the SHARED reservation, which is what the per-table unique above CANNOT do: a refund
    // export (stream ①) rides the same PromptPay product code off the same one-second clock, so it
    // produces the identical HEADER field 1 and BCHDET field 1 — in a different table, invisible to
    // `uq_payout_batches_file_ref`. Reserved here, inside the transaction, so a cross-stream
    // collision rolls this whole export back with nothing marked paid. Same typed 409: same
    // situation, same remedy (click again a second later).
    //
    // `&mut tx` reaches the reservation as the transaction's own connection (Transaction derefs to
    // it), so the row is claimed under THIS transaction and released again if it rolls back.
    if let Err(e) = reserve_scb_file_ref(
        &mut tx,
        &batch.file_ref,
        &batch.batch_ref,
        SCB_STREAM_PAYOUT,
        batch_id,
    )
    .await
    {
        tx.rollback().await?;
        if is_unique_violation(&e) {
            return Err(payout_batch_ref_taken());
        }
        return Err(e.into());
    }

    // ONE statement for every paid-marker (see the `UNNEST` note above) — column-parallel arrays,
    // zipped back into rows by Postgres.
    let mut booking_ids = Vec::with_capacity(batch.items.len());
    let mut guard_ids = Vec::with_capacity(batch.items.len());
    let mut incomes = Vec::with_capacity(batch.items.len());
    let mut whts = Vec::with_capacity(batch.items.len());
    let mut transfers = Vec::with_capacity(batch.items.len());
    for item in &batch.items {
        booking_ids.push(item.booking_id);
        guard_ids.push(item.guard_id);
        incomes.push(item.income);
        whts.push(item.wht);
        transfers.push(item.transfer_amount);
    }
    let res = sqlx::query(
        "INSERT INTO payment.payout_batch_items \
             (batch_id, booking_id, guard_id, income, wht, transfer_amount) \
         SELECT $1, i.booking_id, i.guard_id, i.income, i.wht, i.transfer_amount \
           FROM UNNEST($2::uuid[], $3::uuid[], $4::numeric[], $5::numeric[], $6::numeric[]) \
                AS i(booking_id, guard_id, income, wht, transfer_amount)",
    )
    .bind(batch_id)
    .bind(&booking_ids)
    .bind(&guard_ids)
    .bind(&incomes)
    .bind(&whts)
    .bind(&transfers)
    .execute(&mut *tx)
    .await;
    if let Err(e) = res {
        tx.rollback().await?;
        // A unique violation means one of these bookings was paid out by a concurrent export —
        // refuse the whole batch rather than pay anyone twice; the admin re-previews the (now
        // smaller) backlog. Unchanged from the row-at-a-time version: the partial unique fires on
        // the offending row either way, and the whole transaction rolls back either way.
        if is_unique_violation(&e) {
            return Err(AppError::ConflictCode {
                code: "PAYOUT_ALREADY_PAID",
                message: "One or more jobs were already paid out; re-run the preview.".to_string(),
            });
        }
        return Err(e.into());
    }

    // The compliance record, in the SAME tx: an audit row for a batch that rolled back would be a
    // lie, and a batch with no audit row would be money moved with no trace of who moved it.
    insert_money_audit(
        &mut *tx,
        batch.created_by,
        AUDIT_PAYOUT_EXPORTED,
        AUDIT_TARGET_PAYOUT_BATCH,
        Some(batch_id),
        serde_json::json!({
            "file_ref": batch.file_ref,
            "batch_ref": batch.batch_ref,
            "value_date": batch.value_date,
            "total_amount": batch.total_amount.to_string(),
            "recipient_count": batch.recipient_count,
            "item_count": batch.items.len(),
        }),
    )
    .await?;

    tx.commit().await?;
    Ok(batch_id)
}

// ----- Payout batch lifecycle (history · re-download · status · void) -----

/// `money_audit.target_kind` for everything in this section.
pub const AUDIT_TARGET_PAYOUT_BATCH: &str = "payout_batch";
/// `money_audit.action` values. `&'static str` so only this fixed vocabulary can be logged.
pub const AUDIT_PAYOUT_EXPORTED: &str = "payout_batch_exported";
pub const AUDIT_PAYOUT_STATUS_CHANGED: &str = "payout_batch_status_changed";
pub const AUDIT_PAYOUT_VOIDED: &str = "payout_batch_voided";
/// A PER-ITEM void: some of a batch's bookings went back to the backlog while the rest stayed paid.
/// Its own action (not a `payout_batch_voided` with a smaller item count) because the two answer
/// different questions in an audit: "the file never landed" vs "these credit lines failed".
pub const AUDIT_PAYOUT_ITEMS_VOIDED: &str = "payout_batch_items_voided";

/// Append one row to the money-action compliance log. Generic over the executor so it can be called
/// INSIDE the transaction that performs the action (which is the only correct way — see
/// [`insert_payout_batch`]) as well as standalone.
pub async fn insert_money_audit<'e, E>(
    db: E,
    actor: Option<Uuid>,
    action: &str,
    target_kind: &str,
    target_id: Option<Uuid>,
    detail: Value,
) -> Result<(), AppError>
where
    E: sqlx::Executor<'e, Database = sqlx::Postgres>,
{
    sqlx::query(
        "INSERT INTO payment.money_audit (actor, action, target_kind, target_id, detail) \
         VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(actor)
    .bind(action)
    .bind(target_kind)
    .bind(target_id)
    .bind(detail)
    .execute(db)
    .await?;
    Ok(())
}

/// One page of the payout history, newest first, PLUS the total count so the screen can paginate.
/// The file text is never selected here (see [`PAYOUT_BATCH_COLUMNS`]).
pub async fn list_payout_batches(
    db: &sqlx::PgPool,
    limit: i64,
    offset: i64,
) -> Result<PayoutBatchList, AppError> {
    let batches: Vec<PayoutBatchRow> = sqlx::query_as(&format!(
        "SELECT {PAYOUT_BATCH_COLUMNS} FROM payment.payout_batches \
         ORDER BY created_at DESC, id DESC LIMIT $1 OFFSET $2"
    ))
    .bind(limit)
    .bind(offset)
    .fetch_all(db)
    .await?;
    let total: i64 = sqlx::query_scalar("SELECT count(*) FROM payment.payout_batches")
        .fetch_one(db)
        .await?;
    Ok(PayoutBatchList { batches, total })
}

/// One batch header + every booking it paid (the drill-down). 404 when the id is unknown.
pub async fn get_payout_batch(
    db: &sqlx::PgPool,
    batch_id: Uuid,
) -> Result<PayoutBatchDetail, AppError> {
    let batch: PayoutBatchRow = sqlx::query_as(&format!(
        "SELECT {PAYOUT_BATCH_COLUMNS} FROM payment.payout_batches WHERE id = $1"
    ))
    .bind(batch_id)
    .fetch_optional(db)
    .await?
    .ok_or_else(|| AppError::NotFound("ไม่พบไฟล์จ่ายเงินรายการนี้".to_string()))?;
    let items: Vec<PayoutBatchItemRow> = sqlx::query_as(
        "SELECT id, booking_id, guard_id, income, wht, transfer_amount, voided_at, created_at \
         FROM payment.payout_batch_items WHERE batch_id = $1 ORDER BY guard_id, created_at",
    )
    .bind(batch_id)
    .fetch_all(db)
    .await?;
    Ok(PayoutBatchDetail { batch, items })
}

/// The STORED file text for a re-download (never a regenerated one — the config, the WHT rate or a
/// guard profile may have changed since, and a money file must reproduce byte-for-byte). Reads only
/// the header, so the cost does not grow with the size of the batch.
///
/// 404 both when the batch is unknown and when it has no stored text (generated before the column
/// existed) — the second case is honest: there IS no file to hand over, and inventing one is worse.
pub async fn get_payout_batch_file(
    db: &sqlx::PgPool,
    batch_id: Uuid,
) -> Result<ExportedBatchFile, AppError> {
    let row: Option<(String, Option<String>)> =
        sqlx::query_as("SELECT file_ref, file_text FROM payment.payout_batches WHERE id = $1")
            .bind(batch_id)
            .fetch_optional(db)
            .await?;
    let (file_ref, file_text) =
        row.ok_or_else(|| AppError::NotFound("ไม่พบไฟล์จ่ายเงินรายการนี้".to_string()))?;
    let file_text = file_text.ok_or_else(|| {
        AppError::NotFound("ไฟล์นี้ถูกสร้างก่อนระบบเริ่มเก็บตัวไฟล์ไว้ จึงดาวน์โหลดซ้ำไม่ได้".to_string())
    })?;
    Ok(ExportedBatchFile {
        file_ref,
        file_text,
    })
}

/// Move a batch along its lifecycle (`generated → uploaded → confirmed | rejected`), enforcing the
/// legal transitions in ONE place — the pure table in [`crate::domain::batch_status`] — and stamping
/// the matching timestamp column. Writes the audit row in the same transaction. Returns the updated
/// header.
///
/// The current status is read `FOR UPDATE` so two admins clicking at once cannot both pass the
/// transition check against the same stale state. Voiding does NOT go through here: it has to touch
/// every item as well, so it is [`void_payout_batch`].
pub async fn set_payout_batch_status(
    db: &sqlx::PgPool,
    batch_id: Uuid,
    to: BatchStatus,
    note: Option<&str>,
    actor: Uuid,
) -> Result<PayoutBatchRow, AppError> {
    let mut tx = db.begin().await?;
    let from = locked_batch_status(&mut tx, batch_id).await?;
    batch_status::check_transition(BatchKind::Payout, from, to)?;

    // The timestamp column is chosen by the TARGET status, so the batch keeps a full history of
    // when each step happened rather than one column that forgets the previous one.
    let stamped = match to {
        BatchStatus::Uploaded => "uploaded_at",
        BatchStatus::Confirmed => "confirmed_at",
        BatchStatus::Rejected => "rejected_at",
        // `Generated` is only ever the initial state and `Voided` goes through `void_payout_batch`;
        // neither is reachable here (the transition table refuses both), but the arm must exist and
        // must not panic in the money path — re-stamping `created_at` is a harmless no-op write.
        BatchStatus::Generated | BatchStatus::Voided => "created_at",
    };
    // `stamped` is one of four hard-coded column names chosen by a match on an enum — never user
    // input — so interpolating it is safe (Postgres has no bind parameter for an identifier).
    let row: PayoutBatchRow = sqlx::query_as(&format!(
        "UPDATE payment.payout_batches \
            SET status = $2, status_note = $3, {stamped} = now() \
          WHERE id = $1 RETURNING {PAYOUT_BATCH_COLUMNS}"
    ))
    .bind(batch_id)
    .bind(to.as_str())
    .bind(note)
    .fetch_one(&mut *tx)
    .await?;

    insert_money_audit(
        &mut *tx,
        Some(actor),
        AUDIT_PAYOUT_STATUS_CHANGED,
        AUDIT_TARGET_PAYOUT_BATCH,
        Some(batch_id),
        serde_json::json!({
            "from": from.as_str(),
            "to": to.as_str(),
            "note": note,
            "file_ref": row.file_ref,
        }),
    )
    .await?;
    tx.commit().await?;
    Ok(row)
}

/// VOID a batch: flip the header to `voided`, stamp `voided_at` on EVERY one of its items, and write
/// the audit row — all in ONE transaction. Returns the updated header.
///
/// Stamping the ITEMS is the whole point, not bookkeeping: the paid-marker unique is partial on
/// `voided_at IS NULL`, and [`unpaid_payout_rows`] ignores voided items, so this is what actually
/// returns the work to the payable backlog. Flagging only the header would leave the bookings
/// unpayable forever — the exact bug void exists to fix.
///
/// Already-voided is a typed 409 from the pure transition table, never a silent no-op: the admin
/// needs to know the first void already happened (their page may be stale).
pub async fn void_payout_batch(
    db: &sqlx::PgPool,
    batch_id: Uuid,
    actor: Uuid,
    reason: &str,
) -> Result<PayoutBatchRow, AppError> {
    let mut tx = db.begin().await?;
    let from = locked_batch_status(&mut tx, batch_id).await?;
    batch_status::check_transition(BatchKind::Payout, from, BatchStatus::Voided)?;

    let row: PayoutBatchRow = sqlx::query_as(&format!(
        "UPDATE payment.payout_batches \
            SET status = 'voided', voided_at = now(), voided_by = $2, void_reason = $3 \
          WHERE id = $1 RETURNING {PAYOUT_BATCH_COLUMNS}"
    ))
    .bind(batch_id)
    .bind(actor)
    .bind(reason)
    .fetch_one(&mut *tx)
    .await?;

    // Every LIVE item goes back to the backlog. `voided_at IS NULL` in the predicate keeps the write
    // idempotent and preserves the original void time if this ever re-runs.
    let unmarked = sqlx::query(
        "UPDATE payment.payout_batch_items SET voided_at = now() \
          WHERE batch_id = $1 AND voided_at IS NULL",
    )
    .bind(batch_id)
    .execute(&mut *tx)
    .await?
    .rows_affected();

    insert_money_audit(
        &mut *tx,
        Some(actor),
        AUDIT_PAYOUT_VOIDED,
        AUDIT_TARGET_PAYOUT_BATCH,
        Some(batch_id),
        serde_json::json!({
            "from": from.as_str(),
            "reason": reason,
            "file_ref": row.file_ref,
            "items_returned_to_backlog": unmarked,
            "total_amount": row.total_amount.to_string(),
        }),
    )
    .await?;
    tx.commit().await?;
    Ok(row)
}

/// Return SOME of a batch's bookings to the payable backlog, leaving the batch itself alone.
///
/// WHY THIS EXISTS, AND WHY IT DELIBERATELY BYPASSES [`batch_status::is_terminal`]. SCB can ACCEPT a
/// bulk file and still fail individual credit lines — an unregistered PromptPay proxy, or one not
/// linked to a receiving account, is the everyday case. The file is structurally valid, so it passes
/// the whole-file check and the batch is honestly `confirmed`: most guards were paid. A handful were
/// not. Voiding the WHOLE batch would un-pay everyone (and `confirmed` is terminal, so it is not
/// even offered), which is why the only remedy used to be a hand-written UPDATE in production.
///
/// So this is an ITEM-level action, not a batch-level one: it does not consult the status machine,
/// does not move the batch's status, and works on a `confirmed` batch — that is the entire point.
/// What it DOES share with [`void_payout_batch`] is the transaction shape, deliberately: lock the
/// batch header first (so a concurrent whole-batch void or status change cannot interleave), stamp
/// `voided_at` on ONLY the named items, write the audit row, all in ONE transaction.
///
/// DO NOT "UNIFY" THIS WITH [`void_deduction_batch_items`], which REFUSES on `confirmed`. The
/// difference is the file shape, not an inconsistency: a `PPY` payout file carries one credit line
/// PER GUARD, so an individual line really can bounce inside a confirmed file. An `OAT` sweep carries
/// ONE line for the whole batch, so `confirmed` there means the entire summed amount moved and
/// releasing a job would let its cut be swept a second time. Same table, opposite correct answer.
///
/// Rejects, each as a typed 4xx and never a partial success: a `booking_id` that is not in THIS
/// batch (404 — an admin acting on the wrong file must not silently un-pay a subset of another),
/// and an item already voided (409 — their page is stale, and pretending it worked would hide that
/// the money question was already answered). The empty list is refused before this by the API's pure
/// validator. Returns the batch drill-down so the caller re-renders the truth it just wrote.
pub async fn void_payout_batch_items(
    db: &sqlx::PgPool,
    batch_id: Uuid,
    booking_ids: &[Uuid],
    actor: Uuid,
    reason: &str,
) -> Result<PayoutBatchDetail, AppError> {
    let mut tx = db.begin().await?;
    // Locks the header (404s an unknown batch). The status is read for the AUDIT record only — it
    // is deliberately not gated on: see the note above.
    let status = locked_batch_status(&mut tx, batch_id).await?;
    let file_ref: String =
        sqlx::query_scalar("SELECT file_ref FROM payment.payout_batches WHERE id = $1")
            .bind(batch_id)
            .fetch_one(&mut *tx)
            .await?;

    // Lock the item rows too: two admins voiding overlapping lines must serialise, or the second
    // would see them live, pass the check, and update zero rows.
    let found: Vec<(Uuid, Option<DateTime<Utc>>)> = sqlx::query_as(
        "SELECT booking_id, voided_at FROM payment.payout_batch_items \
          WHERE batch_id = $1 AND booking_id = ANY($2) FOR UPDATE",
    )
    .bind(batch_id)
    .bind(booking_ids)
    .fetch_all(&mut *tx)
    .await?;

    let missing: Vec<Uuid> = booking_ids
        .iter()
        .copied()
        .filter(|id| !found.iter().any(|(b, _)| b == id))
        .collect();
    if !missing.is_empty() {
        return Err(AppError::NotFound(format!(
            "ไม่พบงาน {} รายการในไฟล์จ่ายเงินนี้ (เช่น {}) — ตรวจสอบว่าเลือกงานจากไฟล์ที่ถูกต้อง",
            missing.len(),
            missing[0]
        )));
    }
    if let Some((already, _)) = found.iter().find(|(_, voided)| voided.is_some()) {
        return Err(AppError::ConflictCode {
            code: "PAYOUT_ITEM_ALREADY_VOIDED",
            message: format!(
                "งานบางรายการถูกดึงกลับเข้าคิวรอจ่ายไปแล้ว (เช่น {already}) — โปรดรีเฟรชหน้าจอแล้วเลือกใหม่"
            ),
        });
    }

    let returned = sqlx::query(
        "UPDATE payment.payout_batch_items SET voided_at = now() \
          WHERE batch_id = $1 AND booking_id = ANY($2) AND voided_at IS NULL",
    )
    .bind(batch_id)
    .bind(booking_ids)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    // The checks above proved every named booking is present and live, and the rows are locked, so
    // a short count means the two disagree — refuse the whole thing rather than report a number the
    // admin would read as "these went back to the queue".
    if returned != booking_ids.len() as u64 {
        return Err(AppError::Internal(format!(
            "payout item void touched {returned} of {} rows",
            booking_ids.len()
        )));
    }

    insert_money_audit(
        &mut *tx,
        Some(actor),
        AUDIT_PAYOUT_ITEMS_VOIDED,
        AUDIT_TARGET_PAYOUT_BATCH,
        Some(batch_id),
        serde_json::json!({
            // The batch's OWN status is untouched; recording it explains what state the correction
            // was made against (usually `confirmed` — the bank took the file, some lines failed).
            "batch_status": status.as_str(),
            "reason": reason,
            "file_ref": file_ref,
            "booking_ids": booking_ids,
            "items_returned_to_backlog": returned,
        }),
    )
    .await?;
    tx.commit().await?;
    get_payout_batch(db, batch_id).await
}

/// Read + LOCK one batch's current status inside a transaction (so a concurrent status change or
/// void cannot slip between the check and the write). 404 when the id is unknown; a status the enum
/// does not know is an internal error, not a client one — the DB CHECK should have refused it.
async fn locked_batch_status(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    batch_id: Uuid,
) -> Result<BatchStatus, AppError> {
    let stored: Option<String> =
        sqlx::query_scalar("SELECT status FROM payment.payout_batches WHERE id = $1 FOR UPDATE")
            .bind(batch_id)
            .fetch_optional(&mut **tx)
            .await?;
    let stored = stored.ok_or_else(|| AppError::NotFound("ไม่พบไฟล์จ่ายเงินรายการนี้".to_string()))?;
    BatchStatus::parse(&stored)
        .ok_or_else(|| AppError::Internal(format!("unknown payout batch status: {stored}")))
}

// ----- Customer refunds (stream ① ยอดที่ต้องโอนคืนกับคนจ้าง — the SCB refund file) -----

/// `money_audit.target_kind` for everything in this section.
pub const AUDIT_TARGET_REFUND_BATCH: &str = "refund_batch";
/// `money_audit.action` values. `&'static str` so only this fixed vocabulary can be logged.
pub const AUDIT_REFUND_EXPORTED: &str = "refund_batch_exported";
pub const AUDIT_REFUND_STATUS_CHANGED: &str = "refund_batch_status_changed";
pub const AUDIT_REFUND_VOIDED: &str = "refund_batch_voided";
/// A PER-ITEM void: some of a batch's obligations went back to the refundable queue while the rest
/// stayed settled. Its own action (not a `refund_batch_voided` with a smaller item count) because
/// the two answer different questions in an audit: "the file never landed" vs "these credit lines
/// failed".
pub const AUDIT_REFUND_ITEMS_VOIDED: &str = "refund_batch_items_voided";

/// The batch-header columns every refund read returns. `has_file` is DERIVED, not stored: the list
/// and the drill-down must tell the screen whether the re-download will work without shipping the
/// file text itself.
const REFUND_BATCH_COLUMNS: &str =
    "id, file_ref, system_ref, batch_ref, value_date, total_amount, \
     recipient_count, status, status_note, void_reason, (file_text IS NOT NULL) AS has_file, \
     created_by, created_at, uploaded_at, confirmed_at, rejected_at, voided_at, voided_by";

/// The UNPAID customer-refund backlog: every obligation still owed, from BOTH lanes, that no LIVE
/// `refund_batch_items` row has claimed. Ordered by customer so the aggregator can group one credit
/// line per person.
///
/// TWO LANES, one UNION, because two different tables owe this money and neither may be forgotten
/// (a missed lane is unrefunded money nobody is looking for):
///  * **A — `payment.payments`**: `refund_status = 'pending'` with `refund_amount > 0`. This is the
///    completion-reconcile overpay (`reconcile_on_completion`), the cancellation refund — full or
///    net of a retained fee (`refund_on_cancellation`) — and the race-lost pre-pay compensator
///    (`refund_race_lost_prepay`). The amount is `refund_amount`, the customer is `customer_id`, and
///    the row may be `completed` (a partial refund) or `refunded` (a full one), so the payment
///    STATUS is deliberately not filtered on. `refund_amount > 0` is belt-and-braces: every writer
///    already sets `refund_status` only when money is actually going back.
///  * **B — `payment.payment_slips`**: `applied = FALSE AND refund_status = 'pending'` — a SECOND,
///    REAL transfer for an already-paid booking (migration 0006). Different table, different id, and
///    the amount is the slip's OWN `amount` (the whole duplicate transfer goes back). It has NO
///    `customer_id` column, so the customer is resolved by joining its `payment_id` to the payment
///    it duplicated.
///
/// `sel` narrows the run (see [`RefundSelection`]): to the customers the admin ticked, and/or to a
/// day window. The window is compared in **Thai local days** (`Asia/Bangkok`), inclusive on both
/// ends, against the timestamp at which the obligation AROSE — `payments.updated_at` (stamped by the
/// settle that wrote `refund_status`) for lane A, `payment_slips.created_at` (the moment the
/// duplicate transfer was recorded) for lane B.
///
/// A VOIDED item does not count as settled (`i.voided_at IS NULL`): voiding exists to put the
/// obligation back in this backlog, and the item rows are kept as history rather than deleted — so
/// without that predicate a voided obligation would stay filtered out and could never be refunded.
///
/// THE BACKLOG IS READ FROM THE PRIMARY, DELIBERATELY — do not "optimise" it onto the read replica.
/// This is the single most serious defect the payout's P2 review found, and it is a read-after-write
/// on the money path: every write that changes this query's answer goes to the primary
/// (`refund_batch_items` rows on export, `voided_at` + `refund_status = 'pending'` on a void), and
/// the same admin performs those writes seconds before reading here. On a lagging replica:
///  * void a batch, then immediately export → the items still look live, so the obligations the void
///    just released are SILENTLY MISSING from the new file and the void looks like it did nothing;
///  * export, then export again → a marker that has not replicated lets an obligation be picked up
///    twice. The partial unique still refuses the second batch, so nobody is refunded twice — but
///    the whole file is lost to a confusing 409 instead.
pub async fn unpaid_refund_rows(
    db: &sqlx::PgPool,
    sel: &RefundSelection,
) -> Result<Vec<UnpaidRefundRow>, AppError> {
    let rows = sqlx::query_as::<_, UnpaidRefundRow>(
        "SELECT source_kind, source_id, booking_id, customer_id, amount FROM ( \
             SELECT 'payment'::text AS source_kind, p.id AS source_id, p.booking_id, \
                    p.customer_id, p.refund_amount AS amount, p.updated_at AS owed_at \
               FROM payment.payments p \
              WHERE p.refund_status = 'pending' \
                AND p.refund_amount IS NOT NULL AND p.refund_amount > 0 \
                AND NOT EXISTS ( \
                    SELECT 1 FROM payment.refund_batch_items i \
                     WHERE i.source_kind = 'payment' AND i.source_id = p.id \
                       AND i.voided_at IS NULL) \
             UNION ALL \
             SELECT 'slip'::text AS source_kind, s.id AS source_id, s.booking_id, \
                    p.customer_id, s.amount, s.created_at AS owed_at \
               FROM payment.payment_slips s \
               JOIN payment.payments p ON p.id = s.payment_id \
              WHERE s.applied = FALSE AND s.refund_status = 'pending' AND s.amount > 0 \
                AND NOT EXISTS ( \
                    SELECT 1 FROM payment.refund_batch_items i \
                     WHERE i.source_kind = 'slip' AND i.source_id = s.id \
                       AND i.voided_at IS NULL) \
         ) owed \
         WHERE ($1::uuid[] IS NULL OR customer_id = ANY($1)) \
           AND ($2::date IS NULL OR (owed_at AT TIME ZONE 'Asia/Bangkok')::date >= $2) \
           AND ($3::date IS NULL OR (owed_at AT TIME ZONE 'Asia/Bangkok')::date <= $3) \
         ORDER BY customer_id, owed_at, source_kind, source_id \
         LIMIT $4",
    )
    .bind(sel.customer_ids.as_deref())
    .bind(sel.from)
    .bind(sel.to)
    .bind(MAX_REFUND_BACKLOG_ROWS + 1)
    .fetch_all(db)
    .await?;
    // Bounded like the other two backlogs, and refused rather than truncated for the same reason —
    // a short refund file silently leaves customers unpaid while looking complete. See
    // [`MAX_PAYOUT_BACKLOG_ROWS`].
    if rows.len() as i64 > MAX_REFUND_BACKLOG_ROWS {
        return Err(too_many_rows(
            "รายการรอคืนเงินในช่วงที่เลือกมีมากเกินไป",
            MAX_REFUND_BACKLOG_ROWS,
        ));
    }
    Ok(rows)
}

/// Persist a generated refund batch: the `refund_batches` header (INCLUDING the exact file text
/// handed to the admin), all `refund_batch_items`, the `refund_status → 'processed'` advance on BOTH
/// source tables, and the `money_audit` row — in ONE transaction. Returns the new batch id.
///
/// ADVANCING THE SOURCE ROWS IS THE POINT OF THIS FUNCTION, not bookkeeping around it. Before stream
/// ① existed, NOTHING in the codebase ever wrote `refund_status = 'processed'`: the queue only ever
/// gained rows, the customer got a push saying their money was on the way, and the money never left.
/// The marker rows and the queue state are advanced together so they can never disagree about
/// whether a customer has been paid.
///
/// The partial `UNIQUE(source_kind, source_id) WHERE voided_at IS NULL` on the items is the atomic
/// double-refund guard: if any obligation in this batch is already claimed by a LIVE item (a
/// concurrent export won the race), the insert violates the unique, the whole tx ROLLS BACK, and a
/// typed 409 is returned so nothing is refunded twice.
///
/// The batch reference is claimed in `payment.scb_file_refs` in the same tx — the SHARED space that
/// also catches a PAYOUT export stamped in the same Bangkok second (see [`reserve_scb_file_ref`]).
///
/// `updated_at` on the payments rows is deliberately LEFT ALONE. It is what the backlog's day window
/// compares against — "when the refund became owed" — so stamping it here would silently move an
/// obligation into a different window if the batch were later voided and re-previewed.
pub async fn insert_refund_batch(
    db: &sqlx::PgPool,
    batch: &NewRefundBatch,
) -> Result<Uuid, AppError> {
    let mut tx = db.begin().await?;
    let inserted: Result<Uuid, sqlx::Error> = sqlx::query_scalar(
        "INSERT INTO payment.refund_batches \
             (file_ref, system_ref, batch_ref, value_date, total_amount, recipient_count, \
              file_text, status, created_by) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'generated', $8) RETURNING id",
    )
    .bind(&batch.file_ref)
    .bind(&batch.system_ref)
    .bind(&batch.batch_ref)
    .bind(batch.value_date)
    .bind(batch.total_amount)
    // CUSTOMERS (one TXNDET each), not obligations (see `NewRefundBatch::recipient_count`).
    .bind(batch.recipient_count as i32)
    .bind(&batch.file_text)
    .bind(batch.created_by)
    .fetch_one(&mut *tx)
    .await;
    // `uq_refund_batches_file_ref` (migration 0011) — the same guard, and the same reasoning, as the
    // payout's: `file_ref` is `batch_ref || product`, the batch ref is a timestamp at ONE-SECOND
    // resolution, so two refund exports committed in the same Bangkok second collide here even when
    // their customer selections are DISJOINT (nothing for the per-obligation marker to catch). Their
    // customer transaction refs are derived from the same batch ref, so two files would carry the
    // refs SCB de-dups on. A typed 409, never a retry loop sleeping in the request path: the whole
    // insert is one transaction, so the loser rolls back with NOTHING marked refunded.
    let batch_id = match inserted {
        Ok(id) => id,
        Err(e) => {
            tx.rollback().await?;
            if is_unique_violation(&e) {
                return Err(refund_batch_ref_taken());
            }
            return Err(e.into());
        }
    };

    // …and the SHARED reservation the per-table unique above cannot do: the PAYOUT export (stream ③)
    // stamps the same PromptPay product code off the same one-second clock, in a table
    // `uq_refund_batches_file_ref` cannot see, so only a cross-stream claim catches a refund and a
    // payout generated in the same Bangkok second. Inside the transaction, so a collision rolls this
    // export back with nothing marked processed — the same typed 409, because it is the same
    // situation and the same remedy. See migration 0012.
    if let Err(e) = reserve_scb_file_ref(
        &mut tx,
        &batch.file_ref,
        &batch.batch_ref,
        SCB_STREAM_REFUND,
        batch_id,
    )
    .await
    {
        tx.rollback().await?;
        if is_unique_violation(&e) {
            return Err(refund_batch_ref_taken());
        }
        return Err(e.into());
    }

    // ONE statement for every marker (see the `UNNEST` note above).
    let mut source_kinds = Vec::with_capacity(batch.items.len());
    let mut source_ids = Vec::with_capacity(batch.items.len());
    let mut booking_ids = Vec::with_capacity(batch.items.len());
    let mut customer_ids = Vec::with_capacity(batch.items.len());
    let mut amounts = Vec::with_capacity(batch.items.len());
    for item in &batch.items {
        source_kinds.push(item.source_kind.clone());
        source_ids.push(item.source_id);
        booking_ids.push(item.booking_id);
        customer_ids.push(item.customer_id);
        amounts.push(item.amount);
    }
    let res = sqlx::query(
        "INSERT INTO payment.refund_batch_items \
             (batch_id, source_kind, source_id, booking_id, customer_id, amount) \
         SELECT $1, i.source_kind, i.source_id, i.booking_id, i.customer_id, i.amount \
           FROM UNNEST($2::text[], $3::uuid[], $4::uuid[], $5::uuid[], $6::numeric[]) \
                AS i(source_kind, source_id, booking_id, customer_id, amount)",
    )
    .bind(batch_id)
    .bind(&source_kinds)
    .bind(&source_ids)
    .bind(&booking_ids)
    .bind(&customer_ids)
    .bind(&amounts)
    .execute(&mut *tx)
    .await;
    if let Err(e) = res {
        tx.rollback().await?;
        // A unique violation means one of these obligations was claimed by a concurrent export —
        // refuse the whole batch rather than refund anyone twice; the admin re-previews the (now
        // smaller) backlog.
        if is_unique_violation(&e) {
            return Err(AppError::ConflictCode {
                code: "REFUND_ALREADY_EXPORTED",
                message: "มีรายการคืนเงินบางรายการถูกใส่ในไฟล์อื่นไปแล้ว — กรุณาดูตัวอย่างใหม่แล้วสร้างไฟล์อีกครั้ง"
                    .to_string(),
            });
        }
        return Err(e.into());
    }

    // CLOSE THE QUEUE — the half that never existed. Split by lane: the two tables have different
    // predicates, and lane B must keep `applied = FALSE` in the WHERE so an APPLIED slip (the one
    // that actually settled its payment) can never be dragged into a refund workflow by a stray id.
    let mut parsed = Vec::with_capacity(batch.items.len());
    for item in &batch.items {
        // A kind the enum does not know cannot occur — the aggregation builds these and the DB CHECK
        // would have refused the item insert above — so it is an INTERNAL error, never a default.
        // Falling back to a lane would advance the WRONG table and leave the real obligation
        // permanently pending while a stranger's row was marked settled.
        let Some(kind) = RefundSourceKind::parse(&item.source_kind) else {
            tx.rollback().await?;
            return Err(AppError::Internal(format!(
                "unknown refund source kind: {}",
                item.source_kind
            )));
        };
        parsed.push(RefundSource {
            kind,
            id: item.source_id,
        });
    }
    let (payment_ids, slip_ids) = split_refund_sources(parsed);

    let advanced_payments = sqlx::query(
        "UPDATE payment.payments SET refund_status = 'processed' \
          WHERE id = ANY($1) AND refund_status = 'pending'",
    )
    .bind(&payment_ids)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    let advanced_slips = sqlx::query(
        "UPDATE payment.payment_slips SET refund_status = 'processed' \
          WHERE id = ANY($1) AND applied = FALSE AND refund_status = 'pending'",
    )
    .bind(&slip_ids)
    .execute(&mut *tx)
    .await?
    .rows_affected();

    // Every obligation in this file was read out of the backlog moments ago as `pending`, and the
    // marker inserts above just proved none of them was claimed. A short count therefore means the
    // source row moved underneath us — refuse the WHOLE batch rather than hand the admin a file that
    // pays a customer whose queue row says something else. The tx rolls back: nothing is marked.
    let expected = (payment_ids.len() + slip_ids.len()) as u64;
    if advanced_payments + advanced_slips != expected {
        tx.rollback().await?;
        return Err(AppError::ConflictCode {
            code: "REFUND_QUEUE_CHANGED",
            message: "สถานะคิวคืนเงินเปลี่ยนไประหว่างสร้างไฟล์ — ยังไม่มีรายการใดถูกทำเครื่องหมายว่าคืนแล้ว กรุณาดูตัวอย่างใหม่แล้วลองอีกครั้ง"
                .to_string(),
        });
    }

    // The compliance record, in the SAME tx: an audit row for a batch that rolled back would be a
    // lie, and a batch with no audit row would be money moved with no trace of who moved it.
    insert_money_audit(
        &mut *tx,
        batch.created_by,
        AUDIT_REFUND_EXPORTED,
        AUDIT_TARGET_REFUND_BATCH,
        Some(batch_id),
        serde_json::json!({
            "file_ref": batch.file_ref,
            "batch_ref": batch.batch_ref,
            "value_date": batch.value_date,
            "total_amount": batch.total_amount.to_string(),
            "recipient_count": batch.recipient_count,
            "item_count": batch.items.len(),
            "payments_marked_processed": advanced_payments,
            "slips_marked_processed": advanced_slips,
        }),
    )
    .await?;

    tx.commit().await?;
    Ok(batch_id)
}

/// Split refund obligations into the two lanes' id lists, so each source table is updated with its
/// OWN predicate. One shared list would force a single UPDATE over an id space that spans two
/// tables — the exact ambiguity [`RefundSourceKind`] exists to prevent.
fn split_refund_sources(sources: impl IntoIterator<Item = RefundSource>) -> (Vec<Uuid>, Vec<Uuid>) {
    let mut payments = Vec::new();
    let mut slips = Vec::new();
    for s in sources {
        match s.kind {
            RefundSourceKind::Payment => payments.push(s.id),
            RefundSourceKind::Slip => slips.push(s.id),
        }
    }
    (payments, slips)
}

/// Put the named obligations back in the refundable queue: `refund_status → 'pending'` on whichever
/// table owns each one. Returns how many rows each lane actually moved (for the audit record).
///
/// The guard is `refund_status IS NOT NULL`, not `= 'processed'`: the caller has just un-marked
/// these items, i.e. asserted that THIS file did not settle them, and the backlog only re-lists a
/// row whose status is exactly `'pending'`. Leaving a row in any other state would un-mark the item
/// while keeping the obligation invisible — the worst of both. A `NULL` row is skipped because NULL
/// means no refund is owed at all, and inventing one would refund money that was never due.
async fn return_refund_sources_to_queue(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    payment_ids: &[Uuid],
    slip_ids: &[Uuid],
) -> Result<(u64, u64), AppError> {
    let payments = sqlx::query(
        "UPDATE payment.payments SET refund_status = 'pending' \
          WHERE id = ANY($1) AND refund_status IS NOT NULL",
    )
    .bind(payment_ids)
    .execute(&mut **tx)
    .await?
    .rows_affected();
    let slips = sqlx::query(
        "UPDATE payment.payment_slips SET refund_status = 'pending' \
          WHERE id = ANY($1) AND applied = FALSE AND refund_status IS NOT NULL",
    )
    .bind(slip_ids)
    .execute(&mut **tx)
    .await?
    .rows_affected();
    Ok((payments, slips))
}

/// One page of the refund-file history, newest first, PLUS the total count so the screen can
/// paginate. The file text is never selected here (see [`REFUND_BATCH_COLUMNS`]).
pub async fn list_refund_batches(
    db: &sqlx::PgPool,
    limit: i64,
    offset: i64,
) -> Result<RefundBatchList, AppError> {
    let batches: Vec<RefundBatchRow> = sqlx::query_as(&format!(
        "SELECT {REFUND_BATCH_COLUMNS} FROM payment.refund_batches \
         ORDER BY created_at DESC, id DESC LIMIT $1 OFFSET $2"
    ))
    .bind(limit)
    .bind(offset)
    .fetch_all(db)
    .await?;
    let total: i64 = sqlx::query_scalar("SELECT count(*) FROM payment.refund_batches")
        .fetch_one(db)
        .await?;
    Ok(RefundBatchList { batches, total })
}

/// One refund batch header + every obligation it settled (a voided item shows its `voided_at`, i.e.
/// that obligation is back in the queue). 404 when the id is unknown.
pub async fn get_refund_batch(
    db: &sqlx::PgPool,
    batch_id: Uuid,
) -> Result<RefundBatchDetail, AppError> {
    let batch: RefundBatchRow = sqlx::query_as(&format!(
        "SELECT {REFUND_BATCH_COLUMNS} FROM payment.refund_batches WHERE id = $1"
    ))
    .bind(batch_id)
    .fetch_optional(db)
    .await?
    .ok_or_else(|| AppError::NotFound("ไม่พบไฟล์คืนเงินรายการนี้".to_string()))?;
    let items: Vec<RefundBatchItemRow> = sqlx::query_as(
        "SELECT id, source_kind, source_id, booking_id, customer_id, amount, voided_at, created_at \
         FROM payment.refund_batch_items WHERE batch_id = $1 \
         ORDER BY customer_id, created_at, source_kind, source_id",
    )
    .bind(batch_id)
    .fetch_all(db)
    .await?;
    Ok(RefundBatchDetail { batch, items })
}

/// The STORED refund-file text for a re-download (never a regenerated one — the backlog has moved on
/// since, and a money file must reproduce byte-for-byte). Reads only the header, so the cost does not
/// grow with the size of the batch. 404 both when the batch is unknown and when it has no stored
/// text.
pub async fn get_refund_batch_file(
    db: &sqlx::PgPool,
    batch_id: Uuid,
) -> Result<ExportedBatchFile, AppError> {
    let row: Option<(String, Option<String>)> =
        sqlx::query_as("SELECT file_ref, file_text FROM payment.refund_batches WHERE id = $1")
            .bind(batch_id)
            .fetch_optional(db)
            .await?;
    let (file_ref, file_text) =
        row.ok_or_else(|| AppError::NotFound("ไม่พบไฟล์คืนเงินรายการนี้".to_string()))?;
    let file_text = file_text
        .ok_or_else(|| AppError::NotFound("ไฟล์นี้ไม่มีตัวไฟล์เก็บไว้ จึงดาวน์โหลดซ้ำไม่ได้".to_string()))?;
    Ok(ExportedBatchFile {
        file_ref,
        file_text,
    })
}

/// Move a refund batch along its lifecycle (`generated → uploaded → confirmed | rejected`), enforcing
/// the legal transitions in the ONE shared pure table ([`crate::domain::batch_status`]) and stamping
/// the matching timestamp column. Writes the audit row in the same transaction.
///
/// The current status is read `FOR UPDATE` so two admins clicking at once cannot both pass the
/// transition check against the same stale state. Voiding does NOT go through here: it has to touch
/// every item AND both source tables, so it is [`void_refund_batch`].
pub async fn set_refund_batch_status(
    db: &sqlx::PgPool,
    batch_id: Uuid,
    to: BatchStatus,
    note: Option<&str>,
    actor: Uuid,
) -> Result<RefundBatchRow, AppError> {
    let mut tx = db.begin().await?;
    let from = locked_refund_batch_status(&mut tx, batch_id).await?;
    batch_status::check_transition(BatchKind::Refund, from, to)?;

    let stamped = match to {
        BatchStatus::Uploaded => "uploaded_at",
        BatchStatus::Confirmed => "confirmed_at",
        BatchStatus::Rejected => "rejected_at",
        // `Generated` is only ever the initial state and `Voided` goes through `void_refund_batch`;
        // neither is reachable here (the transition table refuses both), but the arm must exist and
        // must not panic in the money path — re-stamping `created_at` is a harmless no-op write.
        BatchStatus::Generated | BatchStatus::Voided => "created_at",
    };
    // `stamped` is one of four hard-coded column names chosen by a match on an enum — never user
    // input — so interpolating it is safe (Postgres has no bind parameter for an identifier).
    let row: RefundBatchRow = sqlx::query_as(&format!(
        "UPDATE payment.refund_batches \
            SET status = $2, status_note = $3, {stamped} = now() \
          WHERE id = $1 RETURNING {REFUND_BATCH_COLUMNS}"
    ))
    .bind(batch_id)
    .bind(to.as_str())
    .bind(note)
    .fetch_one(&mut *tx)
    .await?;

    insert_money_audit(
        &mut *tx,
        Some(actor),
        AUDIT_REFUND_STATUS_CHANGED,
        AUDIT_TARGET_REFUND_BATCH,
        Some(batch_id),
        serde_json::json!({
            "from": from.as_str(),
            "to": to.as_str(),
            "note": note,
            "file_ref": row.file_ref,
        }),
    )
    .await?;
    tx.commit().await?;
    Ok(row)
}

/// VOID a refund batch: flip the header to `voided`, stamp `voided_at` on EVERY live item, RETURN
/// each of those obligations to the queue (`refund_status → 'pending'` on its own table), and write
/// the audit row — all in ONE transaction.
///
/// The two writes on the items are what actually undo the export, and BOTH are required: the
/// paid-marker unique is partial on `voided_at IS NULL` and [`unpaid_refund_rows`] ignores voided
/// items, but the backlog ALSO requires the source row to say `pending`. Flagging only the header
/// would leave the obligations unrefundable forever; flagging only the items would leave them
/// invisible. Either half alone is the bug void exists to fix.
///
/// Already-voided is a typed 409 from the pure transition table, never a silent no-op: the admin
/// needs to know the first void already happened (their page may be stale).
pub async fn void_refund_batch(
    db: &sqlx::PgPool,
    batch_id: Uuid,
    actor: Uuid,
    reason: &str,
) -> Result<RefundBatchRow, AppError> {
    let mut tx = db.begin().await?;
    let from = locked_refund_batch_status(&mut tx, batch_id).await?;
    batch_status::check_transition(BatchKind::Refund, from, BatchStatus::Voided)?;

    let row: RefundBatchRow = sqlx::query_as(&format!(
        "UPDATE payment.refund_batches \
            SET status = 'voided', voided_at = now(), voided_by = $2, void_reason = $3 \
          WHERE id = $1 RETURNING {REFUND_BATCH_COLUMNS}"
    ))
    .bind(batch_id)
    .bind(actor)
    .bind(reason)
    .fetch_one(&mut *tx)
    .await?;

    // Which obligations are still LIVE — read (and locked) BEFORE the flag is stamped, because they
    // are exactly the rows whose source status must go back to `pending`. Items already voided by an
    // earlier per-item correction are left alone: their obligations returned to the queue then, and
    // may since have ridden another file.
    let live: Vec<(String, Uuid)> = sqlx::query_as(
        "SELECT source_kind, source_id FROM payment.refund_batch_items \
          WHERE batch_id = $1 AND voided_at IS NULL FOR UPDATE",
    )
    .bind(batch_id)
    .fetch_all(&mut *tx)
    .await?;

    // `voided_at IS NULL` in the predicate keeps the write idempotent and preserves the original
    // void time if this ever re-runs.
    let unmarked = sqlx::query(
        "UPDATE payment.refund_batch_items SET voided_at = now() \
          WHERE batch_id = $1 AND voided_at IS NULL",
    )
    .bind(batch_id)
    .execute(&mut *tx)
    .await?
    .rows_affected();

    let (payment_ids, slip_ids) = split_refund_sources(live.iter().filter_map(|(kind, id)| {
        // A stored kind the enum does not know would be a row the DB CHECK should have refused.
        // Skipping it is the only safe answer here: guessing a lane would flip the WRONG table's
        // refund status back to `pending`, i.e. queue up a refund that is not owed.
        RefundSourceKind::parse(kind).map(|kind| RefundSource { kind, id: *id })
    }));
    let (payments_returned, slips_returned) =
        return_refund_sources_to_queue(&mut tx, &payment_ids, &slip_ids).await?;

    insert_money_audit(
        &mut *tx,
        Some(actor),
        AUDIT_REFUND_VOIDED,
        AUDIT_TARGET_REFUND_BATCH,
        Some(batch_id),
        serde_json::json!({
            "from": from.as_str(),
            "reason": reason,
            "file_ref": row.file_ref,
            "items_returned_to_queue": unmarked,
            "payments_returned_to_pending": payments_returned,
            "slips_returned_to_pending": slips_returned,
            "total_amount": row.total_amount.to_string(),
        }),
    )
    .await?;
    tx.commit().await?;
    Ok(row)
}

/// Return SOME of a refund batch's obligations to the refundable queue, leaving the batch itself
/// alone.
///
/// WHY THIS EXISTS, AND WHY IT DELIBERATELY BYPASSES [`batch_status::is_terminal`]. SCB can ACCEPT a
/// bulk file and still fail individual credit lines — a PromptPay proxy not linked to a receiving
/// account is the everyday case. The file is structurally valid, so it passes the whole-file check
/// and the batch is honestly `confirmed`: most customers got their money, a handful did not. Voiding
/// the whole batch would un-settle the ones who DID, and `confirmed` is terminal so it is not even
/// offered — which would leave a hand-written UPDATE in production as the only remedy.
///
/// So this is an ITEM-level action: it does not consult the status machine, does not move the
/// batch's status, and works on a `confirmed` batch — that is the entire point. What it DOES share
/// with [`void_refund_batch`] is the transaction shape, deliberately: lock the batch header first
/// (so a concurrent whole-batch void or status change cannot interleave), stamp `voided_at` on ONLY
/// the named items, return ONLY those obligations to `pending`, write the audit row, in ONE
/// transaction.
///
/// DO NOT "UNIFY" THIS WITH [`void_deduction_batch_items`], which REFUSES on `confirmed`. The
/// difference is the file shape, not an inconsistency: a `PPY` refund file carries one credit line
/// PER CUSTOMER, so an individual line really can bounce inside a confirmed file. An `OAT` sweep
/// carries ONE line for the whole batch, so `confirmed` there means the entire summed amount moved
/// and releasing a job would let its cut be swept a second time. Same table, opposite correct answer.
///
/// Rejects, each as a typed 4xx and never a partial success: an obligation that is not in THIS batch
/// (404 — an admin acting on the wrong file must not silently un-settle a subset of another), and one
/// already voided (409 — their page is stale, and pretending it worked would hide that the money
/// question was already answered). The empty list is refused before this by the API's pure validator.
/// Returns the batch drill-down so the caller re-renders the truth it just wrote.
pub async fn void_refund_batch_items(
    db: &sqlx::PgPool,
    batch_id: Uuid,
    sources: &[RefundSource],
    actor: Uuid,
    reason: &str,
) -> Result<RefundBatchDetail, AppError> {
    let mut tx = db.begin().await?;
    // Locks the header (404s an unknown batch). The status is read for the AUDIT record only — it is
    // deliberately not gated on: see the note above.
    let status = locked_refund_batch_status(&mut tx, batch_id).await?;
    let file_ref: String =
        sqlx::query_scalar("SELECT file_ref FROM payment.refund_batches WHERE id = $1")
            .bind(batch_id)
            .fetch_one(&mut *tx)
            .await?;

    let (payment_ids, slip_ids) = split_refund_sources(sources.iter().copied());

    // Lock the item rows too: two admins voiding overlapping lines must serialise, or the second
    // would see them live, pass the check, and update zero rows. Matching BOTH halves of the
    // composite key at once — a `source_id` alone could name the other lane's row.
    let found: Vec<(String, Uuid, Option<DateTime<Utc>>)> = sqlx::query_as(
        "SELECT source_kind, source_id, voided_at FROM payment.refund_batch_items \
          WHERE batch_id = $1 \
            AND ((source_kind = 'payment' AND source_id = ANY($2)) \
              OR (source_kind = 'slip'    AND source_id = ANY($3))) FOR UPDATE",
    )
    .bind(batch_id)
    .bind(&payment_ids)
    .bind(&slip_ids)
    .fetch_all(&mut *tx)
    .await?;

    let missing: Vec<&RefundSource> = sources
        .iter()
        .filter(|s| {
            !found
                .iter()
                .any(|(kind, id, _)| kind == s.kind.as_str() && id == &s.id)
        })
        .collect();
    if let Some(first) = missing.first() {
        return Err(AppError::NotFound(format!(
            "ไม่พบรายการคืนเงิน {} รายการในไฟล์นี้ (เช่น {} {}) — ตรวจสอบว่าเลือกรายการจากไฟล์ที่ถูกต้อง",
            missing.len(),
            first.kind.label_th(),
            first.id
        )));
    }
    if let Some((kind, id, _)) = found.iter().find(|(_, _, voided)| voided.is_some()) {
        return Err(AppError::ConflictCode {
            code: "REFUND_ITEM_ALREADY_VOIDED",
            message: format!(
                "รายการคืนเงินบางรายการถูกดึงกลับเข้าคิวไปแล้ว (เช่น {kind} {id}) — โปรดรีเฟรชหน้าจอแล้วเลือกใหม่"
            ),
        });
    }

    let returned = sqlx::query(
        "UPDATE payment.refund_batch_items SET voided_at = now() \
          WHERE batch_id = $1 AND voided_at IS NULL \
            AND ((source_kind = 'payment' AND source_id = ANY($2)) \
              OR (source_kind = 'slip'    AND source_id = ANY($3)))",
    )
    .bind(batch_id)
    .bind(&payment_ids)
    .bind(&slip_ids)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    // The checks above proved every named obligation is present and live, and the rows are locked, so
    // a short count means the two disagree — refuse the whole thing rather than report a number the
    // admin would read as "these went back to the queue".
    if returned != sources.len() as u64 {
        return Err(AppError::Internal(format!(
            "refund item void touched {returned} of {} rows",
            sources.len()
        )));
    }

    let (payments_returned, slips_returned) =
        return_refund_sources_to_queue(&mut tx, &payment_ids, &slip_ids).await?;

    insert_money_audit(
        &mut *tx,
        Some(actor),
        AUDIT_REFUND_ITEMS_VOIDED,
        AUDIT_TARGET_REFUND_BATCH,
        Some(batch_id),
        serde_json::json!({
            // The batch's OWN status is untouched; recording it explains what state the correction
            // was made against (usually `confirmed` — the bank took the file, some lines failed).
            "batch_status": status.as_str(),
            "reason": reason,
            "file_ref": file_ref,
            "payment_ids": payment_ids,
            "slip_ids": slip_ids,
            "items_returned_to_queue": returned,
            "payments_returned_to_pending": payments_returned,
            "slips_returned_to_pending": slips_returned,
        }),
    )
    .await?;
    tx.commit().await?;
    get_refund_batch(db, batch_id).await
}

/// Read + LOCK one refund batch's current status inside a transaction (so a concurrent status change
/// or void cannot slip between the check and the write). 404 when the id is unknown; a status the
/// enum does not know is an internal error, not a client one — the DB CHECK should have refused it.
async fn locked_refund_batch_status(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    batch_id: Uuid,
) -> Result<BatchStatus, AppError> {
    let stored: Option<String> =
        sqlx::query_scalar("SELECT status FROM payment.refund_batches WHERE id = $1 FOR UPDATE")
            .bind(batch_id)
            .fetch_optional(&mut **tx)
            .await?;
    let stored = stored.ok_or_else(|| AppError::NotFound("ไม่พบไฟล์คืนเงินรายการนี้".to_string()))?;
    BatchStatus::parse(&stored)
        .ok_or_else(|| AppError::Internal(format!("unknown refund batch status: {stored}")))
}

// ----- Platform cut (stream ② ยอดที่โดนหักเข้าระบบ — the SCB OAT sweep) -----

/// `money_audit.target_kind` for everything in this section.
pub const AUDIT_TARGET_DEDUCTION_BATCH: &str = "deduction_batch";
/// `money_audit.action` values. `&'static str` so only this fixed vocabulary can be logged.
pub const AUDIT_DEDUCTION_EXPORTED: &str = "deduction_batch_exported";
pub const AUDIT_DEDUCTION_STATUS_CHANGED: &str = "deduction_batch_status_changed";
pub const AUDIT_DEDUCTION_VOIDED: &str = "deduction_batch_voided";
/// A PER-ITEM void: some of a sweep's jobs went back to the sweepable backlog while the rest stayed
/// collected. Its own action (not a `deduction_batch_voided` with a smaller item count) because the
/// two answer different questions in an audit: "the file never landed" vs "these jobs should not
/// have been in it".
pub const AUDIT_DEDUCTION_ITEMS_VOIDED: &str = "deduction_batch_items_voided";

/// The batch-header columns every sweep read returns. `has_file` is DERIVED, not stored: the list
/// and the drill-down must tell the screen whether the re-download will work without shipping the
/// file text itself.
const DEDUCTION_BATCH_COLUMNS: &str =
    "id, file_ref, system_ref, batch_ref, value_date, total_amount, credit_account, \
     recipient_count, job_count, status, status_note, void_reason, \
     (file_text IS NOT NULL) AS has_file, created_by, created_at, uploaded_at, confirmed_at, \
     rejected_at, voided_at, voided_by";

/// The item columns the drill-down returns.
const DEDUCTION_ITEM_COLUMNS: &str =
    "id, payment_id, booking_id, commission, cancellation_fee, tip, unpaid_guard_share, \
     rounding_adjustment, uncollected, amount, voided_at, created_at";

/// The UNSWEPT platform-cut backlog: every SETTLED payment whose cut no LIVE `deduction_batch_items`
/// row has claimed, with every column [`crate::domain::settlement::split`] needs to price it.
///
/// SETTLED means `final_amount IS NOT NULL` — the completion reconcile or the cancellation settle has
/// run and the bill is final. A payment is `completed` from the moment of PRE-PAY, so that status
/// alone would sweep the platform's cut off an ESTIMATE for a job still in progress, and the later
/// proration would have no way to take it back. `status <> 'pending'` drops a reserved-but-never-
/// captured charge, which is not money at all.
///
/// ROWS WITH AN INCOMPLETE SNAPSHOT ARE RETURNED, NOT FILTERED OUT — deliberately. A row that
/// predates migration 0005 or 0013 cannot be priced, and the caller has to be able to say so: an
/// honest "N jobs unknown, and here is why" is the whole difference between this and a report that
/// quietly under-states the cut by treating a NULL as a zero. The pure `settlement::split` makes that
/// call, per row, with a reason; the SQL's job is only to decide which rows are in the RUN.
///
/// BOUNDED by [`MAX_SWEEP_BACKLOG_ROWS`] + 1, and refused rather than truncated when it overflows.
/// `DeductionSelection::default()` (both ends `None`) is documented as "sweep the whole unswept
/// backlog", so `GET /admin/deductions/preview` with the window cleared used to `fetch_all` over
/// every settled payment in the table. A silently truncated sweep would be worse than a slow one: the
/// total on the preview screen is a MONEY figure an admin reconciles a bank transfer against, and a
/// short one looks exactly like a correct one. So the caller gets a typed 400 telling them to narrow
/// the window, and preview and export refuse identically — an admin can never export a different set
/// of jobs from the one they previewed.
///
/// `sel` narrows the run to a Thai-local day window (inclusive both ends) compared against
/// `payments.updated_at` — the timestamp whichever settle path stamped when it wrote `final_amount`,
/// i.e. WHEN THE CUT BECAME FINAL. That is the SAME basis `unpaid_payout_rows` windows on, and the
/// choice is deliberate: an admin who pays guards for 1–7 September and then sweeps 1–7 September
/// must get the two halves of the same jobs. (The revenue report and the VAT register bucket on
/// `paid_at` instead — a different question, "when did the money arrive", and it is documented at
/// each of those.)
///
/// A VOIDED item does not count as swept (`i.voided_at IS NULL`): voiding a sweep exists to put its
/// jobs back in this backlog, and the item rows are kept as history rather than deleted — so without
/// that predicate a voided job would stay filtered out and could never be swept at all.
///
/// THE BACKLOG IS READ FROM THE PRIMARY, DELIBERATELY — do not "optimise" it onto the read replica.
/// This is the single most serious defect the payout's P2 review found, and it is a read-after-write
/// on the money path: every write that changes this query's answer goes to the primary
/// (`deduction_batch_items` rows on export, `voided_at` on a void), and the same admin performs those
/// writes seconds before reading here. On a lagging replica: void a batch then immediately re-export
/// and the jobs the void just released are SILENTLY MISSING from the new file; export twice and a
/// marker that has not replicated lets a job be picked up again (the partial unique still refuses the
/// second batch, so nothing is swept twice — but the whole file is lost to a confusing 409).
pub async fn unswept_deduction_rows(
    db: &sqlx::PgPool,
    sel: &DeductionSelection,
) -> Result<Vec<SettledPaymentRow>, AppError> {
    let rows = sqlx::query_as::<_, SettledPaymentRow>(
        "SELECT p.id AS payment_id, p.booking_id, p.amount, p.overpaid_amount, \
                p.final_amount, p.refund_amount, p.subtotal, p.vat_amount, \
                (p.status = 'refunded'::payment.payment_status) AS cancelled, \
                p.base_fee, p.booked_hours, p.guard_count, p.tip, p.commission_amount, \
                p.actual_hours, p.updated_at AS settled_at \
           FROM payment.payments p \
          WHERE p.final_amount IS NOT NULL \
            AND p.status <> 'pending'::payment.payment_status \
            AND ($1::date IS NULL OR (p.updated_at AT TIME ZONE 'Asia/Bangkok')::date >= $1) \
            AND ($2::date IS NULL OR (p.updated_at AT TIME ZONE 'Asia/Bangkok')::date <= $2) \
            AND NOT EXISTS ( \
                SELECT 1 FROM payment.deduction_batch_items i \
                 WHERE i.payment_id = p.id AND i.voided_at IS NULL) \
          ORDER BY p.updated_at, p.id \
          LIMIT $3",
    )
    .bind(sel.from)
    .bind(sel.to)
    .bind(MAX_SWEEP_BACKLOG_ROWS + 1)
    .fetch_all(db)
    .await?;
    if rows.len() as i64 > MAX_SWEEP_BACKLOG_ROWS {
        return Err(too_many_rows(
            "งานที่รอหักเข้าระบบในช่วงที่เลือกมีมากเกินไป",
            MAX_SWEEP_BACKLOG_ROWS,
        ));
    }
    Ok(rows)
}

/// Persist a generated sweep: the `deduction_batches` header (INCLUDING the exact file text handed to
/// the admin), all `deduction_batch_items` ledger rows, the shared SCB reference reservation and the
/// `money_audit` row — in ONE transaction. Returns the new batch id.
///
/// The partial `UNIQUE(payment_id) WHERE voided_at IS NULL` on the items is the atomic double-sweep
/// guard: if any job in this batch is already claimed by a LIVE item (a concurrent export won the
/// race), the insert violates the unique, the whole tx ROLLS BACK, and a typed 409 is returned so no
/// cut is transferred twice.
///
/// Storing `file_text` here — in the same tx that marks the jobs swept — is what closes the one-way
/// door: the markers and the only copy of the file that justifies them are committed together, so the
/// file can always be re-downloaded and, if the upload never lands, the batch voided.
///
/// UNLIKE the other two streams there is no source row to advance: the platform's cut has no queue
/// state of its own. The item rows ARE the state, which is why the partial unique is the whole
/// mechanism here rather than half of it.
pub async fn insert_deduction_batch(
    db: &sqlx::PgPool,
    batch: &NewDeductionBatch,
) -> Result<Uuid, AppError> {
    let mut tx = db.begin().await?;
    let inserted: Result<Uuid, sqlx::Error> = sqlx::query_scalar(
        "INSERT INTO payment.deduction_batches \
             (file_ref, system_ref, batch_ref, value_date, total_amount, credit_account, \
              recipient_count, job_count, file_text, status, created_by) \
         VALUES ($1, $2, $3, $4, $5, $6, 1, $7, $8, 'generated', $9) RETURNING id",
    )
    .bind(&batch.file_ref)
    .bind(&batch.system_ref)
    .bind(&batch.batch_ref)
    .bind(batch.value_date)
    .bind(batch.total_amount)
    .bind(&batch.credit_account)
    // `recipient_count` is the literal 1 above: an OAT batch credits ONE destination, so the file
    // carries a single TXNDET however many jobs back it. `job_count` is the figure that varies.
    .bind(batch.items.len() as i32)
    .bind(&batch.file_text)
    .bind(batch.created_by)
    .fetch_one(&mut *tx)
    .await;
    // `uq_deduction_batches_file_ref` (migration 0013) — the same guard, and the same reasoning, as
    // the other two streams': `file_ref` is `batch_ref || product`, the batch ref is a timestamp at
    // ONE-SECOND resolution, so two sweeps committed in the same Bangkok second collide here even
    // when their day windows are DISJOINT (nothing for the per-job marker to catch). A typed 409,
    // never a retry loop sleeping in the request path: the whole insert is one transaction, so the
    // loser rolls back with NOTHING marked swept.
    let batch_id = match inserted {
        Ok(id) => id,
        Err(e) => {
            tx.rollback().await?;
            if is_unique_violation(&e) {
                return Err(deduction_batch_ref_taken());
            }
            return Err(e.into());
        }
    };

    // …and the SHARED reservation, which the per-table unique above cannot do: the payout and refund
    // exports stamp their BATCH ref off the same one-second clock, in tables
    // `uq_deduction_batches_file_ref` cannot see. The product suffix keeps the FILE refs apart, but
    // BCHDET field 1 — the reference the bank de-dups a batch on — would still be byte-identical.
    // Inside the transaction, so a collision rolls this export back with nothing marked swept.
    if let Err(e) = reserve_scb_file_ref(
        &mut tx,
        &batch.file_ref,
        &batch.batch_ref,
        SCB_STREAM_DEDUCTION,
        batch_id,
    )
    .await
    {
        tx.rollback().await?;
        if is_unique_violation(&e) {
            return Err(deduction_batch_ref_taken());
        }
        return Err(e.into());
    }

    // ONE statement for every swept-marker (see the `UNNEST` note above). This is the loop that hurt
    // most: the sweep's ledger is one row per JOB, so a month's backlog is thousands of round trips
    // holding the write lock on `uq_deduction_batch_items_payment_live` — the very index every
    // concurrent export and every backlog read has to consult.
    let mut payment_ids = Vec::with_capacity(batch.items.len());
    let mut booking_ids = Vec::with_capacity(batch.items.len());
    let mut commissions = Vec::with_capacity(batch.items.len());
    let mut cancellation_fees = Vec::with_capacity(batch.items.len());
    let mut tips = Vec::with_capacity(batch.items.len());
    let mut unpaid_shares = Vec::with_capacity(batch.items.len());
    let mut roundings = Vec::with_capacity(batch.items.len());
    let mut uncollected = Vec::with_capacity(batch.items.len());
    let mut amounts = Vec::with_capacity(batch.items.len());
    for item in &batch.items {
        payment_ids.push(item.payment_id);
        booking_ids.push(item.booking_id);
        commissions.push(item.commission);
        cancellation_fees.push(item.cancellation_fee);
        tips.push(item.tip);
        unpaid_shares.push(item.unpaid_guard_share);
        roundings.push(item.rounding_adjustment);
        uncollected.push(item.uncollected);
        amounts.push(item.amount);
    }
    let res = sqlx::query(
        "INSERT INTO payment.deduction_batch_items \
             (batch_id, payment_id, booking_id, commission, cancellation_fee, tip, \
              unpaid_guard_share, rounding_adjustment, uncollected, amount) \
         SELECT $1, i.payment_id, i.booking_id, i.commission, i.cancellation_fee, i.tip, \
                i.unpaid_guard_share, i.rounding_adjustment, i.uncollected, i.amount \
           FROM UNNEST($2::uuid[], $3::uuid[], $4::numeric[], $5::numeric[], $6::numeric[], \
                       $7::numeric[], $8::numeric[], $9::numeric[], $10::numeric[]) \
                AS i(payment_id, booking_id, commission, cancellation_fee, tip, \
                     unpaid_guard_share, rounding_adjustment, uncollected, amount)",
    )
    .bind(batch_id)
    .bind(&payment_ids)
    .bind(&booking_ids)
    .bind(&commissions)
    .bind(&cancellation_fees)
    .bind(&tips)
    .bind(&unpaid_shares)
    .bind(&roundings)
    .bind(&uncollected)
    .bind(&amounts)
    .execute(&mut *tx)
    .await;
    if let Err(e) = res {
        tx.rollback().await?;
        // A unique violation means one of these jobs was swept by a concurrent export — refuse the
        // whole batch rather than transfer the same cut twice; the admin re-previews the (now
        // smaller) backlog.
        if is_unique_violation(&e) {
            return Err(AppError::ConflictCode {
                code: "DEDUCTION_ALREADY_SWEPT",
                message: "มีบางรายการถูกใส่ในไฟล์หักเข้าระบบอื่นไปแล้ว — กรุณาดูตัวอย่างใหม่แล้วสร้างไฟล์อีกครั้ง"
                    .to_string(),
            });
        }
        return Err(e.into());
    }

    // The compliance record, in the SAME tx: an audit row for a batch that rolled back would be a
    // lie, and a batch with no audit row would be money moved with no trace of who moved it.
    insert_money_audit(
        &mut *tx,
        batch.created_by,
        AUDIT_DEDUCTION_EXPORTED,
        AUDIT_TARGET_DEDUCTION_BATCH,
        Some(batch_id),
        serde_json::json!({
            "file_ref": batch.file_ref,
            "batch_ref": batch.batch_ref,
            "value_date": batch.value_date,
            "credit_account": batch.credit_account,
            "total_amount": batch.total_amount.to_string(),
            "job_count": batch.items.len(),
        }),
    )
    .await?;

    tx.commit().await?;
    Ok(batch_id)
}

/// One page of the sweep history, newest first, PLUS the total count so the screen can paginate. The
/// file text is never selected here (see [`DEDUCTION_BATCH_COLUMNS`]).
pub async fn list_deduction_batches(
    db: &sqlx::PgPool,
    limit: i64,
    offset: i64,
) -> Result<DeductionBatchList, AppError> {
    let batches: Vec<DeductionBatchRow> = sqlx::query_as(&format!(
        "SELECT {DEDUCTION_BATCH_COLUMNS} FROM payment.deduction_batches \
         ORDER BY created_at DESC, id DESC LIMIT $1 OFFSET $2"
    ))
    .bind(limit)
    .bind(offset)
    .fetch_all(db)
    .await?;
    let total: i64 = sqlx::query_scalar("SELECT count(*) FROM payment.deduction_batches")
        .fetch_one(db)
        .await?;
    Ok(DeductionBatchList { batches, total })
}

/// One sweep header + every job it collected (a voided item shows its `voided_at`, i.e. that job is
/// back in the sweepable backlog). 404 when the id is unknown.
pub async fn get_deduction_batch(
    db: &sqlx::PgPool,
    batch_id: Uuid,
) -> Result<DeductionBatchDetail, AppError> {
    let batch: DeductionBatchRow = sqlx::query_as(&format!(
        "SELECT {DEDUCTION_BATCH_COLUMNS} FROM payment.deduction_batches WHERE id = $1"
    ))
    .bind(batch_id)
    .fetch_optional(db)
    .await?
    .ok_or_else(|| AppError::NotFound("ไม่พบไฟล์หักเข้าระบบรายการนี้".to_string()))?;
    let items: Vec<DeductionBatchItemRow> = sqlx::query_as(&format!(
        "SELECT {DEDUCTION_ITEM_COLUMNS} FROM payment.deduction_batch_items \
          WHERE batch_id = $1 ORDER BY created_at, payment_id"
    ))
    .bind(batch_id)
    .fetch_all(db)
    .await?;
    Ok(DeductionBatchDetail { batch, items })
}

/// The STORED sweep-file text for a re-download (never a regenerated one — the backlog has moved on
/// since, and a money file must reproduce byte-for-byte). Reads only the header, so the cost does not
/// grow with the size of the batch. 404 both when the batch is unknown and when it has no stored text.
pub async fn get_deduction_batch_file(
    db: &sqlx::PgPool,
    batch_id: Uuid,
) -> Result<ExportedBatchFile, AppError> {
    let row: Option<(String, Option<String>)> =
        sqlx::query_as("SELECT file_ref, file_text FROM payment.deduction_batches WHERE id = $1")
            .bind(batch_id)
            .fetch_optional(db)
            .await?;
    let (file_ref, file_text) =
        row.ok_or_else(|| AppError::NotFound("ไม่พบไฟล์หักเข้าระบบรายการนี้".to_string()))?;
    let file_text = file_text
        .ok_or_else(|| AppError::NotFound("ไฟล์นี้ไม่มีตัวไฟล์เก็บไว้ จึงดาวน์โหลดซ้ำไม่ได้".to_string()))?;
    Ok(ExportedBatchFile {
        file_ref,
        file_text,
    })
}

/// Move a sweep along its lifecycle (`generated → uploaded → confirmed | rejected`), enforcing the
/// legal transitions in the ONE shared pure table ([`crate::domain::batch_status`]) and stamping the
/// matching timestamp column. Writes the audit row in the same transaction.
///
/// The current status is read `FOR UPDATE` so two admins clicking at once cannot both pass the
/// transition check against the same stale state. Voiding does NOT go through here: it has to touch
/// every item, so it is [`void_deduction_batch`].
pub async fn set_deduction_batch_status(
    db: &sqlx::PgPool,
    batch_id: Uuid,
    to: BatchStatus,
    note: Option<&str>,
    actor: Uuid,
) -> Result<DeductionBatchRow, AppError> {
    let mut tx = db.begin().await?;
    let from = locked_deduction_batch_status(&mut tx, batch_id).await?;
    batch_status::check_transition(BatchKind::Deduction, from, to)?;

    let stamped = match to {
        BatchStatus::Uploaded => "uploaded_at",
        BatchStatus::Confirmed => "confirmed_at",
        BatchStatus::Rejected => "rejected_at",
        // `Generated` is only ever the initial state and `Voided` goes through
        // `void_deduction_batch`; neither is reachable here (the transition table refuses both), but
        // the arm must exist and must not panic in the money path — re-stamping `created_at` is a
        // harmless no-op write.
        BatchStatus::Generated | BatchStatus::Voided => "created_at",
    };
    // `stamped` is one of four hard-coded column names chosen by a match on an enum — never user
    // input — so interpolating it is safe (Postgres has no bind parameter for an identifier).
    let row: DeductionBatchRow = sqlx::query_as(&format!(
        "UPDATE payment.deduction_batches \
            SET status = $2, status_note = $3, {stamped} = now() \
          WHERE id = $1 RETURNING {DEDUCTION_BATCH_COLUMNS}"
    ))
    .bind(batch_id)
    .bind(to.as_str())
    .bind(note)
    .fetch_one(&mut *tx)
    .await?;

    insert_money_audit(
        &mut *tx,
        Some(actor),
        AUDIT_DEDUCTION_STATUS_CHANGED,
        AUDIT_TARGET_DEDUCTION_BATCH,
        Some(batch_id),
        serde_json::json!({
            "from": from.as_str(),
            "to": to.as_str(),
            "note": note,
            "file_ref": row.file_ref,
        }),
    )
    .await?;
    tx.commit().await?;
    Ok(row)
}

/// VOID a sweep: flip the header to `voided`, stamp `voided_at` on EVERY live item — which returns
/// each of those jobs to the sweepable backlog — and write the audit row, in ONE transaction.
///
/// Simpler than the other two streams' voids by exactly one step, and the reason is worth stating:
/// there is no source row to flip back. A payout void has to un-mark the booking, a refund void has
/// to put `refund_status` back to `pending`; the platform's cut has no queue state of its own, so
/// stamping the ITEM is the whole undo — the backlog is defined as "no live item claims this
/// payment", and [`unswept_deduction_rows`] reads exactly that.
///
/// Already-voided is a typed 409 from the pure transition table, never a silent no-op: the admin
/// needs to know the first void already happened (their page may be stale).
pub async fn void_deduction_batch(
    db: &sqlx::PgPool,
    batch_id: Uuid,
    actor: Uuid,
    reason: &str,
) -> Result<DeductionBatchRow, AppError> {
    let mut tx = db.begin().await?;
    let from = locked_deduction_batch_status(&mut tx, batch_id).await?;
    batch_status::check_transition(BatchKind::Deduction, from, BatchStatus::Voided)?;

    let row: DeductionBatchRow = sqlx::query_as(&format!(
        "UPDATE payment.deduction_batches \
            SET status = 'voided', voided_at = now(), voided_by = $2, void_reason = $3 \
          WHERE id = $1 RETURNING {DEDUCTION_BATCH_COLUMNS}"
    ))
    .bind(batch_id)
    .bind(actor)
    .bind(reason)
    .fetch_one(&mut *tx)
    .await?;

    // `voided_at IS NULL` in the predicate keeps the write idempotent and preserves the original void
    // time of items an earlier per-item correction already released.
    let released = sqlx::query(
        "UPDATE payment.deduction_batch_items SET voided_at = now() \
          WHERE batch_id = $1 AND voided_at IS NULL",
    )
    .bind(batch_id)
    .execute(&mut *tx)
    .await?
    .rows_affected();

    insert_money_audit(
        &mut *tx,
        Some(actor),
        AUDIT_DEDUCTION_VOIDED,
        AUDIT_TARGET_DEDUCTION_BATCH,
        Some(batch_id),
        serde_json::json!({
            "from": from.as_str(),
            "reason": reason,
            "file_ref": row.file_ref,
            "jobs_returned_to_backlog": released,
            "total_amount": row.total_amount.to_string(),
        }),
    )
    .await?;
    tx.commit().await?;
    Ok(row)
}

/// Return SOME of a sweep's jobs to the sweepable backlog, leaving the batch itself alone.
///
/// **A CONFIRMED SWEEP CANNOT BE RELEASED FROM, AND THAT IS THE OPPOSITE OF THE OTHER TWO STREAMS.**
/// Do not "unify" this with `void_payout_batch_items` / `void_refund_batch_items`: the asymmetry is
/// forced by the FILE SHAPE, not by taste.
///
///  * Streams ① and ③ are `PPY` files carrying ONE CREDIT LINE PER RECIPIENT. SCB routinely accepts a
///    structurally valid file and still fails individual lines (a PromptPay proxy not linked to a
///    receiving account is the everyday cause), so a batch can be `confirmed` — the file landed —
///    while one guard's or one customer's credit genuinely bounced. Releasing THAT item is correct,
///    which is why those two bypass [`batch_status::is_terminal`].
///  * This is an `OAT` sweep with ONE CREDIT LINE FOR THE WHOLE BATCH. `confirmed` therefore means
///    the entire summed amount moved into the revenue account — there is no per-job outcome for the
///    bank to have failed. Releasing a job from it would return that job's cut to the sweepable
///    backlog, and the next sweep would move it a SECOND time: real double-movement of company money,
///    the one thing this stream must make impossible.
///
/// So a `confirmed` sweep is refused here with a typed Thai 409 naming the two correct remedies: the
/// WHOLE-BATCH void (if the money truly never moved — e.g. the admin marked it confirmed by mistake)
/// or a manual accounting adjustment (if it did). Every non-terminal status still releases items
/// freely, which is what the escape hatch is for: a `generated` or `uploaded` sweep whose window was
/// wrong, or a settled row later found to be incorrect, is corrected here rather than by a
/// hand-written UPDATE in production.
///
/// A `voided` batch needs no gate of its own: every item in it was already stamped by the void, so
/// the "already released" 409 below catches it with a message that fits better.
///
/// Beyond that it still does not CONSULT the transition table and does not MOVE the batch's status:
/// the status describes what happened to the FILE at the bank (still true), while this corrects which
/// JOBS the file is considered to have collected. The audit row names them and carries the
/// (mandatory) reason.
///
/// Rejects, each as a typed 4xx and never a partial success: a confirmed batch (409), a job that is
/// not in THIS batch (404 — an admin acting on the wrong file must not silently release a subset of
/// another), and one already released (409 — their page is stale). The empty list is refused before
/// this by the API's pure validator. Returns the batch drill-down so the caller re-renders the truth
/// it just wrote.
pub async fn void_deduction_batch_items(
    db: &sqlx::PgPool,
    batch_id: Uuid,
    payment_ids: &[Uuid],
    actor: Uuid,
    reason: &str,
) -> Result<DeductionBatchDetail, AppError> {
    let mut tx = db.begin().await?;
    // Locks the header (404s an unknown batch) — under the lock, so a concurrent status change
    // cannot slip between this check and the release below.
    let status = locked_deduction_batch_status(&mut tx, batch_id).await?;
    if status == BatchStatus::Confirmed {
        return Err(AppError::ConflictCode {
            code: "DEDUCTION_BATCH_CONFIRMED",
            message: "ไฟล์นี้ธนาคารยืนยันแล้ว และไฟล์หักเข้าระบบมีรายการโอนเพียงรายการเดียวสำหรับทั้งไฟล์ \
                      — เงินทั้งก้อนถูกโอนเข้าบัญชีรายได้ไปแล้ว จึงดึงงานรายตัวกลับไม่ได้ (จะถูกหักซ้ำในรอบถัดไป) \
                      ถ้าเงินยังไม่ได้โอนจริงให้ยกเลิกทั้งไฟล์ ถ้าโอนไปแล้วต้องทำรายการปรับปรุงทางบัญชีแทน"
                .to_string(),
        });
    }
    let file_ref: String =
        sqlx::query_scalar("SELECT file_ref FROM payment.deduction_batches WHERE id = $1")
            .bind(batch_id)
            .fetch_one(&mut *tx)
            .await?;

    // Lock the item rows too: two admins releasing overlapping jobs must serialise, or the second
    // would see them live, pass the check, and update zero rows.
    let found: Vec<(Uuid, Option<DateTime<Utc>>, Decimal)> = sqlx::query_as(
        "SELECT payment_id, voided_at, amount FROM payment.deduction_batch_items \
          WHERE batch_id = $1 AND payment_id = ANY($2) FOR UPDATE",
    )
    .bind(batch_id)
    .bind(payment_ids)
    .fetch_all(&mut *tx)
    .await?;

    let missing: Vec<&Uuid> = payment_ids
        .iter()
        .filter(|id| !found.iter().any(|(found_id, _, _)| found_id == *id))
        .collect();
    if let Some(first) = missing.first() {
        return Err(AppError::NotFound(format!(
            "ไม่พบรายการ {} รายการในไฟล์นี้ (เช่น {}) — ตรวจสอบว่าเลือกรายการจากไฟล์ที่ถูกต้อง",
            missing.len(),
            first
        )));
    }
    if let Some((id, _, _)) = found.iter().find(|(_, voided, _)| voided.is_some()) {
        return Err(AppError::ConflictCode {
            code: "DEDUCTION_ITEM_ALREADY_VOIDED",
            message: format!("บางรายการถูกดึงกลับเข้าคิวไปแล้ว (เช่น {id}) — โปรดรีเฟรชหน้าจอแล้วเลือกใหม่"),
        });
    }

    let released = sqlx::query(
        "UPDATE payment.deduction_batch_items SET voided_at = now() \
          WHERE batch_id = $1 AND voided_at IS NULL AND payment_id = ANY($2)",
    )
    .bind(batch_id)
    .bind(payment_ids)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    // The checks above proved every named job is present and live, and the rows are locked, so a
    // short count means the two disagree — refuse the whole thing rather than report a number the
    // admin would read as "these went back to the backlog".
    if released != payment_ids.len() as u64 {
        return Err(AppError::Internal(format!(
            "deduction item void touched {released} of {} rows",
            payment_ids.len()
        )));
    }

    // The amounts are recorded because they are what the NEXT sweep will now collect that this file's
    // stated total already covered — the figure an auditor needs to tie the two files together. (It
    // is no longer an OVER-SWEEP: a `confirmed` batch is refused above precisely so a released job
    // cannot be collected twice.)
    let released_amount: Decimal = found.iter().map(|(_, _, amount)| *amount).sum();
    insert_money_audit(
        &mut *tx,
        Some(actor),
        AUDIT_DEDUCTION_ITEMS_VOIDED,
        AUDIT_TARGET_DEDUCTION_BATCH,
        Some(batch_id),
        serde_json::json!({
            // The batch's OWN status is untouched; recording it explains what state the correction
            // was made against.
            "batch_status": status.as_str(),
            "reason": reason,
            "file_ref": file_ref,
            "payment_ids": payment_ids,
            "jobs_returned_to_backlog": released,
            "released_amount": released_amount.to_string(),
        }),
    )
    .await?;
    tx.commit().await?;
    get_deduction_batch(db, batch_id).await
}

/// Read + LOCK one sweep's current status inside a transaction (so a concurrent status change or void
/// cannot slip between the check and the write). 404 when the id is unknown; a status the enum does
/// not know is an internal error, not a client one — the DB CHECK should have refused it.
async fn locked_deduction_batch_status(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    batch_id: Uuid,
) -> Result<BatchStatus, AppError> {
    let stored: Option<String> =
        sqlx::query_scalar("SELECT status FROM payment.deduction_batches WHERE id = $1 FOR UPDATE")
            .bind(batch_id)
            .fetch_optional(&mut **tx)
            .await?;
    let stored = stored.ok_or_else(|| AppError::NotFound("ไม่พบไฟล์หักเข้าระบบรายการนี้".to_string()))?;
    BatchStatus::parse(&stored)
        .ok_or_else(|| AppError::Internal(format!("unknown deduction batch status: {stored}")))
}

// ----- The two TAX REPORTS (ภ.พ.30 output-VAT register · ภ.ง.ด.3/53 payee list) -----

/// The OUTPUT-VAT register (รายงานภาษีขาย) for `[from, to)` — one line per settled payment that
/// charged VAT, ordered by the day the money arrived.
///
/// BUCKETED ON `paid_at`, and the choice is the report's most important decision. Thai VAT on a
/// service has its tax point at RECEIPT OF PAYMENT, so the period a sale belongs to is the period the
/// customer paid in — and it is the same basis [`revenue_series`] uses, so the two reports tie out
/// line for line (the register's `subtotal` column IS what the revenue chart counts). The sweep and
/// the payout backlog bucket on `updated_at` instead, because they answer a different question
/// ("when did the cut become final"); the three can only ever be reconciled if each says which basis
/// it uses, so each does.
///
/// The AMOUNT is the SETTLED split (`subtotal`/`vat_amount` as the reconcile last rewrote them), not
/// the amount originally charged: a job paid in one month and prorated in the next reports its final
/// VAT in the month it was PAID. That is the honest reading of a tax point plus a later price
/// adjustment, and an accountant filing a correction needs the settled figure, not the estimate.
///
/// WHICH STATUSES COUNT — the same question B7 got wrong next door, checked here and answered
/// deliberately. `payment.payment_status` has exactly three values:
///  * `pending` — the charge was reserved and never captured. NO money arrived, so there is no tax
///    point and no sale: EXCLUDED, as it always was.
///  * `completed` — the customer paid. INCLUDED.
///  * `refunded` — the job was cancelled and the pre-payment unwound. INCLUDED, and it must be: the
///    cancellation settle rewrites `subtotal`/`vat_amount` to the RETAINED FEE's own VAT split, so
///    the row reports VAT on the money actually kept (0.00/0.00 when nothing was). A ฿0 line in a
///    register is a fact; a missing line is a gap.
///
/// There is no batch-lifecycle join here at all — the register reads `payments` directly — so the
/// "a rejected batch never moved money" class of mistake cannot arise in this query.
///
/// Rows with no VAT split at all are excluded: a pre-migration-0005 charge carried no VAT and
/// belongs on no VAT return.
///
/// BOUNDED by [`MAX_VAT_REGISTER_ROWS`] + 1 and REFUSED rather than truncated on overflow: this
/// response is not streamed and a year-end CSV would otherwise pull the whole result set into the
/// heap — and a silently short VAT total is a number an accountant would file. See
/// [`MAX_PAYOUT_BACKLOG_ROWS`].
///
/// Read from the REPLICA: it is a read-only analytics query over a closed month, with no
/// read-after-write relationship to anything (unlike the sweep backlog next door, which must be
/// primary).
pub async fn vat_register(
    db: &sqlx::PgPool,
    from: DateTime<Utc>,
    to: DateTime<Utc>,
) -> Result<Vec<VatRegisterRow>, AppError> {
    let rows = sqlx::query_as::<_, VatRegisterRow>(
        "SELECT (COALESCE(p.paid_at, p.created_at) AT TIME ZONE 'Asia/Bangkok')::date AS date, \
                p.id AS payment_id, p.booking_id, p.customer_id, \
                p.subtotal, p.vat_amount AS vat, (p.subtotal + p.vat_amount) AS total \
           FROM payment.payments p \
          WHERE p.status <> 'pending'::payment.payment_status \
            AND p.subtotal IS NOT NULL AND p.vat_amount IS NOT NULL \
            AND COALESCE(p.paid_at, p.created_at) >= $1 \
            AND COALESCE(p.paid_at, p.created_at) < $2 \
          ORDER BY 1, p.id \
          LIMIT $3",
    )
    .bind(from)
    .bind(to)
    .bind(MAX_VAT_REGISTER_ROWS + 1)
    .fetch_all(db)
    .await?;
    if rows.len() as i64 > MAX_VAT_REGISTER_ROWS {
        return Err(too_many_rows(
            "รายงานภาษีขายของเดือนนี้มีรายการมากเกินไป",
            MAX_VAT_REGISTER_ROWS,
        ));
    }
    Ok(rows)
}

/// The ภ.ง.ด.3/53 PAYEE LIST for `[from, to)`: every guard who had tax withheld from a payout whose
/// value date falls in the period, with their gross assessable income and the tax withheld, summed
/// over every non-voided item.
///
/// THIS IS THE FIGURE THE LAW REQUIRES US TO REPORT, and until now it was unreachable:
/// `payout_batch_items.wht` has been WRITE-ONLY since migration 0007 — no endpoint has ever read it.
///
/// BUCKETED ON `payout_batches.value_date` — the day the transfer settles at the bank, which is the
/// day the payment to the payee is MADE and therefore the month the filing covers (ภ.ง.ด.3/53 is due
/// by the 7th of the following month). Not `created_at`: generating a file on the 31st for a value
/// date of the 1st would otherwise file the withholding a month early.
///
/// MONEY THAT NEVER MOVED WAS NEVER WITHHELD — so the predicate is an ALLOW-LIST of the batch
/// statuses under which the transfer actually happened, not a deny-list of `voided`. Every value of
/// the closed vocabulary (`domain::batch_status::BATCH_STATUSES`), and why it is in or out:
///
///  * `generated` — IN. The certificate has been produced and handed to the admin; the withholding is
///    recorded at that point. If the file never lands the admin voids it, which removes it here.
///  * `uploaded` — IN. The file is at the bank and the transfers are in flight.
///  * `confirmed` — IN. The bank took the file; the money left the account. The unambiguous case.
///  * `rejected` — **OUT, and this is the bug B7 found.** The bank REFUSED the file, so not one baht
///    was transferred to any payee in it and not one baht of tax was withheld from them. The old
///    `b.status <> 'voided'` let every rejected batch through, producing a ภ.ง.ด.3/53 return that
///    claimed withholding that did not occur — an over-declaration to the Revenue Department, with a
///    payee certificate nobody can match. `rejected` is deliberately NOT terminal (the remedy is to
///    void it and let the work ride a fresh batch), so a rejected batch can sit in this state
///    indefinitely and it is reachable on the ordinary failure path, not an exotic one.
///  * `voided` — OUT, as before. The batch was cancelled and its work returned to the payable
///    backlog.
///
/// `i.voided_at IS NULL` stays on the ITEM as well, and is the finer-grained half of the same rule: a
/// whole-batch void stamps every live item, and a PER-ITEM void on an otherwise-good batch releases
/// individual credit lines that the bank could not deliver. Belt and braces on the one query whose
/// output goes to the Revenue Department.
///
/// BOUNDED by [`MAX_WHT_PAYEE_ROWS`] + 1 and refused rather than truncated — see
/// [`MAX_PAYOUT_BACKLOG_ROWS`]. It GROUPs by guard, so the cap is a backstop rather than the real
/// limit, but the response is not streamed and the report fans out one profile read per row.
///
/// Read from the REPLICA (read-only analytics over a closed month).
pub async fn wht_payees(
    db: &sqlx::PgPool,
    from: NaiveDate,
    to: NaiveDate,
) -> Result<Vec<WhtPayeeTotals>, AppError> {
    let rows = sqlx::query_as::<_, WhtPayeeTotals>(
        "SELECT i.guard_id, count(*) AS job_count, \
                COALESCE(SUM(i.income), 0) AS income, COALESCE(SUM(i.wht), 0) AS wht \
           FROM payment.payout_batch_items i \
           JOIN payment.payout_batches b ON b.id = i.batch_id \
          WHERE i.voided_at IS NULL \
            AND b.status IN ('generated', 'uploaded', 'confirmed') \
            AND b.value_date >= $1 AND b.value_date < $2 \
            AND i.wht > 0 \
          GROUP BY i.guard_id \
          ORDER BY i.guard_id \
          LIMIT $3",
    )
    .bind(from)
    .bind(to)
    .bind(MAX_WHT_PAYEE_ROWS + 1)
    .fetch_all(db)
    .await?;
    if rows.len() as i64 > MAX_WHT_PAYEE_ROWS {
        return Err(too_many_rows(
            "รายชื่อผู้ถูกหักภาษี ณ ที่จ่ายของเดือนนี้มีมากเกินไป",
            MAX_WHT_PAYEE_ROWS,
        ));
    }
    Ok(rows)
}

/// Admin cross-user payment ledger — every payment (NO owner filter; the admin-role gate is
/// the API layer's job), newest first, with optional `status` and `customer_id` (drill into one
/// customer's spend) filters + limit/offset. Diverges from [`list_payments`] by dropping the
/// implicit `WHERE customer_id = $1` scope — here `customer_id` is an explicit, optional filter
/// (index-backed by `idx_payments_customer (customer_id, created_at DESC)`). `$n` placeholders
/// are built from a controlled counter; every value is a BOUND param (`status` validated against
/// the enum in the handler) — no user input is interpolated. READ-ONLY: money moves through the
/// refund EXPORT ([`insert_refund_batch`]), which is the only writer of `refund_status = 'processed'`.
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
            commission_percent, cancellation_fee, payment_method, \
            base_fee, booked_hours, guard_count, tip, commission_amount, \
            status, paid_at) \
         VALUES ($1, $2, $3, $4, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, \
                 'completed'::payment.payment_status, now()) \
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
        // THE PRICING SNAPSHOT (migration 0013), written in the SAME statement as the VAT split so
        // the two can never drift: the split is what the customer pays, these are what it was
        // multiplied out of, and stream ② cannot tell platform cut from guard pay without both.
        // `commission_amount` here is the BOOKED-hours estimate — the completion reconcile rewrites
        // it from the ACTUAL hours, and until it does the row has no `final_amount` and is not
        // sweepable at all.
        .bind(terms.inputs.base_fee)
        .bind(terms.inputs.booked_hours)
        .bind(terms.inputs.guard_count)
        .bind(terms.inputs.tip)
        .bind(terms.commission_amount())
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
            commission_percent, cancellation_fee, overpaid_amount, payment_method, \
            base_fee, booked_hours, guard_count, tip, commission_amount, \
            status, paid_at) \
         VALUES ($1, $2, $3, $4, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, \
                 'completed'::payment.payment_status, now()) \
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
        // The PRICING SNAPSHOT, identical to the simulated pre-pay's (migration 0013) — the two pay
        // paths write the same money shape, so a slip-paid job is as sweepable as a pre-paid one.
        .bind(terms.inputs.base_fee)
        .bind(terms.inputs.booked_hours)
        .bind(terms.inputs.guard_count)
        .bind(terms.inputs.tip)
        .bind(terms.commission_amount())
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

    // THE COMMISSION IN BAHT (migration 0013) — the largest component of the platform cut, and the
    // one figure `payments` never recorded. Recomputed here from the hours ACTUALLY worked, because
    // that is the basis the payout pays on: the pre-pay wrote an estimate off the BOOKED hours, and
    // a prorated job would otherwise be swept for a commission that was never deducted from anyone.
    //
    // It goes through `settlement::commission_on ∘ guard_gross`, the very pair `payout::compute_payout`
    // deducts with, so the money the guard does not receive and the money the sweep transfers are one
    // number rather than two that agree today.
    //
    // `commission_percent` is the row's own snapshot (written at charge time) and is read INSIDE the
    // transaction off the row already locked FOR UPDATE above — not from the event, which does not
    // carry it, and not from booking, which may have re-priced since.
    let commission_percent: Option<Decimal> =
        sqlx::query_scalar("SELECT commission_percent FROM payment.payments WHERE id = $1")
            .bind(payment.id)
            .fetch_one(&mut *tx)
            .await?;
    let pay_hours = actual_hours.unwrap_or_else(|| Decimal::from(booked_hours.max(0)));
    let commission_amount = crate::domain::settlement::commission_on(
        crate::domain::settlement::guard_gross(base_fee, pay_hours),
        commission_percent,
    );

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
                       base_fee = $6, booked_hours = $7, guard_count = $8, tip = $9, \
                       commission_amount = $10, updated_at = now() \
                 WHERE id = $1",
            )
            .bind(payment.id)
            .bind(settled.grand_total)
            .bind(settled.subtotal)
            .bind(settled.vat)
            .bind(actual_hours)
            .bind(base_fee)
            .bind(booked_hours)
            .bind(guard_count)
            .bind(tip)
            .bind(commission_amount)
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
                       subtotal = $4, vat_amount = $5, actual_hours = $6, \
                       base_fee = $7, booked_hours = $8, guard_count = $9, tip = $10, \
                       commission_amount = $11, updated_at = now() \
                 WHERE id = $1",
            )
            .bind(payment.id)
            .bind(final_amount)
            .bind(refund)
            .bind(settled.subtotal)
            .bind(settled.vat)
            .bind(actual_hours)
            .bind(base_fee)
            .bind(booked_hours)
            .bind(guard_count)
            .bind(tip)
            .bind(commission_amount)
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
                       base_fee = $6, booked_hours = $7, guard_count = $8, tip = $9, \
                       commission_amount = $10, updated_at = now() \
                 WHERE id = $1",
            )
            .bind(payment.id)
            .bind(final_amount)
            .bind(settled.subtotal)
            .bind(settled.vat)
            .bind(actual_hours)
            .bind(base_fee)
            .bind(booked_hours)
            .bind(guard_count)
            .bind(tip)
            .bind(commission_amount)
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
    // `commission_amount = 0` in the UPDATE below (migration 0013): the job never ran, so no guard
    // was paid and nothing was deducted from anyone's pay. The platform's cut on a cancelled job is
    // the RETAINED FEE alone — and only its VAT-exclusive part, which is what `kept.subtotal`
    // already carries. Leaving the pre-pay's booked-hours ESTIMATE standing here would have the
    // sweep transfer a commission that was never taken. The four multiplicands are deliberately left
    // untouched: they are booking facts that a cancellation does not change.
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
               subtotal = $6, vat_amount = $7, commission_amount = 0, updated_at = now() \
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

    // Full refund of everything the customer transferred — the estimate AND any slip overpay. The
    // whole settled split goes to zero, `commission_amount` included (migration 0013): this charge
    // landed on a booking that was already dead, nobody worked and nobody was paid, so there is
    // nothing for the platform-cut sweep to take.
    let refund = payment.amount + payment.overpaid_amount;
    sqlx::query(
        "UPDATE payment.payments \
           SET status = 'refunded'::payment.payment_status, final_amount = 0, \
               refund_amount = $2, refund_status = 'pending', cancellation_fee_charged = 0, \
               subtotal = 0, vat_amount = 0, commission_amount = 0, updated_at = now() \
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

    use crate::domain::PricingInputs;

    fn dec(s: &str) -> Decimal {
        s.parse().unwrap()
    }

    /// The row caps are a REFUSAL, not a truncation, and the message has to make that actionable.
    /// Hermetic (no pool): seeding 20,000 settled payments to watch a `LIMIT` fire would cost minutes
    /// per run to test one comparison, so the arithmetic is exercised by the queries themselves and
    /// the CONTRACT — an honest Thai error naming the cap and the remedy — is pinned here.
    #[test]
    fn a_capped_money_query_refuses_with_a_number_and_a_remedy_rather_than_truncating() {
        let AppError::BadRequest(msg) = too_many_rows("งานที่รอหักเข้าระบบในช่วงที่เลือกมีมากเกินไป", 20_000)
        else {
            panic!("a cap must be a client 400 the admin can act on, not a 500");
        };
        assert!(msg.contains("20000"), "it names the cap: {msg}");
        assert!(
            msg.contains("แบ่งช่วงวันที่ให้สั้นลง"),
            "it names the remedy: {msg}"
        );
        assert!(
            msg.contains("ไม่ตัดรายการทิ้ง"),
            "and says WHY it refused instead of silently returning fewer rows: {msg}"
        );
        // Every cap is a positive bound — a zero or negative one would refuse every request, and the
        // `+ 1` fetch each query uses would then be meaningless.
        for cap in [
            MAX_PAYOUT_BACKLOG_ROWS,
            MAX_SWEEP_BACKLOG_ROWS,
            MAX_REFUND_BACKLOG_ROWS,
            MAX_VAT_REGISTER_ROWS,
            MAX_WHT_PAYEE_ROWS,
        ] {
            assert!(cap > 0, "{cap} is not a usable bound");
        }
    }

    /// The pricing multiplicands that produce a given VAT-EXCLUSIVE `subtotal`: ONE booked hour for
    /// ONE guard at `subtotal` ฿/h, no tip. Deliberately the simplest factorisation — these tests
    /// assert on the resulting bill, and a subtotal is one equation in four unknowns, so any
    /// factorisation with the same product would do.
    fn inputs_for(subtotal: &str) -> PricingInputs {
        PricingInputs {
            base_fee: dec(subtotal),
            booked_hours: 1,
            guard_count: 1,
            tip: Decimal::ZERO,
        }
    }

    /// Charge terms for a VAT-EXCLUSIVE `subtotal` with no commission and no cancellation fee —
    /// what the API layer assembles from a booking that carries neither snapshot. The charged
    /// `amount` is the GRAND TOTAL (`subtotal` + 7%), e.g. `terms_of("2000.00")` charges 2140.00.
    fn terms_of(subtotal: &str) -> ChargeTerms {
        ChargeTerms::new(inputs_for(subtotal), Decimal::ZERO, Decimal::ZERO)
    }

    /// Charge terms carrying the booking's commission % + cancellation-fee snapshot.
    fn terms_with(subtotal: &str, commission_percent: &str, cancellation_fee: &str) -> ChargeTerms {
        ChargeTerms::new(
            inputs_for(subtotal),
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

    /// A FRESH 12-digit customer batch ref, in the shape production uses (`DDMMYYHHMMSS`, ≤12 chars)
    /// but derived from a UUID rather than the clock.
    ///
    /// `uq_payout_batches_file_ref` (migration 0010) means every generated file must carry its own
    /// reference — two files sharing one would share the customer transaction refs SCB de-dups on.
    /// Production gets uniqueness from the export timestamp; these tests run in parallel and repeat
    /// within the same second, so a hard-coded ref would make every payout test collide with its
    /// neighbours (which is exactly what the index is for, and exactly not what those tests measure).
    fn unique_batch_ref() -> String {
        let digits: String = Uuid::new_v4()
            .simple()
            .to_string()
            .chars()
            .filter(char::is_ascii_digit)
            .collect();
        // A hex UUID averages ~20 digits, but pad rather than assume — no slicing a short string.
        format!("{digits:0<12}").chars().take(12).collect()
    }

    /// A payout batch paying the given `(booking_id, guard_id)` jobs, carrying a file text with
    /// CRLF line endings and Thai characters — the shapes a byte-for-byte re-download assertion has
    /// to survive (a UTF-8 slip or a newline translation would show up here).
    fn payout_batch_of(jobs: &[(Uuid, Uuid)]) -> NewPayoutBatch {
        let batch_ref = unique_batch_ref();
        let mut guards: Vec<Uuid> = jobs.iter().map(|(_, g)| *g).collect();
        guards.sort();
        guards.dedup();
        NewPayoutBatch {
            file_ref: format!("{batch_ref}PPY"),
            system_ref: "PGUARD-PAYOUT".to_string(),
            batch_ref,
            value_date: chrono::NaiveDate::from_ymd_opt(2026, 9, 1).unwrap(),
            total_amount: dec("349.20") * Decimal::from(jobs.len()),
            recipient_count: guards.len(),
            file_text: format!(
                "HEADER|010926120000PPY|PGUARD-PAYOUT\r\nBCHDET|010926120000|PPY\r\n\
                 TXNDET|PO-1|1234567890123|NAT|111|0000|349.20||รปภ ทดสอบ\r\nTRAILR|1|{}|349.20\r\n",
                jobs.len()
            ),
            created_by: Some(Uuid::new_v4()),
            items: jobs
                .iter()
                .map(|(booking_id, guard_id)| crate::models::NewPayoutItem {
                    booking_id: *booking_id,
                    guard_id: *guard_id,
                    income: dec("360.00"),
                    wht: dec("10.80"),
                    transfer_amount: dec("349.20"),
                })
                .collect(),
        }
    }

    /// Seed a reconciled, guard-assigned completed payment — i.e. one finished job payable to
    /// `guard_id`, which is what puts a booking in the payout backlog.
    async fn seed_payable_job(pool: &sqlx::PgPool, booking_id: Uuid, guard_id: Uuid) {
        prepay_idempotent(
            pool,
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
            "UPDATE payment.payments SET actual_hours = 4, commission_percent = 10 \
             WHERE booking_id = $1",
        )
        .bind(booking_id)
        .execute(pool)
        .await
        .expect("reconcile");
    }

    /// Is this booking currently payable (in the unpaid backlog)?
    async fn in_backlog(pool: &sqlx::PgPool, booking_id: Uuid) -> bool {
        unpaid_payout_rows(pool, &PayoutSelection::default())
            .await
            .expect("backlog")
            .iter()
            .any(|r| r.booking_id == booking_id)
    }

    /// How many audit rows this batch has for `action`.
    async fn audit_count(pool: &sqlx::PgPool, batch_id: Uuid, action: &str) -> i64 {
        sqlx::query_scalar(
            "SELECT count(*) FROM payment.money_audit \
             WHERE target_kind = $1 AND target_id = $2 AND action = $3",
        )
        .bind(AUDIT_TARGET_PAYOUT_BATCH)
        .bind(batch_id)
        .bind(action)
        .fetch_one(pool)
        .await
        .expect("audit count")
    }

    /// Remove everything a payout test wrote for these bookings (items cascade with their batch;
    /// the audit log is append-only in the service, so the test clears its own rows by hand).
    async fn cleanup_payout(pool: &sqlx::PgPool, booking_ids: &[Uuid]) {
        let batch_ids: Vec<Uuid> = sqlx::query_scalar(
            "SELECT DISTINCT batch_id FROM payment.payout_batch_items WHERE booking_id = ANY($1)",
        )
        .bind(booking_ids)
        .fetch_all(pool)
        .await
        .unwrap_or_default();
        let _ = sqlx::query("DELETE FROM payment.money_audit WHERE target_id = ANY($1)")
            .bind(&batch_ids)
            .execute(pool)
            .await;
        // The SHARED reservation (migration 0012) has no FK to hang a cascade on — it is
        // polymorphic — so a test that deletes its batches must release its references too.
        let _ = sqlx::query("DELETE FROM payment.scb_file_refs WHERE batch_id = ANY($1)")
            .bind(&batch_ids)
            .execute(pool)
            .await;
        let _ = sqlx::query("DELETE FROM payment.payout_batches WHERE id = ANY($1)")
            .bind(&batch_ids)
            .execute(pool)
            .await;
        let _ = sqlx::query("DELETE FROM payment.payout_batch_items WHERE booking_id = ANY($1)")
            .bind(booking_ids)
            .execute(pool)
            .await;
        let _ = sqlx::query(
            "DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = ANY($1)",
        )
        .bind(
            booking_ids
                .iter()
                .map(|b| b.to_string())
                .collect::<Vec<_>>(),
        )
        .execute(pool)
        .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = ANY($1)")
            .bind(booking_ids)
            .execute(pool)
            .await;
    }

    /// THE test of this phase: VOID genuinely returns the work to the payable backlog.
    ///
    /// The paid-marker is a UNIQUE on `booking_id`, so flagging only the BATCH would leave the item
    /// row in place, the unique would still fire, and the booking could never be paid again — the
    /// exact bug void exists to fix. The proof is the full round trip: pay → gone from the backlog
    /// → void → BACK in the backlog → payable again into a NEW batch. Plus: double-void is a typed
    /// 409, and every step writes its audit row. DATABASE_URL-gated.
    #[tokio::test]
    async fn voiding_a_batch_returns_the_work_to_the_backlog() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let admin = Uuid::new_v4();
        seed_payable_job(&pool, booking_id, guard_id).await;
        assert!(
            in_backlog(&pool, booking_id).await,
            "the job starts payable"
        );

        // ── pay it: the booking leaves the backlog and the file text is stored with the markers.
        let batch = payout_batch_of(&[(booking_id, guard_id)]);
        let batch_id = insert_payout_batch(&pool, &batch).await.expect("pay");
        assert!(
            !in_backlog(&pool, booking_id).await,
            "a paid job drops out of the backlog"
        );
        assert_eq!(
            audit_count(&pool, batch_id, AUDIT_PAYOUT_EXPORTED).await,
            1,
            "the export writes exactly one audit row, in the batch's own transaction"
        );

        // ── the stored file round-trips BYTE FOR BYTE (this is what a re-download serves; a
        //    regenerated file could differ under the same batch ref).
        let stored = get_payout_batch_file(&pool, batch_id)
            .await
            .expect("stored file");
        assert_eq!(stored.file_text, batch.file_text, "byte-for-byte");
        assert_eq!(
            stored.file_text.as_bytes(),
            batch.file_text.as_bytes(),
            "CRLF + Thai bytes survive the round trip"
        );
        assert_eq!(stored.file_ref, batch.file_ref);

        // ── VOID it. The booking must come BACK.
        let voided = void_payout_batch(&pool, batch_id, admin, "ธนาคารตีกลับไฟล์")
            .await
            .expect("void");
        assert_eq!(voided.status, "voided");
        assert_eq!(voided.void_reason.as_deref(), Some("ธนาคารตีกลับไฟล์"));
        assert!(voided.voided_at.is_some() && voided.voided_by == Some(admin));
        assert!(
            in_backlog(&pool, booking_id).await,
            "VOID must return the job to the payable backlog — this is the whole point"
        );
        // The item row is KEPT (history: the guard WAS in a voided batch), just flagged.
        let (items, live): (i64, i64) = sqlx::query_as(
            "SELECT count(*), count(*) FILTER (WHERE voided_at IS NULL) \
             FROM payment.payout_batch_items WHERE batch_id = $1",
        )
        .bind(batch_id)
        .fetch_one(&pool)
        .await
        .expect("item state");
        assert_eq!((items, live), (1, 0), "kept as history, but not live");
        assert_eq!(audit_count(&pool, batch_id, AUDIT_PAYOUT_VOIDED).await, 1);

        // ── and it can be paid again, into a NEW batch (proves the unique is PARTIAL: the voided
        //    item row is still there and must not block the new one).
        let second = payout_batch_of(&[(booking_id, guard_id)]);
        let second_id = insert_payout_batch(&pool, &second)
            .await
            .expect("a voided booking is payable again");
        assert_ne!(second_id, batch_id);
        assert!(!in_backlog(&pool, booking_id).await);

        // ── a double-void is a typed 409, never a silent no-op: the admin's page may be stale and
        //    they need to know the first void already returned the work.
        let err = void_payout_batch(&pool, batch_id, admin, "กดซ้ำ")
            .await
            .expect_err("already voided");
        assert!(
            matches!(&err, AppError::ConflictCode { code, .. } if *code == "PAYOUT_BATCH_ALREADY_VOIDED"),
            "got {err:?}"
        );
        assert_eq!(
            audit_count(&pool, batch_id, AUDIT_PAYOUT_VOIDED).await,
            1,
            "the refused second void writes nothing"
        );

        cleanup_payout(&pool, &[booking_id]).await;
    }

    /// TWO EXPORTS IN THE SAME BANGKOK SECOND cannot both commit — and the loser marks NOTHING paid.
    ///
    /// `batch_ref` is a 12-digit timestamp at ONE-SECOND resolution and `file_ref` is that stamp plus
    /// the product code, so two exports a fraction of a second apart produce the SAME refs. Their
    /// guard selections here are DISJOINT, so the per-booking paid-marker has nothing to catch: before
    /// `uq_payout_batches_file_ref` both committed, and two files went out carrying the same customer
    /// transaction refs — the key SCB de-dups on. The whole insert is one transaction, so the loser
    /// must roll back completely: its booking stays payable. DATABASE_URL-gated.
    #[tokio::test]
    async fn two_exports_in_the_same_second_cannot_both_commit() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let (booking_a, booking_b) = (Uuid::new_v4(), Uuid::new_v4());
        let (guard_a, guard_b) = (Uuid::new_v4(), Uuid::new_v4());
        seed_payable_job(&pool, booking_a, guard_a).await;
        seed_payable_job(&pool, booking_b, guard_b).await;

        // The same second → the same refs. Different guards, so nothing overlaps but the reference.
        let first = payout_batch_of(&[(booking_a, guard_a)]);
        let second = NewPayoutBatch {
            file_ref: first.file_ref.clone(),
            batch_ref: first.batch_ref.clone(),
            ..payout_batch_of(&[(booking_b, guard_b)])
        };

        let batch_id = insert_payout_batch(&pool, &first).await.expect("first");
        let err = insert_payout_batch(&pool, &second)
            .await
            .expect_err("the second file may not reuse the reference");
        assert!(
            matches!(&err, AppError::ConflictCode { code, .. } if *code == "PAYOUT_BATCH_REF_TAKEN"),
            "a typed 409 the admin can act on, not a 500: got {err:?}"
        );

        // THE POINT: the loser wrote nothing. Its booking is still payable (so the retry a second
        // later pays it), and no orphan batch header was left behind.
        assert!(
            in_backlog(&pool, booking_b).await,
            "the losing export must mark NOTHING paid"
        );
        assert!(!in_backlog(&pool, booking_a).await, "the winner did pay");
        let with_ref: i64 =
            sqlx::query_scalar("SELECT count(*) FROM payment.payout_batches WHERE file_ref = $1")
                .bind(&first.file_ref)
                .fetch_one(&pool)
                .await
                .expect("count");
        assert_eq!(with_ref, 1, "exactly one file carries that reference");

        // …and a second later (a fresh ref) the very same work goes through.
        let retry = payout_batch_of(&[(booking_b, guard_b)]);
        let retry_id = insert_payout_batch(&pool, &retry).await.expect("retry");
        assert_ne!(retry_id, batch_id);
        assert!(!in_backlog(&pool, booking_b).await);

        cleanup_payout(&pool, &[booking_a, booking_b]).await;
    }

    /// PER-ITEM VOID: exactly the named bookings go back to the payable backlog, the rest of the
    /// batch stays paid, and it works on a `confirmed` batch — which is the whole reason it exists.
    ///
    /// SCB can accept a structurally valid file and still fail individual credit lines (an
    /// unregistered PromptPay proxy is the everyday case), so the batch is honestly `confirmed`
    /// while a handful of guards were never paid. Voiding the WHOLE batch would un-pay everyone and
    /// is refused on a confirmed batch anyway. DATABASE_URL-gated.
    #[tokio::test]
    async fn voiding_single_items_returns_only_those_bookings_even_on_a_confirmed_batch() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let (booking_ok, booking_bounced) = (Uuid::new_v4(), Uuid::new_v4());
        let (guard_ok, guard_bounced) = (Uuid::new_v4(), Uuid::new_v4());
        let admin = Uuid::new_v4();
        seed_payable_job(&pool, booking_ok, guard_ok).await;
        seed_payable_job(&pool, booking_bounced, guard_bounced).await;

        let batch = payout_batch_of(&[(booking_ok, guard_ok), (booking_bounced, guard_bounced)]);
        let batch_id = insert_payout_batch(&pool, &batch).await.expect("pay");
        // The bank TOOK the file: uploaded → confirmed. Both statuses are on the way to terminal.
        set_payout_batch_status(&pool, batch_id, BatchStatus::Uploaded, None, admin)
            .await
            .expect("uploaded");
        set_payout_batch_status(&pool, batch_id, BatchStatus::Confirmed, None, admin)
            .await
            .expect("confirmed");
        // …so the whole-batch escape hatch is closed — that is what makes this action necessary.
        assert!(
            void_payout_batch(&pool, batch_id, admin, "ทั้งไฟล์")
                .await
                .is_err(),
            "a confirmed batch can never be voided wholesale"
        );

        // Return ONLY the bounced line.
        let detail = void_payout_batch_items(
            &pool,
            batch_id,
            &[booking_bounced],
            admin,
            "พร้อมเพย์ปลายทางไม่ผูกบัญชี ธนาคารโอนไม่สำเร็จ",
        )
        .await
        .expect("per-item void on a confirmed batch");
        assert_eq!(
            detail.batch.status, "confirmed",
            "the batch's own status is untouched — the bank really did take the file"
        );
        assert!(
            detail.batch.voided_at.is_none() && detail.batch.void_reason.is_none(),
            "an item-level correction is not a batch void"
        );
        let voided_items: Vec<Uuid> = detail
            .items
            .iter()
            .filter(|i| i.voided_at.is_some())
            .map(|i| i.booking_id)
            .collect();
        assert_eq!(voided_items, vec![booking_bounced]);

        assert!(
            in_backlog(&pool, booking_bounced).await,
            "the failed line is payable again"
        );
        assert!(
            !in_backlog(&pool, booking_ok).await,
            "the guard who WAS paid must not be re-queued — this is the bug whole-batch void has"
        );
        assert_eq!(
            audit_count(&pool, batch_id, AUDIT_PAYOUT_ITEMS_VOIDED).await,
            1,
            "one audit row, naming the bookings, in the same transaction"
        );

        // Double-voiding the same item is a typed 409, never a silent success (the admin's page may
        // be stale, and "it worked" would hide that the money question was already answered).
        let err = void_payout_batch_items(&pool, batch_id, &[booking_bounced], admin, "กดซ้ำ")
            .await
            .expect_err("already returned");
        assert!(
            matches!(&err, AppError::ConflictCode { code, .. } if *code == "PAYOUT_ITEM_ALREADY_VOIDED"),
            "got {err:?}"
        );

        // A booking that is not in THIS batch is a 404 — and must not un-pay the ones that are.
        let err = void_payout_batch_items(
            &pool,
            batch_id,
            &[booking_ok, Uuid::new_v4()],
            admin,
            "ไฟล์ผิด",
        )
        .await
        .expect_err("unknown booking");
        assert!(matches!(err, AppError::NotFound(_)), "got {err:?}");
        assert!(
            !in_backlog(&pool, booking_ok).await,
            "a rejected request must be all-or-nothing"
        );
        assert_eq!(
            audit_count(&pool, batch_id, AUDIT_PAYOUT_ITEMS_VOIDED).await,
            1,
            "refused requests write no audit rows"
        );

        // An unknown BATCH is a 404 too (the lock read is the same one the whole-batch void uses).
        assert!(matches!(
            void_payout_batch_items(&pool, Uuid::new_v4(), &[booking_ok], admin, "ไม่มีไฟล์").await,
            Err(AppError::NotFound(_))
        ));

        // …and the returned booking really is payable into a NEW file.
        let redo = payout_batch_of(&[(booking_bounced, guard_bounced)]);
        insert_payout_batch(&pool, &redo)
            .await
            .expect("the bounced guard can be paid by a fresh file");

        cleanup_payout(&pool, &[booking_ok, booking_bounced]).await;
    }

    /// READ-AFTER-WRITE on the payable backlog: a void and an immediate re-query must agree.
    ///
    /// The backlog read used to be offloaded to the read REPLICA while every write that changes its
    /// answer (`payout_batch_items` inserts, `voided_at` stamps) goes to the primary. An admin voids
    /// a batch and exports again within seconds, so replica lag silently dropped the freshly-released
    /// bookings out of the new file — the void appeared to do nothing. `api::payouts::aggregate` now
    /// reads `state.db()`; this pins the behaviour that change is there to guarantee. DATABASE_URL-gated.
    #[tokio::test]
    async fn the_backlog_sees_a_void_immediately() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let admin = Uuid::new_v4();
        seed_payable_job(&pool, booking_id, guard_id).await;
        let batch = payout_batch_of(&[(booking_id, guard_id)]);
        let batch_id = insert_payout_batch(&pool, &batch).await.expect("pay");
        // No await in between beyond the calls themselves — this is the "void, then export" gap.
        assert!(!in_backlog(&pool, booking_id).await);
        void_payout_batch(&pool, batch_id, admin, "ยังไม่ได้อัปโหลดเข้าธนาคาร")
            .await
            .expect("void");
        assert!(
            in_backlog(&pool, booking_id).await,
            "the very next backlog read must already show the released booking"
        );
        // The same holds for the per-item flavour.
        let second = payout_batch_of(&[(booking_id, guard_id)]);
        let second_id = insert_payout_batch(&pool, &second).await.expect("re-pay");
        assert!(!in_backlog(&pool, booking_id).await);
        void_payout_batch_items(&pool, second_id, &[booking_id], admin, "ธนาคารโอนไม่สำเร็จ")
            .await
            .expect("item void");
        assert!(in_backlog(&pool, booking_id).await);

        cleanup_payout(&pool, &[booking_id]).await;
    }

    /// The batch lifecycle: the history read, the stored-file read, the legal walk
    /// (generated → uploaded → confirmed) with its timestamps + audit rows, and the refusal of an
    /// illegal step. DATABASE_URL-gated.
    #[tokio::test]
    async fn payout_batch_status_walks_the_lifecycle_and_refuses_illegal_steps() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let admin = Uuid::new_v4();
        seed_payable_job(&pool, booking_id, guard_id).await;
        let batch = payout_batch_of(&[(booking_id, guard_id)]);
        let batch_id = insert_payout_batch(&pool, &batch).await.expect("pay");

        // A freshly exported batch is `generated`, has its file, and shows up in the history.
        let detail = get_payout_batch(&pool, batch_id).await.expect("detail");
        assert_eq!(detail.batch.status, "generated");
        assert!(detail.batch.has_file, "the file text was stored");
        assert_eq!(detail.batch.recipient_count, 1);
        assert_eq!(detail.items.len(), 1);
        assert_eq!(detail.items[0].booking_id, booking_id);
        let page = list_payout_batches(&pool, 50, 0).await.expect("history");
        assert!(page.batches.iter().any(|b| b.id == batch_id));
        assert!(page.total >= 1, "the total counts beyond the page window");

        // generated → uploaded → confirmed, each stamping its OWN timestamp column so the history
        // survives the next step.
        let up = set_payout_batch_status(&pool, batch_id, BatchStatus::Uploaded, None, admin)
            .await
            .expect("uploaded");
        assert_eq!(up.status, "uploaded");
        assert!(up.uploaded_at.is_some() && up.confirmed_at.is_none());
        let done = set_payout_batch_status(
            &pool,
            batch_id,
            BatchStatus::Confirmed,
            Some("ธนาคารรับไฟล์แล้ว"),
            admin,
        )
        .await
        .expect("confirmed");
        assert_eq!(done.status, "confirmed");
        assert!(done.uploaded_at.is_some(), "the earlier stamp is kept");
        assert!(done.confirmed_at.is_some());
        assert_eq!(done.status_note.as_deref(), Some("ธนาคารรับไฟล์แล้ว"));
        assert_eq!(
            audit_count(&pool, batch_id, AUDIT_PAYOUT_STATUS_CHANGED).await,
            2
        );

        // An illegal step is refused, and refused WITHOUT writing anything.
        let err = set_payout_batch_status(&pool, batch_id, BatchStatus::Rejected, None, admin)
            .await
            .expect_err("confirmed is terminal");
        assert!(
            matches!(&err, AppError::ConflictCode { code, .. } if *code == "PAYOUT_BATCH_TERMINAL"),
            "got {err:?}"
        );
        // …including a void: the money already moved, so un-marking would pay the guard twice.
        let void_err = void_payout_batch(&pool, batch_id, admin, "เปลี่ยนใจ")
            .await
            .expect_err("a confirmed batch cannot be voided");
        assert!(matches!(&void_err, AppError::ConflictCode { .. }));
        assert!(
            !in_backlog(&pool, booking_id).await,
            "a refused void leaves the job paid"
        );
        assert_eq!(
            audit_count(&pool, batch_id, AUDIT_PAYOUT_STATUS_CHANGED).await,
            2,
            "refused transitions write no audit rows"
        );
        assert_eq!(
            get_payout_batch(&pool, batch_id)
                .await
                .expect("detail")
                .batch
                .status,
            "confirmed",
            "and leave the status alone"
        );

        // An unknown batch id is a 404 on every read, not an empty success.
        let missing = Uuid::new_v4();
        assert!(matches!(
            get_payout_batch(&pool, missing).await,
            Err(AppError::NotFound(_))
        ));
        assert!(matches!(
            get_payout_batch_file(&pool, missing).await,
            Err(AppError::NotFound(_))
        ));

        cleanup_payout(&pool, &[booking_id]).await;
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
                // A REAL SCB account (it passes the §14 check digit). It matters that every test
                // touching this SINGLETON row writes the same VALID account: the config is one
                // shared row, tests run in parallel, and a neighbour that stored an account the
                // export refuses would 400 somebody else's money file.
                debit_account: Some("1234567896".to_string()),
                fee_debit_account: None,
                revenue_account: None,
                wht_form_type_code: None,
                wht_pay_type_code: None,
                wht_income_type_code: None,
                wht_income_desc: None,
                wht_rate_percent: Some(dec("3")),
                max_transfer_per_txn: None,
                fee_charge_code: None,
                sms_notify: None,
            },
            Uuid::new_v4(),
        )
        .await
        .expect("upsert config");
        assert_eq!(cfg.debit_account.as_deref(), Some("1234567896"));
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
        let batch = payout_batch_of(&[(booking_id, guard_id)]);
        let batch_id = insert_payout_batch(&pool, &batch).await.expect("pay");

        // The batch header records how many GUARDS it pays (one TXNDET each) — NOT how many
        // bookings. It used to store `items.len()`, so a guard with several finished jobs inflated
        // the count past the number of credit lines the file actually carries.
        let recipients: i32 =
            sqlx::query_scalar("SELECT recipient_count FROM payment.payout_batches WHERE id = $1")
                .bind(batch_id)
                .fetch_one(&pool)
                .await
                .expect("recipient_count");
        assert_eq!(recipients, 1, "one guard = one recipient");

        // now it is NO LONGER in the backlog (paid-marker excludes it).
        let after = unpaid_payout_rows(&pool, &all).await.expect("backlog 2");
        assert!(
            !after.iter().any(|r| r.booking_id == booking_id),
            "a paid job drops out of the backlog"
        );

        // a SECOND batch for the same booking is refused — never pay twice. It is a genuinely NEW
        // file (its own batch/file ref, as a second export would be), so what refuses it is the
        // per-booking paid-marker and not the file-ref unique.
        let err = insert_payout_batch(&pool, &payout_batch_of(&[(booking_id, guard_id)]))
            .await
            .expect_err("double pay refused");
        assert!(
            matches!(&err, AppError::ConflictCode { code, .. } if *code == "PAYOUT_ALREADY_PAID"),
            "double-pay is a typed conflict, got {err:?}"
        );

        // cleanup (items cascade with the batch; the audit rows go too).
        cleanup_payout(&pool, &[booking_id]).await;
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

    // ----- stream ① customer refunds: the queue that could never be drained -----

    /// Seed a LANE-A obligation: a completed pre-pay whose settle left `refund` owed
    /// (`refund_status = 'pending'`). Returns the `payments.id` — the obligation's `source_id`.
    ///
    /// The columns are written directly rather than by driving a real cancel/reconcile: this
    /// exercises the EXPORT, and all three lane-A writers (`reconcile_on_completion`,
    /// `refund_on_cancellation`, `refund_race_lost_prepay`) leave exactly this shape behind.
    async fn seed_pending_refund(
        pool: &sqlx::PgPool,
        booking_id: Uuid,
        customer_id: Uuid,
        refund: &str,
    ) -> Uuid {
        let payment = payment_of(
            prepay_idempotent(
                pool,
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
        sqlx::query(
            "UPDATE payment.payments \
                SET refund_amount = $2::numeric, refund_status = 'pending' WHERE id = $1",
        )
        .bind(payment.id)
        .bind(refund)
        .execute(pool)
        .await
        .expect("queue the refund");
        payment.id
    }

    /// Seed a LANE-B obligation: a SECOND, real transfer for an already-paid booking, recorded as an
    /// UNAPPLIED slip (`applied = FALSE`, `refund_status = 'pending'`) exactly as `pay_with_slip`
    /// records a genuine double-pay. Returns the `payment_slips.id`.
    ///
    /// This lane is the easy one to forget: a different table, a different id, a different amount
    /// column, and NO `customer_id` of its own — the backlog has to reach the customer through
    /// `payment_id`. A test that only covers lane A would leave every double-payer unrefunded.
    async fn seed_duplicate_slip(
        pool: &sqlx::PgPool,
        booking_id: Uuid,
        customer_id: Uuid,
        amount: &str,
    ) -> Uuid {
        let payment = payment_of(
            prepay_idempotent(
                pool,
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
        let unique = Uuid::new_v4().simple().to_string();
        sqlx::query_scalar(
            "INSERT INTO payment.payment_slips \
                 (payment_id, booking_id, reference_id, trans_ref, amount, slip_key, applied, refund_status) \
             VALUES ($1, $2, $3, $4, $5::numeric, $6, FALSE, 'pending') RETURNING id",
        )
        .bind(payment.id)
        .bind(booking_id)
        .bind(format!("ref-{unique}"))
        .bind(format!("txn-{unique}"))
        .bind(amount)
        .bind(format!("slips/{unique}.jpg"))
        .fetch_one(pool)
        .await
        .expect("record the duplicate transfer")
    }

    /// A refund batch settling the given obligations, carrying a file text with CRLF line endings
    /// and Thai characters — the shapes a byte-for-byte re-download assertion has to survive.
    /// The `batch_ref` is randomised for the same reason [`payout_batch_of`]'s is: these tests run in
    /// parallel within the same second, and `uq_refund_batches_file_ref` is exactly what would
    /// otherwise make them collide with each other.
    fn refund_batch_of(items: &[(&str, Uuid, Uuid, &str)]) -> NewRefundBatch {
        let batch_ref = unique_batch_ref();
        let mut customers: Vec<Uuid> = items.iter().map(|(_, _, c, _)| *c).collect();
        customers.sort();
        customers.dedup();
        let total: Decimal = items.iter().map(|(_, _, _, amt)| dec(amt)).sum();
        NewRefundBatch {
            file_ref: format!("{batch_ref}PPY"),
            system_ref: "PGUARD-REFUND".to_string(),
            batch_ref,
            value_date: chrono::NaiveDate::from_ymd_opt(2026, 9, 8).unwrap(),
            total_amount: total,
            recipient_count: customers.len(),
            file_text: format!(
                "HEADER|080926120000PPY|PGUARD-REFUND\r\nBCHDET|080926120000|PPY\r\n\
                 TXNDET|RF-1|0812345678|MOB|111|0000|{total}||ลูกค้า ทดสอบ\r\nTRAILR|1|{}|{total}\r\n",
                customers.len()
            ),
            created_by: Some(Uuid::new_v4()),
            items: items
                .iter()
                .map(|(kind, source_id, customer_id, amount)| crate::models::NewRefundItem {
                    source_kind: (*kind).to_string(),
                    source_id: *source_id,
                    booking_id: Uuid::new_v4(),
                    customer_id: *customer_id,
                    amount: dec(amount),
                })
                .collect(),
        }
    }

    /// Is this obligation currently in the refundable backlog?
    async fn in_refund_backlog(pool: &sqlx::PgPool, kind: &str, source_id: Uuid) -> bool {
        unpaid_refund_rows(pool, &RefundSelection::default())
            .await
            .expect("backlog")
            .iter()
            .any(|r| r.source_kind == kind && r.source_id == source_id)
    }

    /// The stored `refund_status` of one obligation, read off whichever table owns it.
    async fn refund_status_of(pool: &sqlx::PgPool, kind: &str, source_id: Uuid) -> Option<String> {
        let sql = match kind {
            "payment" => "SELECT refund_status FROM payment.payments WHERE id = $1",
            _ => "SELECT refund_status FROM payment.payment_slips WHERE id = $1",
        };
        sqlx::query_scalar(sql)
            .bind(source_id)
            .fetch_one(pool)
            .await
            .expect("read refund_status")
    }

    /// How many audit rows this refund batch has for `action`.
    async fn refund_audit_count(pool: &sqlx::PgPool, batch_id: Uuid, action: &str) -> i64 {
        sqlx::query_scalar(
            "SELECT count(*) FROM payment.money_audit \
             WHERE target_kind = $1 AND target_id = $2 AND action = $3",
        )
        .bind(AUDIT_TARGET_REFUND_BATCH)
        .bind(batch_id)
        .bind(action)
        .fetch_one(pool)
        .await
        .expect("audit count")
    }

    /// Remove everything a refund test wrote for these bookings (items cascade with their batch;
    /// the audit log is append-only in the service, so the test clears its own rows by hand).
    async fn cleanup_refund(pool: &sqlx::PgPool, booking_ids: &[Uuid]) {
        let batch_ids: Vec<Uuid> = sqlx::query_scalar(
            "SELECT DISTINCT batch_id FROM payment.refund_batch_items WHERE booking_id = ANY($1) \
              OR source_id IN (SELECT id FROM payment.payments WHERE booking_id = ANY($1)) \
              OR source_id IN (SELECT id FROM payment.payment_slips WHERE booking_id = ANY($1))",
        )
        .bind(booking_ids)
        .fetch_all(pool)
        .await
        .unwrap_or_default();
        let _ = sqlx::query("DELETE FROM payment.money_audit WHERE target_id = ANY($1)")
            .bind(&batch_ids)
            .execute(pool)
            .await;
        let _ = sqlx::query("DELETE FROM payment.scb_file_refs WHERE batch_id = ANY($1)")
            .bind(&batch_ids)
            .execute(pool)
            .await;
        let _ = sqlx::query("DELETE FROM payment.refund_batches WHERE id = ANY($1)")
            .bind(&batch_ids)
            .execute(pool)
            .await;
        let _ = sqlx::query("DELETE FROM payment.payment_slips WHERE booking_id = ANY($1)")
            .bind(booking_ids)
            .execute(pool)
            .await;
        let _ = sqlx::query(
            "DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = ANY($1)",
        )
        .bind(
            booking_ids
                .iter()
                .map(|b| b.to_string())
                .collect::<Vec<_>>(),
        )
        .execute(pool)
        .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = ANY($1)")
            .bind(booking_ids)
            .execute(pool)
            .await;
    }

    /// THE DOUBLE-REFUND GUARD, over BOTH lanes: an exported obligation leaves the backlog, its
    /// source row flips to `processed`, and a second export finds nothing left.
    ///
    /// This is the test that proves the queue can actually be DRAINED. Before this phase nothing in
    /// the codebase ever wrote `refund_status = 'processed'` — the rows only ever accumulated while
    /// the customer got a push saying their money was on the way. Both halves are asserted because
    /// either alone is a bug: a marker without the status flip leaves the obligation invisible to
    /// `/admin/refunds/queue` forever, and a status flip without the marker would let the very next
    /// export send the money twice. DATABASE_URL-gated.
    #[tokio::test]
    async fn refund_export_closes_both_lanes_and_cannot_pay_them_twice() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let (booking_a, booking_b) = (Uuid::new_v4(), Uuid::new_v4());
        let customer = Uuid::new_v4();
        // Lane A: a settle left 640.00 owed. Lane B: the customer transferred twice; the whole
        // duplicate 2140.00 goes back.
        let payment_id = seed_pending_refund(&pool, booking_a, customer, "640.00").await;
        let slip_id = seed_duplicate_slip(&pool, booking_b, customer, "2140.00").await;

        // Both lanes start in the backlog, and the UNION reaches lane B's customer through its
        // payment (the slips table has no customer_id of its own).
        let backlog = unpaid_refund_rows(&pool, &RefundSelection::default())
            .await
            .expect("backlog");
        let mine: Vec<_> = backlog
            .iter()
            .filter(|r| r.customer_id == customer)
            .collect();
        assert_eq!(mine.len(), 2, "both lanes are owed: {mine:?}");
        assert!(mine.iter().any(|r| r.source_kind == "payment"
            && r.source_id == payment_id
            && r.amount == dec("640.00")));
        assert!(mine.iter().any(|r| r.source_kind == "slip"
            && r.source_id == slip_id
            && r.amount == dec("2140.00")));

        // ── export both. The markers and the queue advance in ONE transaction.
        let batch = refund_batch_of(&[
            ("payment", payment_id, customer, "640.00"),
            ("slip", slip_id, customer, "2140.00"),
        ]);
        let batch_id = insert_refund_batch(&pool, &batch).await.expect("export");
        for (kind, id) in [("payment", payment_id), ("slip", slip_id)] {
            assert!(
                !in_refund_backlog(&pool, kind, id).await,
                "{kind} left the backlog"
            );
            assert_eq!(
                refund_status_of(&pool, kind, id).await.as_deref(),
                Some("processed"),
                "{kind}: the queue row must actually close — this never happened before"
            );
        }
        assert_eq!(
            refund_audit_count(&pool, batch_id, AUDIT_REFUND_EXPORTED).await,
            1,
            "the export writes exactly one audit row, in the batch's own transaction"
        );
        // The stored file round-trips BYTE FOR BYTE (this is what a re-download serves).
        let stored = get_refund_batch_file(&pool, batch_id)
            .await
            .expect("stored file");
        assert_eq!(stored.file_text.as_bytes(), batch.file_text.as_bytes());

        // ── a SECOND export of the same obligations is refused by the partial unique, and refuses
        //    the WHOLE batch rather than settling a subset.
        let again = refund_batch_of(&[("payment", payment_id, customer, "640.00")]);
        let err = insert_refund_batch(&pool, &again)
            .await
            .expect_err("an already-exported obligation may not ride a second file");
        assert!(
            matches!(&err, AppError::ConflictCode { code, .. } if *code == "REFUND_ALREADY_EXPORTED"),
            "a typed 409 the admin can act on, not a 500: got {err:?}"
        );
        let orphan: i64 =
            sqlx::query_scalar("SELECT count(*) FROM payment.refund_batches WHERE file_ref = $1")
                .bind(&again.file_ref)
                .fetch_one(&pool)
                .await
                .expect("count");
        assert_eq!(orphan, 0, "the losing export left no batch header behind");

        cleanup_refund(&pool, &[booking_a, booking_b]).await;
    }

    /// TWO REFUND EXPORTS IN THE SAME BANGKOK SECOND cannot both commit — and the loser marks
    /// NOTHING. Same guard, same reasoning as the payout's `uq_payout_batches_file_ref`: the
    /// obligations here are DISJOINT, so the per-obligation marker has nothing to catch, yet two
    /// files sharing a reference would carry the customer transaction refs SCB de-dups on.
    #[tokio::test]
    async fn two_refund_exports_in_the_same_second_cannot_both_commit() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let (booking_a, booking_b) = (Uuid::new_v4(), Uuid::new_v4());
        let (cust_a, cust_b) = (Uuid::new_v4(), Uuid::new_v4());
        let a = seed_pending_refund(&pool, booking_a, cust_a, "100.00").await;
        let b = seed_pending_refund(&pool, booking_b, cust_b, "200.00").await;

        let first = refund_batch_of(&[("payment", a, cust_a, "100.00")]);
        let second = NewRefundBatch {
            file_ref: first.file_ref.clone(),
            batch_ref: first.batch_ref.clone(),
            ..refund_batch_of(&[("payment", b, cust_b, "200.00")])
        };
        insert_refund_batch(&pool, &first).await.expect("first");
        let err = insert_refund_batch(&pool, &second)
            .await
            .expect_err("the second file may not reuse the reference");
        assert!(
            matches!(&err, AppError::ConflictCode { code, .. } if *code == "REFUND_BATCH_REF_TAKEN"),
            "got {err:?}"
        );
        // THE POINT: the loser wrote nothing — its obligation is still owed AND still `pending`, so
        // the retry a second later refunds it.
        assert!(in_refund_backlog(&pool, "payment", b).await);
        assert_eq!(
            refund_status_of(&pool, "payment", b).await.as_deref(),
            Some("pending"),
            "the losing export must not close a queue row"
        );

        cleanup_refund(&pool, &[booking_a, booking_b]).await;
    }

    /// A PAYOUT AND A REFUND IN THE SAME BANGKOK SECOND cannot both commit either — the collision
    /// the two per-table uniques are structurally unable to see.
    ///
    /// Both streams ride PromptPay, so both stamp `batch_ref` = the same 12-digit second and
    /// `file_ref` = that stamp + `PPY`: byte-identical HEADER field 1 AND BCHDET field 1, in TWO
    /// DIFFERENT TABLES. `uq_payout_batches_file_ref` and `uq_refund_batches_file_ref` each see only
    /// their own, so before `payment.scb_file_refs` (migration 0012) both committed and two files
    /// went to the bank carrying the references it de-dups on.
    ///
    /// Asserted in BOTH directions, because the loser is whoever commits second and each stream must
    /// roll back completely: the payout's booking stays payable, and the refund's obligation stays in
    /// the queue AND stays `pending` (a closed queue row with no money sent is the worst outcome
    /// available). Plus the batch-ref-only case: two files whose product suffixes DIFFER still share
    /// BCHDET field 1, which is why `uq_scb_file_refs_batch_ref` exists on top of the primary key.
    /// DATABASE_URL-gated.
    #[tokio::test]
    async fn a_payout_and_a_refund_cannot_share_one_bank_reference() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };

        // ── direction 1: the payout commits first, the refund loses.
        let (booking_p, guard_p) = (Uuid::new_v4(), Uuid::new_v4());
        let (booking_r, cust_r) = (Uuid::new_v4(), Uuid::new_v4());
        seed_payable_job(&pool, booking_p, guard_p).await;
        let owed_r = seed_pending_refund(&pool, booking_r, cust_r, "310.00").await;

        let payout = payout_batch_of(&[(booking_p, guard_p)]);
        let refund = NewRefundBatch {
            file_ref: payout.file_ref.clone(),
            batch_ref: payout.batch_ref.clone(),
            ..refund_batch_of(&[("payment", owed_r, cust_r, "310.00")])
        };
        insert_payout_batch(&pool, &payout).await.expect("payout");
        let err = insert_refund_batch(&pool, &refund)
            .await
            .expect_err("a refund may not reuse the payout's bank reference");
        assert!(
            matches!(&err, AppError::ConflictCode { code, .. } if *code == "REFUND_BATCH_REF_TAKEN"),
            "the SAME typed 409 as an intra-stream collision — same situation, same remedy: {err:?}"
        );
        // THE POINT: the loser wrote NOTHING. Not a marker row, and above all not a `processed`.
        assert!(
            in_refund_backlog(&pool, "payment", owed_r).await,
            "the losing refund export must leave its obligation refundable"
        );
        assert_eq!(
            refund_status_of(&pool, "payment", owed_r).await.as_deref(),
            Some("pending"),
            "no queue row may be closed by an export that rolled back"
        );

        // ── direction 2: the refund commits first, the payout loses.
        let (booking_p2, guard_p2) = (Uuid::new_v4(), Uuid::new_v4());
        let (booking_r2, cust_r2) = (Uuid::new_v4(), Uuid::new_v4());
        seed_payable_job(&pool, booking_p2, guard_p2).await;
        let owed_r2 = seed_pending_refund(&pool, booking_r2, cust_r2, "88.00").await;

        let refund2 = refund_batch_of(&[("payment", owed_r2, cust_r2, "88.00")]);
        let payout2 = NewPayoutBatch {
            file_ref: refund2.file_ref.clone(),
            batch_ref: refund2.batch_ref.clone(),
            ..payout_batch_of(&[(booking_p2, guard_p2)])
        };
        insert_refund_batch(&pool, &refund2).await.expect("refund");
        let err = insert_payout_batch(&pool, &payout2)
            .await
            .expect_err("a payout may not reuse the refund's bank reference");
        assert!(
            matches!(&err, AppError::ConflictCode { code, .. } if *code == "PAYOUT_BATCH_REF_TAKEN"),
            "got {err:?}"
        );
        assert!(
            in_backlog(&pool, booking_p2).await,
            "the losing payout export must mark NOTHING paid"
        );

        // ── the batch-ref-only case. A future stream ② sweep is an `OAT` file, so its FILE ref
        //    differs by product suffix while its BCHDET field 1 is the identical stamp. The primary
        //    key alone would wave that through; the UNIQUE on `batch_ref` is what does not.
        let (booking_r3, cust_r3) = (Uuid::new_v4(), Uuid::new_v4());
        let owed_r3 = seed_pending_refund(&pool, booking_r3, cust_r3, "44.00").await;
        let other_product = NewRefundBatch {
            file_ref: format!("{}OAT", refund2.batch_ref),
            batch_ref: refund2.batch_ref.clone(),
            ..refund_batch_of(&[("payment", owed_r3, cust_r3, "44.00")])
        };
        assert_ne!(
            other_product.file_ref, refund2.file_ref,
            "different file ref"
        );
        let err = insert_refund_batch(&pool, &other_product)
            .await
            .expect_err("the BATCH ref is what the bank de-dups a batch on");
        assert!(
            matches!(&err, AppError::ConflictCode { code, .. } if *code == "REFUND_BATCH_REF_TAKEN"),
            "got {err:?}"
        );
        assert_eq!(
            refund_status_of(&pool, "payment", owed_r3).await.as_deref(),
            Some("pending"),
        );

        cleanup_payout(&pool, &[booking_p, booking_p2]).await;
        cleanup_refund(&pool, &[booking_r, booking_r2, booking_r3]).await;
    }

    /// VOID genuinely returns the obligation to the refundable queue — BOTH halves of it.
    ///
    /// The paid-marker is a partial unique on the LIVE items, so un-flagging the item is what lets
    /// the obligation ride a new file; but the backlog ALSO requires the source row to say
    /// `pending`, so the void has to flip `refund_status` back too. Either half alone leaves the
    /// customer permanently unrefunded, which is the bug void exists to fix. Proof is the full round
    /// trip: refund → gone → void → BACK (and `pending`) → refunded again into a NEW batch. Plus: a
    /// double-void is a typed 409 with the REFUND code, and every step writes its audit row.
    #[tokio::test]
    async fn voiding_a_refund_batch_returns_the_obligation_to_the_queue() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let customer = Uuid::new_v4();
        let admin = Uuid::new_v4();
        let payment_id = seed_pending_refund(&pool, booking_id, customer, "1070.00").await;

        let batch = refund_batch_of(&[("payment", payment_id, customer, "1070.00")]);
        let batch_id = insert_refund_batch(&pool, &batch).await.expect("export");
        assert!(!in_refund_backlog(&pool, "payment", payment_id).await);

        let voided = void_refund_batch(&pool, batch_id, admin, "ธนาคารตีกลับไฟล์")
            .await
            .expect("void");
        assert_eq!(voided.status, "voided");
        assert_eq!(voided.void_reason.as_deref(), Some("ธนาคารตีกลับไฟล์"));
        assert!(voided.voided_at.is_some() && voided.voided_by == Some(admin));
        assert!(
            in_refund_backlog(&pool, "payment", payment_id).await,
            "VOID must return the obligation to the refundable backlog — this is the whole point"
        );
        assert_eq!(
            refund_status_of(&pool, "payment", payment_id)
                .await
                .as_deref(),
            Some("pending"),
            "…and the queue row must be OPEN again, or the money is invisible"
        );
        // The item row is KEPT (history: the customer WAS in a voided file), just flagged.
        let (items, live): (i64, i64) = sqlx::query_as(
            "SELECT count(*), count(*) FILTER (WHERE voided_at IS NULL) \
             FROM payment.refund_batch_items WHERE batch_id = $1",
        )
        .bind(batch_id)
        .fetch_one(&pool)
        .await
        .expect("item state");
        assert_eq!((items, live), (1, 0), "kept as history, but not live");
        assert_eq!(
            refund_audit_count(&pool, batch_id, AUDIT_REFUND_VOIDED).await,
            1
        );

        // …and it can be refunded again, into a NEW batch (proves the unique is PARTIAL: the voided
        // item row is still there and must not block the new one).
        let second = refund_batch_of(&[("payment", payment_id, customer, "1070.00")]);
        let second_id = insert_refund_batch(&pool, &second)
            .await
            .expect("a voided obligation is refundable again");
        assert_ne!(second_id, batch_id);
        assert!(!in_refund_backlog(&pool, "payment", payment_id).await);

        // A double-void is a typed 409 carrying the REFUND stream's own code, never a silent no-op.
        let err = void_refund_batch(&pool, batch_id, admin, "กดซ้ำ")
            .await
            .expect_err("already voided");
        assert!(
            matches!(&err, AppError::ConflictCode { code, .. } if *code == "REFUND_BATCH_ALREADY_VOIDED"),
            "got {err:?}"
        );
        assert_eq!(
            refund_audit_count(&pool, batch_id, AUDIT_REFUND_VOIDED).await,
            1,
            "the refused second void writes nothing"
        );

        cleanup_refund(&pool, &[booking_id]).await;
    }

    /// PER-ITEM VOID: exactly the named obligations go back in the queue, the rest of the batch stays
    /// settled, and it works on a `confirmed` batch — which is the whole reason it exists.
    ///
    /// SCB can accept a structurally valid file and still fail individual credit lines (a PromptPay
    /// proxy not linked to a receiving account is the everyday case), so the batch is honestly
    /// `confirmed` while a handful of customers never got their money. Voiding the WHOLE batch would
    /// un-settle everyone and is refused on a confirmed batch anyway. The composite key is exercised
    /// too: the released obligation is a LANE-B slip while a lane-A payment in the same file stays
    /// settled.
    #[tokio::test]
    async fn voiding_single_refund_items_releases_only_those_even_on_a_confirmed_batch() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let (booking_a, booking_b) = (Uuid::new_v4(), Uuid::new_v4());
        let (cust_a, cust_b) = (Uuid::new_v4(), Uuid::new_v4());
        let admin = Uuid::new_v4();
        let stays = seed_pending_refund(&pool, booking_a, cust_a, "300.00").await;
        let released = seed_duplicate_slip(&pool, booking_b, cust_b, "800.00").await;

        let batch = refund_batch_of(&[
            ("payment", stays, cust_a, "300.00"),
            ("slip", released, cust_b, "800.00"),
        ]);
        let batch_id = insert_refund_batch(&pool, &batch).await.expect("export");

        // The bank TOOK the file — the batch is confirmed and can no longer be whole-voided.
        set_refund_batch_status(&pool, batch_id, BatchStatus::Uploaded, None, admin)
            .await
            .expect("uploaded");
        set_refund_batch_status(&pool, batch_id, BatchStatus::Confirmed, None, admin)
            .await
            .expect("confirmed");
        let refused = void_refund_batch(&pool, batch_id, admin, "อยากยกเลิกทั้งไฟล์")
            .await
            .expect_err("a confirmed batch may never be whole-voided");
        assert!(
            matches!(&refused, AppError::ConflictCode { code, .. } if *code == "REFUND_BATCH_TERMINAL"),
            "got {refused:?}"
        );

        // …but the ONE failed credit line can be released.
        let target = [RefundSource {
            kind: RefundSourceKind::Slip,
            id: released,
        }];
        let detail = void_refund_batch_items(
            &pool,
            batch_id,
            &target,
            admin,
            "ธนาคารแจ้งว่าพร้อมเพย์ปลายทางไม่ผูกบัญชี",
        )
        .await
        .expect("the failed line goes back");
        assert_eq!(
            detail.batch.status, "confirmed",
            "the record of what the BANK did is untouched"
        );
        assert!(
            in_refund_backlog(&pool, "slip", released).await
                && refund_status_of(&pool, "slip", released).await.as_deref() == Some("pending"),
            "only the named obligation returns — and it returns fully"
        );
        assert!(
            !in_refund_backlog(&pool, "payment", stays).await
                && refund_status_of(&pool, "payment", stays).await.as_deref() == Some("processed"),
            "the customer who DID get their money stays settled"
        );

        // A second attempt is a typed 409, not a silent success (their page may be stale).
        let err = void_refund_batch_items(&pool, batch_id, &target, admin, "กดซ้ำ")
            .await
            .expect_err("already released");
        assert!(
            matches!(&err, AppError::ConflictCode { code, .. } if *code == "REFUND_ITEM_ALREADY_VOIDED"),
            "got {err:?}"
        );
        // An obligation from ANOTHER file is a 404, never a silent partial success — and naming the
        // lane matters: the same UUID could exist in the other table.
        let foreign = [RefundSource {
            kind: RefundSourceKind::Payment,
            id: released, // a real id, but it belongs to the SLIP lane
        }];
        assert!(matches!(
            void_refund_batch_items(&pool, batch_id, &foreign, admin, "ผิดไฟล์").await,
            Err(AppError::NotFound(_))
        ));
        assert_eq!(
            refund_audit_count(&pool, batch_id, AUDIT_REFUND_ITEMS_VOIDED).await,
            1,
            "only the successful release is logged"
        );

        cleanup_refund(&pool, &[booking_a, booking_b]).await;
    }

    /// The BANGKOK DAY WINDOW and the customer tick-list narrow the backlog the same way the payout's
    /// do — and both lanes honour both filters (lane A dates off `payments.updated_at`, lane B off
    /// `payment_slips.created_at`, because those are when each obligation actually arose).
    #[tokio::test]
    async fn the_refund_backlog_honours_the_customer_tick_list_and_the_day_window() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let (booking_a, booking_b) = (Uuid::new_v4(), Uuid::new_v4());
        let (cust_a, cust_b) = (Uuid::new_v4(), Uuid::new_v4());
        let a = seed_pending_refund(&pool, booking_a, cust_a, "50.00").await;
        let b = seed_duplicate_slip(&pool, booking_b, cust_b, "60.00").await;

        // Ticking ONE customer must not sweep the other in.
        let only_a = unpaid_refund_rows(
            &pool,
            &RefundSelection {
                customer_ids: Some(vec![cust_a]),
                ..Default::default()
            },
        )
        .await
        .expect("backlog");
        assert_eq!(only_a.len(), 1);
        assert_eq!(
            (only_a[0].source_kind.as_str(), only_a[0].source_id),
            ("payment", a)
        );

        // A window that ends YESTERDAY (Bangkok) excludes both — they became owed just now.
        let yesterday = crate::domain::scb_export::bangkok_today(Utc::now())
            .pred_opt()
            .expect("yesterday");
        let stale = unpaid_refund_rows(
            &pool,
            &RefundSelection {
                customer_ids: Some(vec![cust_a, cust_b]),
                from: None,
                to: Some(yesterday),
            },
        )
        .await
        .expect("backlog");
        assert!(
            stale.is_empty(),
            "a window ending yesterday cannot contain today's obligations: {stale:?}"
        );

        // …and a window that INCLUDES today contains both lanes.
        let today = crate::domain::scb_export::bangkok_today(Utc::now());
        let fresh = unpaid_refund_rows(
            &pool,
            &RefundSelection {
                customer_ids: Some(vec![cust_a, cust_b]),
                from: Some(today),
                to: Some(today),
            },
        )
        .await
        .expect("backlog");
        assert_eq!(fresh.len(), 2, "both lanes are inside today's window");
        assert!(fresh
            .iter()
            .any(|r| r.source_id == b && r.source_kind == "slip"));

        cleanup_refund(&pool, &[booking_a, booking_b]).await;
    }

    /// An APPLIED slip — the one that actually settled its payment — must NEVER appear in the refund
    /// backlog, and neither must a payment with no refund owed. The backlog predicate is the only
    /// thing standing between "a customer paid us" and "we send them their money back", so both
    /// halves of it are asserted directly.
    #[tokio::test]
    async fn a_settled_payment_and_an_applied_slip_are_never_refundable() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let customer = Uuid::new_v4();
        // A normal, fully-settled pre-pay with its APPLIED slip: nothing is owed on either lane.
        let payment = payment_of(
            prepay_idempotent(
                &pool,
                booking_id,
                customer,
                Some(Uuid::new_v4()),
                &terms_of("2000.00"),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );
        let unique = Uuid::new_v4().simple().to_string();
        let applied: Uuid = sqlx::query_scalar(
            "INSERT INTO payment.payment_slips \
                 (payment_id, booking_id, reference_id, trans_ref, amount, slip_key) \
             VALUES ($1, $2, $3, $4, 2140.00, $5) RETURNING id",
        )
        .bind(payment.id)
        .bind(booking_id)
        .bind(format!("ref-{unique}"))
        .bind(format!("txn-{unique}"))
        .bind(format!("slips/{unique}.jpg"))
        .fetch_one(&pool)
        .await
        .expect("the slip that settled the payment");

        assert!(!in_refund_backlog(&pool, "payment", payment.id).await);
        assert!(
            !in_refund_backlog(&pool, "slip", applied).await,
            "the slip that PAID us must never be queued as money to send back"
        );

        // A zero refund is not an obligation either — `refund_amount > 0` is what keeps a
        // fully-retained cancellation fee out of the file.
        sqlx::query(
            "UPDATE payment.payments SET refund_amount = 0, refund_status = 'pending' WHERE id = $1",
        )
        .bind(payment.id)
        .execute(&pool)
        .await
        .expect("zero refund");
        assert!(!in_refund_backlog(&pool, "payment", payment.id).await);

        cleanup_refund(&pool, &[booking_id]).await;
    }

    // ----- Stream ② ยอดที่โดนหักเข้าระบบ — the platform-cut sweep -----

    /// Settle ONE job end to end through the REAL money path: pre-pay the estimate, then reconcile it
    /// against the hours actually worked. Returns the payment id.
    ///
    /// Deliberately NOT a hand-written INSERT. The whole point of migration 0013 is that the pricing
    /// snapshot is written by the SAME statements that write the VAT split, so a test that inserted
    /// the columns itself would prove nothing about the settle paths and would keep passing if one of
    /// them stopped writing them.
    #[allow(clippy::too_many_arguments)]
    async fn settled_job(
        pool: &sqlx::PgPool,
        booking_id: Uuid,
        guard_id: Uuid,
        base_fee: &str,
        booked_hours: i32,
        guard_count: i32,
        tip: &str,
        commission_percent: &str,
        worked_seconds: i64,
    ) -> Uuid {
        settled_job_billed_over(
            pool,
            booking_id,
            guard_id,
            base_fee,
            booked_hours,
            guard_count,
            tip,
            tip,
            commission_percent,
            worked_seconds,
        )
        .await
    }

    /// The same walk, but the customer PRE-PAID for `prepaid_tip` and the job SETTLED at `tip` — the
    /// reconcile's `Extra` arm when `tip > prepaid_tip`: it writes the HIGHER `final_amount` and
    /// captures nothing ("a real gateway would capture the extra here").
    ///
    /// This is the row shape B1 is about, produced by the REAL settle path rather than by an UPDATE,
    /// so a change that stopped writing `final_amount` above `amount` would break these tests rather
    /// than quietly making them vacuous.
    #[allow(clippy::too_many_arguments)]
    async fn settled_job_billed_over(
        pool: &sqlx::PgPool,
        booking_id: Uuid,
        guard_id: Uuid,
        base_fee: &str,
        booked_hours: i32,
        guard_count: i32,
        prepaid_tip: &str,
        tip: &str,
        commission_percent: &str,
        worked_seconds: i64,
    ) -> Uuid {
        let terms = ChargeTerms::new(
            PricingInputs {
                base_fee: dec(base_fee),
                booked_hours,
                guard_count,
                tip: dec(prepaid_tip),
            },
            dec(commission_percent),
            Decimal::ZERO,
        );
        let payment = payment_of(
            prepay_idempotent(
                pool,
                booking_id,
                Uuid::new_v4(),
                Some(guard_id),
                &terms,
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );
        reconcile_on_completion(
            pool,
            Uuid::new_v4(),
            topics::BOOKING_COMPLETED,
            booking_id,
            dec(base_fee),
            booked_hours,
            guard_count,
            dec(tip),
            Some(worked_seconds),
            Uuid::new_v4(),
        )
        .await
        .expect("reconcile");
        payment.id
    }

    /// Pre-pay a job and then CANCEL it, through the real cancellation settle: the customer keeps
    /// `min(fee, paid)` retained against them and the rest is refunded. Returns the payment id.
    ///
    /// A cancelled job is the OTHER shape of the sweep, and it exercises a different half of the
    /// code: no guard was paid, no pricing snapshot is needed, and the only thing kept is the fee —
    /// net of the VAT inside it, which stays the Revenue Department's.
    async fn cancelled_job(
        pool: &sqlx::PgPool,
        booking_id: Uuid,
        base_fee: &str,
        booked_hours: i32,
        cancellation_fee: &str,
    ) -> Uuid {
        let terms = ChargeTerms::new(
            PricingInputs {
                base_fee: dec(base_fee),
                booked_hours,
                guard_count: 1,
                tip: Decimal::ZERO,
            },
            Decimal::ZERO,
            dec(cancellation_fee),
        );
        let payment = payment_of(
            prepay_idempotent(
                pool,
                booking_id,
                Uuid::new_v4(),
                Some(Uuid::new_v4()),
                &terms,
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay"),
        );
        refund_on_cancellation(
            pool,
            Uuid::new_v4(),
            topics::BOOKING_CANCELLED,
            booking_id,
            // A genuine CUSTOMER cancellation of a still-active booking: the one case that retains a
            // fee, and therefore the one that leaves anything for the sweep.
            true,
            Uuid::new_v4(),
        )
        .await
        .expect("cancellation settle");
        payment.id
    }

    /// The unswept backlog rows for these payment ids, in the order the sweep would take them.
    async fn sweep_backlog(pool: &sqlx::PgPool, payment_ids: &[Uuid]) -> Vec<SettledPaymentRow> {
        unswept_deduction_rows(pool, &DeductionSelection::default())
            .await
            .expect("backlog")
            .into_iter()
            .filter(|r| payment_ids.contains(&r.payment_id))
            .collect()
    }

    /// Price a backlog row the way `api::deductions` does, and turn it into the ledger item the sweep
    /// writes. `None` = the job could not be priced and must be EXCLUDED (never swept as zero).
    fn sweep_item(row: &SettledPaymentRow) -> Option<crate::models::NewDeductionItem> {
        let s = crate::domain::settlement::split(&crate::domain::settlement::SettledPayment {
            amount: row.amount,
            overpaid: row.overpaid_amount,
            final_amount: row.final_amount,
            refund_amount: row.refund_amount,
            subtotal: row.subtotal,
            vat_amount: row.vat_amount,
            cancelled: row.cancelled,
            base_fee: row.base_fee,
            booked_hours: row.booked_hours,
            guard_count: row.guard_count,
            tip: row.tip,
            commission_amount: row.commission_amount,
            actual_hours: row.actual_hours,
            wht_withheld: Decimal::ZERO,
        })
        .ok()?;
        Some(crate::models::NewDeductionItem {
            payment_id: row.payment_id,
            booking_id: row.booking_id,
            commission: s.commission,
            cancellation_fee: s.cancellation_fee,
            tip: s.tip,
            unpaid_guard_share: s.unpaid_guard_share,
            rounding_adjustment: s.rounding_adjustment,
            uncollected: s.uncollected,
            amount: s.platform_cut(),
        })
    }

    /// A sweep batch carrying the given ledger items, with a fresh reference (the tests run in
    /// parallel inside the same Bangkok second, which is exactly what the unique index is for).
    fn sweep_batch_of(
        items: Vec<crate::models::NewDeductionItem>,
    ) -> crate::models::NewDeductionBatch {
        let batch_ref = unique_batch_ref();
        let total: Decimal = items.iter().map(|i| i.amount).sum();
        crate::models::NewDeductionBatch {
            file_ref: format!("{batch_ref}OAT"),
            system_ref: "PGUARD-DEDUCT".to_string(),
            batch_ref,
            value_date: chrono::NaiveDate::from_ymd_opt(2026, 9, 1).expect("valid date"),
            total_amount: total,
            // A REAL SCB account (it passes the §14 check digit).
            credit_account: "4051234567".to_string(),
            file_text:
                "HEADER|010926120000OAT|PGUARD-DEDUCT\r\nBCHDET|010926120000|OAT\r\n\
                        TXNDET|DD0109261200000001|4051234567||014|0111|1.00||OUR\r\nTRAILR|1|1|1.00"
                    .to_string(),
            created_by: Some(Uuid::new_v4()),
            items,
        }
    }

    /// Remove everything a sweep test wrote for these bookings.
    async fn cleanup_deduction(pool: &sqlx::PgPool, booking_ids: &[Uuid]) {
        let batch_ids: Vec<Uuid> = sqlx::query_scalar(
            "SELECT DISTINCT batch_id FROM payment.deduction_batch_items WHERE booking_id = ANY($1)",
        )
        .bind(booking_ids)
        .fetch_all(pool)
        .await
        .unwrap_or_default();
        let payout_batches: Vec<Uuid> = sqlx::query_scalar(
            "SELECT DISTINCT batch_id FROM payment.payout_batch_items WHERE booking_id = ANY($1)",
        )
        .bind(booking_ids)
        .fetch_all(pool)
        .await
        .unwrap_or_default();
        let all: Vec<Uuid> = batch_ids.iter().chain(&payout_batches).copied().collect();
        let _ = sqlx::query("DELETE FROM payment.money_audit WHERE target_id = ANY($1)")
            .bind(&all)
            .execute(pool)
            .await;
        // The SHARED reservation (migration 0012) is polymorphic, so it has no FK to cascade on.
        let _ = sqlx::query("DELETE FROM payment.scb_file_refs WHERE batch_id = ANY($1)")
            .bind(&all)
            .execute(pool)
            .await;
        let _ = sqlx::query("DELETE FROM payment.deduction_batches WHERE id = ANY($1)")
            .bind(&batch_ids)
            .execute(pool)
            .await;
        let _ = sqlx::query("DELETE FROM payment.payout_batches WHERE id = ANY($1)")
            .bind(&payout_batches)
            .execute(pool)
            .await;
        let _ = sqlx::query("DELETE FROM payment.payout_batch_items WHERE booking_id = ANY($1)")
            .bind(booking_ids)
            .execute(pool)
            .await;
        let _ = sqlx::query(
            "DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = ANY($1)",
        )
        .bind(
            booking_ids
                .iter()
                .map(|b| b.to_string())
                .collect::<Vec<_>>(),
        )
        .execute(pool)
        .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = ANY($1)")
            .bind(booking_ids)
            .execute(pool)
            .await;
    }

    /// THE DOUBLE-SWEEP GUARD: a swept job leaves the backlog and a second export finds nothing.
    ///
    /// The platform cut has no queue column of its own — the LEDGER ROW is the state — so this one
    /// partial unique is the whole mechanism, and it is the only thing standing between one sweep and
    /// transferring the same money into the revenue account twice. DATABASE_URL-gated.
    #[tokio::test]
    async fn the_sweep_marks_the_jobs_swept_and_a_second_export_sweeps_nothing() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let jobs: Vec<(Uuid, Uuid)> = (0..2).map(|_| (Uuid::new_v4(), Uuid::new_v4())).collect();
        let mut payment_ids = Vec::new();
        for (booking_id, guard_id) in &jobs {
            // 500 ฿/h × 4h × 1 guard, no tip, 10% commission, worked the full 4h → a ฿200 cut each.
            payment_ids.push(
                settled_job(
                    &pool,
                    *booking_id,
                    *guard_id,
                    "500",
                    4,
                    1,
                    "0",
                    "10",
                    4 * 3600,
                )
                .await,
            );
        }
        let booking_ids: Vec<Uuid> = jobs.iter().map(|(b, _)| *b).collect();

        let backlog = sweep_backlog(&pool, &payment_ids).await;
        assert_eq!(backlog.len(), 2, "both settled jobs are sweepable");
        let items: Vec<_> = backlog.iter().filter_map(sweep_item).collect();
        assert_eq!(items.len(), 2, "both priced — the snapshot is complete");
        assert_eq!(items[0].commission, dec("200.00"));
        assert_eq!(
            items[0].amount,
            dec("200.00"),
            "the cut IS the commission here"
        );

        let batch = sweep_batch_of(items);
        assert_eq!(batch.total_amount, dec("400.00"));
        let batch_id = insert_deduction_batch(&pool, &batch)
            .await
            .expect("first sweep");

        // The jobs are gone from the backlog…
        assert!(
            sweep_backlog(&pool, &payment_ids).await.is_empty(),
            "a swept job must not be offered again"
        );
        // …and the batch is a complete, re-downloadable record with one credit line and two ledger
        // rows (the OAT shape: ONE recipient, many jobs).
        let detail = get_deduction_batch(&pool, batch_id).await.expect("detail");
        assert_eq!(detail.batch.status, "generated");
        assert_eq!(
            detail.batch.recipient_count, 1,
            "an OAT batch credits ONE account"
        );
        assert_eq!(detail.batch.job_count, 2);
        assert_eq!(detail.items.len(), 2);
        assert!(detail.batch.has_file);
        assert_eq!(
            get_deduction_batch_file(&pool, batch_id)
                .await
                .expect("stored file")
                .file_text,
            batch.file_text,
            "byte-for-byte — never regenerated"
        );
        // Every money action is audited.
        assert_eq!(
            sqlx::query_scalar::<_, i64>(
                "SELECT count(*) FROM payment.money_audit WHERE target_id = $1 AND action = $2"
            )
            .bind(batch_id)
            .bind(AUDIT_DEDUCTION_EXPORTED)
            .fetch_one(&pool)
            .await
            .expect("audit"),
            1
        );

        // A SECOND export of the same jobs is refused by the partial unique — the guard against
        // transferring the same cut twice — and the whole transaction rolls back.
        let second = insert_deduction_batch(
            &pool,
            &sweep_batch_of(vec![crate::models::NewDeductionItem {
                payment_id: payment_ids[0],
                booking_id: booking_ids[0],
                commission: dec("200.00"),
                cancellation_fee: Decimal::ZERO,
                tip: Decimal::ZERO,
                unpaid_guard_share: Decimal::ZERO,
                rounding_adjustment: Decimal::ZERO,
                uncollected: Decimal::ZERO,
                amount: dec("200.00"),
            }]),
        )
        .await;
        assert!(
            matches!(second, Err(AppError::ConflictCode { code, .. }) if code == "DEDUCTION_ALREADY_SWEPT"),
            "a re-sweep must be a typed 409, got {second:?}"
        );
        // The losing transaction rolled back ENTIRELY: no second header, no second reference
        // reservation, and the ledger row still points at the FIRST batch. Counted through the items,
        // because the table is shared with every other test running in parallel.
        assert_eq!(
            sqlx::query_scalar::<_, i64>(
                "SELECT count(DISTINCT batch_id) FROM payment.deduction_batch_items \
                  WHERE payment_id = ANY($1)"
            )
            .bind(&payment_ids)
            .fetch_one(&pool)
            .await
            .expect("count"),
            1,
            "these jobs belong to exactly ONE batch — the re-sweep wrote nothing"
        );

        cleanup_deduction(&pool, &booking_ids).await;
    }

    /// VOID releases every job in the sweep, and they can then be swept again — the escape hatch from
    /// the one-way door. Without it a lost download left the cut recorded as collected with no money
    /// moved and no way back short of a hand-written UPDATE. DATABASE_URL-gated.
    #[tokio::test]
    async fn voiding_a_sweep_returns_the_jobs_and_they_can_be_swept_again() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let booking_id = Uuid::new_v4();
        let payment_id = settled_job(
            &pool,
            booking_id,
            Uuid::new_v4(),
            "500",
            4,
            1,
            "0",
            "10",
            4 * 3600,
        )
        .await;
        let items: Vec<_> = sweep_backlog(&pool, &[payment_id])
            .await
            .iter()
            .filter_map(sweep_item)
            .collect();
        let batch_id = insert_deduction_batch(&pool, &sweep_batch_of(items))
            .await
            .expect("sweep");
        assert!(sweep_backlog(&pool, &[payment_id]).await.is_empty());

        let actor = Uuid::new_v4();
        let voided = void_deduction_batch(&pool, batch_id, actor, "ธนาคารตีกลับ")
            .await
            .expect("void");
        assert_eq!(voided.status, "voided");
        assert_eq!(voided.void_reason.as_deref(), Some("ธนาคารตีกลับ"));

        // BACK IN THE BACKLOG — and swept again, into a NEW batch, which is the whole point.
        let back = sweep_backlog(&pool, &[payment_id]).await;
        assert_eq!(back.len(), 1, "a voided job is sweepable again");
        let again = insert_deduction_batch(
            &pool,
            &sweep_batch_of(back.iter().filter_map(sweep_item).collect()),
        )
        .await
        .expect("re-sweep after a void");
        assert_ne!(again, batch_id);

        // A SECOND void of the same batch is a typed 409, never a silent success.
        let twice = void_deduction_batch(&pool, batch_id, actor, "อีกครั้ง").await;
        assert!(
            matches!(twice, Err(AppError::ConflictCode { code, .. }) if code == "DEDUCTION_BATCH_ALREADY_VOIDED"),
            "got {twice:?}"
        );
        // …and a CONFIRMED batch cannot be voided at all: the money moved.
        set_deduction_batch_status(&pool, again, BatchStatus::Uploaded, None, actor)
            .await
            .expect("generated → uploaded");
        set_deduction_batch_status(&pool, again, BatchStatus::Confirmed, None, actor)
            .await
            .expect("uploaded → confirmed");
        let after = void_deduction_batch(&pool, again, actor, "ไม่ควรได้").await;
        assert!(
            matches!(after, Err(AppError::ConflictCode { code, .. }) if code == "DEDUCTION_BATCH_TERMINAL"),
            "a confirmed sweep is terminal, got {after:?}"
        );

        cleanup_deduction(&pool, &[booking_id]).await;
    }

    /// **B3 — A PER-ITEM VOID IS REFUSED ON A CONFIRMED SWEEP, AND ALLOWED BEFORE THAT.**
    ///
    /// The two halves are one test on purpose: the rule is not "sweeps cannot be corrected", it is
    /// "a sweep the bank already executed cannot be corrected THIS WAY". An `OAT` file carries ONE
    /// credit line for the whole batch, so `confirmed` means the entire summed amount moved into the
    /// revenue account — releasing a job would put its cut back in the backlog and the next sweep
    /// would move it a SECOND time. (Streams ① and ③ carry one line per recipient and DO allow it;
    /// their tests assert the opposite, deliberately.) DATABASE_URL-gated.
    #[tokio::test]
    async fn a_confirmed_sweep_refuses_a_per_item_void_but_an_uploaded_one_allows_it() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let jobs: Vec<(Uuid, Uuid)> = (0..3).map(|_| (Uuid::new_v4(), Uuid::new_v4())).collect();
        let mut payment_ids = Vec::new();
        for (booking_id, guard_id) in &jobs {
            payment_ids.push(
                settled_job(
                    &pool,
                    *booking_id,
                    *guard_id,
                    "500",
                    4,
                    1,
                    "0",
                    "10",
                    4 * 3600,
                )
                .await,
            );
        }
        let booking_ids: Vec<Uuid> = jobs.iter().map(|(b, _)| *b).collect();
        let items: Vec<_> = sweep_backlog(&pool, &payment_ids)
            .await
            .iter()
            .filter_map(sweep_item)
            .collect();
        let batch_id = insert_deduction_batch(&pool, &sweep_batch_of(items))
            .await
            .expect("sweep");

        let actor = Uuid::new_v4();
        set_deduction_batch_status(&pool, batch_id, BatchStatus::Uploaded, None, actor)
            .await
            .expect("uploaded");

        // ── BEFORE the bank confirms: releasing ONE job is the escape hatch and still works. The
        //    batch stays `uploaded` — the status describes the FILE, this corrects which JOBS it is
        //    considered to have collected.
        let detail = void_deduction_batch_items(
            &pool,
            batch_id,
            &payment_ids[..1],
            actor,
            "งานนี้ไม่ควรถูกหักเข้าระบบ",
        )
        .await
        .expect("per-item void before the bank confirms");
        assert_eq!(
            detail.batch.status, "uploaded",
            "the batch itself is untouched"
        );
        assert_eq!(
            detail
                .items
                .iter()
                .filter(|i| i.voided_at.is_some())
                .count(),
            1
        );
        let back = sweep_backlog(&pool, &payment_ids).await;
        assert_eq!(back.len(), 1, "ONLY the named job came back");
        assert_eq!(back[0].payment_id, payment_ids[0]);

        // Releasing it twice is a typed 409, and a job from ANOTHER file is a 404 — an admin acting
        // on the wrong batch must not silently release a subset of a different one.
        let twice =
            void_deduction_batch_items(&pool, batch_id, &payment_ids[..1], actor, "อีกครั้ง").await;
        assert!(
            matches!(twice, Err(AppError::ConflictCode { code, .. }) if code == "DEDUCTION_ITEM_ALREADY_VOIDED"),
            "got {twice:?}"
        );
        let stranger =
            void_deduction_batch_items(&pool, batch_id, &[Uuid::new_v4()], actor, "ไม่มีในไฟล์").await;
        assert!(
            matches!(stranger, Err(AppError::NotFound(_))),
            "got {stranger:?}"
        );

        // ── AFTER the bank confirms: the whole summed amount moved as ONE credit, so no job may be
        //    released. This is the double-movement guard.
        set_deduction_batch_status(&pool, batch_id, BatchStatus::Confirmed, None, actor)
            .await
            .expect("confirmed");
        let refused =
            void_deduction_batch_items(&pool, batch_id, &payment_ids[1..2], actor, "ขอดึงกลับ").await;
        let Err(AppError::ConflictCode { code, message }) = refused else {
            panic!("a confirmed sweep must refuse a per-item void with a typed 409: {refused:?}");
        };
        assert_eq!(code, "DEDUCTION_BATCH_CONFIRMED");
        // The Thai copy has to say WHY and WHAT TO DO — "ยกเลิกทั้งไฟล์" or an accounting adjustment.
        assert!(
            message.contains("ยกเลิกทั้งไฟล์") && message.contains("ปรับปรุงทางบัญชี"),
            "the error must name both remedies: {message}"
        );
        // …and it changed NOTHING: the second job is still swept, and the released one is still the
        // only thing back in the backlog.
        let after = sweep_backlog(&pool, &payment_ids).await;
        assert_eq!(after.len(), 1, "the refusal released nothing");
        assert_eq!(after[0].payment_id, payment_ids[0]);

        cleanup_deduction(&pool, &booking_ids).await;
    }

    /// A job whose pricing SNAPSHOT is incomplete is EXCLUDED and never marked swept — the behaviour
    /// that keeps the sweep from silently under-transferring.
    ///
    /// Simulated by NULLing `commission_amount` on a settled row, which is exactly the shape every
    /// charge taken before migration 0013 has. The job stays in the backlog run after run (visible,
    /// answerable) instead of contributing a zero nobody could ever notice. DATABASE_URL-gated.
    #[tokio::test]
    async fn a_job_with_an_incomplete_snapshot_is_excluded_and_never_marked_swept() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let (good_booking, stale_booking) = (Uuid::new_v4(), Uuid::new_v4());
        let good = settled_job(
            &pool,
            good_booking,
            Uuid::new_v4(),
            "500",
            4,
            1,
            "0",
            "10",
            4 * 3600,
        )
        .await;
        let stale = settled_job(
            &pool,
            stale_booking,
            Uuid::new_v4(),
            "500",
            4,
            1,
            "0",
            "10",
            4 * 3600,
        )
        .await;
        // Make the second row look like a pre-migration-0013 charge.
        sqlx::query("UPDATE payment.payments SET commission_amount = NULL WHERE id = $1")
            .bind(stale)
            .execute(&pool)
            .await
            .expect("clear the snapshot");

        // BOTH are returned by the backlog — the SQL's job is to say which rows are in the run, and
        // the pure split's job is to say which of them can be priced.
        let backlog = sweep_backlog(&pool, &[good, stale]).await;
        assert_eq!(backlog.len(), 2);
        let stale_row = backlog
            .iter()
            .find(|r| r.payment_id == stale)
            .expect("still listed");
        assert!(
            sweep_item(stale_row).is_none(),
            "an incomplete snapshot must not price — a ฿0 cut would look identical and be wrong"
        );

        // Sweep what CAN be priced.
        let items: Vec<_> = backlog.iter().filter_map(sweep_item).collect();
        assert_eq!(items.len(), 1);
        insert_deduction_batch(&pool, &sweep_batch_of(items))
            .await
            .expect("sweep the priceable job");

        // The excluded job is STILL in the backlog — never marked swept, still visible next run.
        let after = sweep_backlog(&pool, &[good, stale]).await;
        assert_eq!(after.len(), 1);
        assert_eq!(after[0].payment_id, stale, "the unpriceable job stays");

        cleanup_deduction(&pool, &[good_booking, stale_booking]).await;
    }

    /// **B2 — THE PAYOUT AND THE SWEEP PRICE ONE JOB OFF ONE ROW.**
    ///
    /// The guard's gross and the platform's commission are two halves of the SAME number, and until
    /// now they came from two different places: the payout multiplied booking's LIVE `base_fee`
    /// (fetched over HTTP) while the sweep used `payments.base_fee` (the migration-0013 snapshot). A
    /// correction or re-price of the booking after completion moved one and not the other, and the
    /// difference landed silently in — or leaked out of — the cut with nothing able to notice.
    ///
    /// Both sides are read here out of the DATABASE, through the same two production queries, and
    /// asserted to reconstruct the gross exactly. DATABASE_URL-gated.
    #[tokio::test]
    async fn the_payout_and_the_sweep_price_one_job_from_the_same_stored_row() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let (booking_id, guard_id) = (Uuid::new_v4(), Uuid::new_v4());
        // 437.50 ฿/h × 4h booked, 12.5% commission, 3h15m worked — deliberately awkward, so a
        // rounding difference between the two sides would show up rather than cancel.
        let payment_id = settled_job(
            &pool,
            booking_id,
            guard_id,
            "437.50",
            4,
            1,
            "0",
            "12.5",
            3 * 3600 + 15 * 60,
        )
        .await;

        // ── the PAYOUT side, straight out of `unpaid_payout_rows`.
        let payout_row = unpaid_payout_rows(&pool, &PayoutSelection::default())
            .await
            .expect("payout backlog")
            .into_iter()
            .find(|r| r.booking_id == booking_id)
            .expect("the settled job is payable");
        // The snapshot columns are SELECTED — this is the query change B2 turns on, and without it
        // the aggregation silently falls back to booking's live row for every job.
        assert_eq!(
            payout_row.base_fee,
            Some(dec("437.50")),
            "the pay basis comes from payment's own snapshot, not an HTTP read"
        );
        assert_eq!(payout_row.booked_hours, Some(4));
        let hours = payout_row.actual_hours.expect("reconciled");
        let paid = crate::domain::payout::compute_payout(
            payout_row.base_fee.expect("snapshot"),
            hours,
            payout_row.commission_percent,
            dec("3"),
        );

        // ── the SWEEP side, straight out of `unswept_deduction_rows`.
        let sweep_row = sweep_backlog(&pool, &[payment_id])
            .await
            .into_iter()
            .next()
            .expect("the settled job is sweepable");
        assert_eq!(
            sweep_row.base_fee, payout_row.base_fee,
            "both streams read the SAME column of the SAME row"
        );
        assert_eq!(sweep_row.actual_hours, Some(hours));
        let split = crate::domain::settlement::split(&crate::domain::settlement::SettledPayment {
            amount: sweep_row.amount,
            overpaid: sweep_row.overpaid_amount,
            final_amount: sweep_row.final_amount,
            refund_amount: sweep_row.refund_amount,
            subtotal: sweep_row.subtotal,
            vat_amount: sweep_row.vat_amount,
            cancelled: sweep_row.cancelled,
            base_fee: sweep_row.base_fee,
            booked_hours: sweep_row.booked_hours,
            guard_count: sweep_row.guard_count,
            tip: sweep_row.tip,
            commission_amount: sweep_row.commission_amount,
            actual_hours: sweep_row.actual_hours,
            wht_withheld: paid.wht,
        })
        .expect("prices");

        // THE AGREEMENT: what the guard is paid plus what the platform keeps out of his pay is
        // exactly the gross, with nothing over and nothing missing.
        let gross =
            crate::domain::settlement::guard_gross(payout_row.base_fee.expect("snapshot"), hours);
        assert_eq!(
            paid.income + split.commission,
            gross,
            "payout income {} + swept commission {} != gross {gross}",
            paid.income,
            split.commission
        );
        assert_eq!(split.guard_income, paid.income, "one income, one job");
        assert_eq!(split.wht, paid.wht);
        assert_eq!(split.guard_transfer, paid.transfer);
        assert!(split.reconciles(), "and the job still balances");

        cleanup_deduction(&pool, &[booking_id]).await;
    }

    /// **B1 — THE SWEEP MAY NOT TRANSFER BAHT THE CUSTOMER NEVER PAID.**
    ///
    /// Settled through the REAL `Extra` arm (pre-pay with no tip, complete with one): the reconcile
    /// writes a `final_amount` above what was collected and captures nothing. The sweep must deduct
    /// that shortfall, record it in the ledger, and hand the file the smaller figure — otherwise it
    /// draws down an account that also holds the Revenue Department's VAT and the guards' unpaid
    /// income. DATABASE_URL-gated.
    #[tokio::test]
    async fn a_sweep_never_transfers_the_part_of_a_bill_that_was_never_collected() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let (booking_id, guard_id) = (Uuid::new_v4(), Uuid::new_v4());
        // Pre-paid 500×4h with NO tip (2140.00 collected); settled with a 300 tip → 2300 + 161 VAT =
        // 2461.00 billed, so 321.00 was billed and never collected.
        let payment_id = settled_job_billed_over(
            &pool,
            booking_id,
            guard_id,
            "500",
            4,
            1,
            "0",
            "300",
            "10",
            4 * 3600,
        )
        .await;
        let row = sweep_backlog(&pool, &[payment_id])
            .await
            .into_iter()
            .next()
            .expect("sweepable");
        assert_eq!(row.amount, dec("2140.00"), "what was actually transferred");
        assert_eq!(row.final_amount, Some(dec("2461.00")), "what was billed");
        assert!(row.refund_amount.is_none(), "the Extra arm refunds nothing");

        let item = sweep_item(&row).expect("prices");
        assert_eq!(item.commission, dec("200.00"));
        assert_eq!(item.tip, dec("300.00"));
        assert_eq!(
            item.uncollected,
            dec("321.00"),
            "the 300 tip and the 21 VAT on it — billed, never collected"
        );
        assert_eq!(
            item.amount,
            dec("179.00"),
            "500 earned − 321 never collected: what the file may actually move"
        );

        // The INSERT itself is half the assertion: migration 0014's CHECK refuses any row whose
        // `amount` is not its five components minus `uncollected`, so a future writer that forgot to
        // pass the deduction through would fail here rather than over-sweep.
        let batch_id = insert_deduction_batch(&pool, &sweep_batch_of(vec![item]))
            .await
            .expect("sweep");
        let stored: (Decimal, Decimal, Decimal) = sqlx::query_as(
            "SELECT uncollected, amount, tip FROM payment.deduction_batch_items \
              WHERE batch_id = $1 AND payment_id = $2",
        )
        .bind(batch_id)
        .bind(payment_id)
        .fetch_one(&pool)
        .await
        .expect("ledger row");
        assert_eq!(stored, (dec("321.00"), dec("179.00"), dec("300.00")));

        // …and the whole job still balances against the money that ACTUALLY arrived: 2140.00 paid =
        // 1800.00 to the guard + 161.00 VAT + 179.00 swept. (The guard's 1800 leaves via stream ③;
        // the split reports it as still-owed while no payout file has withheld anything yet.)
        let split = crate::domain::settlement::split(&crate::domain::settlement::SettledPayment {
            amount: row.amount,
            overpaid: row.overpaid_amount,
            final_amount: row.final_amount,
            refund_amount: row.refund_amount,
            subtotal: row.subtotal,
            vat_amount: row.vat_amount,
            cancelled: row.cancelled,
            base_fee: row.base_fee,
            booked_hours: row.booked_hours,
            guard_count: row.guard_count,
            tip: row.tip,
            commission_amount: row.commission_amount,
            actual_hours: row.actual_hours,
            wht_withheld: Decimal::ZERO,
        })
        .expect("prices");
        assert_eq!(
            split.guard_transfer + split.vat + split.platform_cut(),
            dec("2140.00")
        );

        cleanup_deduction(&pool, &[booking_id]).await;
    }

    /// The two TAX REPORTS return the right rows — and **B7**: the ภ.ง.ด. payee list counts a batch
    /// only when the money ACTUALLY MOVED, which excludes a `rejected` batch as well as a `voided`
    /// one.
    ///
    /// `rejected` is the bug: the bank REFUSED the file, so no transfer happened and no tax was
    /// withheld from anyone in it — yet the old `b.status <> 'voided'` counted every one, producing a
    /// return that declared withholding that never occurred. It is a reachable, ordinary state (the
    /// transition table has `uploaded → rejected` and deliberately leaves `rejected` non-terminal), so
    /// it is asserted here alongside the voided case rather than trusted to be rare.
    /// DATABASE_URL-gated.
    #[tokio::test]
    async fn the_wht_return_counts_only_batches_whose_money_actually_moved() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let (paid_booking, voided_booking, rejected_booking) =
            (Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
        let (paid_guard, voided_guard, rejected_guard) =
            (Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
        let paid_payment = settled_job(
            &pool,
            paid_booking,
            paid_guard,
            "500",
            4,
            1,
            "0",
            "10",
            4 * 3600,
        )
        .await;
        settled_job(
            &pool,
            voided_booking,
            voided_guard,
            "500",
            4,
            1,
            "0",
            "10",
            4 * 3600,
        )
        .await;
        settled_job(
            &pool,
            rejected_booking,
            rejected_guard,
            "500",
            4,
            1,
            "0",
            "10",
            4 * 3600,
        )
        .await;

        // ── ภ.พ.30: the settled job appears with its SETTLED split (2000 + 140).
        let now = Utc::now();
        let register = vat_register(
            &pool,
            now - chrono::Duration::days(1),
            now + chrono::Duration::days(1),
        )
        .await
        .expect("vat register");
        let row = register
            .iter()
            .find(|r| r.payment_id == paid_payment)
            .expect("the settled payment is on the VAT register");
        assert_eq!(row.subtotal, dec("2000.00"));
        assert_eq!(row.vat, dec("140.00"));
        assert_eq!(
            row.total,
            dec("2140.00"),
            "subtotal + vat is the tax-invoice total"
        );

        // ── ภ.ง.ด.3/53: THREE payout batches with the same value date — one left `generated` (the
        //    withholding was certified and the file is on its way), one VOIDED, and one the bank
        //    REJECTED. Only the first moved money, so only the first may be on the return.
        let value_date = chrono::NaiveDate::from_ymd_opt(2026, 9, 15).expect("valid date");
        let actor = Uuid::new_v4();
        let mut live = payout_batch_of(&[(paid_booking, paid_guard)]);
        live.value_date = value_date;
        let live_id = insert_payout_batch(&pool, &live).await.expect("live batch");
        let mut dead = payout_batch_of(&[(voided_booking, voided_guard)]);
        dead.value_date = value_date;
        let dead_id = insert_payout_batch(&pool, &dead)
            .await
            .expect("second batch");
        void_payout_batch(&pool, dead_id, actor, "ธนาคารตีกลับ")
            .await
            .expect("void");
        // The B7 case, walked through the REAL lifecycle: uploaded → rejected. The items are NOT
        // voided — `rejected` is not terminal and the admin may not have got round to voiding it —
        // which is exactly why the item-level `voided_at` predicate could not catch this on its own.
        let mut refused = payout_batch_of(&[(rejected_booking, rejected_guard)]);
        refused.value_date = value_date;
        let refused_id = insert_payout_batch(&pool, &refused)
            .await
            .expect("third batch");
        set_payout_batch_status(&pool, refused_id, BatchStatus::Uploaded, None, actor)
            .await
            .expect("uploaded");
        set_payout_batch_status(
            &pool,
            refused_id,
            BatchStatus::Rejected,
            Some("รูปแบบไฟล์ไม่ถูกต้อง"),
            actor,
        )
        .await
        .expect("rejected");

        let payees = wht_payees(
            &pool,
            chrono::NaiveDate::from_ymd_opt(2026, 9, 1).expect("valid date"),
            chrono::NaiveDate::from_ymd_opt(2026, 10, 1).expect("valid date"),
        )
        .await
        .expect("payee list");
        let listed = payees
            .iter()
            .find(|p| p.guard_id == paid_guard)
            .expect("the guard we actually paid is on the filing");
        assert_eq!(
            listed.wht,
            dec("10.80"),
            "the withheld tax, read back at last"
        );
        assert_eq!(listed.income, dec("360.00"));
        assert_eq!(listed.job_count, 1);
        assert!(
            !payees.iter().any(|p| p.guard_id == voided_guard),
            "a VOIDED batch withheld nothing — it must never reach a tax return"
        );
        assert!(
            !payees.iter().any(|p| p.guard_id == rejected_guard),
            "a REJECTED batch never left the bank's door, so no tax was withheld from anyone in it \
             — counting it would DECLARE withholding that did not occur (B7)"
        );
        // …and a month with no payouts is an empty list, not last month's.
        let empty = wht_payees(
            &pool,
            chrono::NaiveDate::from_ymd_opt(2026, 10, 1).expect("valid date"),
            chrono::NaiveDate::from_ymd_opt(2026, 11, 1).expect("valid date"),
        )
        .await
        .expect("next month");
        assert!(!empty.iter().any(|p| p.guard_id == paid_guard));

        let _ = live_id;
        cleanup_deduction(&pool, &[paid_booking, voided_booking, rejected_booking]).await;
    }

    /// **THE CROSS-STREAM RECONCILIATION** — the point of the whole feature.
    ///
    /// For a set of jobs, what the CUSTOMER PAID must equal, to the satang:
    /// ```text
    ///     guard transfers  (stream ③, payout_batch_items.transfer_amount)
    ///   + refunds returned (payments.refund_amount)
    ///   + the swept cut    (stream ②, deduction_batch_items.amount)
    ///   + VAT              (payments.vat_amount — remitted via ภ.พ.30)
    ///   + WHT              (payout_batch_items.wht — remitted via ภ.ง.ด.3/53)
    /// ```
    /// Every term is SUMMED OUT OF THE DATABASE rather than out of the structs that wrote it, so this
    /// measures what was actually persisted by three independent write paths. The jobs deliberately
    /// span the interesting shapes: a plain full-hours job, a PRORATED one (which refunds), a
    /// MULTI-GUARD one (whose unpaid share is cut), one with a TIP (likewise — the two deferred bugs
    /// included, because they are real money today), and one BILLED OVER what was collected (the
    /// reconcile's `Extra` arm — B1: if the sweep took the billed cut rather than the collected one,
    /// this equation is the thing that stops balancing). DATABASE_URL-gated.
    #[tokio::test]
    async fn the_three_streams_reconcile_to_the_satang() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        // (base_fee, booked_hours, guard_count, PRE-PAID tip, settled tip, commission %, worked secs)
        let shapes: [(&str, i32, i32, &str, &str, &str, i64); 5] = [
            ("500", 4, 1, "0", "0", "10", 4 * 3600),            // plain
            ("500", 4, 1, "0", "0", "10", 2 * 3600),            // prorated → refunds
            ("500", 4, 3, "0", "0", "10", 4 * 3600),            // multi-guard → two unpaid shares
            ("450", 3, 1, "137.37", "137.37", "7.5", 2 * 3600), // a tip + awkward rate + proration
            // THE `Extra` ARM: pre-paid with no tip, settled with a ฿300 one → ฿321 (tip + its VAT)
            // was billed and never collected, and the sweep must NOT transfer it.
            ("500", 4, 1, "0", "300", "10", 4 * 3600),
        ];
        let mut booking_ids = Vec::new();
        let mut payment_ids = Vec::new();
        let mut payout_items = Vec::new();
        let wht_rate = dec("3");

        // …plus a CANCELLED job, which balances a completely different way: no guard was paid at all,
        // so the equation has to close on the retained fee (net of ITS VAT) and the refund alone.
        let cancelled_booking = Uuid::new_v4();
        let cancelled_payment = cancelled_job(&pool, cancelled_booking, "500", 4, "500.00").await;
        booking_ids.push(cancelled_booking);
        payment_ids.push(cancelled_payment);
        for (base_fee, hours, guards, prepaid_tip, tip, pct, worked) in shapes {
            let booking_id = Uuid::new_v4();
            let guard_id = Uuid::new_v4();
            let payment_id = settled_job_billed_over(
                &pool,
                booking_id,
                guard_id,
                base_fee,
                hours,
                guards,
                prepaid_tip,
                tip,
                pct,
                worked,
            )
            .await;
            booking_ids.push(booking_id);
            payment_ids.push(payment_id);
            // The PAYOUT, priced exactly as `api::payouts::aggregate` prices it: off the stored
            // `actual_hours` + `commission_percent`, through the shared pure helpers.
            let (actual_hours, commission_percent): (Option<Decimal>, Option<Decimal>) =
                sqlx::query_as(
                    "SELECT actual_hours, commission_percent FROM payment.payments WHERE id = $1",
                )
                .bind(payment_id)
                .fetch_one(&pool)
                .await
                .expect("reconciled row");
            let amounts = crate::domain::payout::compute_payout(
                dec(base_fee),
                actual_hours.expect("reconciled"),
                commission_percent,
                wht_rate,
            );
            payout_items.push(crate::models::NewPayoutItem {
                booking_id,
                guard_id,
                income: amounts.income,
                wht: amounts.wht,
                transfer_amount: amounts.transfer,
            });
        }

        // Stream ③ — pay the guards.
        let mut payout = payout_batch_of(&[]);
        payout.total_amount = payout_items.iter().map(|i| i.transfer_amount).sum();
        payout.recipient_count = payout_items.len();
        payout.items = payout_items;
        insert_payout_batch(&pool, &payout).await.expect("payout");

        // Stream ② — sweep the platform's cut.
        let items: Vec<_> = sweep_backlog(&pool, &payment_ids)
            .await
            .iter()
            .filter_map(sweep_item)
            .collect();
        assert_eq!(
            items.len(),
            shapes.len() + 1,
            "every job priced — the five worked shapes AND the cancelled one"
        );
        // Exactly ONE of them was billed over what was collected, and the ledger says so — proof the
        // deduction actually rode this run rather than the shapes happening to net out.
        let billed_over: Vec<&crate::models::NewDeductionItem> = items
            .iter()
            .filter(|i| i.uncollected > Decimal::ZERO)
            .collect();
        assert_eq!(billed_over.len(), 1, "the `Extra`-arm job is in the sweep");
        assert_eq!(billed_over[0].uncollected, dec("321.00"));
        insert_deduction_batch(&pool, &sweep_batch_of(items))
            .await
            .expect("sweep");

        // Now SUM EVERY TERM OUT OF THE DATABASE.
        let (customer_paid, refunded, vat): (Decimal, Decimal, Decimal) = sqlx::query_as(
            "SELECT COALESCE(SUM(amount + overpaid_amount), 0), \
                    COALESCE(SUM(COALESCE(refund_amount, 0)), 0), \
                    COALESCE(SUM(COALESCE(vat_amount, 0)), 0) \
               FROM payment.payments WHERE id = ANY($1)",
        )
        .bind(&payment_ids)
        .fetch_one(&pool)
        .await
        .expect("customer side");
        let (guard_transfer, wht): (Decimal, Decimal) = sqlx::query_as(
            "SELECT COALESCE(SUM(transfer_amount), 0), COALESCE(SUM(wht), 0) \
               FROM payment.payout_batch_items WHERE booking_id = ANY($1) AND voided_at IS NULL",
        )
        .bind(&booking_ids)
        .fetch_one(&pool)
        .await
        .expect("guard side");
        let swept_cut: Decimal = sqlx::query_scalar(
            "SELECT COALESCE(SUM(amount), 0) FROM payment.deduction_batch_items \
              WHERE booking_id = ANY($1) AND voided_at IS NULL",
        )
        .bind(&booking_ids)
        .fetch_one(&pool)
        .await
        .expect("platform side");

        assert_eq!(
            customer_paid,
            guard_transfer + refunded + swept_cut + vat + wht,
            "ลูกค้าจ่าย {customer_paid} ≠ โอน รปภ {guard_transfer} + คืนเงิน {refunded} \
             + หักเข้าระบบ {swept_cut} + VAT {vat} + WHT {wht}"
        );
        // …and none of the three streams is trivially zero, or the equation above would prove nothing.
        assert!(guard_transfer > Decimal::ZERO);
        assert!(refunded > Decimal::ZERO, "the prorated jobs refunded");
        assert!(swept_cut > Decimal::ZERO);
        assert!(vat > Decimal::ZERO);
        assert!(wht > Decimal::ZERO);
        // The cancelled job contributed its retained fee NET of VAT — 500.00 retained is 467.29 kept
        // and 32.71 owed to the Revenue Department, never 500.00 of income.
        let cancelled_cut: Decimal = sqlx::query_scalar(
            "SELECT COALESCE(SUM(amount), 0) FROM payment.deduction_batch_items \
              WHERE booking_id = $1 AND voided_at IS NULL",
        )
        .bind(cancelled_booking)
        .fetch_one(&pool)
        .await
        .expect("the cancelled job's cut");
        assert_eq!(
            cancelled_cut,
            dec("467.29"),
            "500.00 fee − the 7/107 inside it"
        );

        cleanup_deduction(&pool, &booking_ids).await;
    }
}
