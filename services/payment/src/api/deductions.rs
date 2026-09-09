//! Platform-cut admin endpoints — stream ② *ยอดที่โดนหักเข้าระบบ*: generate the SCB Business Net
//! bulk-upload file that sweeps what the PLATFORM KEEPS out of the account that receives customer
//! money and into the company revenue account. THE MONEY PATH (deduction side). Admin-role gated.
//!
//! - `GET  /admin/deductions/preview` — the itemised cut for the window: a total per component
//!   (commission / retained cancellation fee / tip / unpaid multi-guard share / rounding), the
//!   BILLED-BUT-NEVER-COLLECTED total that is deducted from it, the job count, and the jobs EXCLUDED
//!   because their snapshot is incomplete, each with a Thai reason.
//! - `POST /admin/deductions/export` — build the file, PERSIST the batch + its per-job ledger (which
//!   marks those jobs swept), return the text as UTF-8 (no BOM) for download.
//! - `GET  /admin/deductions/batches` · `…/{id}` · `…/{id}/file` — history, drill-down, re-download.
//! - `POST …/{id}/status` · `…/{id}/void` · `…/{id}/items/void` — where the file got to at the bank,
//!   and the two escape hatches.
//!
//! # THE ONE THING TO GET RIGHT: what this file may and may not carry
//!
//! It sweeps the platform's cut ONLY — the commission deducted from the guard's pay, the
//! cancellation fee retained when a customer backs out, the tip, and the billed-but-unpaid share of
//! a multi-guard booking. It must NOT sweep VAT or the WHT withheld from guards: both are the
//! Revenue Department's money, sitting in the same bank account, remitted by e-filing (**ภ.พ.30**
//! monthly and **ภ.ง.ด.3/53** by the 7th of the following month) rather than by a transfer file.
//! Sweeping either would move the Revenue Department's money into company income and leave a tax
//! liability with no cash behind it. The arithmetic lives in
//! [`crate::domain::settlement::platform_cut`]; the two tax figures get REPORTS
//! (`/admin/reports/vat-register`, `/admin/reports/wht-payees`), never a file.
//!
//! It also carries only what was actually COLLECTED. The completion reconcile's `Extra` arm writes a
//! settled bill ABOVE the pre-payment and never captures the delta, so a cut priced off the settled
//! bill would transfer baht that never arrived — out of the very account that holds the two tax
//! liabilities above. [`crate::domain::settlement::JobSettlement::uncollected`] is deducted, and the
//! preview shows it on its own line rather than letting the cut silently shrink.
//!
//! # Structurally different from the other two streams, and the difference matters
//!
//! An `OAT` (own-account transfer) batch credits ONE destination — the company's own SCB account —
//! so the file carries a SINGLE `TXNDET` summing the whole sweep. The per-booking rows in
//! `deduction_batch_items` are the LEDGER backing that one credit line, not separate recipients.
//! Everything shaped by that: `recipient_count` is always 1, the preview reports a JOB count and
//! per-component totals rather than a recipient list, and the amount bound
//! ([`scb_export::transfer_bound_rejection`]) applies to the WHOLE sweep rather than per row — an
//! `OAT` line has effectively no bank ceiling, so only the operator's configured cap can bite, and
//! when it does the remedy is a NARROWER DAY WINDOW, which the error says.
//!
//! # Exclusion, not failure — and never a silent zero
//!
//! A settled job whose pricing snapshot is incomplete (a charge that predates migration 0005 or
//! 0013) CANNOT be priced: `subtotal = base_fee × hours × guards + tip` is one equation in four
//! unknowns, and booking's current row is not what the job was billed on. Such a job is EXCLUDED
//! with a reason and COUNTED, and is NOT marked swept — so it stays visible instead of quietly
//! contributing zero. A report that under-states the platform's cut is worse than one that says "N
//! jobs unknown"; see [`crate::domain::settlement::SnapshotGap`].

