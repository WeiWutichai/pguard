//! DTOs for the payment service (transport shapes). Pure data — no I/O.
//!
//! ALL money fields are [`rust_decimal::Decimal`] — never `f64` (CLAUDE.md money rules).

use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ----- Requests -----

/// Body of `POST /payments` (createPayment — PRE-PAY). The client sends ONLY the booking id;
/// the amount is computed SERVER-SIDE from the authoritative booking (`base_fee × hours ×
/// guard_count + tip`), never trusted from the client (CLAUDE.md money rules).
#[derive(Debug, Deserialize)]
pub struct CreatePaymentRequest {
    pub booking_id: Uuid,
}

/// Inclusive-from / exclusive-to date window for the analytics reports (RFC3339). Both
/// optional — the handler defaults to the last 30 days ending now.
#[derive(Debug, Deserialize)]
pub struct ReportRangeQuery {
    pub from: Option<DateTime<Utc>>,
    pub to: Option<DateTime<Utc>>,
}

/// Query params for `GET /admin/payments` (admin cross-user ledger). `status` is validated
/// against the payment status enum (unknown → 400); `customer_id` narrows to one customer's
/// payments (the customer-spend drill-down). House limit/offset pagination.
#[derive(Debug, Deserialize)]
pub struct AdminListPaymentsQuery {
    pub status: Option<String>,
    pub customer_id: Option<Uuid>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

// ----- Responses -----

/// A payment row as returned to clients. `status` is read as text (the DB enum cast to
/// text) so the read path needs no enum decoding — mirrors the booking/notification slices.
///
/// TAX-INVOICE FIELDS (`subtotal` / `vat_amount` / `grand_total`): catalog prices are
/// VAT-EXCLUSIVE and 7% VAT is added on top, so `amount` (what was charged) is a GRAND TOTAL and
/// these three describe how it was reached. They always describe the CURRENTLY SETTLED bill: the
/// completion reconcile rewrites `subtotal`/`vat_amount` from the prorated hours, and a
/// cancellation rewrites them to the retained fee. `subtotal`/`vat_amount` are `None` only on rows
/// charged BEFORE VAT was introduced (those were never VAT'd — do not infer zero VAT-exclusive
/// pricing from a missing split).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct PaymentResponse {
    pub id: Uuid,
    pub booking_id: Uuid,
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub amount: Decimal,
    /// Server-computed authoritative total at charge time (`base_fee × hours × guards + tip`,
    /// VAT included) — the figure the customer was required to cover.
    pub expected_total: Option<Decimal>,
    /// VAT-EXCLUSIVE service cost of the settled bill. `None` on pre-VAT rows.
    pub subtotal: Option<Decimal>,
    /// 7% VAT charged on `subtotal`. `None` on pre-VAT rows.
    pub vat_amount: Option<Decimal>,
    /// `subtotal + vat_amount` — what the customer owes in total (falls back to `amount` on
    /// pre-VAT rows, so this field is always present and always the payable figure).
    pub grand_total: Decimal,
    /// Cancellation fee RETAINED when the customer cancelled (`min(fee, amount paid)`); `0` when
    /// the guard withdrew (no fault of the customer) and `None` when the booking was not cancelled.
    pub cancellation_fee_charged: Option<Decimal>,
    /// Excess the customer transferred ABOVE the estimate on a slip payment
    /// (`max(0, slip_amount − amount)`); `0` for simulated/exact payments. Always refundable ON TOP
    /// of the settled bill (never platform revenue), so every refund path returns
    /// `amount + overpaid_amount`. NOT NULL (default 0) — present on every row.
    pub overpaid_amount: Decimal,
    pub payment_method: Option<String>,
    pub status: String,
    pub final_amount: Option<Decimal>,
    pub refund_amount: Option<Decimal>,
    pub actual_hours: Option<Decimal>,
    /// `pending` once a refund is owed (admin marks `processed` later); else `None`.
    pub refund_status: Option<String>,
    pub paid_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

// ----- PromptPay QR (customer payment screen) -----

/// `GET /payments/{id}/promptpay` response — everything the mobile needs to render the PromptPay
/// transfer screen. The `qr_payload` is the authoritative EMVCo string built SERVER-SIDE from our
/// `RECEIVING_ACCOUNT` + the server estimate (one place — the client never composes its own), so
/// the amount + receiver can never drift. Only meaningful under `PAYMENT_PROVIDER=slip2go`.
///
/// `amount` is the same exact-decimal estimate (`base_fee × hours × guards + tip`) the slip /
/// prepay handlers charge → JSON string (money rule). `amount_satang` is that amount in the
/// smallest unit (×100, integer) as a convenience for clients that price in satang — derived
/// from the same Decimal, never an f64.
#[derive(Debug, Serialize)]
pub struct PromptPayResponse {
    /// The server-side estimate the customer must transfer (exact decimal → JSON string).
    pub amount: Decimal,
    /// The estimate in satang (the smallest THB unit, ×100) as an integer — a convenience field.
    pub amount_satang: i64,
    /// OUR receiving PromptPay account, formatted for human display (e.g. `081-234-5678`).
    pub receiving_account: String,
    /// The authoritative EMVCo PromptPay QR string — render this as a QR; do NOT rebuild it.
    pub qr_payload: String,
}

// ----- Revenue report (admin analytics) -----

/// One day's net revenue point. `revenue` is net of refunds (Decimal → JSON string, money
/// rule); `payments` counts completed charges that day.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct RevenuePoint {
    pub date: NaiveDate,
    pub revenue: Decimal,
    pub payments: i64,
}

