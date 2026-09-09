//! Guard-payout admin endpoints — generate the SCB Business Net bulk-upload file (PromptPay credit
//! + ภ.ง.ด.53 WHT) that pays guards. THE MONEY PATH (payout side). Admin-role gated.
//!
//! - `GET /admin/payouts/config` — the single-row payout settings (debit accounts + WHT terms).
//! - `PUT /admin/payouts/config` — save them (incremental).
//! - `GET /admin/payouts/preview` — the unpaid backlog aggregated per guard (who gets paid what) +
//!   the guards EXCLUDED, each with a Thai reason. Optional `from`/`to` day window.
//! - `POST /admin/payouts/export` — build the file, PERSIST the batch (marking those bookings paid),
//!   return the text as UTF-8 (no BOM) for download. Optional body selects WHICH guards (and which
//!   day window) to pay and may pin the value date; no body = the whole unpaid backlog, every
//!   payable guard, dated the next Bangkok business day.
//! - `GET /admin/payouts/batches` · `…/{id}` · `…/{id}/file` — the history of generated files, one
//!   batch's drill-down, and the RE-DOWNLOAD of the stored text.
//! - `POST …/{id}/status` · `…/{id}/void` — where the file got to at the bank, and the escape hatch.
//! - `POST …/{id}/items/void` — the PER-ITEM release, for an individual PromptPay credit that
//!   BOUNCED at the bank while the file as a whole succeeded: it returns just those bookings to the
//!   payable backlog and leaves every other guard in the batch paid.
//!
//! THE ONE-WAY DOOR, AND WHY THESE LAST SIX EXIST. The export commits the per-booking paid-markers
//! and then streams the file exactly once. When that was ALL it did, a failed download, a closed
//! tab, a proxy timeout or an SCB rejection left those bookings marked paid forever with no copy of
//! the file that was meant to pay them — the guards silently never got paid for that work and the
//! only remedy was a hand-written DELETE in production. So the export now STORES the file text, the
//! batch carries a status through the bank, and a VOID returns bookings to the payable backlog —
//! the whole file, or just the credit lines the bank bounced. (Deliberately NOT a draft/confirm
//! handshake: that trades this bug for a stuck draft whose bookings are neither paid nor payable
//! when the client dies mid-flow.)
//!
//! ONE file pays MANY guards: the aggregation groups the backlog per guard, and the SCB writer emits
//! one `TXNDET` (+ a `WHTCER`/`WHTDET` certificate pair) per guard inside a single `BCHDET` batch.
//! Narrowing the selection only narrows WHO is in the file — the per-booking paid-markers are written
//! from the SAME filtered rows, so a guard left unticked stays unpaid and simply shows up in the next
//! run.
//!
//! EXCLUSION, NOT FAILURE, is the rule for one bad guard: a missing profile, missing PII, or an
//! amount outside SCB's per-transaction bounds takes THAT guard out of the batch with a reason the
//! admin can act on. One broken profile must never fail the payroll for everyone, and an
//! out-of-bounds line must never reach the bank (SCB rejects the whole file — by which time these
//! bookings are already marked paid).
//!
//! The aggregation reads the authoritative `base_fee` per booking from booking's internal read, the
//! guard PII + the company WHT-payer block from profile's internal reads, and computes the payout
//! with the pure [`crate::domain::payout`] math + the pure [`crate::domain::scb_export`] file writer.

use axum::extract::{Path, Query, State};
use axum::http::header;
use axum::response::{IntoResponse, Response};
use axum::Json;
use chrono::{NaiveDate, Utc};
use futures::stream::{StreamExt, TryStreamExt};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;

use crate::booking_client::BookingReader;
use crate::domain::batch_status::{self, BatchStatus};
use crate::domain::payout::{compute_payout, normalize_voided_booking_ids, PayoutSelection};
use crate::domain::promptpay::{classify_proxy, PromptPayProxy};
use crate::domain::scb_export::{
    self, format_amount, CreditDestination, PayoutBatch, PayoutConfig, PayoutRecipient, ScbProduct,
    WhtPayer,
};
use crate::domain::thai_id;
use crate::models::{
    InternalBooking, NewPayoutBatch, NewPayoutItem, PayoutBatchDetail, PayoutBatchList,
    PayoutBatchRow, PayoutConfigRow, SetPayoutBatchStatusRequest, UpdatePayoutConfigRequest,
    VoidPayoutBatchItemsRequest, VoidPayoutBatchRequest,
};
use crate::profile_client::{GuardPayoutProfile, OrgTaxInfo, ProfileReader};
use crate::repo;
use crate::state::PaymentDeps;

/// Guard payout is stream ③ *ยอดที่โอนให้ รปภ*, and it pays by PromptPay — so this whole module builds
/// `PPY` files. The other two streams (customer refunds, the platform-cut sweep) get their OWN files
/// with their own product code: one `BCHDET` carries exactly one product.
const PAYOUT_PRODUCT: ScbProduct = ScbProduct::PromptPay;

pub(crate) fn require_admin(user: &AuthUser) -> Result<(), AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
    }
    Ok(())
}

/// Reject a company debit account that is not a real SCB account number, in Thai and naming WHICH
/// field is wrong (`label`).
///
/// `BCHDET` fields 4 and 5 are both mandatory and both validated with
/// `ValidateTextFormatSCBAccount(…, 10, 10)` (doc line 1847) — a 9- or 11-digit account, or a
/// 10-digit one with a single transposed digit, fails the check digit (`SCB_CHECK_DIGIT`, doc line
/// 729) and SCB rejects the batch HEADER before it reads a single transaction. That is the single
/// most likely typo in the whole payout config and it is BATCH-fatal: by the time the bank bounces
/// the file, `payout_batch_items` has already marked every booking in it paid.
pub(crate) fn require_scb_account(label: &str, account: &str) -> Result<(), AppError> {
    if scb_export::is_valid_scb_account(account) {
        return Ok(());
    }
    // The message must work on BOTH screens that can hit it (saving the config, and generating a
    // file from a config saved earlier), so it points at the setting rather than at "save again".
    Err(AppError::BadRequest(format!(
        "{label}ไม่ถูกต้อง — ต้องเป็นเลขบัญชี SCB 10 หลักที่ผ่านการตรวจเลขหลักสุดท้าย \
         (ถ้าพิมพ์สลับหลักธนาคารจะตีกลับทั้งไฟล์) — แก้ไขที่หน้าตั้งค่าการจ่ายเงิน"
    )))
}

/// Validate the company ACCOUNTS a `PUT /admin/payouts/config` actually CARRIES.
///
/// All three are SCB account numbers and all three are batch-fatal if mistyped: the two debit
/// accounts head the FILE (`BCHDET` fields 4/5) and the revenue account is the platform-cut sweep's
/// sole credit destination (`TXNDET` field 2 of an `OAT` line, which may address no other bank). A
/// typo costs the whole batch rather than one recipient, and the bank finds it AFTER the rows in the
/// file were marked settled — so catching it on the settings screen is the only cheap moment.
///
/// Only a field PRESENT in the request is checked: the PUT is a COALESCE-merge (an absent field
/// keeps the stored value), so validating `None` would break every incremental save. A blank string
/// is left alone too — that is how a field is cleared, and an unset account is already a typed 400 at
/// export time. Pure.
fn validate_config_accounts(req: &UpdatePayoutConfigRequest) -> Result<(), AppError> {
    for (label, value) in [
        ("บัญชีตัดเงินบริษัท", req.debit_account.as_deref()),
        ("บัญชีตัดค่าธรรมเนียม", req.fee_debit_account.as_deref()),
        ("บัญชีรายได้บริษัท", req.revenue_account.as_deref()),
    ] {
        if let Some(account) = value.map(str::trim).filter(|s| !s.is_empty()) {
            require_scb_account(label, account)?;
        }
    }
    Ok(())
}

// ----- the four SCB master-data codes, validated in ONE place -----
//
// Each of these lands VERBATIM in the file (three on every `WHTCER`/`WHTDET`, one on every
// `TXNDET`), and each is a picklist key SCB resolves against a `Master_data` table — so a value
// outside the table is not "unusual", it is a file the bank refuses. They are checked in two places
// on purpose: when the admin SAVES (so they find out on the settings screen), and again when a file
// is BUILT (so a value stored before the check existed cannot quietly produce a rejected batch).
// Pure, so both callers share exactly one rule per field.

/// `WHTCER` field 13 — the ภ.ง.ด. form code (`Master_data!TBWHTType`, doc lines 142-155).
fn require_wht_form_type(code: &str) -> Result<(), AppError> {
    if scb_export::is_valid_wht_form_type_code(code) {
        return Ok(());
    }
    Err(AppError::BadRequest(format!(
        "รหัสแบบ ภ.ง.ด. ไม่ถูกต้อง — ต้องเป็นหนึ่งใน {} (ภ.ง.ด.3 = 04 สำหรับบุคคลธรรมดา, ภ.ง.ด.53 = 53 สำหรับนิติบุคคล)",
        scb_export::WHT_FORM_TYPE_CODES.join(", ")
    )))
}