use axum::extract::{Path, Query, State};
use axum::response::Response;
use axum::Json;
use chrono::{NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;

use crate::api::payouts::{
    build_transfer_config, clean_note, file_download_response, mask_proxy, require_admin,
    require_scb_account, ListBatchesQuery,
};
use crate::domain::batch_status::{self, BatchStatus};
use crate::domain::deduction::{normalize_voided_payment_ids, DeductionSelection};
use crate::domain::scb_export::{
    self, format_amount, CreditDestination, PayoutBatch, PayoutRecipient, ScbProduct, WhtPayer,
};
use crate::domain::settlement::{self, JobSettlement};
use crate::models::{
    DeductionBatchDetail, DeductionBatchList, DeductionBatchRow, NewDeductionBatch,
    NewDeductionItem, PayoutConfigRow, SetDeductionBatchStatusRequest, SettledPaymentRow,
    VoidDeductionBatchItemsRequest, VoidDeductionBatchRequest,
};
use crate::profile_client::ProfileReader;
use crate::repo;
use crate::state::PaymentDeps;

/// The platform cut is stream ②, and it moves between two accounts the company owns — so this whole
/// module builds `OAT` files. The other two streams get their OWN files with their own product code:
/// one `BCHDET` carries exactly one product.
const DEDUCTION_PRODUCT: ScbProduct = ScbProduct::OwnAccount;

/// `HEADER` field 2 — our own system reference for a sweep file. Distinct from the payout's
/// (`PGUARD-PAYOUT`) and the refund's (`PGUARD-REFUND`) so a file recovered from a bank mailbox says
/// which stream it came from without being parsed.
const DEDUCTION_SYSTEM_REF: &str = "PGUARD-DEDUCT";

/// How many per-job ledger rows and how many exclusions the PREVIEW will list.
///
/// The other two previews are naturally bounded (one row per guard / per customer); this one is one
/// row per JOB, and a month of trading is thousands. The TOTALS are always computed over every row in
/// the window — only the visible list is cut, with a flag saying so — because a truncated total would
/// be a wrong number on a money screen, while a truncated list is just a screen.
const MAX_PREVIEW_ROWS: usize = 500;

// ----- preview + export shared aggregation -----

/// The `from`/`to` day window a preview may be narrowed to (both optional, inclusive, Thai days).
#[derive(Debug, Default, Deserialize)]
pub struct DeductionWindowQuery {
    pub from: Option<NaiveDate>,
    pub to: Option<NaiveDate>,
}

/// `POST /admin/deductions/export` body — ALL fields optional, and an absent body means "sweep the
/// whole unswept backlog".
///
/// There is no per-job tick-list, unlike the other two streams, and that is deliberate: an `OAT` file
/// credits one destination, so there is nobody to choose between, and letting an admin sweep half a
/// day's cut would leave the rest looking unswept for a reason nobody could reconstruct later.
#[derive(Debug, Default, Deserialize)]
pub struct ExportDeductionRequest {
    #[serde(default)]
    pub from: Option<NaiveDate>,
    #[serde(default)]
    pub to: Option<NaiveDate>,
    /// The batch's effective/value date. Omit for "today in Bangkok, rolled off a weekend"; set it to
    /// schedule a later settlement day or to step over a Thai public holiday (the platform has no
    /// holiday calendar). A PAST date is a 400 — SCB rejects a back-dated batch (doc §15.11).
    #[serde(default)]
    pub value_date: Option<NaiveDate>,
}

/// One job EXCLUDED from the sweep, with why. Its cut is NOT counted anywhere and it is NOT marked
/// swept — so it reappears in the next preview, still visible, rather than silently contributing 0.
#[derive(Debug, Serialize)]
pub struct ExcludedJob {
    pub payment_id: Uuid,
    pub booking_id: Uuid,
    /// Stable machine code ([`SnapshotGap::code`]) — the screen groups by it.
    pub code: &'static str,
    pub reason: &'static str,
}

/// One job's cut, as the preview lists it and as the export writes it.
struct AggregatedJob {
    payment_id: Uuid,
    booking_id: Uuid,
    settled_at: chrono::DateTime<Utc>,
    settlement: JobSettlement,
}

/// The aggregation result: every priceable job in the window, and the ones that could not be priced.
struct AggregatedCut {
    jobs: Vec<AggregatedJob>,
    excluded: Vec<ExcludedJob>,
}

impl AggregatedCut {
    /// Σ of one component across every priceable job — the preview's per-component totals and the
    /// figure an accountant checks the transfer against.
    fn total_of(&self, pick: impl Fn(&JobSettlement) -> Decimal) -> Decimal {
        self.jobs.iter().map(|j| pick(&j.settlement)).sum()
    }

    /// Σ of the whole cut — the single `TXNDET` amount the file transfers.
    fn total_cut(&self) -> Decimal {
        self.total_of(|s| s.platform_cut())
    }
}

/// Price every settled, unswept job in the window. PURE per row — the only I/O is the backlog read.
///
/// Both callers (preview AND export) use this one function precisely so they cannot disagree: an
/// admin reads the preview and then clicks export, and a preview describing a different set of jobs
/// than the export it precedes is its own money bug.
///
/// THE BACKLOG IS READ FROM THE PRIMARY — see [`repo::unswept_deduction_rows`] for why that is a
/// money requirement rather than a preference.
async fn aggregate<S: PaymentDeps>(
    state: &S,
    sel: &DeductionSelection,
) -> Result<AggregatedCut, AppError> {
    let rows = repo::unswept_deduction_rows(state.db(), sel).await?;
    let mut jobs = Vec::with_capacity(rows.len());
    let mut excluded = Vec::new();
    for row in rows {
        match settlement::split(&to_settled_payment(&row)) {
            Ok(settlement) => jobs.push(AggregatedJob {
                payment_id: row.payment_id,
                booking_id: row.booking_id,
                settled_at: row.settled_at,
                settlement,
            }),
            // A job we cannot price is REPORTED, never counted as zero. See the module doc.
            Err(gap) => excluded.push(ExcludedJob {
                payment_id: row.payment_id,
                booking_id: row.booking_id,
                code: gap.code(),
                reason: gap.reason_th(),
            }),
        }
    }
    Ok(AggregatedCut { jobs, excluded })
}

/// Map the stored row onto the pure split's input.
///
/// `wht_withheld` is deliberately ZERO here rather than joined from `payout_batch_items`: the WHT is
/// NOT part of the cut (it is the Revenue Department's, remitted by ภ.ง.ด. e-filing), and
/// [`JobSettlement::platform_cut`] never reads it — so joining a payout table onto the sweep's
/// backlog would add a table to the money path to compute a number this file must not use. The
/// cross-stream reconciliation that DOES need it passes the real figure in
/// (`GET /admin/reports/wht-payees` is where it is reported).
fn to_settled_payment(row: &SettledPaymentRow) -> settlement::SettledPayment {
    settlement::SettledPayment {
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
    }
}

/// The company account the sweep credits, validated the way a money file demands.
///
/// Checked in TWO places, exactly like the debit accounts: when the admin saves the setting (so they
/// find out on the settings screen) and again HERE (so a value stored before this check existed
/// cannot quietly produce a file the bank bounces). An `OAT` credit line may address only an SCB
/// account — 10 digits passing the §14 check digit — and a check-digit typo is BATCH-fatal: SCB
/// rejects the file after `deduction_batch_items` has marked every job in it swept.
fn revenue_account(cfg: &PayoutConfigRow) -> Result<String, AppError> {
    let account = cfg
        .revenue_account
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| {
            AppError::BadRequest(
                "ยังไม่ได้ตั้งค่าบัญชีรายได้บริษัท (ปลายทางของยอดหักเข้าระบบ) — แก้ไขที่หน้าตั้งค่าการจ่ายเงิน"
                    .to_string(),
            )
        })?;
    require_scb_account("บัญชีรายได้บริษัท", account)?;
    Ok(account.to_string())
}