/// Revenue-trend report. `mom_pct` compares the window's total to the immediately-preceding
/// equal-length window (`None` when the prior window had zero revenue — no baseline). It is a
/// display-only percentage (f64); the money totals stay Decimal-as-string on the wire.
#[derive(Debug, Serialize)]
pub struct RevenueReport {
    pub series: Vec<RevenuePoint>,
    pub total: Decimal,
    pub prev_total: Decimal,
    pub mom_pct: Option<f64>,
}

/// One completed job's earning basis for the assigned guard. `actual_hours` is the clamped hours
/// ACTUALLY worked (persisted at reconcile); NULL for an even-match / not-yet-reconciled row, where
/// the client falls back to the booked hours. The client multiplies `base_fee` (from its own
/// booking feed) × these hours to show the guard's pay for hours actually worked — so the guard's
/// figure tracks what the customer was actually charged (net of the overpay refund), instead of the
/// full booked estimate that used to overstate it.
///
/// `commission_percent` is the per-service commission SNAPSHOT taken from the booking at charge
/// time, so the app can show what was deducted:
///   `gross = base_fee × actual_hours` · `commission = gross × commission_percent / 100` ·
///   `net = gross − commission`
/// (no `guard_count`, no tip — this is ONE guard's share). Commission comes out of the GUARD's pay,
/// never off the customer's bill, and VAT is not part of it: the guard is paid on the VAT-exclusive
/// service price. `None` on a job booked before commissions existed → treat as 0%.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct GuardEarningRow {
    pub booking_id: Uuid,
    pub actual_hours: Option<Decimal>,
    pub commission_percent: Option<Decimal>,
}

// ----- booking internal read (deserialized from booking's /internal/bookings/{id}) -----

/// The authoritative booking fields the PRE-PAY charge verifies + prices against. Mirrors the
/// relevant subset of booking's `InternalBooking`; serde ignores the extra fields (id/guard_id)
/// the charge does not need. The PRE-PAY estimate is `base_fee × hours × guard_count + tip`
/// computed from THESE server-owned values — never a client body. Money fields deserialize from
/// a JSON string (rust_decimal serde-str, workspace-wide).
#[derive(Debug, Clone, Deserialize)]
pub struct InternalBooking {
    pub customer_id: Uuid,
    /// The accepted guard (`Some` once a guard claimed the booking — always set in a payable
    /// state). Carried onto `payment.completed` so notification can push the guard
    /// "ลูกค้าชำระเงินแล้ว".
    pub guard_id: Option<Uuid>,
    pub status: String,
    pub hours: i32,
    /// ฿ per hour per guard (server-owned; the client never sets this). VAT-EXCLUSIVE — VAT is
    /// added on top by [`crate::domain::pricing::price_breakdown`], never baked into the catalog price.
    pub base_fee: Decimal,
    pub guard_count: i32,
    pub tip: Decimal,
    /// Per-service commission %, SNAPSHOT on the booking at creation. `None` when booking has not
    /// deployed the field yet, or the booking predates commissions → treat as 0 (see
    /// [`crate::domain::ChargeTerms::new`], which also clamps it to `0..=100`).
    #[serde(default)]
    pub commission_percent: Option<Decimal>,
    /// What a CUSTOMER cancellation of this booking costs, SNAPSHOT on the booking at creation.
    /// `None`/absent → 0 (no fee). Payment copies it onto the payment row so the refund path —
    /// an event consumer with no HTTP — can price a cancellation without a cross-service read.
    #[serde(default)]
    pub cancellation_fee: Option<Decimal>,
}

// ----- Refund queue (admin dashboard signal) -----

/// Query params for `GET /admin/refunds/queue`. `status` optionally narrows to one refund-workflow
/// state (`pending` = awaiting action, `processed` = done); omitted → both. House limit/offset.
#[derive(Debug, Deserialize)]
pub struct RefundQueueQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// One refund-queue row — a payment whose settle left a refund owed. `amount` is the
/// `refund_amount` (the money to return, not the original charge); `status` is the refund-workflow
/// state (`pending`/`processed`), NOT the payment status (a partial refund stays `completed`).
/// Exact-decimal `amount` → JSON string (money rule).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct RefundQueueItem {
    pub payment_id: Uuid,
    pub booking_id: Uuid,
    pub amount: Decimal,
    pub status: String,
    pub created_at: DateTime<Utc>,
}

/// The admin refund-queue response: the matching refund rows (newest first) + the total `count`
/// of rows matching the same filter (the dashboard "คิวคืนเงิน" badge), independent of limit/offset.
#[derive(Debug, Serialize)]
pub struct RefundQueueResponse {
    pub refunds: Vec<RefundQueueItem>,
    pub count: i64,
}

// ----- Customer-spend report (admin analytics) -----

/// One customer's lifetime spend — the sum of their actually-charged (completed) payments'
/// effective amount (prorated `final_amount` when set, else `amount`). Powers the web-admin
/// customers page's spend column. `total` is exact-decimal → JSON string (money rule), mirroring
/// `RevenuePoint.revenue`.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct CustomerSpend {
    pub customer_id: Uuid,
    pub total: Decimal,
}

// ----- Guard payout (SCB Business Net bulk file + ภ.ง.ด.53 WHT) -----