/// `WHTCER` field 15 — the WHT pay-type code (`Master_data!TBWHTPayType`, doc lines 157-166).
///
/// Two DIFFERENT refusals, and the messages must stay distinct: a code outside the table is a typo,
/// while `4` (อื่นๆ) is a real SCB choice we cannot honour — it requires the free-text pay-type
/// remark on `WHTCER` field 16 (`ValidWHTMandatory`, doc line 2582) and pguard models no such field,
/// so a `4` would ship a certificate the bank rejects AFTER the bookings were marked paid. Telling
/// the admin "not supported yet" is honest; telling them "invalid" would send them hunting a typo
/// that is not there.
fn require_wht_pay_type(code: &str) -> Result<(), AppError> {
    if code.trim() == scb_export::WHT_PAY_TYPE_CODE_OTHER {
        return Err(AppError::BadRequest(
            "ยังไม่รองรับผู้จ่ายเงินแบบ \"อื่นๆ\" (รหัส 4) — ธนาคารบังคับให้ระบุหมายเหตุกำกับ ซึ่งระบบยังไม่มีช่องให้กรอก \
             กรุณาเลือก 1 (ผู้จ่ายออกครั้งเดียว), 2 (ออกให้ตลอดไป) หรือ 3 (หักภาษี ณ ที่จ่าย)"
                .to_string(),
        ));
    }
    if scb_export::is_valid_wht_pay_type_code(code) {
        return Ok(());
    }
    Err(AppError::BadRequest(format!(
        "รหัสผู้จ่ายเงิน (WHT pay type) ไม่ถูกต้อง — ต้องเป็นหนึ่งใน {}",
        scb_export::WHT_PAY_TYPE_CODES.join(", ")
    )))
}

/// `WHTDET` field 1 — the assessable-income type (`Master_data!TBIncomeType`, doc lines 167-190).
fn require_wht_income_type(code: &str) -> Result<(), AppError> {
    if scb_export::is_valid_wht_income_type_code(code) {
        return Ok(());
    }
    Err(AppError::BadRequest(format!(
        "รหัสประเภทเงินได้ไม่ถูกต้อง — ต้องเป็นหนึ่งใน {} (ค่าบริการ รปภ. คือ 5)",
        scb_export::WHT_INCOME_TYPE_CODES.join(", ")
    )))
}

/// `TXNDET` field 8 — who bears the transfer fee (`Master_data!TBFeeOther`, doc line 314).
fn require_fee_charge_code(code: &str) -> Result<(), AppError> {
    if scb_export::is_valid_fee_charge_code(code) {
        return Ok(());
    }
    Err(AppError::BadRequest(
        "รหัสผู้รับภาระค่าธรรมเนียมไม่ถูกต้อง — ต้องเป็น OUR (บริษัทจ่ายค่าธรรมเนียม) หรือ BEN (หักจาก รปภ). \
         แนะนำ OUR: ถ้าใช้ BEN รปภ จะได้รับเงินน้อยกว่ายอดที่ระบบบันทึกว่าจ่าย"
            .to_string(),
    ))
}

/// Validate the master-data codes a `PUT /admin/payouts/config` actually CARRIES.
///
/// Only a field PRESENT in the request is checked — the PUT is a COALESCE-merge, so validating
/// `None` would break every incremental save (same rule as [`validate_config_accounts`]).
fn validate_config_codes(req: &UpdatePayoutConfigRequest) -> Result<(), AppError> {
    if let Some(code) = req.wht_form_type_code.as_deref() {
        require_wht_form_type(code)?;
    }
    if let Some(code) = req.wht_pay_type_code.as_deref() {
        require_wht_pay_type(code)?;
    }
    if let Some(code) = req.wht_income_type_code.as_deref() {
        require_wht_income_type(code)?;
    }
    if let Some(code) = req.fee_charge_code.as_deref() {
        require_fee_charge_code(code)?;
    }
    Ok(())
}

// ----- config -----

/// GET /admin/payouts/config — the single-row payout settings (blank/default when unset).
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn get_config<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<PayoutConfigRow>>, AppError> {
    require_admin(&user)?;
    let cfg = repo::get_payout_config(state.db()).await?;
    Ok(Json(ApiResponse::success(cfg)))
}

/// PUT /admin/payouts/config — save the payout settings (incremental; `None` keeps the stored value).
#[tracing::instrument(skip(state, req), fields(user = %user.user_id))]
pub async fn put_config<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Json(req): Json<UpdatePayoutConfigRequest>,
) -> Result<Json<ApiResponse<PayoutConfigRow>>, AppError> {
    require_admin(&user)?;
    if let Some(rate) = req.wht_rate_percent {
        if rate.is_sign_negative() || rate > rust_decimal::Decimal::from(100) {
            return Err(AppError::BadRequest(
                "wht_rate_percent must be between 0 and 100".to_string(),
            ));
        }
    }
    // The four master-data codes (ภ.ง.ด. form / pay type / income type / fee charge) land VERBATIM
    // in the file, and each is a picklist key — anything outside its table makes the upload invalid.
    // Rejected at SAVE time, not at export time, so the admin finds out on the settings screen
    // rather than when the bank bounces a money file. Only `wht_form_type_code` used to be checked;
    // the other three reached the file unvalidated.
    validate_config_codes(&req)?;
    validate_config_accounts(&req)?;
    // A negative cap would exclude every guard from every batch (the DB CHECK also refuses it).
    if let Some(cap) = req.max_transfer_per_txn {
        if cap.is_sign_negative() {
            return Err(AppError::BadRequest(
                "เพดานยอดโอนต่อรายการต้องไม่ติดลบ".to_string(),
            ));
        }
    }
    let cfg = repo::upsert_payout_config(state.db(), &req, user.user_id).await?;
    Ok(Json(ApiResponse::success(cfg)))
}

// ----- preview + export shared aggregation -----

/// The `from`/`to` day window a preview may be narrowed to (both optional, inclusive, Thai days).
#[derive(Debug, Default, Deserialize)]
pub struct PayoutWindowQuery {
    pub from: Option<NaiveDate>,
    pub to: Option<NaiveDate>,
}

/// `POST /admin/payouts/export` body — ALL fields optional, and an absent body means the historical
/// default: pay the whole unpaid backlog for every payable guard. `guard_ids` is the admin's tick
/// list from the preview screen (MANY guards ride one file); `from`/`to` bound the finished-job days.
#[derive(Debug, Default, Deserialize)]
pub struct ExportPayoutRequest {
    #[serde(default)]
    pub guard_ids: Option<Vec<Uuid>>,
    #[serde(default)]
    pub from: Option<NaiveDate>,
    #[serde(default)]
    pub to: Option<NaiveDate>,
    /// The batch's effective/value date. Omit for "today in Bangkok, rolled off a weekend"; set it
    /// to schedule a later settlement day or to step over a Thai public holiday (the repo has no
    /// holiday calendar). A PAST date is a 400 — SCB rejects a back-dated batch (doc §15.11).
    #[serde(default)]
    pub value_date: Option<NaiveDate>,
}

/// One guard EXCLUDED from the batch, with why (so the admin can fix the profile and re-run).
#[derive(Debug, Serialize)]
pub struct ExcludedGuard {
    pub guard_id: Uuid,
    pub reason: String,
    pub job_count: usize,
}

/// One payable guard: the SCB recipient plus the identity the preview screen needs to let an admin
/// tick them (`guard_id` is what `export`'s `guard_ids` selects on) and how many jobs they cover.
struct AggregatedRecipient {
    guard_id: Uuid,
    job_count: usize,
    recipient: PayoutRecipient,
}

/// The aggregation result: the SCB recipients to pay, the per-booking paid-marker items, and the
/// guards excluded with reasons.
struct Aggregated {
    recipients: Vec<AggregatedRecipient>,
    items: Vec<NewPayoutItem>,
    excluded: Vec<ExcludedGuard>,
}

/// How many cross-service reads the aggregation keeps in flight at once — see `refunds::
/// PROFILE_FANOUT` for the reasoning; the SAME number on purpose, because
/// both aggregations hit the same two internal services from the same admin screens and a second,
/// differently-tuned constant would only invite drift.
///
/// The payout run is the heavier of the two: it fans out over BOTH readers (one profile read per
/// GUARD *and* one booking read per BOOKING), and before this it did all of them one after another —
/// a preview covering 50 guards with 200 finished jobs cost 250 sequential round trips.
const READ_FANOUT: usize = 8;

/// Resolve every guard's payout PII ONCE, at most [`READ_FANOUT`] reads in flight, into a map the
/// grouping loop reads with no further I/O.
///
/// THE ERROR SPLIT IS PRESERVED EXACTLY: a `NotFound` becomes `None` and excludes that ONE guard
/// further down (with a reason the admin can act on), while any OTHER error — transport, 5xx, decode
/// — aborts the whole run loudly, because silently skipping a guard on a network blip would UNDERPAY
/// them and an underpayment nobody is told about is worse than a failed export the admin retries.
/// `try_collect` is what keeps the two apart: only the hard errors are `Err`, so only they
/// short-circuit.
///
/// NO DB TRANSACTION IS HELD ACROSS THIS FAN-OUT — the backlog read has already returned its rows.
async fn load_guard_profiles<S: PaymentDeps>(
    state: &S,
    guard_ids: Vec<Uuid>,
) -> Result<HashMap<Uuid, Option<GuardPayoutProfile>>, AppError> {
    let fetched: Vec<(Uuid, Option<GuardPayoutProfile>)> = futures::stream::iter(guard_ids)
        .map(|guard_id| async move {
            match state
                .profile_reader()
                .get_guard_payout_profile(guard_id)
                .await
            {
                Ok(p) => Ok((guard_id, Some(p))),
                Err(AppError::NotFound(_)) => Ok((guard_id, None)),
                Err(e) => Err(e),
            }
        })
        .buffer_unordered(READ_FANOUT)
        .try_collect()
        .await?;
    Ok(fetched.into_iter().collect())
}