// ----- preview -----

/// One job's cut as the preview lists it — every component itemised, so an accountant can see WHY a
/// job contributes what it does rather than only that it does.
#[derive(Debug, Serialize)]
pub struct PreviewCutJob {
    pub payment_id: Uuid,
    pub booking_id: Uuid,
    /// The Bangkok day the job was settled — the same basis the window filters on.
    pub settled_on: NaiveDate,
    pub commission: String,
    pub cancellation_fee: String,
    pub tip: String,
    pub unpaid_guard_share: String,
    pub rounding_adjustment: String,
    /// Billed and never collected — SUBTRACTED from `amount`. See [`DeductionPreview::uncollected_total`].
    pub uncollected: String,
    /// The job's total cut: the five components LESS `uncollected`. May be negative.
    pub amount: String,
}

/// The per-component totals of a sweep — what the file transfers, and what it is made of.
///
/// VAT and WHT are reported ALONGSIDE, clearly labelled as NOT swept, because the question an admin
/// asks this screen ("what happens to the money in the receiving account?") has three answers and
/// showing only one invites the other two to be swept by mistake later.
#[derive(Debug, Serialize)]
pub struct DeductionPreview {
    pub job_count: usize,
    /// What the file will actually TRANSFER: `billed_cut_total − uncollected_total`.
    pub total_amount: String,
    pub commission_total: String,
    pub cancellation_fee_total: String,
    pub tip_total: String,
    pub unpaid_guard_share_total: String,
    pub rounding_adjustment_total: String,
    /// Σ of the five components above — what the SETTLED BILLS earned, before asking whether the
    /// customer transferred it. Shown so `total_amount` visibly equals this minus
    /// [`Self::uncollected_total`] rather than the two differing for no reason on screen.
    pub billed_cut_total: String,
    /// **BILLED AND NEVER COLLECTED.** The completion reconcile's `Extra` arm records a settled bill
    /// above the pre-payment and captures nothing, so this much of the cut is not in the bank. It is
    /// DEDUCTED from `total_amount`, and it gets its own visible line precisely so an admin can see
    /// that billed-but-unpaid money exists — silently shrinking the cut would leave them reconciling
    /// a transfer against a number with no explanation.
    pub uncollected_total: String,
    /// Collected FOR the Revenue Department and remitted via ภ.พ.30 — shown so it is visible, and
    /// NOT part of `total_amount`.
    pub vat_not_swept: String,
    /// What is still owed to guards out of this window's jobs — also not swept (it leaves via the
    /// guard-payout file, stream ③).
    pub guard_income_not_swept: String,
    /// The jobs whose cut could not be computed, with a reason each. Capped at
    /// [`MAX_PREVIEW_ROWS`] rows; `excluded_count` is the true total.
    pub excluded: Vec<ExcludedJob>,
    pub excluded_count: usize,
    /// The per-job ledger, capped at [`MAX_PREVIEW_ROWS`] rows. The TOTALS above always cover every
    /// job in the window.
    pub jobs: Vec<PreviewCutJob>,
    pub jobs_truncated: bool,
    /// The destination, masked to its last 4 (an account number on a list screen is PII-adjacent).
    /// `None` when no revenue account is configured yet — the screen can then say so instead of the
    /// export being the first place an admin finds out.
    pub credit_account_masked: Option<String>,
}

/// GET /admin/deductions/preview — the itemised platform cut for the window, plus the jobs that could
/// not be priced. Read-only: computes but does NOT persist or mark anything swept. Admin only.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn preview<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(window): Query<DeductionWindowQuery>,
) -> Result<Json<ApiResponse<DeductionPreview>>, AppError> {
    require_admin(&user)?;
    let sel = DeductionSelection {
        from: window.from,
        to: window.to,
    };
    sel.validate()?;
    let cfg = repo::get_payout_config(state.db()).await?;
    let agg = aggregate(&state, &sel).await?;

    let jobs: Vec<PreviewCutJob> = agg
        .jobs
        .iter()
        .take(MAX_PREVIEW_ROWS)
        .map(|j| PreviewCutJob {
            payment_id: j.payment_id,
            booking_id: j.booking_id,
            settled_on: scb_export::bangkok_today(j.settled_at),
            commission: format_amount(j.settlement.commission),
            cancellation_fee: format_amount(j.settlement.cancellation_fee),
            tip: format_amount(j.settlement.tip),
            unpaid_guard_share: format_amount(j.settlement.unpaid_guard_share),
            rounding_adjustment: format_amount(j.settlement.rounding_adjustment),
            uncollected: format_amount(j.settlement.uncollected),
            amount: format_amount(j.settlement.platform_cut()),
        })
        .collect();

    Ok(Json(ApiResponse::success(DeductionPreview {
        job_count: agg.jobs.len(),
        total_amount: format_amount(agg.total_cut()),
        commission_total: format_amount(agg.total_of(|s| s.commission)),
        cancellation_fee_total: format_amount(agg.total_of(|s| s.cancellation_fee)),
        tip_total: format_amount(agg.total_of(|s| s.tip)),
        unpaid_guard_share_total: format_amount(agg.total_of(|s| s.unpaid_guard_share)),
        rounding_adjustment_total: format_amount(agg.total_of(|s| s.rounding_adjustment)),
        billed_cut_total: format_amount(agg.total_of(|s| s.billed_cut())),
        uncollected_total: format_amount(agg.total_of(|s| s.uncollected)),
        vat_not_swept: format_amount(agg.total_of(|s| s.vat)),
        guard_income_not_swept: format_amount(agg.total_of(|s| s.guard_income)),
        excluded_count: agg.excluded.len(),
        excluded: agg.excluded.into_iter().take(MAX_PREVIEW_ROWS).collect(),
        jobs_truncated: agg.jobs.len() > jobs.len(),
        jobs,
        credit_account_masked: cfg
            .revenue_account
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(mask_proxy),
    })))
}