/// One UNPAID, reconciled, guard-assigned job the payout aggregator will pay. Read from
/// `payment.payments` (a `completed` payment with `guard_id` + `actual_hours` set — i.e. the job
/// finished and reconciled — whose `booking_id` is NOT yet in `payout_batch_items`).
///
/// `base_fee`/`booked_hours` are the migration-0013 pricing SNAPSHOT, and the snapshot is the
/// AUTHORITY for what the guard is paid: it is payment's own schema, it makes a historical export
/// reproducible, and it is the very column stream ② sweeps the platform's cut from — so the two
/// cannot disagree about one job. `None` means the row predates the snapshot and ONLY then does the
/// aggregation fall back to booking's live `base_fee` over HTTP; see `api::payouts::aggregate`.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct UnpaidPayoutRow {
    pub booking_id: Uuid,
    pub guard_id: Uuid,
    pub actual_hours: Option<Decimal>,
    pub commission_percent: Option<Decimal>,
    /// ฿/hour/guard as SNAPSHOTTED at charge time. `None` = pre-migration-0013 row.
    pub base_fee: Option<Decimal>,
    /// The billed duration as SNAPSHOTTED at charge time — the hours fallback when a row somehow
    /// carries no `actual_hours`. `None` = pre-migration-0013 row.
    pub booked_hours: Option<i32>,
}

/// The single-row company payout settings (`GET`/`PUT /admin/payouts/config`). The WHT-term columns
/// are `NOT NULL DEFAULT` in the schema, so a read always has them; the debit accounts are nullable
/// (blank until an admin configures them — the export refuses to run until they are set). `updated_at`
/// is `None` until the row is first written (honest "unset" state, like `org_settings`).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct PayoutConfigRow {
    pub debit_account: Option<String>,
    pub fee_debit_account: Option<String>,
    /// The company SCB account the PLATFORM-CUT sweep (stream ②, product `OAT`) is CREDITED to.
    /// `None` until an admin sets it; the sweep export refuses to run without it. Validated as a real
    /// SCB account (10 digits + the §14 check digit) at save time AND again at export, exactly like
    /// the two debit accounts — an `OAT` line may credit no other bank, and a check-digit typo is
    /// BATCH-fatal: the bank rejects the file after the jobs in it were marked swept.
    pub revenue_account: Option<String>,
    pub wht_form_type_code: String,
    pub wht_pay_type_code: String,
    pub wht_income_type_code: String,
    pub wht_income_desc: String,
    pub wht_rate_percent: Decimal,
    pub product_code: String,
    /// `TXNDET` field 8 — who bears the transfer fee (`OUR` = the company, `BEN` = the guard;
    /// `Master_data!TBFeeOther`). `NOT NULL DEFAULT 'OUR'` in the schema, so a read always has it.
    /// The default is a LEDGER decision: with `BEN` the bank deducts its fee from the credit and the
    /// guard receives less than `payout_batch_items.transfer_amount` records, so our books and the
    /// bank's would permanently disagree about the same transfer.
    pub fee_charge_code: String,
    /// Whether SCB should SMS the guard about the transfer (`TXNDET` fields 9/10). OFF by default:
    /// SCB bills per SMS and the number is the guard's login phone, which nobody opted into sharing
    /// with the bank. It does NOT gate the PromptPay `MOB` fallback — that same phone still
    /// ADDRESSES the money for a guard with no tax id.
    pub sms_notify: bool,
    /// Per-transaction transfer cap in THB (`NULL` = uncapped). A guard whose TOTAL transfer would
    /// exceed it is EXCLUDED from the batch with a reason — SCB rejects an over-limit credit line,
    /// and a rejected file arrives AFTER the bookings were marked paid. See migration
    /// `0008_payout_txn_cap.sql` for why ฿2,000,000 (not ฿10,000) is the guard default.
    pub max_transfer_per_txn: Option<Decimal>,
    pub updated_at: Option<DateTime<Utc>>,
}

impl PayoutConfigRow {
    /// The "unset" default returned before any row exists — the schema DEFAULTs mirrored so a fresh
    /// install shows the standard ภ.ง.ด.53 terms with blank debit accounts (GET never 404s).
    pub fn unset() -> Self {
        Self {
            debit_account: None,
            fee_debit_account: None,
            revenue_account: None,
            wht_form_type_code: "53".to_string(),
            wht_pay_type_code: "1".to_string(),
            wht_income_type_code: "5".to_string(),
            wht_income_desc: "ค่าบริการรักษาความปลอดภัย".to_string(),
            wht_rate_percent: Decimal::from(3),
            product_code: "PPY".to_string(),
            fee_charge_code: "OUR".to_string(),
            sms_notify: false,
            // Mirrors the schema DEFAULT (the NAT/MOB PromptPay per-transaction limit). Parsed from
            // the domain constant so the two can never drift; an unparseable literal would be a
            // compile-time-constant bug, so fall back to "uncapped" rather than panic at startup.
            max_transfer_per_txn: crate::domain::scb_export::DEFAULT_MAX_TRANSFER_PER_TXN
                .parse()
                .ok(),
            updated_at: None,
        }
    }
}