/// Resolve the bookings that STILL need a cross-service read, at most [`READ_FANOUT`] in flight.
///
/// **THIS IS NOW A FALLBACK FOR UN-BACKFILLED HISTORY ONLY, AND IT SHOULD DISAPPEAR.** Since
/// migration 0013 every settle path snapshots `base_fee`/`booked_hours` onto the payment row, and
/// `unpaid_payout_rows` selects them; the caller only asks for a booking when a row's snapshot is
/// NULL, i.e. when the charge predates that migration. Once no such row remains payable, this
/// function, [`InternalBooking`] and the whole booking-reader dependency can be deleted from the
/// payout path — there is nothing else on it that needs booking.
///
/// The snapshot is authoritative rather than booking's live row for three reasons, and the first is a
/// money bug: booking's `base_fee` is its CURRENT column, so a correction or re-price after the job
/// completed used to pay the guard off one number while the sweep computed `subtotal − guard_income`
/// off `payments.base_fee` — and the difference landed silently in (or leaked out of) the platform's
/// cut with nothing able to notice. The snapshot is also payment's own schema (no cross-service read
/// on the money path), and it makes a historical export reproducible.
///
/// UNLIKE the profile read, a missing booking is NOT an exclusion and never was: without `base_fee`
/// there is no payout to COMPUTE for such a row. It fails the whole run loudly rather than quietly
/// paying that guard for their other jobs only — which would look like a completed payroll while
/// underpaying someone.
async fn load_bookings<S: PaymentDeps>(
    state: &S,
    booking_ids: Vec<Uuid>,
) -> Result<HashMap<Uuid, InternalBooking>, AppError> {
    let fetched: Vec<(Uuid, InternalBooking)> = futures::stream::iter(booking_ids)
        .map(|booking_id| async move {
            state
                .booking_reader()
                .get_booking(booking_id)
                .await
                .map(|b| (booking_id, b))
        })
        .buffer_unordered(READ_FANOUT)
        .try_collect()
        .await?;
    Ok(fetched.into_iter().collect())
}

/// Whether a stored tax id would be used as a 13-digit `NAT` PromptPay destination but FAILS the
/// Thai national-ID check digit. Such a guard is EXCLUDED, never paid.
///
/// DEFENCE IN DEPTH, and the depth is the point. profile enforces this checksum at its own write
/// boundary, but that only covers values written through that endpoint after the rule landed —
/// nothing about a 13-digit id that predates it, was seeded, or arrived another way. Here the number
/// stops being an identifier and becomes a DESTINATION: PromptPay credits whoever owns that id, so a
/// single mistyped digit does not fail, it pays a STRANGER, irreversibly. Classifying by LENGTH
/// alone (which is all `classify_proxy` does — SCB itself stamps the type from the digit count, doc
/// line 2055) cannot catch that.
///
/// Note the narrow scope: only a 13-digit value is judged, because only a 13-digit value becomes a
/// `NAT` proxy. A shorter/longer tax id (profile accepts 8-20 digits) is a certificate REFERENCE
/// only, and the citizen checksum has no authority over a juristic-person TIN.
fn tax_id_fails_national_id_checksum(tax_digits: &str) -> bool {
    tax_digits.chars().count() == thai_id::NATIONAL_ID_DIGITS
        && !thai_id::national_id_check_digit_ok(tax_digits)
}

/// SCB proxy value + type for a guard: prefer the national/tax id (`NAT`), fall back to the phone
/// (`MOB`). `None` when neither is a valid PromptPay proxy.
///
/// The value comes back DIGITS-ONLY. `classify_proxy` already strips separators before deciding, but
/// the value SCB parses (`TXNDET` field 2 — 10-15 numeric characters, doc lines 2052-2055) must be
/// normalised too: profile's validator accepts the human form `1-2345-67890-12-3`, and that shape
/// used to reach the file verbatim.
///
/// A 13-digit tax id that fails [`tax_id_fails_national_id_checksum`] DISQUALIFIES the guard
/// outright — it does not fall through to the phone. Falling through would pay them on a different
/// rail while the ภ.ง.ด. certificate still carried the bad TIN, i.e. quietly turn a "fix this
/// profile" into a wrong tax filing. The caller excludes such a guard with its own Thai reason
/// anyway; refusing here too means a future reordering of that ladder cannot resurrect the fallback.
fn resolve_proxy(tax_id: Option<&str>, phone: Option<&str>) -> Option<(String, PromptPayProxy)> {
    if tax_id
        .map(scb_export::digits_only)
        .as_deref()
        .is_some_and(tax_id_fails_national_id_checksum)
    {
        return None;
    }
    for candidate in [tax_id, phone].into_iter().flatten() {
        let digits = scb_export::digits_only(candidate);
        if let Some(p) = classify_proxy(&digits) {
            return Some((digits, p));
        }
    }
    None
}