// ----- export -----

/// POST /admin/deductions/export — build ONE SCB `OAT` upload file sweeping the platform's cut for
/// the window into the company revenue account, PERSIST the batch + its per-job ledger (which marks
/// those jobs swept), then return the file text as UTF-8 (no BOM) for download.
///
/// ONE credit line: an `OAT` batch has a single destination, so the file's one `TXNDET` carries the
/// SUM and the ledger rows explain it. The recipient NAME on that line is the company's own
/// (`/internal/org-settings`) — `TXNDET` field 13 is mandatory and a blank one fails the upload — but
/// the company TIN is NOT required: nothing is withheld here, so no `WHTCER`/`WHTDET` is emitted and
/// [`WhtPayer::none`] is the payer block. Requiring a ภ.ง.ด. setting before an admin can move the
/// company's own money between the company's own accounts would be a bug, not a safeguard.
///
/// 409 `DEDUCTION_ALREADY_SWEPT` if a concurrent export claimed a job; 409
/// `DEDUCTION_BATCH_REF_TAKEN` if ANY export — payout, refund or sweep — committed in the SAME
/// Bangkok second (the batch ref has one-second resolution and it is what the bank de-dups on; the
/// loser's whole transaction rolls back, marking nothing, and the admin simply clicks again). 400
/// when the window is invalid, `value_date` is in the past, there is nothing to sweep, the total is
/// not a positive transferable amount, or the debit/revenue account config is incomplete. Admin only.
#[tracing::instrument(skip(state, body), fields(user = %user.user_id))]
pub async fn export<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    body: Option<Json<ExportDeductionRequest>>,
) -> Result<Response, AppError> {
    require_admin(&user)?;
    let req = body.map(|Json(b)| b).unwrap_or_default();
    let sel = DeductionSelection {
        from: req.from,
        to: req.to,
    };
    sel.validate()?;

    // The value date is a THAI banking day: today in Asia/Bangkok rolled off a weekend, or the
    // admin's explicit pick (rejected when back-dated — doc §15.11).
    let now = Utc::now();
    let value_date = scb_export::resolve_value_date(req.value_date, now)?;

    let cfg = repo::get_payout_config(state.db()).await?;
    // DEBIT ACCOUNTS + FEE-CHARGE CODE ONLY, like the refund file: this batch withholds nothing, so
    // the ภ.ง.ด. codes can reach no record in it and refusing the run over one would be a bug.
    let config = build_transfer_config(&cfg, value_date)?;
    let credit_account = revenue_account(&cfg)?;
    let org = state.profile_reader().get_org_settings().await?;
    // `TXNDET` field 13 is the recipient name SCB prints on the credit, and it is mandatory. The
    // recipient here IS the company, so its name is the company's — sanitised the way that column is
    // validated (`validateTextWithSpecialChar`), and a name that sanitises to nothing is a typed 400
    // rather than a blank field that bounces the whole file.
    let company_name = org
        .company_name
        .as_deref()
        .map(|s| scb_export::sanitize_no_special_char(s, scb_export::MAX_NAME))
        .filter(|s| !s.is_empty())
        .ok_or_else(|| AppError::BadRequest("ยังไม่ได้ตั้งชื่อบริษัท (Settings → บริษัท)".to_string()))?;

    let agg = aggregate(&state, &sel).await?;
    if agg.jobs.is_empty() {
        return Err(AppError::BadRequest(
            "ไม่มีรายการที่ต้องหักเข้าระบบในช่วงนี้".to_string(),
        ));
    }
    let total_cut = agg.total_cut();

    // The DESTINATION and the AMOUNT are checked before anything is written, both as pure
    // predicates. A rejected file arrives AFTER the jobs in it are marked swept, so an out-of-bounds
    // or mis-addressed line must stop the run rather than ride it.
    let destination = CreditDestination::scb_account(credit_account.clone());
    if let Some(reason) = scb_export::destination_rejection(DEDUCTION_PRODUCT, &destination) {
        return Err(AppError::BadRequest(reason));
    }
    // The bound applies to the WHOLE sweep, because the whole sweep is one credit line — and it is
    // ALSO where the per-job signedness stops: individual jobs may net down (a rounding drift, or a
    // bill that was never collected), but the FILE has to carry a real, positive, transferable
    // amount. SCB's own ceiling for an account credit is effectively unlimited, so above the minimum
    // only the operator's configured cap can bite.
    //
    // The appended sentence is split because the two ends have OPPOSITE remedies and one wrong hint
    // sends an admin round in circles: too BIG wants a narrower window; too SMALL means this window's
    // cut nets to nothing (the uncollected extras and the rounding drift cancelled it out), and a
    // narrower window would only make it smaller — a WIDER one, or simply waiting for more settled
    // jobs, is the answer.
    if let Some(reason) =
        scb_export::transfer_bound_rejection(&destination, total_cut, cfg.max_transfer_per_txn)
    {
        let hint = if total_cut > Decimal::ZERO {
            "ลองแบ่งช่วงวันที่ให้สั้นลง"
        } else {
            "ยอดหักของช่วงนี้หักลบกันแล้วไม่เหลือเป็นบวก (มีงานที่ตั้งบิลแล้วเก็บเงินไม่ได้ หรือมีเศษปัดลบ) \
             — ลองขยายช่วงวันที่ หรือรอให้มีงานปิดยอดเพิ่ม"
        };
        return Err(AppError::BadRequest(format!(
            "{reason} — ยอดหักรวมของช่วงที่เลือกคือ {} บาท {hint}",
            format_amount(total_cut)
        )));
    }

    // The two references are DIFFERENT things: `batch_ref` is the bare 12-digit Bangkok timestamp
    // (capped at 12 chars) and `file_ref` is `batchRef & productCode` — `…OAT` here, which is what
    // distinguishes a sweep from the two PromptPay streams stamped in the same second.
    let batch_ref = scb_export::batch_ref(now);
    let file_ref = scb_export::file_ref(&batch_ref, DEDUCTION_PRODUCT);

    let batch = PayoutBatch {
        file_ref: file_ref.clone(),
        system_ref: DEDUCTION_SYSTEM_REF.to_string(),
        batch_ref: batch_ref.clone(),
        product: DEDUCTION_PRODUCT,
        // No transaction purpose is configured, so `TXNDET` field 7 stays blank (SCB passes it
        // straight through for `OAT` — doc line 2035).
        service_type_code: String::new(),
        // NO ภ.ง.ด. PAYER — `wht` is 0 on the single recipient, so no `WHTCER`/`WHTDET` is emitted
        // and this block reaches no record in the file. See `WhtPayer::none`.
        payer: WhtPayer::none(),
        config: config.clone(),
        // EXACTLY ONE recipient: the company's own revenue account, credited with the summed cut.
        // The per-job ledger below is what explains this single line.
        recipients: vec![PayoutRecipient {
            transaction_ref: scb_export::transaction_ref(
                scb_export::TXN_REF_PREFIX_DEDUCTION,
                &batch_ref,
                1,
            ),
            destination,
            // No certificate, so no recipient TIN is written anywhere.
            tax_id: String::new(),
            name: company_name,
            address: org.address.clone().unwrap_or_default(),
            income: total_cut,
            // The company does not withhold tax from itself.
            wht: Decimal::ZERO,
            // No SMS and no e-mail: SCB bills per SMS, and the "recipient" is our own account.
            phone: None,
            email: None,
        }],
    };
    let file_text = scb_export::generate(&batch);

    // Persist the batch + the per-job ledger + the FILE TEXT + the shared reference reservation + the
    // money-audit row, in ONE transaction (the partial UNIQUE(payment_id) WHERE voided_at IS NULL is
    // the atomic double-sweep guard).
    //
    // Storing the text is what makes this reversible: the response below is streamed exactly once, so
    // without it a failed download / closed tab / proxy timeout would leave these jobs marked swept
    // forever with no copy of the file meant to sweep them. Now the batch can be re-downloaded from
    // `/admin/deductions/batches/{id}/file` and, if the upload never lands, voided — which returns
    // every job in it to the sweepable backlog.
    repo::insert_deduction_batch(
        state.db(),
        &NewDeductionBatch {
            file_ref,
            system_ref: batch.system_ref.clone(),
            batch_ref,
            value_date: config.value_date,
            total_amount: total_cut,
            credit_account,
            file_text: file_text.clone(),
            created_by: Some(user.user_id),
            items: agg
                .jobs
                .iter()
                .map(|j| NewDeductionItem {
                    payment_id: j.payment_id,
                    booking_id: j.booking_id,
                    commission: j.settlement.commission,
                    cancellation_fee: j.settlement.cancellation_fee,
                    tip: j.settlement.tip,
                    unpaid_guard_share: j.settlement.unpaid_guard_share,
                    rounding_adjustment: j.settlement.rounding_adjustment,
                    // Billed and never collected — SUBTRACTED from `amount` by the pure split, and
                    // stored so the ledger can still explain a total that is smaller than its own
                    // five components (migration 0014's CHECK enforces the arithmetic).
                    uncollected: j.settlement.uncollected,
                    amount: j.settlement.platform_cut(),
                })
                .collect(),
        },
    )
    .await?;

    Ok(file_download_response(&batch.file_ref, file_text))
}