/// `PUT /admin/payouts/config` body — every field optional (the admin saves incrementally). A field
/// left `None` keeps the stored value (or the schema default on first write).
#[derive(Debug, Deserialize)]
pub struct UpdatePayoutConfigRequest {
    pub debit_account: Option<String>,
    pub fee_debit_account: Option<String>,
    /// The company account the platform-cut sweep credits. `None` keeps the stored value; a value
    /// that is not a valid SCB account is a 400 on the settings screen rather than a bounced file.
    pub revenue_account: Option<String>,
    pub wht_form_type_code: Option<String>,
    pub wht_pay_type_code: Option<String>,
    pub wht_income_type_code: Option<String>,
    pub wht_income_desc: Option<String>,
    pub wht_rate_percent: Option<Decimal>,
    /// `OUR` or `BEN` (`Master_data!TBFeeOther`) — anything else is a 400. `None` keeps the stored
    /// value, so the mandatory credit-row field can never be blanked through this API.
    pub fee_charge_code: Option<String>,
    /// Opt in/out of the bank's SMS notification to the guard. `None` keeps the stored value.
    pub sms_notify: Option<bool>,
    /// Per-transaction transfer cap in THB. `None` keeps the stored value (like every other field
    /// here) — the cap cannot be CLEARED through this API, only raised/lowered, so a fat-fingered
    /// partial save can never quietly remove the guard-rail on a money file.
    pub max_transfer_per_txn: Option<Decimal>,
}

/// The persisted record of a generated batch + its per-booking items (the paid-marker rows). Passed
/// to [`crate::repo::insert_payout_batch`], which writes the batch header + all items in ONE tx; the
/// partial `UNIQUE(booking_id) WHERE voided_at IS NULL` on the items is the atomic guard against
/// paying a job twice.
#[derive(Debug, Clone)]
pub struct NewPayoutBatch {
    pub file_ref: String,
    pub system_ref: String,
    pub batch_ref: String,
    pub value_date: NaiveDate,
    pub total_amount: Decimal,
    /// How many GUARDS the file pays (= `TXNDET` lines), NOT how many bookings. It used to be
    /// written as `items.len()`, which counts BOOKINGS — a guard with three finished jobs is one
    /// recipient and one credit line, so a 3-booking/1-guard batch claimed "3 recipients" while the
    /// file it describes has one. Passed explicitly rather than derived here because only the
    /// aggregation knows how the items were grouped.
    pub recipient_count: usize,
    /// The EXACT file text handed to the admin. Stored so it can be re-downloaded: without it, a
    /// failed download / closed tab / proxy timeout left the bookings marked paid forever with no
    /// copy of the file that was meant to pay them. It is never REGENERATED on read — a regenerated
    /// file could differ (config, WHT rate or a guard profile changed) under the same batch ref.
    pub file_text: String,
    pub created_by: Option<Uuid>,
    pub items: Vec<NewPayoutItem>,
}

#[derive(Debug, Clone)]
pub struct NewPayoutItem {
    pub booking_id: Uuid,
    pub guard_id: Uuid,
    pub income: Decimal,
    pub wht: Decimal,
    pub transfer_amount: Decimal,
}

/// One generated payout file as the admin history screen sees it — the header, never the file text
/// (that is its own endpoint; a list must not haul N × ~1 KB of pipe-delimited money file).
/// `has_file` says whether the re-download will work: batches generated before the text was stored
/// have none, and the UI should not offer a button that 404s.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct PayoutBatchRow {
    pub id: Uuid,
    pub file_ref: String,
    pub system_ref: String,
    pub batch_ref: String,
    pub value_date: NaiveDate,
    pub total_amount: Decimal,
    pub recipient_count: i32,
    pub status: String,
    pub status_note: Option<String>,
    pub void_reason: Option<String>,
    pub has_file: bool,
    pub created_by: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub uploaded_at: Option<DateTime<Utc>>,
    pub confirmed_at: Option<DateTime<Utc>>,
    pub rejected_at: Option<DateTime<Utc>>,
    pub voided_at: Option<DateTime<Utc>>,
    pub voided_by: Option<Uuid>,
}

/// One paid-marker row in a batch's drill-down. `voided_at` set = the batch was voided and THIS
/// booking is payable again (the row is kept as history, not deleted — you can still see the guard
/// was in a voided file).
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct PayoutBatchItemRow {
    pub id: Uuid,
    pub booking_id: Uuid,
    pub guard_id: Uuid,
    pub income: Decimal,
    pub wht: Decimal,
    pub transfer_amount: Decimal,
    pub voided_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

/// A page of the payout history + the TOTAL matching count, so the screen can paginate without
/// guessing from a short page.
#[derive(Debug, Serialize)]
pub struct PayoutBatchList {
    pub batches: Vec<PayoutBatchRow>,
    pub total: i64,
}

/// One batch header + every booking it paid.
#[derive(Debug, Serialize)]
pub struct PayoutBatchDetail {
    #[serde(flatten)]
    pub batch: PayoutBatchRow,
    pub items: Vec<PayoutBatchItemRow>,
}

/// The stored file of ANY export batch, for a re-download: just the text + the ref the download
/// name is built from (the items are deliberately NOT read — a download must not depend on the size
/// of the batch). Shared by the payout and the refund history, because the download response is
/// built by one helper for both and the two must never disagree about the filename or the bytes.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct ExportedBatchFile {
    pub file_ref: String,
    pub file_text: String,
}

/// `POST /admin/payouts/batches/{id}/status` body — where the file has got to at the bank.
#[derive(Debug, Deserialize)]
pub struct SetPayoutBatchStatusRequest {
    pub status: String,
    /// Optional free text kept with the change (typically the bank's own rejection message).
    #[serde(default)]
    pub note: Option<String>,
}

/// `POST /admin/payouts/batches/{id}/void` body. The reason is REQUIRED and must be non-blank: a
/// void returns every booking in the batch to the payable backlog, and six months later "voided"
/// with no reason cannot be told apart from a mis-click.
#[derive(Debug, Deserialize)]
pub struct VoidPayoutBatchRequest {
    pub reason: String,
}