/// Build the payout recipients + paid-marker items from the unpaid backlog, narrowed by `sel` (the
/// ticked guards and/or the finished-job day window; an all-`None` selection = the whole backlog).
/// `cfg.wht_rate_percent` drives the withholding (0 → no WHT). Fetches `base_fee` per booking
/// (booking reader) + guard PII (profile reader); groups by guard — MANY guards in one run.
///
/// A guard is EXCLUDED (with a Thai reason the preview screen shows, so the admin can fix the
/// profile and re-run) rather than paid with blanks or written as a line SCB will reject, when they
/// have no profile row at all, no name, no usable PromptPay proxy, no tax id/address for the
/// ภ.ง.ด. certificate, or a total transfer outside the per-transaction bounds.
///
/// THE BACKLOG IS READ FROM THE PRIMARY, DELIBERATELY — do not "optimise" it onto the read replica.
/// Every write that changes this query's answer goes to the primary: `payout_batch_items` rows are
/// inserted by an export, and `voided_at` is stamped by a void. Both are read-after-write on the
/// money path, seconds apart, by the same admin:
///  * void a batch, then immediately export → a lagging replica still sees the items as live, so
///    the bookings the void just released are SILENTLY MISSING from the new file and the void looks
///    like it did nothing;
///  * export, then export again → a paid-marker that has not replicated yet lets a booking be
///    picked up twice. The partial unique still refuses the second batch, so nobody is paid twice —
///    but the whole file is lost to a confusing 409 instead.
///
/// Both callers (preview AND export) use this one function precisely so they cannot disagree: the
/// admin ticks guards off the preview, and a preview describing a different backlog than the export
/// it precedes is its own money bug.
///
/// The two cross-service reads are fanned out with bounded concurrency BEFORE the grouping loop (see
/// [`load_guard_profiles`] + [`load_bookings`]); the loop itself performs no I/O and holds no
/// transaction.
async fn aggregate<S: PaymentDeps>(
    state: &S,
    cfg: &PayoutConfigRow,
    sel: &PayoutSelection,
) -> Result<Aggregated, AppError> {
    let wht_rate = cfg.wht_rate_percent;
    let rows = repo::unpaid_payout_rows(state.db(), sel).await?;

    // Group consecutive rows by guard (the query orders by guard_id).
    let mut by_guard: Vec<(Uuid, Vec<crate::models::UnpaidPayoutRow>)> = Vec::new();
    for row in rows {
        match by_guard.last_mut() {
            Some((g, jobs)) if *g == row.guard_id => jobs.push(row),
            _ => by_guard.push((row.guard_id, vec![row])),
        }
    }

    // Resolve BOTH cross-service reads up front, with bounded concurrency, so the grouping loop
    // below performs no I/O at all. The two fan-outs run against each other as well (`join!`): they
    // hit different services, so waiting for the guards before starting the bookings would add a
    // whole round of latency for nothing. Neither holds a DB transaction.
    //
    // The id lists are DE-DUPLICATED rather than trusted to be distinct: the grouping above is
    // consecutive, so it only yields each guard once while the query's `ORDER BY guard_id` holds.
    // Sorting here means a future change to that ORDER BY costs a wrong grouping, never a doubled
    // request rate against profile.
    let mut guard_ids: Vec<Uuid> = by_guard.iter().map(|(g, _)| *g).collect();
    guard_ids.sort_unstable();
    guard_ids.dedup();
    // ONLY the rows whose migration-0013 pricing snapshot is missing need a booking read. Every row
    // written since that migration carries its own `base_fee`, which is the AUTHORITY for what the
    // guard is paid (see [`load_bookings`]) — so in steady state this list is EMPTY and the payout's
    // hot path makes no call to booking at all.
    let mut booking_ids: Vec<Uuid> = by_guard
        .iter()
        .flat_map(|(_, jobs)| {
            jobs.iter()
                .filter(|j| j.base_fee.is_none())
                .map(|j| j.booking_id)
        })
        .collect();
    booking_ids.sort_unstable();
    booking_ids.dedup();
    let (profiles, bookings) = futures::join!(
        load_guard_profiles(state, guard_ids),
        load_bookings(state, booking_ids)
    );
    // The booking read is checked FIRST and unconditionally, exactly as the sequential version did:
    // it was the inner `?` inside the per-guard loop, so an unreadable booking failed the run before
    // any profile decision was reached. Keeping that order means a bad booking still 500s the export
    // rather than turning into a per-guard exclusion.
    let bookings = bookings?;
    let profiles = profiles?;

    let mut recipients = Vec::new();
    let mut items = Vec::new();
    let mut excluded = Vec::new();

    for (guard_id, jobs) in by_guard {
        // Sum this guard's jobs (per-job compute → sum, so per-job rounding is preserved).
        let mut income = rust_decimal::Decimal::ZERO;
        let mut wht = rust_decimal::Decimal::ZERO;
        let mut guard_items = Vec::new();
        for job in &jobs {
            // THE PAY BASIS COMES FROM THE PAYMENT ROW'S OWN SNAPSHOT (migration 0013). It is the
            // same column stream ② computes the platform's cut from, so the guard's gross and the
            // swept `subtotal − guard_income` are provably derived from ONE number for one job.
            // Reading booking's LIVE `base_fee` instead meant a re-price after completion moved one
            // side and not the other, and the difference vanished into the cut unnoticed.
            //
            // The booking fallback exists SOLELY for rows that predate that migration and have never
            // been backfilled; it should disappear once no un-backfilled row is still payable, and
            // with it the payout's whole dependency on the booking service.
            let (base_fee, booked_hours) = match (job.base_fee, job.booked_hours) {
                (Some(base_fee), booked_hours) => (base_fee, booked_hours),
                // Present by construction — the map was built from exactly the snapshot-less booking
                // ids, and a read that failed already aborted the run above. An error rather than an
                // `expect`: a panic in the money path is never the right answer.
                (None, _) => {
                    let booking = bookings.get(&job.booking_id).ok_or_else(|| {
                        AppError::Internal(format!(
                            "booking {} missing from the run",
                            job.booking_id
                        ))
                    })?;
                    (booking.base_fee, Some(booking.hours))
                }
            };
            // `unpaid_payout_rows` requires `actual_hours IS NOT NULL`, so the fallback is defensive
            // only — but it must not reach for a booking that was deliberately not fetched.
            let hours = job.actual_hours.unwrap_or_else(|| {
                rust_decimal::Decimal::from(booked_hours.unwrap_or_default().max(0))
            });
            let amt = compute_payout(base_fee, hours, job.commission_percent, wht_rate);
            income += amt.income;
            wht += amt.wht;
            guard_items.push(NewPayoutItem {
                booking_id: job.booking_id,
                guard_id,
                income: amt.income,
                wht: amt.wht,
                transfer_amount: amt.transfer,
            });
        }

        // ONE broken guard must cost ONE guard, not the whole run: a missing profile row used to
        // propagate with `?` and 500 the export for everybody. That split now lives in
        // `load_guard_profiles`, which already failed the run loudly on any error that is NOT a
        // NotFound — so a `None` here is precisely "profile has no row for this guard". A MISSING
        // key means the same (the map is built from these very ids, so it cannot happen); it is an
        // exclusion rather than an `expect` because a panic in the money path is never the right
        // answer and a silent `continue` would drop a payable guard without telling anyone.
        let Some(Some(pii)) = profiles.get(&guard_id) else {
            excluded.push(ExcludedGuard {
                guard_id,
                reason: "ไม่พบโปรไฟล์ รปภ ในระบบ (ต้องสร้าง/อนุมัติโปรไฟล์ก่อนจ่ายเงิน)".to_string(),
                job_count: jobs.len(),
            });
            continue;
        };
        // Test the PII in the shape it will actually be WRITTEN: a name of `|||` or a tax id of
        // `----` is non-empty but sanitises to nothing, and a blank mandatory field fails the
        // upload just as surely as a missing one. The cleaned values are what we hand to the writer
        // (sanitising is idempotent, so it re-applying there changes nothing).
        //
        // Each field uses the rule its OWN column is validated with: a NAME loses the characters in
        // `validateTextWithSpecialChar` (doc lines 925-932), an ADDRESS keeps its special characters
        // (doc line 2504). Using one rule for both would either bounce the file or mangle an address.
        let name = pii
            .full_name
            .as_deref()
            .map(|s| scb_export::sanitize_no_special_char(s, scb_export::MAX_NAME))
            .filter(|s| !s.is_empty());
        let address = pii
            .address
            .as_deref()
            .map(|s| scb_export::sanitize_allow_special_char(s, scb_export::MAX_ADDRESS))
            .filter(|s| !s.is_empty());
        let tax_id = pii
            .tax_id
            .as_deref()
            .map(scb_export::digits_only)
            .filter(|s| !s.is_empty());
        // WHERE the money goes, in the sum type the writer addresses a credit line with. Guard
        // payout is a PromptPay (`PPY`) file, so every destination here is a proxy — the bank-account
        // variant belongs to the platform-cut sweep, which is its own file with its own product.
        let destination = resolve_proxy(pii.tax_id.as_deref(), pii.phone.as_deref())
            .map(|(value, _)| CreditDestination::promptpay(value));
        let withholding = wht_rate > rust_decimal::Decimal::ZERO;
        let transfer = income - wht;

        let reason: Option<String> = if name.is_none() {
            Some("ไม่มีชื่อในโปรไฟล์ (จำเป็นสำหรับใบหัก ณ ที่จ่าย)".to_string())
        } else if tax_id
            .as_deref()
            .is_some_and(tax_id_fails_national_id_checksum)
        {
            // Checked BEFORE the missing-proxy arm so the admin gets the real cause: a 13-digit id
            // that fails the check digit is not "no PromptPay", it is a WRONG one — and PromptPay
            // would happily credit whoever does own it.
            Some(
                "เลขบัตรประชาชนในโปรไฟล์ไม่ถูกต้อง (หลักตรวจสอบไม่ผ่าน) — โอนพร้อมเพย์ด้วยเลขนี้เงินจะเข้าบัญชีคนอื่น \
                 กรุณาแก้ไขในโปรไฟล์ รปภ ก่อนจ่ายเงิน"
                    .to_string(),
            )
        } else if destination.is_none() {
            Some("ไม่มีพร้อมเพย์ (เลขบัตร ปชช./เบอร์) ที่ใช้โอนได้".to_string())
        } else if withholding && tax_id.is_none() {
            Some("ไม่มีเลขบัตรประชาชน/เลขผู้เสียภาษี (จำเป็นสำหรับหัก ณ ที่จ่าย)".to_string())
        } else if withholding && tax_id.as_deref().is_some_and(scb_export::tax_id_over_cap) {
            // `WHTCER` field 7 is capped at 15 (doc line 2502) but profile's `validate_tax_id`
            // accepts 8-20 DIGITS, so a 16-20-digit id reaches this file today and bounces it.
            // TRUNCATING is not an option: a cut TIN is the WRONG number on a tax certificate,
            // which is worse than not paying. Exclude the ONE guard and name the limit.
            Some(format!(
                "เลขผู้เสียภาษี/เลขบัตรประชาชนในโปรไฟล์ยาวเกินที่ธนาคารรับได้ (ไม่เกิน {} หลัก) — แก้ไขในโปรไฟล์ รปภ ก่อนจ่ายเงิน",
                scb_export::MAX_TAX_ID
            ))
        } else if withholding && address.is_none() {
            // `ValidWHTMandatory` requires the recipient's address line 1 on every certificate
            // (doc line 2582) — a blank one fails the upload, so exclude instead of emitting it.
            Some("ไม่มีที่อยู่ในโปรไฟล์ (จำเป็นสำหรับใบหัก ณ ที่จ่าย)".to_string())
        } else {
            // Out-of-bounds amount → exclude with the number, never write a line SCB will reject
            // (a rejected file arrives AFTER these bookings were marked paid). The bound depends on
            // the DESTINATION (an e-wallet proxy caps at ฿10,000, a NAT/MOB one at ฿2,000,000), so
            // it is read off the destination and only tightened by the configured cap.
            // Pure + unit-tested.
            match destination.as_ref() {
                // `destination_rejection` first: it checks that the destination is addressable the
                // way THIS file's product demands (a `PPY` line needs a proxy SCB can stamp a type
                // from). `resolve_proxy` already only yields 10/13-digit proxies, so it should never
                // fire — which is exactly why it is here: the writer is infallible, so the invariant
                // has to be asserted at the one place that builds the batch.
                Some(dest) => {
                    scb_export::destination_rejection(PAYOUT_PRODUCT, dest).or_else(|| {
                        scb_export::transfer_bound_rejection(
                            dest,
                            transfer,
                            cfg.max_transfer_per_txn,
                        )
                    })
                }
                // Unreachable — a missing destination was already excluded further up the ladder.
                None => None,
            }
        };

        if let Some(reason) = reason {
            excluded.push(ExcludedGuard {
                guard_id,
                reason,
                job_count: jobs.len(),
            });
            continue;
        }

        // Unreachable — the ladder above already excluded a missing name/proxy. Expressed as one
        // more exclusion rather than `expect`, because a panic in the money path is never the right
        // answer and a silent `continue` would drop a payable guard without telling anyone.
        let (Some(name), Some(destination)) = (name, destination) else {
            excluded.push(ExcludedGuard {
                guard_id,
                reason: "ข้อมูลโปรไฟล์ไม่ครบ (ชื่อ/พร้อมเพย์)".to_string(),
                job_count: jobs.len(),
            });
            continue;
        };
        recipients.push(AggregatedRecipient {
            guard_id,
            job_count: jobs.len(),
            recipient: PayoutRecipient {
                // PROVISIONAL: the export stamps the real, file-unique customer transaction ref
                // (`scb_export::transaction_ref`) once the batch ref exists — a ref derived from the
                // guard alone repeats across files. Preview never shows this field.
                transaction_ref: format!("PO-{}", &guard_id.simple().to_string()[..12]),
                destination,
                tax_id: tax_id.unwrap_or_default(),
                name,
                address: address.unwrap_or_default(),
                income,
                wht,
                // TWO UNRELATED USES OF ONE VALUE — do not collapse them. `PayoutRecipient.phone`
                // drives ONLY the SMS-notify fields (`TXNDET` 9/10): SCB texts the guard and bills
                // us per message, and the number is their LOGIN phone, so it stays `None` unless an
                // operator opted in. The very same phone is still the PromptPay `MOB` fallback that
                // ADDRESSES the money (it went into `destination` above via `resolve_proxy`) — that
                // is how a guard with no tax id gets paid at all, and it is never gated by a
                // notification preference.
                phone: cfg.sms_notify.then(|| pii.phone.clone()).flatten(),
                email: None,
            },
        });
        items.extend(guard_items);
    }

    Ok(Aggregated {
        recipients,
        items,
        excluded,
    })
}