// ----- batch history · re-download · lifecycle -----

/// GET /admin/deductions/batches — the sweep history, newest first, with the total count for paging.
/// Header rows only: the stored file text is served by its own endpoint. Admin only.
///
/// PRIMARY, not the replica: the admin lands here seconds after an export, usually because the
/// download went wrong, and a replica-lagged list that does not yet show the batch they just
/// generated would send them to re-export.
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn list_batches<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<ListBatchesQuery>,
) -> Result<Json<ApiResponse<DeductionBatchList>>, AppError> {
    require_admin(&user)?;
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);
    let page = repo::list_deduction_batches(state.db(), limit, offset).await?;
    Ok(Json(ApiResponse::success(page)))
}

/// GET /admin/deductions/batches/{id} — one sweep header + every job it collected (an item showing
/// `voided_at` is back in the sweepable backlog). Admin only. PRIMARY read, for the same
/// read-after-write reason as the history list.
#[tracing::instrument(skip(state), fields(user = %user.user_id, batch = %batch_id))]
pub async fn get_batch<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
) -> Result<Json<ApiResponse<DeductionBatchDetail>>, AppError> {
    require_admin(&user)?;
    let detail = repo::get_deduction_batch(state.db(), batch_id).await?;
    Ok(Json(ApiResponse::success(detail)))
}