/// `POST /admin/payouts/batches/{id}/items/void` body — return SOME of a batch's bookings to the
/// payable backlog, leaving the rest paid and the batch's own status alone.
///
/// This is the remedy for the everyday partial failure: SCB accepts a structurally valid file and
/// still fails individual credit lines (an unregistered PromptPay proxy, or one not linked to a
/// receiving account). Voiding the whole batch would un-pay the guards who DID get their money —
/// and is not even offered once the batch is `confirmed`.
#[derive(Debug, Deserialize)]
pub struct VoidPayoutBatchItemsRequest {
    /// The bookings whose credit lines failed. Must be non-empty, and every one must belong to THIS
    /// batch (else 404) and still be live (else 409).
    pub booking_ids: Vec<Uuid>,
    /// Why — required and non-blank, exactly like the whole-batch void: this is the record of why
    /// money that our ledger says was paid is being queued up to be paid again.
    pub reason: String,
}

// ----- Customer refunds (stream ① ยอดที่ต้องโอนคืนกับคนจ้าง — the SCB refund file) -----

/// ONE unpaid refund obligation from the UNION backlog. Two tables owe this money, so the row
/// carries the LANE with the id: `source_kind` is `payment` (a `payment.payments` row whose settle
/// left `refund_amount` owed) or `slip` (a `payment.payment_slips` row — a genuine double-pay whose
/// whole `amount` goes back). Ordered by customer so the aggregator can group.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct UnpaidRefundRow {
    /// `payment` | `slip` — parsed by [`crate::domain::refund_export::RefundSourceKind`].
    pub source_kind: String,
    /// The owing row's id: `payment.payments.id` or `payment.payment_slips.id`.
    pub source_id: Uuid,
    /// What the refund is FOR. Present on both lanes; carried so support can trace a credit line
    /// back to a job without joining through the source table.
    pub booking_id: Uuid,
    /// Who gets the money. Lane B has no `customer_id` column of its own — it is resolved through
    /// the slip's `payment_id` in the backlog query.
    pub customer_id: Uuid,
    /// This obligation's amount: `payments.refund_amount` (lane A) or `payment_slips.amount`
    /// (lane B — the whole duplicate transfer).
    pub amount: Decimal,
}

/// The persisted record of a generated refund batch + its per-obligation items (the paid-marker
/// rows). Passed to [`crate::repo::insert_refund_batch`], which writes the header, all items, the
/// `refund_status → 'processed'` advance on BOTH source tables and the audit row in ONE transaction;
/// the partial `UNIQUE(source_kind, source_id) WHERE voided_at IS NULL` is the atomic guard against
/// refunding the same obligation twice.
#[derive(Debug, Clone)]
pub struct NewRefundBatch {
    pub file_ref: String,
    pub system_ref: String,
    pub batch_ref: String,
    pub value_date: NaiveDate,
    pub total_amount: Decimal,
    /// How many CUSTOMERS the file refunds (= `TXNDET` lines), NOT how many obligations — a customer
    /// with three pending refunds is one recipient on one credit line. Passed explicitly rather than
    /// derived from `items` (which counts obligations) because only the aggregation knows how they
    /// were grouped; the payout learned this the expensive way (migration 0009 had to backfill it).
    pub recipient_count: usize,
    /// The EXACT file text handed to the admin, stored so it can be re-downloaded. Committed in the
    /// same transaction as the markers: without it, a failed download / closed tab / proxy timeout
    /// would leave the obligations marked `processed` forever with no copy of the file meant to
    /// settle them.
    pub file_text: String,
    pub created_by: Option<Uuid>,
    pub items: Vec<NewRefundItem>,
}

/// One refund obligation this batch settles (the paid-marker row).
#[derive(Debug, Clone)]
pub struct NewRefundItem {
    /// `payment` | `slip` — which table to advance to `refund_status = 'processed'`.
    pub source_kind: String,
    pub source_id: Uuid,
    pub booking_id: Uuid,
    pub customer_id: Uuid,
    pub amount: Decimal,
}

/// One generated refund file as the admin history screen sees it — the header, never the file text
/// (that is its own endpoint; a list must not haul N × ~1 KB of pipe-delimited money file).
/// `has_file` says whether the re-download will work, so the UI does not offer a button that 404s.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct RefundBatchRow {
    pub id: Uuid,
    pub file_ref: String,
    pub system_ref: String,
    pub batch_ref: String,
    pub value_date: NaiveDate,
    pub total_amount: Decimal,
    pub recipient_count: i32,
    pub status: String,
    pub status_note: Option<String>,
    pub void_reason: Option<String>,
    pub has_file: bool,
    pub created_by: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub uploaded_at: Option<DateTime<Utc>>,
    pub confirmed_at: Option<DateTime<Utc>>,
    pub rejected_at: Option<DateTime<Utc>>,
    pub voided_at: Option<DateTime<Utc>>,
    pub voided_by: Option<Uuid>,
}

/// One paid-marker row in a refund batch's drill-down. `voided_at` set = this obligation was
/// returned to the refundable queue (its source row is `pending` again) — the row is kept as
/// history, not deleted, so you can still see it rode that file.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct RefundBatchItemRow {
    pub id: Uuid,
    pub source_kind: String,
    pub source_id: Uuid,
    pub booking_id: Uuid,
    pub customer_id: Uuid,
    pub amount: Decimal,
    pub voided_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

/// A page of the refund-file history + the TOTAL matching count, so the screen can paginate without
/// guessing from a short page.
#[derive(Debug, Serialize)]
pub struct RefundBatchList {
    pub batches: Vec<RefundBatchRow>,
    pub total: i64,
}