// ----- preview -----

#[derive(Debug, Serialize)]
pub struct PreviewRecipient {
    /// The guard this row pays — the id an admin sends back in `export`'s `guard_ids` to pay
    /// exactly this subset.
    pub guard_id: Uuid,
    pub name: String,
    pub proxy_masked: String,
    /// How many finished jobs this row's amounts add up (one `TXNDET` covers all of them).
    pub job_count: usize,
    pub income: String,
    pub wht: String,
    pub transfer: String,
}

#[derive(Debug, Serialize)]
pub struct PayoutPreview {
    pub recipients: Vec<PreviewRecipient>,
    pub excluded: Vec<ExcludedGuard>,
    pub recipient_count: usize,
    pub total_transfer: String,
    pub total_wht: String,
}

/// Mask a PromptPay proxy to its last 4 (a national id / phone is PII) for the preview screen.
pub(crate) fn mask_proxy(proxy: &str) -> String {
    let n = proxy.chars().count();
    if n <= 4 {
        return proxy.to_string();
    }
    let last4: String = proxy.chars().skip(n - 4).collect();
    format!("{}{last4}", "*".repeat(n - 4))
}

/// GET /admin/payouts/preview — the unpaid backlog aggregated per guard (who gets paid what) +
/// the excluded guards, optionally narrowed to a finished-job day window (`from`/`to`). Read-only:
/// computes but does NOT persist or mark anything paid. Each row carries its `guard_id` so the
/// screen can tick a subset and pass those ids to `export`.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn preview<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(window): Query<PayoutWindowQuery>,
) -> Result<Json<ApiResponse<PayoutPreview>>, AppError> {
    require_admin(&user)?;
    let sel = PayoutSelection {
        guard_ids: None,
        from: window.from,
        to: window.to,
    };
    sel.validate()?;
    let cfg = repo::get_payout_config(state.db()).await?;
    let agg = aggregate(&state, &cfg, &sel).await?;

    let total_transfer: rust_decimal::Decimal = agg
        .recipients
        .iter()
        .map(|r| r.recipient.transfer_amount())
        .sum();
    let total_wht: rust_decimal::Decimal = agg.recipients.iter().map(|r| r.recipient.wht).sum();
    let recipients = agg
        .recipients
        .iter()
        .map(|r| PreviewRecipient {
            guard_id: r.guard_id,
            name: r.recipient.name.clone(),
            proxy_masked: mask_proxy(r.recipient.destination.credit_account()),
            job_count: r.job_count,
            income: format_amount(r.recipient.income),
            wht: format_amount(r.recipient.wht),
            transfer: format_amount(r.recipient.transfer_amount()),
        })
        .collect();

    Ok(Json(ApiResponse::success(PayoutPreview {
        recipient_count: agg.recipients.len(),
        recipients,
        excluded: agg.excluded,
        total_transfer: format_amount(total_transfer),
        total_wht: format_amount(total_wht),
    })))
}

// ----- export -----

/// Build the part of the SCB batch config that EVERY stream needs: the two debit accounts and the
/// fee-charge code, dated `value_date`. Fails with a typed 400 when one is unset or invalid.
///
/// SPLIT OUT OF [`build_payer_and_config`] SO A REFUND DOES NOT NEED A TAX SETTING. Stream ① pays
/// customers back with `wht = 0` on every line, so no `WHTCER`/`WHTDET` is emitted and the ภ.ง.ด.
/// terms + the company TIN never reach that file — demanding them would block a refund on a tax
/// block the file does not carry. What IS genuinely needed is here: `BCHDET` fields 4/5 (the debit
/// accounts, which head the file) and `TXNDET` field 8 (the fee-charge code, mandatory on every
/// credit row — `ValidCreditMandatory`, doc line 1915).
///
/// The WHT fields are still copied through from the stored config, unvalidated, because a
/// zero-withholding batch can never write them; the payout's own wrapper validates them before they
/// can reach a certificate.
///
/// Everything checked here is BATCH-level: one bad value costs the whole file, so it is a 400 the
/// admin can act on, never a per-recipient exclusion. The debit accounts are re-validated even
/// though `put_config` already validates them — a value saved BEFORE those checks existed must not
/// silently produce a batch the bank rejects.
pub(crate) fn build_transfer_config(
    cfg: &PayoutConfigRow,
    value_date: NaiveDate,
) -> Result<PayoutConfig, AppError> {
    let debit = cfg
        .debit_account
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| {
            AppError::BadRequest("ยังไม่ได้ตั้งค่าบัญชีตัดเงินบริษัท (payout config)".to_string())
        })?;
    require_scb_account("บัญชีตัดเงินบริษัท", debit)?;
    let fee = cfg
        .fee_debit_account
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or(debit);
    require_scb_account("บัญชีตัดค่าธรรมเนียม", fee)?;

    // `TXNDET` field 8 is MANDATORY on every credit row of every product (`ValidCreditMandatory`,
    // doc line 1915) — unlike the service type and the branch code, which get explicit per-product
    // exemptions in the very next lines — so it is checked here, for every stream. Re-checked
    // against what is STORED (the settings screen validates what it SENDS): a row saved before this
    // check existed must not quietly build a file the bank refuses.
    require_fee_charge_code(&cfg.fee_charge_code)?;

    Ok(PayoutConfig {
        debit_account: debit.to_string(),
        fee_debit_account: fee.to_string(),
        // `TXNDET` field 8 — it used to be written blank, which plausibly bounced every file we ever
        // produced.
        fee_charge_code: cfg.fee_charge_code.trim().to_string(),
        value_date,
        // The ภ.ง.ด. terms ride along UNVALIDATED here and are checked by `build_payer_and_config`
        // instead. They can only reach a file through `WHTCER`/`WHTDET`, which `scb_export::generate`
        // emits solely for a recipient with `wht > 0` — so on a zero-withholding batch (stream ①)
        // they are inert, and refusing an admin's refund over a tax code the file never carries
        // would be a bug, not a safeguard.
        wht_form_type_code: cfg.wht_form_type_code.clone(),
        wht_pay_type_code: cfg.wht_pay_type_code.clone(),
        wht_income_type_code: cfg.wht_income_type_code.clone(),
        wht_income_desc: cfg.wht_income_desc.clone(),
        wht_rate_percent: cfg.wht_rate_percent,
    })
}

/// Build the SCB `PayoutConfig` + `WhtPayer` for a WITHHOLDING file — the guard payout — from the
/// stored config + the company org block, failing with a typed 400 when a required field (debit
/// account, ภ.ง.ด. code, company tax id/name) is unset OR invalid.
///
/// Everything [`build_transfer_config`] demands, PLUS the three ภ.ง.ด. master-data codes and the
/// company payer block, because this file DOES emit certificates. Each of those is batch-level — the
/// codes repeat on every certificate and the payer TIN on every one of them — so one bad value is a
/// 400 on the whole run, never a per-guard exclusion.
fn build_payer_and_config(
    cfg: &PayoutConfigRow,
    org: &OrgTaxInfo,
    value_date: NaiveDate,
) -> Result<(WhtPayer, PayoutConfig), AppError> {
    let config = build_transfer_config(cfg, value_date)?;

    // The three ภ.ง.ด. master-data codes, re-checked against what is STORED (the settings screen
    // validates what it SENDS). A row saved before these checks existed — or by a migration default
    // that a later SCB table change invalidates — must not quietly build a file the bank refuses.
    require_wht_form_type(&cfg.wht_form_type_code)?;
    require_wht_pay_type(&cfg.wht_pay_type_code)?;
    require_wht_income_type(&cfg.wht_income_type_code)?;

    // The company TIN repeats on EVERY certificate in the file (`WHTCER` field 2), so unlike a
    // guard's it cannot be an exclusion — a bad one is a batch-level 400 pointing at Settings.
    // It is written digits-only, so the cap is measured on the digits, and it is never truncated:
    // a cut TIN is the wrong number on every certificate in the batch.
    let payer_tax_id = scb_export::digits_only(org.tax_id.as_deref().unwrap_or_default());
    if payer_tax_id.is_empty() {
        return Err(AppError::BadRequest(
            "ยังไม่ได้ตั้งเลขผู้เสียภาษีบริษัท (Settings → บริษัท)".to_string(),
        ));
    }
    if scb_export::tax_id_over_cap(&payer_tax_id) {
        return Err(AppError::BadRequest(format!(
            "เลขผู้เสียภาษีบริษัทยาวเกินที่ธนาคารรับได้ (ไม่เกิน {} หลัก) — แก้ไขที่ Settings → บริษัท",
            scb_export::MAX_TAX_ID
        )));
    }

    let payer = WhtPayer {
        tax_id: payer_tax_id,
        name: org
            .company_name
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .ok_or_else(|| AppError::BadRequest("ยังไม่ได้ตั้งชื่อบริษัท (Settings → บริษัท)".to_string()))?
            .to_string(),
        address: org.address.clone().unwrap_or_default(),
    };
    Ok((payer, config))
}