/// GET /admin/deductions/batches/{id}/file — re-download the STORED file text, byte for byte, with
/// the same content type and filename the export served. Admin only.
///
/// Read from the PRIMARY, not the replica: an admin whose download failed retries within seconds of
/// the export that wrote it. The text is never REGENERATED — the backlog has moved on since, so a
/// regenerated file would differ under the same batch ref.
#[tracing::instrument(skip(state), fields(user = %user.user_id, batch = %batch_id))]
pub async fn get_batch_file<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
) -> Result<Response, AppError> {
    require_admin(&user)?;
    let file = repo::get_deduction_batch_file(state.db(), batch_id).await?;
    Ok(file_download_response(&file.file_ref, file.file_text))
}

/// POST /admin/deductions/batches/{id}/status — record where the file got to at the bank
/// (`uploaded` → `confirmed` | `rejected`). Admin only. Illegal steps are a typed Thai 409 from the
/// shared pure transition table.
///
/// `voided` is the ONE value rejected here by name (400), because it is the one the transition table
/// would otherwise WAVE THROUGH: voiding must also release every job in the batch — that is what
/// returns them to the backlog — and must carry a reason, so it has its own endpoint. Coming through
/// this door it would flip the header while leaving the jobs claimed, i.e. never sweepable again.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, batch = %batch_id))]
pub async fn set_batch_status<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
    Json(req): Json<SetDeductionBatchStatusRequest>,
) -> Result<Json<ApiResponse<DeductionBatchRow>>, AppError> {
    require_admin(&user)?;
    let Some(status) = BatchStatus::parse(req.status.trim()) else {
        return Err(AppError::BadRequest(format!(
            "สถานะไม่ถูกต้อง — ต้องเป็นหนึ่งใน {}",
            batch_status::BATCH_STATUSES.join(", ")
        )));
    };
    if status == BatchStatus::Voided {
        return Err(AppError::BadRequest(
            "การยกเลิกไฟล์ต้องใช้ปุ่มยกเลิก (ระบุเหตุผล) เพื่อให้รายการกลับเข้าคิวรอหักเข้าระบบ".to_string(),
        ));
    }
    let note = match req.note.as_deref() {
        Some(n) => clean_note("หมายเหตุ", n, false)?,
        None => None,
    };
    let row = repo::set_deduction_batch_status(
        state.db(),
        batch_id,
        status,
        note.as_deref(),
        user.user_id,
    )
    .await?;
    Ok(Json(ApiResponse::success(row)))
}

/// POST /admin/deductions/batches/{id}/void — cancel a sweep that never reached the bank (or that the
/// bank refused) and RETURN every job in it to the sweepable backlog. Admin only.
///
/// The escape hatch from the one-way door: without it, a batch whose file was lost would leave its
/// jobs permanently marked swept — cut recorded as collected with no money moved — and only a
/// hand-written UPDATE in production could undo it. The reason is mandatory. A batch the bank
/// CONFIRMED cannot be voided (the money moved — releasing its jobs would sweep the same cut twice);
/// a second void is a typed 409, not a silent success.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, batch = %batch_id))]
pub async fn void_batch<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
    Json(req): Json<VoidDeductionBatchRequest>,
) -> Result<Json<ApiResponse<DeductionBatchRow>>, AppError> {
    require_admin(&user)?;
    let Some(reason) = clean_note("เหตุผลในการยกเลิก", &req.reason, true)?
    else {
        // `clean_note(.., required = true)` already returned the 400 for a blank reason; this arm is
        // unreachable and is written as an error rather than an `expect` (no panics in the money path).
        return Err(AppError::BadRequest("กรุณาระบุเหตุผลในการยกเลิก".to_string()));
    };
    let row = repo::void_deduction_batch(state.db(), batch_id, user.user_id, &reason).await?;
    Ok(Json(ApiResponse::success(row)))
}