/// One refund batch header + every obligation it settled.
#[derive(Debug, Serialize)]
pub struct RefundBatchDetail {
    #[serde(flatten)]
    pub batch: RefundBatchRow,
    pub items: Vec<RefundBatchItemRow>,
}

/// `POST /admin/refunds/batches/{id}/status` body — where the file has got to at the bank.
#[derive(Debug, Deserialize)]
pub struct SetRefundBatchStatusRequest {
    pub status: String,
    /// Optional free text kept with the change (typically the bank's own rejection message).
    #[serde(default)]
    pub note: Option<String>,
}

/// `POST /admin/refunds/batches/{id}/void` body. The reason is REQUIRED and must be non-blank: a
/// void returns every obligation in the batch to the refundable queue (flipping its source row back
/// to `refund_status = 'pending'`), and six months later "voided" with no reason cannot be told
/// apart from a mis-click.
#[derive(Debug, Deserialize)]
pub struct VoidRefundBatchRequest {
    pub reason: String,
}

/// ONE refund obligation named in a request body — the (lane, id) pair, exactly as the batch
/// drill-down reports it. A bare id would be ambiguous: `payment` and `slip` are separate tables
/// with separate id spaces.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RefundSourceRef {
    /// `payment` | `slip`. Anything else is a 400 naming the two.
    pub source_kind: String,
    pub source_id: Uuid,
}

/// `POST /admin/refunds/batches/{id}/items/void` body — return SOME of a batch's obligations to the
/// refundable queue, leaving the rest settled and the batch's own status alone.
///
/// The remedy for the everyday partial failure: SCB accepts a structurally valid file and still
/// fails individual credit lines (a PromptPay proxy not linked to a receiving account is the usual
/// cause). Voiding the whole batch would un-settle the customers who DID get their money — and is
/// not even offered once the batch is `confirmed`.
#[derive(Debug, Deserialize)]
pub struct VoidRefundBatchItemsRequest {
    /// The obligations whose credit lines failed. Must be non-empty, and every one must belong to
    /// THIS batch (else 404) and still be live (else 409).
    pub sources: Vec<RefundSourceRef>,
    /// Why — required and non-blank, exactly like the whole-batch void: this is the record of why
    /// money the ledger says was refunded is being queued up to be sent again.
    pub reason: String,
}

// ----- Platform cut (stream ② ยอดที่โดนหักเข้าระบบ — the SCB OAT sweep + the two tax reports) -----

/// ONE settled payment as the sweep reads it: the money columns [`crate::domain::settlement::split`]
/// needs, plus the two ids the ledger row is keyed on.
///
/// Deliberately EVERY column the pure split takes, and nothing else — no `SELECT *` on the money
/// path, and no cross-service read: a historical sweep has to be reproducible from what payment
/// itself stored (which is the whole reason migration 0013 exists).
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct SettledPaymentRow {
    /// The payment row — the swept-marker key (`deduction_batch_items.payment_id`).
    pub payment_id: Uuid,
    pub booking_id: Uuid,
    pub amount: Decimal,
    pub overpaid_amount: Decimal,
    pub final_amount: Option<Decimal>,
    pub refund_amount: Option<Decimal>,
    pub subtotal: Option<Decimal>,
    pub vat_amount: Option<Decimal>,
    /// `true` when the row is `refunded` — the job was cancelled/declined and never ran, so the only
    /// thing kept is the cancellation fee.
    pub cancelled: bool,
    pub base_fee: Option<Decimal>,
    pub booked_hours: Option<i32>,
    pub guard_count: Option<i32>,
    pub tip: Option<Decimal>,
    pub commission_amount: Option<Decimal>,
    pub actual_hours: Option<Decimal>,
    /// When the job became sweepable — `payments.updated_at`, stamped by whichever settle wrote
    /// `final_amount`. The SAME basis the payout backlog windows on, deliberately (see
    /// [`crate::repo::unswept_deduction_rows`]).
    pub settled_at: DateTime<Utc>,
}

/// The persisted record of a generated sweep + its per-job ledger rows. Passed to
/// [`crate::repo::insert_deduction_batch`], which writes the header, all items, the shared SCB
/// reference reservation and the audit row in ONE transaction; the partial
/// `UNIQUE(payment_id) WHERE voided_at IS NULL` is the atomic guard against sweeping a job twice.
#[derive(Debug, Clone)]
pub struct NewDeductionBatch {
    pub file_ref: String,
    pub system_ref: String,
    pub batch_ref: String,
    pub value_date: NaiveDate,
    /// Σ of every item's cut — and, because an `OAT` batch credits ONE destination, also the single
    /// `TXNDET` amount.
    pub total_amount: Decimal,
    /// The company account this file credits, snapshotted (`payout_config.revenue_account` may be
    /// edited later; a generated money file must still say where its money went).
    pub credit_account: String,
    pub file_text: String,
    pub created_by: Option<Uuid>,
    pub items: Vec<NewDeductionItem>,
}

/// One JOB whose cut this sweep collects — a LEDGER row behind the file's single credit line, not a
/// recipient. The components are stored separately so a report can still say what the money WAS
/// after the two deferred bugs (tip, `guard_count`) are fixed.
#[derive(Debug, Clone)]
pub struct NewDeductionItem {
    pub payment_id: Uuid,
    pub booking_id: Uuid,
    pub commission: Decimal,
    pub cancellation_fee: Decimal,
    pub tip: Decimal,
    pub unpaid_guard_share: Decimal,
    /// Proration-rounding drift — may be negative. See migration 0013.
    pub rounding_adjustment: Decimal,
    /// Billed and never collected, SUBTRACTED from `amount` (migration 0014). Non-negative: the
    /// reconcile's `Extra` arm wrote a settled bill above the pre-payment and captured nothing, so
    /// this much of the cut is not in the bank and must not be transferred out of it.
    pub uncollected: Decimal,
    /// `commission + cancellation_fee + tip + unpaid_guard_share + rounding_adjustment −
    /// uncollected` (a DB CHECK enforces it). SIGNED — such a job nets DOWN against the sweep.
    pub amount: Decimal,
}