/// POST /admin/payouts/export — build ONE SCB upload file paying MANY guards (one `TXNDET` +
/// `WHTCER` per guard inside a single batch), PERSIST the batch + its per-booking paid-markers (so
/// no job is ever paid twice), and return the file text as UTF-8 (no BOM) for download.
///
/// The optional body narrows the run: `guard_ids` = pay only these guards (the preview screen's tick
/// list), `from`/`to` = only jobs finished in that day window. No body (or an all-null one) keeps the
/// original behaviour: the whole unpaid backlog, every payable guard. Unselected guards are neither
/// written to the file NOR marked paid — they simply stay in the backlog for the next run.
///
/// 409 `PAYOUT_ALREADY_PAID` if a concurrent export won a booking; 409 `PAYOUT_BATCH_REF_TAKEN` if
/// another export committed in the SAME Bangkok second (the batch ref has one-second resolution, so
/// the two files would share the customer transaction refs the bank de-dups on — the loser's whole
/// transaction rolls back, marking nothing paid, and the admin simply clicks again); 400 when the
/// selection is empty/invalid, there is nothing to pay, or the company/debit config is incomplete.
#[tracing::instrument(skip(state, body), fields(user = %user.user_id))]
pub async fn export<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    body: Option<Json<ExportPayoutRequest>>,
) -> Result<Response, AppError> {
    require_admin(&user)?;
    let req = body.map(|Json(b)| b).unwrap_or_default();
    let sel = PayoutSelection {
        guard_ids: req.guard_ids,
        from: req.from,
        to: req.to,
    };
    sel.validate()?;

    // The value date is a THAI banking day: today in Asia/Bangkok rolled off a weekend, or the
    // admin's explicit pick (rejected when back-dated — doc §15.11).
    let now = Utc::now();
    let value_date = scb_export::resolve_value_date(req.value_date, now)?;

    let cfg = repo::get_payout_config(state.db()).await?;
    let org = state.profile_reader().get_org_settings().await?;
    let (payer, config) = build_payer_and_config(&cfg, &org, value_date)?;

    let agg = aggregate(&state, &cfg, &sel).await?;
    if agg.recipients.is_empty() {
        return Err(AppError::BadRequest(
            "ไม่มีรายการค้างจ่ายที่จ่ายได้ในขณะนี้".to_string(),
        ));
    }

    // The two references are DIFFERENT things and were previously swapped: `batch_ref` is the bare
    // 12-digit Bangkok timestamp (capped at 12 chars) and `file_ref` is `batchRef & productCode`.
    // The human-readable `SCB_file_reference_…` string is only the DOWNLOAD NAME (stamped below).
    let batch_ref = scb_export::batch_ref(now);
    let file_ref = scb_export::file_ref(&batch_ref, PAYOUT_PRODUCT);

    let batch = PayoutBatch {
        file_ref: file_ref.clone(),
        system_ref: "PGUARD-PAYOUT".to_string(),
        batch_ref: batch_ref.clone(),
        product: PAYOUT_PRODUCT,
        // No transaction purpose is configured for a guard payout, so `TXNDET` field 7 stays blank
        // (SCB passes it straight through for `PPY` — doc line 2035).
        service_type_code: String::new(),
        payer,
        config: config.clone(),
        // One recipient per guard — the file is a BULK payment covering every selected guard. The
        // customer transaction ref is stamped HERE, from the batch ref + the guard's position, so it
        // is unique per file (a guard-derived ref repeated across every run).
        recipients: agg
            .recipients
            .into_iter()
            .enumerate()
            .map(|(i, r)| PayoutRecipient {
                transaction_ref: scb_export::transaction_ref(
                    scb_export::TXN_REF_PREFIX_PAYOUT,
                    &batch_ref,
                    i + 1,
                ),
                ..r.recipient
            })
            .collect(),
    };
    let file_text = scb_export::generate(&batch);
    let total_transfer: rust_decimal::Decimal =
        batch.recipients.iter().map(|r| r.transfer_amount()).sum();

    // Persist the batch + paid-markers + the FILE TEXT + the money-audit row, in one transaction
    // (the partial UNIQUE(booking_id) WHERE voided_at IS NULL is the atomic double-pay guard).
    //
    // Storing the text is what makes this reversible: the response below is streamed exactly once,
    // so before it existed a failed download / closed tab / proxy timeout left these bookings marked
    // paid forever with no copy of the file meant to pay them. Now the batch can be re-downloaded
    // from `/admin/payouts/batches/{id}/file` and, if the upload never lands, voided — which returns
    // every booking in it to the payable backlog.
    repo::insert_payout_batch(
        state.db(),
        &NewPayoutBatch {
            file_ref,
            system_ref: batch.system_ref.clone(),
            batch_ref,
            value_date: config.value_date,
            total_amount: total_transfer,
            // GUARDS (one TXNDET each), not bookings — `agg.items` holds one row per BOOKING and a
            // guard can carry several finished jobs into the same credit line.
            recipient_count: batch.recipients.len(),
            file_text: file_text.clone(),
            created_by: Some(user.user_id),
            items: agg.items,
        },
    )
    .await?;

    Ok(file_download_response(&batch.file_ref, file_text))
}

/// The SCB file as a download: UTF-8 text (no BOM) + the `attachment` disposition.
///
/// ONE helper for BOTH the export and the re-download, so the two can never disagree about the
/// filename or the content type — an admin who re-downloads a batch must get the same file, named
/// the same way, as the export handed them. The DOWNLOAD name is a separate thing from the HEADER
/// reference (doc line 58) and is derived by [`scb_export::download_filename`] alone.
pub(crate) fn file_download_response(file_ref: &str, file_text: String) -> Response {
    let filename = scb_export::download_filename(file_ref);
    (
        [
            (
                header::CONTENT_TYPE,
                "text/plain; charset=utf-8".to_string(),
            ),
            (
                header::CONTENT_DISPOSITION,
                format!("attachment; filename=\"{filename}\""),
            ),
        ],
        file_text,
    )
        .into_response()
}

// ----- batch history · re-download · lifecycle -----

/// `GET /admin/payouts/batches` paging. House limit/offset, same shape as the admin ledger.
#[derive(Debug, Default, Deserialize)]
pub struct ListBatchesQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// Free-text an admin attaches to a lifecycle action (a status note, a void reason). Capped so a
/// runaway paste cannot bloat a money row; counted in CHARACTERS, never bytes — the copy is Thai and
/// every character is 3 bytes in UTF-8.
pub(crate) const MAX_NOTE_CHARS: usize = 500;

/// Trim + length-check a note/reason. `required` marks the void reason, which must not be blank: a
/// void puts every booking in the batch back in the payable backlog, and six months later a void
/// with no reason cannot be told apart from a mis-click.
pub(crate) fn clean_note(
    label: &str,
    value: &str,
    required: bool,
) -> Result<Option<String>, AppError> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        if required {
            return Err(AppError::BadRequest(format!("กรุณาระบุ{label}")));
        }
        return Ok(None);
    }
    if trimmed.chars().count() > MAX_NOTE_CHARS {
        return Err(AppError::BadRequest(format!(
            "{label}ยาวเกินไป (ไม่เกิน {MAX_NOTE_CHARS} ตัวอักษร)"
        )));
    }
    Ok(Some(trimmed.to_string()))
}

/// GET /admin/payouts/batches — the payout-file history, newest first, with the total count for
/// paging. Header rows only: the stored file text is served by its own endpoint. Admin only.
///
/// PRIMARY, not the replica (unlike the analytics reports next door): the admin lands here seconds
/// after an export, usually because the download went wrong, and a replica-lagged list that does not
/// yet show the batch they just generated would send them to re-export — paying nobody twice, but
/// leaving the real file lost. Low-volume admin reads; the offload is not worth that.
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn list_batches<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<ListBatchesQuery>,
) -> Result<Json<ApiResponse<PayoutBatchList>>, AppError> {
    require_admin(&user)?;
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);
    let page = repo::list_payout_batches(state.db(), limit, offset).await?;
    Ok(Json(ApiResponse::success(page)))
}

/// GET /admin/payouts/batches/{id} — one batch header + every booking it paid (a voided item shows
/// its `voided_at`, i.e. that booking is payable again). Admin only. PRIMARY read, for the same
/// read-after-write reason as the history list.
#[tracing::instrument(skip(state), fields(user = %user.user_id, batch = %batch_id))]
pub async fn get_batch<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
) -> Result<Json<ApiResponse<PayoutBatchDetail>>, AppError> {
    require_admin(&user)?;
    let detail = repo::get_payout_batch(state.db(), batch_id).await?;
    Ok(Json(ApiResponse::success(detail)))
}

/// GET /admin/payouts/batches/{id}/file — re-download the STORED file text, byte for byte, with the
/// same content type and filename the export served. Admin only.
///
/// Read from the PRIMARY, not the replica: an admin whose download failed retries within seconds of
/// the export that wrote it, and replica lag would answer "no such batch" for the one file they are
/// standing here to rescue. 404 when the batch predates file storage (there is genuinely no copy —
/// regenerating one is not an option: it could differ under the same batch ref).
#[tracing::instrument(skip(state), fields(user = %user.user_id, batch = %batch_id))]
pub async fn get_batch_file<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
) -> Result<Response, AppError> {
    require_admin(&user)?;
    let file = repo::get_payout_batch_file(state.db(), batch_id).await?;
    Ok(file_download_response(&file.file_ref, file.file_text))
}