/// POST /admin/deductions/batches/{id}/items/void — return SOME of a sweep's jobs to the sweepable
/// backlog, leaving every other job in the file collected and the batch's own status untouched.
/// Admin only.
///
/// WHY THIS IS SEPARATE FROM THE WHOLE-BATCH VOID. The trigger is not a failed credit line — an
/// `OAT` file has ONE line, which the bank takes or does not — it is a job that should never have
/// been collected: a settled row later found to be wrong, or a sweep run over a window an admin did
/// not mean. The whole-batch void would release every OTHER job in the file too.
///
/// **A CONFIRMED SWEEP IS REFUSED HERE (409 `DEDUCTION_BATCH_CONFIRMED`), and that is the OPPOSITE of
/// the other two streams.** Their files carry one credit line per RECIPIENT, so an individual
/// PromptPay credit can genuinely bounce inside a file the bank accepted, and releasing that one item
/// is right. This file carries one credit line for the WHOLE batch, so `confirmed` means the entire
/// summed amount moved into the revenue account — releasing a job would let its cut be swept a second
/// time, which is real double-movement of company money. The Thai error names the two correct
/// remedies: a whole-batch void if the money truly did not move, or a manual accounting adjustment if
/// it did. See [`repo::void_deduction_batch_items`] for the full asymmetry note.
///
/// On every non-terminal status it still DELIBERATELY BYPASSES the transition table: the status
/// machine describes what happened to the FILE at the bank (still true), while this corrects which
/// JOBS the file is considered to have collected. The reason is mandatory and the audit row records
/// the released amount — the figure that ties this file's stated total to the next sweep's.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, batch = %batch_id))]
pub async fn void_batch_items<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
    Json(req): Json<VoidDeductionBatchItemsRequest>,
) -> Result<Json<ApiResponse<DeductionBatchDetail>>, AppError> {
    require_admin(&user)?;
    // Pure validation first (non-empty, capped, de-duplicated) — no DB round trip for a client bug.
    let payment_ids = normalize_voided_payment_ids(&req.payment_ids)?;
    let Some(reason) = clean_note("เหตุผลในการดึงรายการกลับ", &req.reason, true)?
    else {
        // Unreachable — `clean_note(.., required = true)` already 400'd a blank reason. An error
        // rather than an `expect`: no panics in the money path.
        return Err(AppError::BadRequest(
            "กรุณาระบุเหตุผลในการดึงรายการกลับ".to_string(),
        ));
    };
    let detail =
        repo::void_deduction_batch_items(state.db(), batch_id, &payment_ids, user.user_id, &reason)
            .await?;
    Ok(Json(ApiResponse::success(detail)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::settlement::{SettledPayment, SnapshotGap};

    /// `1234567896` passes SCB's §14 check digit; `1234567890` — the same number with the check
    /// digit typo'd — does not.
    const GOOD_ACCOUNT: &str = "1234567896";
    /// A DIFFERENT real SCB account, so the revenue destination is not accidentally the debit one.
    const GOOD_REVENUE_ACCOUNT: &str = "4051234567";

    fn cfg(revenue: Option<&str>) -> PayoutConfigRow {
        PayoutConfigRow {
            debit_account: Some(GOOD_ACCOUNT.to_string()),
            revenue_account: revenue.map(str::to_string),
            ..PayoutConfigRow::unset()
        }
    }

    fn d(s: &str) -> Decimal {
        s.parse().expect("decimal literal")
    }

    /// THE DESTINATION GATE. An `OAT` line may credit only an SCB account that passes the §14 check
    /// digit, and the failure mode is BATCH-fatal: the bank rejects the file after every job in it
    /// was marked swept. So it is refused at save time AND here, and an unset account is an
    /// actionable Thai 400 rather than a blank field on a money file.
    #[test]
    fn the_sweep_refuses_to_run_without_a_real_scb_revenue_account() {
        assert_eq!(
            revenue_account(&cfg(Some(GOOD_REVENUE_ACCOUNT))).expect("a real SCB account"),
            GOOD_REVENUE_ACCOUNT
        );
        // Unset, blank, and every near-miss shape a typo produces.
        for bad in [None, Some(""), Some("   ")] {
            assert!(revenue_account(&cfg(bad)).is_err(), "{bad:?}");
        }
        for typo in ["1234567890", "405123456", "40512345670", "abcdefghij"] {
            assert!(
                revenue_account(&cfg(Some(typo))).is_err(),
                "{typo} is not a 10-digit SCB account that passes the check digit"
            );
        }
    }

    /// The product/destination pair must AGREE, and the pure predicate is what says so. An `OAT`
    /// batch cannot carry a PromptPay proxy and a `PPY` batch cannot carry an account number — either
    /// mismatch emits a well-formed record addressed at nothing.
    #[test]
    fn only_an_scb_account_may_ride_the_own_account_file() {
        let good = CreditDestination::scb_account(GOOD_REVENUE_ACCOUNT);
        assert_eq!(
            scb_export::destination_rejection(DEDUCTION_PRODUCT, &good),
            None
        );
        // The credit line addresses the account itself — no proxy type, and SCB's own bank code.
        assert_eq!(good.proxy_type_code(), None);
        assert_eq!(good.clearing_code(), scb_export::BANK_CODE_SCB);
        // A PromptPay proxy on an OAT file is refused with a reason naming the rule.
        let proxy = CreditDestination::promptpay("0812345678");
        assert!(scb_export::destination_rejection(DEDUCTION_PRODUCT, &proxy).is_some());
    }

    /// The AMOUNT bound applies to the WHOLE sweep, because the whole sweep is ONE credit line. SCB's
    /// own ceiling for an account credit is effectively unlimited, so only the operator's configured
    /// cap can bite — and a sweep of ฿0.00 (or a negative net) must never be written as a credit row.
    #[test]
    fn the_whole_sweep_is_one_credit_line_and_it_is_bounded_as_one() {
        let dest = CreditDestination::scb_account(GOOD_REVENUE_ACCOUNT);
        // Below SCB's ฿0.01 minimum — a window whose cut nets to nothing must not produce a file.
        for empty in ["0", "-2.50"] {
            assert!(
                scb_export::transfer_bound_rejection(&dest, d(empty), None).is_some(),
                "{empty} is not a transferable credit amount"
            );
        }
        // An amount that would exceed a PromptPay proxy's ฿2,000,000 ceiling is perfectly fine on an
        // own-account transfer — which is the whole reason the bound hangs off the DESTINATION.
        assert_eq!(
            scb_export::transfer_bound_rejection(&dest, d("5000000.00"), None),
            None
        );
        // …but the operator's own cap still tightens it.
        assert!(
            scb_export::transfer_bound_rejection(&dest, d("5000000.00"), Some(d("2000000")))
                .is_some()
        );
    }

    /// THE FILE SHAPE, assembled the way `export` assembles it: MANY jobs, ONE credit line.
    ///
    /// This is the structural claim the whole stream rests on and it is asserted on the RENDERED
    /// TEXT, not on the struct: an `OAT` batch credits one destination, so the ledger's job count and
    /// the file's credit count are different numbers, and a refactor that "fixed" the file to emit
    /// one line per job would produce a valid-looking file that credits the company account N times.
    /// It also pins the two things a sweep must never carry: a WHT certificate (the company does not
    /// withhold tax from itself) and a proxy type (field 3 is blank for every non-PromptPay product).
    #[test]
    fn many_jobs_become_exactly_one_credit_line_carrying_their_summed_cut() {
        let batch_ref = "050926120000";
        let total = d("200.00") + d("100.00") + d("2000.00"); // three jobs' cuts
        let batch = PayoutBatch {
            file_ref: scb_export::file_ref(batch_ref, DEDUCTION_PRODUCT),
            system_ref: DEDUCTION_SYSTEM_REF.to_string(),
            batch_ref: batch_ref.to_string(),
            product: DEDUCTION_PRODUCT,
            service_type_code: String::new(),
            payer: WhtPayer::none(),
            config: crate::domain::scb_export::PayoutConfig {
                debit_account: GOOD_ACCOUNT.to_string(),
                fee_debit_account: GOOD_ACCOUNT.to_string(),
                fee_charge_code: "OUR".to_string(),
                value_date: NaiveDate::from_ymd_opt(2026, 9, 5).expect("valid date"),
                wht_form_type_code: "53".to_string(),
                wht_pay_type_code: "1".to_string(),
                wht_income_type_code: "5".to_string(),
                wht_income_desc: "ค่าบริการรักษาความปลอดภัย".to_string(),
                wht_rate_percent: d("3"),
            },
            recipients: vec![PayoutRecipient {
                transaction_ref: scb_export::transaction_ref(
                    scb_export::TXN_REF_PREFIX_DEDUCTION,
                    batch_ref,
                    1,
                ),
                destination: CreditDestination::scb_account(GOOD_REVENUE_ACCOUNT),
                tax_id: String::new(),
                name: "PGuard Revenue".to_string(),
                address: "1 Sathorn Rd, Bangkok 10120".to_string(),
                income: total,
                wht: Decimal::ZERO,
                phone: None,
                email: None,
            }],
        };
        let out = scb_export::generate(&batch);
        let lines: Vec<&str> = out.split("\r\n").collect();

        assert_eq!(lines.len(), 4, "HEADER + BCHDET + ONE TXNDET + TRAILR");
        assert_eq!(lines[0], "HEADER|050926120000OAT|PGUARD-DEDUCT");
        // BCHDET: the product, the value date, the debit accounts, the TOTAL and a credit count of 1.
        assert_eq!(
            lines[1],
            "BCHDET|050926120000|OAT|20260905|1234567896|1234567896|2300.00|1||"
        );
        let txn: Vec<&str> = lines[2].split('|').collect();
        assert_eq!(txn[0], "TXNDET");
        assert_eq!(txn[1], "DD0509261200000001", "the sweep's own ref prefix");
        assert_eq!(txn[2], GOOD_REVENUE_ACCOUNT, "the company revenue account");
        assert_eq!(txn[3], "", "no proxy type — this is not PromptPay");
        assert_eq!(txn[4], "014", "SCB's own bank code");
        assert_eq!(txn[5], "0111", "the OAT branch code, not PPY's 0000");
        assert_eq!(txn[6], "2300.00", "ONE line carrying every job's cut");
        assert_eq!(lines[3], "TRAILR|1|1|2300.00");
        // No certificate: the company does not withhold tax from itself.
        assert!(!out.contains("WHTCER") && !out.contains("WHTDET"));
        // The three streams' transaction refs cannot collide even off the same one-second clock.
        for other in [
            scb_export::TXN_REF_PREFIX_PAYOUT,
            scb_export::TXN_REF_PREFIX_REFUND,
        ] {
            assert_ne!(
                scb_export::transaction_ref(scb_export::TXN_REF_PREFIX_DEDUCTION, batch_ref, 1),
                scb_export::transaction_ref(other, batch_ref, 1)
            );
        }
    }

    /// A job that cannot be priced is EXCLUDED with a reason and is NOT swept — the one behaviour
    /// that keeps the report from silently under-stating the platform's cut.
    #[test]
    fn an_incomplete_snapshot_excludes_the_job_rather_than_counting_it_as_zero() {
        let worked = SettledPayment {
            amount: d("2140.00"),
            overpaid: Decimal::ZERO,
            final_amount: Some(d("2140.00")),
            refund_amount: None,
            subtotal: Some(d("2000.00")),
            vat_amount: Some(d("140.00")),
            cancelled: false,
            base_fee: Some(d("500")),
            booked_hours: Some(4),
            guard_count: Some(1),
            tip: Some(Decimal::ZERO),
            commission_amount: Some(d("200.00")),
            actual_hours: Some(d("4.00")),
            wht_withheld: Decimal::ZERO,
        };
        let priced = settlement::split(&worked).expect("a complete snapshot prices");
        assert_eq!(priced.platform_cut(), d("200.00"));

        // Drop the one column migration 0013 added for the commission and it becomes unpriceable —
        // NOT a ฿0 cut, which would look identical on a total and be wrong by ฿200.
        let mut stale = worked.clone();
        stale.commission_amount = None;
        let gap = settlement::split(&stale).expect_err("an incomplete snapshot must not price");
        assert_eq!(gap, SnapshotGap::NoPricingSnapshot);
        assert_eq!(gap.code(), "NO_PRICING_SNAPSHOT");
        assert!(
            gap.reason_th().contains("ไม่นำมารวมในไฟล์"),
            "the admin is told it was left out: {}",
            gap.reason_th()
        );
    }
}