/// One generated sweep file as the admin history screen sees it — the header, never the file text
/// (that is its own endpoint). `has_file` says whether the re-download will work.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct DeductionBatchRow {
    pub id: Uuid,
    pub file_ref: String,
    pub system_ref: String,
    pub batch_ref: String,
    pub value_date: NaiveDate,
    pub total_amount: Decimal,
    pub credit_account: String,
    /// Always 1 (an `OAT` batch has one destination) — `job_count` is the number that means
    /// something here.
    pub recipient_count: i32,
    /// How many jobs' cuts the file collected.
    pub job_count: i32,
    pub status: String,
    pub status_note: Option<String>,
    pub void_reason: Option<String>,
    pub has_file: bool,
    pub created_by: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub uploaded_at: Option<DateTime<Utc>>,
    pub confirmed_at: Option<DateTime<Utc>>,
    pub rejected_at: Option<DateTime<Utc>>,
    pub voided_at: Option<DateTime<Utc>>,
    pub voided_by: Option<Uuid>,
}

/// One ledger row in a sweep's drill-down. `voided_at` set = the job is back in the sweepable
/// backlog (the row is kept as history, not deleted).
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct DeductionBatchItemRow {
    pub id: Uuid,
    pub payment_id: Uuid,
    pub booking_id: Uuid,
    pub commission: Decimal,
    pub cancellation_fee: Decimal,
    pub tip: Decimal,
    pub unpaid_guard_share: Decimal,
    pub rounding_adjustment: Decimal,
    /// Billed and never collected — SUBTRACTED from `amount` (migration 0014).
    pub uncollected: Decimal,
    pub amount: Decimal,
    pub voided_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

/// A page of the sweep history + the TOTAL matching count, so the screen can paginate without
/// guessing from a short page.
#[derive(Debug, Serialize)]
pub struct DeductionBatchList {
    pub batches: Vec<DeductionBatchRow>,
    pub total: i64,
}

/// One sweep header + every job it collected.
#[derive(Debug, Serialize)]
pub struct DeductionBatchDetail {
    #[serde(flatten)]
    pub batch: DeductionBatchRow,
    pub items: Vec<DeductionBatchItemRow>,
}

/// `POST /admin/deductions/batches/{id}/status` body — where the file has got to at the bank.
#[derive(Debug, Deserialize)]
pub struct SetDeductionBatchStatusRequest {
    pub status: String,
    /// Optional free text kept with the change (typically the bank's own rejection message).
    #[serde(default)]
    pub note: Option<String>,
}

/// `POST /admin/deductions/batches/{id}/void` body. The reason is REQUIRED and must be non-blank: a
/// void returns every job in the batch to the sweepable backlog, and six months later "voided" with
/// no reason cannot be told apart from a mis-click.
#[derive(Debug, Deserialize)]
pub struct VoidDeductionBatchRequest {
    pub reason: String,
}

/// `POST /admin/deductions/batches/{id}/items/void` body — return SOME of a sweep's jobs to the
/// backlog, leaving the rest swept and the batch's own status alone.
#[derive(Debug, Deserialize)]
pub struct VoidDeductionBatchItemsRequest {
    /// The payment rows to release. Must be non-empty, and every one must belong to THIS batch
    /// (else 404) and still be live (else 409).
    pub payment_ids: Vec<Uuid>,
    /// Why — required and non-blank, exactly like the whole-batch void.
    pub reason: String,
}

// ----- The two TAX REPORTS (ภ.พ.30 output-VAT register · ภ.ง.ด.3/53 payee list) -----

/// One line of the OUTPUT-VAT register (รายงานภาษีขาย) backing a ภ.พ.30 filing: one settled payment,
/// the VAT-exclusive subtotal it was billed at, and the VAT charged on it.
///
/// The customer is reported as an ID rather than a name on purpose: resolving names would mean a
/// cross-service fan-out per row on a report that can run to thousands of rows in a month, and the
/// admin panel already has a BATCH name resolver (`POST /admin/users/resolve`) for exactly this.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct VatRegisterRow {
    /// The Bangkok calendar day the customer PAID — the VAT tax point for a service, and the same
    /// basis the revenue report buckets on.
    pub date: NaiveDate,
    pub payment_id: Uuid,
    pub booking_id: Uuid,
    pub customer_id: Uuid,
    /// The VAT-EXCLUSIVE settled bill (`payments.subtotal`).
    pub subtotal: Decimal,
    /// The VAT charged on it (`payments.vat_amount`).
    pub vat: Decimal,
    /// `subtotal + vat` — what the tax invoice totals.
    pub total: Decimal,
}

/// The output-VAT register for one month, with the period totals an accountant transcribes onto the
/// ภ.พ.30 form.
#[derive(Debug, Serialize)]
pub struct VatRegisterReport {
    /// The filing period, `YYYY-MM`.
    pub month: String,
    pub rows: Vec<VatRegisterRow>,
    pub row_count: usize,
    pub total_subtotal: Decimal,
    pub total_vat: Decimal,
    pub total_amount: Decimal,
}