/// POST /admin/payouts/batches/{id}/status — record where the file got to at the bank
/// (`uploaded` → `confirmed` | `rejected`). Admin only. Illegal steps are a typed Thai 409 from the
/// pure transition table.
///
/// `voided` is the ONE value rejected here by name (400), because it is the one the transition table
/// would otherwise WAVE THROUGH: voiding must also stamp every item — that is what returns the work
/// to the backlog — and must carry a reason, so it has its own endpoint. Coming through this door it
/// would flip the header while leaving the items claimed, and the bookings would be unpayable
/// forever: the exact bug the void path exists to prevent. Every other value the lifecycle disallows
/// (`generated`, or a step out of order) needs no special case — the pure table refuses it.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, batch = %batch_id))]
pub async fn set_batch_status<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
    Json(req): Json<SetPayoutBatchStatusRequest>,
) -> Result<Json<ApiResponse<PayoutBatchRow>>, AppError> {
    require_admin(&user)?;
    let Some(status) = BatchStatus::parse(req.status.trim()) else {
        return Err(AppError::BadRequest(format!(
            "สถานะไม่ถูกต้อง — ต้องเป็นหนึ่งใน {}",
            batch_status::BATCH_STATUSES.join(", ")
        )));
    };
    if status == BatchStatus::Voided {
        return Err(AppError::BadRequest(
            "การยกเลิกไฟล์ต้องใช้ปุ่มยกเลิก (ระบุเหตุผล) เพื่อให้งานกลับเข้าคิวรอจ่าย".to_string(),
        ));
    }
    let note = match req.note.as_deref() {
        Some(n) => clean_note("หมายเหตุ", n, false)?,
        None => None,
    };
    let row =
        repo::set_payout_batch_status(state.db(), batch_id, status, note.as_deref(), user.user_id)
            .await?;
    Ok(Json(ApiResponse::success(row)))
}

/// POST /admin/payouts/batches/{id}/void — cancel a batch that never reached the bank (or that the
/// bank refused) and RETURN every booking in it to the payable backlog. Admin only.
///
/// This is the escape hatch from the one-way door: without it, a batch whose file was lost left its
/// guards permanently unpaid and only a hand-written DELETE in production could undo it. The reason
/// is mandatory. A batch the bank CONFIRMED cannot be voided (the money moved — un-marking it would
/// pay those guards twice); a second void is a typed 409, not a silent success.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, batch = %batch_id))]
pub async fn void_batch<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
    Json(req): Json<VoidPayoutBatchRequest>,
) -> Result<Json<ApiResponse<PayoutBatchRow>>, AppError> {
    require_admin(&user)?;
    let Some(reason) = clean_note("เหตุผลในการยกเลิก", &req.reason, true)?
    else {
        // `clean_note(.., required = true)` already returned the 400 for a blank reason; this arm is
        // unreachable and is written as an error rather than an `expect` (no panics in the money path).
        return Err(AppError::BadRequest("กรุณาระบุเหตุผลในการยกเลิก".to_string()));
    };
    let row = repo::void_payout_batch(state.db(), batch_id, user.user_id, &reason).await?;
    Ok(Json(ApiResponse::success(row)))
}

/// POST /admin/payouts/batches/{id}/items/void — return SOME of a batch's bookings to the payable
/// backlog (the guards whose credit lines the bank could not deliver), leaving every other booking
/// in the file paid and the batch's own status untouched. Admin only.
///
/// WHY THIS IS SEPARATE FROM THE WHOLE-BATCH VOID. SCB can ACCEPT a bulk file and still fail
/// individual credit lines — an unregistered PromptPay proxy, or one not linked to a receiving
/// account, is the everyday case. The file is structurally valid, so it passes the whole-file check
/// and the batch is honestly `confirmed`: most guards were paid, a handful were not. Voiding the
/// whole batch would un-pay the ones who DID get their money, and `confirmed` is terminal so it is
/// not even offered — which left a hand-written UPDATE in production as the only remedy.
///
/// It therefore DELIBERATELY BYPASSES `batch_status::is_terminal` and the transition table
/// altogether. That is not a loophole: the status machine describes what happened to the FILE at the
/// bank (which is still true — it was uploaded and accepted), while this action corrects which
/// BOOKINGS the file actually paid. Nothing here changes the batch's status, so the record of what
/// the bank did stays intact; the audit row names the bookings and carries the (mandatory) reason.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, batch = %batch_id))]
pub async fn void_batch_items<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
    Json(req): Json<VoidPayoutBatchItemsRequest>,
) -> Result<Json<ApiResponse<PayoutBatchDetail>>, AppError> {
    require_admin(&user)?;
    // Pure validation first (non-empty, capped, de-duplicated) — no DB round trip for a client bug.
    let booking_ids = normalize_voided_booking_ids(&req.booking_ids)?;
    let Some(reason) = clean_note("เหตุผลในการดึงงานกลับ", &req.reason, true)?
    else {
        // Unreachable — `clean_note(.., required = true)` already 400'd a blank reason. An error
        // rather than an `expect`: no panics in the money path.
        return Err(AppError::BadRequest(
            "กรุณาระบุเหตุผลในการดึงงานกลับ".to_string(),
        ));
    };
    let detail =
        repo::void_payout_batch_items(state.db(), batch_id, &booking_ids, user.user_id, &reason)
            .await?;
    Ok(Json(ApiResponse::success(detail)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn org(tax_id: Option<&str>) -> OrgTaxInfo {
        OrgTaxInfo {
            company_name: Some("PGuard Co., Ltd.".to_string()),
            tax_id: tax_id.map(str::to_string),
            address: Some("1 Sathorn Rd, Bangkok 10120".to_string()),
        }
    }

    /// A stored config with the given debit / fee-debit accounts.
    fn cfg(debit: Option<&str>, fee: Option<&str>) -> PayoutConfigRow {
        PayoutConfigRow {
            debit_account: debit.map(str::to_string),
            fee_debit_account: fee.map(str::to_string),
            ..PayoutConfigRow::unset()
        }
    }

    fn today() -> NaiveDate {
        scb_export::bangkok_today(Utc::now())
    }

    /// `1234567896` passes SCB's §14 check digit (see the domain tests); `1234567890` — the same
    /// number with the check digit typo'd — does not.
    const GOOD_ACCOUNT: &str = "1234567896";
    const TYPO_ACCOUNT: &str = "1234567890";

    #[test]
    fn a_mistyped_debit_account_never_reaches_the_bank() {
        // BCHDET fields 4/5 head the FILE: a bad account is rejected at the BATCH header, i.e.
        // AFTER `payout_batch_items` marked every booking in the run paid. So it must 400 first.
        let bad = build_payer_and_config(
            &cfg(Some(TYPO_ACCOUNT), None),
            &org(Some("0105551234567")),
            today(),
        )
        .expect_err("a check-digit failure must not build a batch");
        assert!(matches!(bad, AppError::BadRequest(_)));
        let AppError::BadRequest(msg) = bad else {
            unreachable!()
        };
        assert!(msg.contains("บัญชีตัดเงินบริษัท"), "names the field: {msg}");
        assert!(msg.contains("10 หลัก"), "…and the rule, in Thai: {msg}");

        // A 9- or 11-digit account is just as fatal, and just as easy to type.
        for len_typo in ["123456789", "12345678960"] {
            assert!(
                build_payer_and_config(
                    &cfg(Some(len_typo), None),
                    &org(Some("0105551234567")),
                    today()
                )
                .is_err(),
                "{len_typo} is not a 10-digit SCB account"
            );
        }
        // The FEE account is a separate BCHDET field and must be checked separately.
        let fee_bad = build_payer_and_config(
            &cfg(Some(GOOD_ACCOUNT), Some(TYPO_ACCOUNT)),
            &org(Some("0105551234567")),
            today(),
        )
        .expect_err("the fee-debit account is mandatory too");
        let AppError::BadRequest(msg) = fee_bad else {
            unreachable!()
        };
        assert!(msg.contains("ค่าธรรมเนียม"), "names the fee field: {msg}");
    }

    #[test]
    fn a_valid_config_builds_and_the_fee_account_defaults_to_the_debit_one() {
        let (payer, config) = build_payer_and_config(
            &cfg(Some(GOOD_ACCOUNT), None),
            &org(Some("0-1055-51234-56-7")),
            today(),
        )
        .expect("a real SCB account + company TIN");
        assert_eq!(config.debit_account, GOOD_ACCOUNT);
        assert_eq!(config.fee_debit_account, GOOD_ACCOUNT, "defaults to debit");
        // The company TIN is normalised digits-only: profile stores the human form with dashes.
        assert_eq!(payer.tax_id, "0105551234567");
    }

    #[test]
    fn the_company_tax_id_is_a_batch_level_400_never_a_truncation() {
        // Over the 15-char WHTCER cap (doc line 2502). It repeats on EVERY certificate in the file,
        // so one bad value fails the run — but it must never be cut down to 15 (that would put a
        // valid-looking WRONG number on every guard's tax certificate).
        let long = "1".repeat(16);
        let err =
            build_payer_and_config(&cfg(Some(GOOD_ACCOUNT), None), &org(Some(&long)), today())
                .expect_err("16 digits is over the cap");
        let AppError::BadRequest(msg) = err else {
            unreachable!()
        };
        assert!(msg.contains("15 หลัก"), "the reason names the limit: {msg}");
        assert!(msg.contains("Settings"), "…and where to fix it: {msg}");

        // Exactly at the cap is fine.
        assert!(build_payer_and_config(
            &cfg(Some(GOOD_ACCOUNT), None),
            &org(Some(&"1".repeat(15))),
            today()
        )
        .is_ok());
        // A TIN that is punctuation only sanitises to nothing — same as unset.
        for empty in [None, Some(""), Some("----")] {
            assert!(
                build_payer_and_config(&cfg(Some(GOOD_ACCOUNT), None), &org(empty), today())
                    .is_err(),
                "{empty:?} is not a company TIN"
            );
        }
    }

    /// A `PUT /admin/payouts/config` body carrying only the named fields.
    fn put_req(
        debit: Option<&str>,
        fee: Option<&str>,
        revenue: Option<&str>,
    ) -> UpdatePayoutConfigRequest {
        UpdatePayoutConfigRequest {
            debit_account: debit.map(str::to_string),
            fee_debit_account: fee.map(str::to_string),
            revenue_account: revenue.map(str::to_string),
            wht_form_type_code: None,
            wht_pay_type_code: None,
            wht_income_type_code: None,
            wht_income_desc: None,
            wht_rate_percent: None,
            max_transfer_per_txn: None,
            fee_charge_code: None,
            sms_notify: None,
        }
    }

    /// ALL THREE company accounts are validated on the way in, and each is batch-fatal on its own:
    /// the two debit accounts head the file and the revenue account is the platform-cut sweep's only
    /// credit destination.
    #[test]
    fn saving_a_mistyped_company_account_is_refused_but_an_absent_one_still_saves() {
        assert!(validate_config_accounts(&put_req(Some(TYPO_ACCOUNT), None, None)).is_err());
        assert!(validate_config_accounts(&put_req(None, Some(TYPO_ACCOUNT), None)).is_err());
        assert!(
            validate_config_accounts(&put_req(None, None, Some(TYPO_ACCOUNT))).is_err(),
            "the sweep destination is checked here too, not only at export"
        );
        assert!(validate_config_accounts(&put_req(
            Some(GOOD_ACCOUNT),
            Some(GOOD_ACCOUNT),
            Some(GOOD_ACCOUNT)
        ))
        .is_ok());
        // The human-written form with dashes is accepted (SCB strips them itself, doc line 1027).
        assert!(validate_config_accounts(&put_req(Some("123-456789-6"), None, None)).is_ok());
        assert!(validate_config_accounts(&put_req(None, None, Some("123-456789-6"))).is_ok());

        // The PUT is a COALESCE-merge: an ABSENT field keeps the stored value, so a save that only
        // touches, say, the WHT rate must not be rejected for "not sending" an account.
        assert!(validate_config_accounts(&put_req(None, None, None)).is_ok());
        // A blank string is the "clear this field" path and stays valid (an unset account is its own
        // typed 400 at export time).
        assert!(validate_config_accounts(&put_req(Some(""), Some("   "), Some(""))).is_ok());
    }

    #[test]
    fn masking_a_proxy_keeps_only_the_last_four() {
        assert_eq!(mask_proxy("1234567890123"), "*********0123");
        assert_eq!(mask_proxy("0812"), "0812", "too short to mask");
    }

    // ----- the destination checksum (a wrong national id pays a STRANGER) -----

    /// A genuinely valid Thai national id: `123456789012` weighted 13…2 sums to 352, 352 mod 11 = 0,
    /// so the check digit is (11 − 0) mod 10 = 1.
    const GOOD_NATIONAL_ID: &str = "1234567890121";
    /// The same twelve digits with the WRONG check digit — shape-perfect, and a PromptPay transfer
    /// to it would credit whoever really owns that number.
    const TYPO_NATIONAL_ID: &str = "1234567890123";

    #[test]
    fn a_thirteen_digit_tax_id_must_pass_the_check_digit_before_it_can_receive_money() {
        // The valid one becomes the NAT proxy, digits-only (profile may store the human form).
        assert_eq!(
            resolve_proxy(Some("1-2345-67890-12-1"), None),
            Some((GOOD_NATIONAL_ID.to_string(), PromptPayProxy::NationalId))
        );
        // The typo is refused, and — critically — does NOT quietly fall through to the phone: the
        // guard must be EXCLUDED so a human fixes the profile, not paid on a different rail while a
        // certificate carries the wrong TIN.
        assert_eq!(
            resolve_proxy(Some(TYPO_NATIONAL_ID), Some("0812345678")),
            None
        );
        assert!(tax_id_fails_national_id_checksum(TYPO_NATIONAL_ID));
        assert!(!tax_id_fails_national_id_checksum(GOOD_NATIONAL_ID));
    }

    #[test]
    fn the_mob_fallback_still_works_and_short_tax_ids_are_not_judged_by_the_citizen_checksum() {
        // No tax id → the phone addresses the money (this is how a guard with no id gets paid).
        assert_eq!(
            resolve_proxy(None, Some("081-234-5678")),
            Some(("0812345678".to_string(), PromptPayProxy::Mobile))
        );
        // A tax id that is not 13 digits is not a NAT proxy candidate at all — the citizen checksum
        // has no authority over it (a juristic TIN is a different thing) — so the phone is used and
        // the id rides the certificate untouched.
        assert_eq!(
            resolve_proxy(Some("12345678"), Some("0812345678")),
            Some(("0812345678".to_string(), PromptPayProxy::Mobile))
        );
        assert!(!tax_id_fails_national_id_checksum("12345678"));
        // Nothing usable at all.
        assert_eq!(resolve_proxy(None, None), None);
        assert_eq!(resolve_proxy(Some("----"), Some("12345")), None);
    }

    // ----- the four master-data codes -----

    #[test]
    fn the_wht_pay_type_four_is_refused_with_its_own_reason_not_as_a_typo() {
        // `4` (อื่นๆ) is a REAL SCB code, but `ValidWHTMandatory` demands a free-text remark on
        // WHTCER field 16 whenever it is used (doc line 2582) and pguard has no field to put one in.
        // The message must say "not supported yet", or the admin hunts for a typo that is not there.
        let AppError::BadRequest(msg) = require_wht_pay_type("4").expect_err("unsupported") else {
            unreachable!()
        };
        assert!(msg.contains("อื่นๆ"), "names the choice: {msg}");
        assert!(msg.contains("หมายเหตุ"), "…and WHY: {msg}");
        // A code outside the table gets the OTHER message (the list of what is allowed).
        let AppError::BadRequest(msg) = require_wht_pay_type("9").expect_err("not in the table")
        else {
            unreachable!()
        };
        assert!(msg.contains("1, 2, 3, 4"), "lists the table: {msg}");
        for ok in ["1", "2", "3"] {
            assert!(require_wht_pay_type(ok).is_ok(), "{ok} is supported");
        }
    }

    #[test]
    fn income_type_and_fee_charge_codes_are_validated_too() {
        assert!(require_wht_income_type("5").is_ok(), "the ค่าบริการ default");
        assert!(require_wht_income_type("4b1.1").is_ok(), "not an integer");
        assert!(require_wht_income_type("7").is_err());
        assert!(require_fee_charge_code("OUR").is_ok());
        assert!(require_fee_charge_code("BEN").is_ok());
        // SHA is BAHTNET's code (doc line 312) — real, but not on a PPY line.
        let AppError::BadRequest(msg) = require_fee_charge_code("SHA").expect_err("not TBFeeOther")
        else {
            unreachable!()
        };
        assert!(msg.contains("OUR"), "recommends the payout answer: {msg}");
    }

    #[test]
    fn saving_the_config_validates_only_the_codes_it_carries() {
        // The PUT is a COALESCE-merge, so an ABSENT code must not be judged (that would break every
        // incremental save) while a PRESENT one must be.
        assert!(validate_config_codes(&put_req(None, None, None)).is_ok());
        let mut req = put_req(None, None, None);
        req.wht_income_type_code = Some("999".to_string());
        assert!(validate_config_codes(&req).is_err(), "income type checked");
        let mut req = put_req(None, None, None);
        req.fee_charge_code = Some("bogus".to_string());
        assert!(validate_config_codes(&req).is_err(), "fee charge checked");
        let mut req = put_req(None, None, None);
        req.wht_form_type_code = Some("02".to_string()); // 02 is NOT one of the seven
        assert!(validate_config_codes(&req).is_err(), "form type checked");
        let mut req = put_req(None, None, None);
        req.wht_pay_type_code = Some("3".to_string());
        req.wht_income_type_code = Some("5".to_string());
        req.fee_charge_code = Some("OUR".to_string());
        req.wht_form_type_code = Some("04".to_string());
        assert!(validate_config_codes(&req).is_ok(), "a real settings save");
    }

    #[test]
    fn the_file_carries_the_fee_charge_code_and_a_stored_bad_one_stops_the_whole_run() {
        // Field 8 is mandatory on EVERY credit row (doc line 1915) and the value is batch-level, so
        // a bad stored code is a 400 on the run, never a per-guard exclusion.
        let (_, config) = build_payer_and_config(
            &cfg(Some(GOOD_ACCOUNT), None),
            &org(Some("0105551234567")),
            today(),
        )
        .expect("the default config builds");
        assert_eq!(config.fee_charge_code, "OUR", "the company bears the fee");

        let mut stored = cfg(Some(GOOD_ACCOUNT), None);
        stored.fee_charge_code = "SHA".to_string();
        assert!(
            build_payer_and_config(&stored, &org(Some("0105551234567")), today()).is_err(),
            "a value saved before the check existed must not build a file"
        );
        // …same for the three ภ.ง.ด. codes, which repeat on every certificate in the batch.
        for (bad_form, bad_pay, bad_income) in
            [("02", "1", "5"), ("53", "4", "5"), ("53", "1", "nope")]
        {
            let mut stored = cfg(Some(GOOD_ACCOUNT), None);
            stored.wht_form_type_code = bad_form.to_string();
            stored.wht_pay_type_code = bad_pay.to_string();
            stored.wht_income_type_code = bad_income.to_string();
            assert!(
                build_payer_and_config(&stored, &org(Some("0105551234567")), today()).is_err(),
                "{bad_form}/{bad_pay}/{bad_income} must not reach the bank"
            );
        }
    }
}