/// One payee of the ภ.ง.ด.3/53 filing — a guard who had tax withheld from a payout that month,
/// summed over every non-voided item they appear on.
#[derive(Debug, Clone, Serialize)]
pub struct WhtPayeeRow {
    pub guard_id: Uuid,
    /// The payee's TIN (their Thai national/tax id). `None` when profile has no id on file — the row
    /// is still reported, because the money WAS withheld and the filing has to account for it.
    pub tax_id: Option<String>,
    pub name: Option<String>,
    pub address: Option<String>,
    /// How many jobs make up this payee's totals.
    pub job_count: i64,
    /// Gross assessable income paid (`Σ payout_batch_items.income`).
    pub income: Decimal,
    /// Tax withheld (`Σ payout_batch_items.wht`) — the figure the law requires us to report.
    pub wht: Decimal,
}

/// The ภ.ง.ด.3/53 payee list for one month, plus the two stored TAX DECISIONS the form is filed
/// under (never derived, never "corrected" here — they are the admin's setting).
#[derive(Debug, Serialize)]
pub struct WhtPayeeReport {
    /// The filing period, `YYYY-MM`.
    pub month: String,
    /// `payout_config.wht_form_type_code` — `53` = ภ.ง.ด.53 (juristic person), `04` = ภ.ง.ด.3
    /// (individual). The user's tax decision, reported as stored.
    pub form_type_code: String,
    /// `payout_config.wht_income_type_code` + its description — the assessable-income category every
    /// certificate in the period was issued under.
    pub income_type_code: String,
    pub income_description: String,
    pub rows: Vec<WhtPayeeRow>,
    pub payee_count: usize,
    pub total_income: Decimal,
    pub total_wht: Decimal,
}

/// The raw per-guard aggregate the WHT report reads out of `payout_batch_items` before the payee PII
/// is resolved. Its own type because the PII arrives from a different service.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct WhtPayeeTotals {
    pub guard_id: Uuid,
    pub job_count: i64,
    pub income: Decimal,
    pub wht: Decimal,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn money_serializes_as_string_not_float() {
        // Guards the rust_decimal `serde-str` wire format: money MUST be a JSON string
        // (matches the OpenAPI contract + never an f64), preserving 2dp scale. The tax-invoice
        // fields (subtotal/vat_amount/grand_total) follow the same rule.
        let epoch = DateTime::<Utc>::from_timestamp(0, 0).unwrap();
        let p = PaymentResponse {
            id: Uuid::nil(),
            booking_id: Uuid::nil(),
            customer_id: Uuid::nil(),
            guard_id: None,
            amount: "428.00".parse().unwrap(),
            expected_total: Some("428.00".parse().unwrap()),
            subtotal: Some("400.00".parse().unwrap()),
            vat_amount: Some("28.00".parse().unwrap()),
            grand_total: "428.00".parse().unwrap(),
            cancellation_fee_charged: None,
            overpaid_amount: Decimal::ZERO,
            payment_method: Some("promptpay".to_string()),
            status: "completed".to_string(),
            final_amount: Some("333.33".parse().unwrap()),
            refund_amount: None,
            actual_hours: None,
            refund_status: None,
            paid_at: None,
            created_at: epoch,
            updated_at: epoch,
        };
        let v = serde_json::to_value(&p).unwrap();
        assert_eq!(
            v["amount"],
            serde_json::json!("428.00"),
            "amount must be a JSON string"
        );
        assert_eq!(v["expected_total"], serde_json::json!("428.00"));
        assert_eq!(v["final_amount"], serde_json::json!("333.33"));
        assert!(v["refund_amount"].is_null());
        // The VAT split is exact-decimal strings too, and reconstructs the grand total.
        assert_eq!(v["subtotal"], serde_json::json!("400.00"));
        assert_eq!(v["vat_amount"], serde_json::json!("28.00"));
        assert_eq!(v["grand_total"], serde_json::json!("428.00"));
        assert!(v["cancellation_fee_charged"].is_null());
        // The overpay rider is exact-decimal too (never an f64) and present on every row.
        assert_eq!(v["overpaid_amount"], serde_json::json!("0"));
    }

    #[test]
    fn guard_earning_row_carries_the_commission_snapshot() {
        // The guard app needs the % that was deducted, per job — a NULL (pre-commission booking)
        // stays NULL on the wire so the client can distinguish "0%" from "unknown".
        let row = GuardEarningRow {
            booking_id: Uuid::nil(),
            actual_hours: Some("2.00".parse().unwrap()),
            commission_percent: Some("12.50".parse().unwrap()),
        };
        let v = serde_json::to_value(&row).unwrap();
        assert_eq!(v["actual_hours"], serde_json::json!("2.00"));
        assert_eq!(v["commission_percent"], serde_json::json!("12.50"));
    }

    #[test]
    fn internal_booking_defaults_the_missing_snapshot_fields() {
        // A booking service that has not deployed the commission/cancellation columns yet sends
        // neither field — the pre-pay must still parse (and treat both as absent → 0), instead of
        // failing the authoritative read and blocking every payment.
        let b: InternalBooking = serde_json::from_value(serde_json::json!({
            "customer_id": Uuid::nil(),
            "guard_id": null,
            "status": "accepted",
            "hours": 4,
            "base_fee": "500.00",
            "guard_count": 1,
            "tip": "0.00",
        }))
        .expect("old-shape booking still parses");
        assert!(b.commission_percent.is_none());
        assert!(b.cancellation_fee.is_none());
    }
}
