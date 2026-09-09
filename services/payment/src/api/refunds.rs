//! Customer-refund admin endpoints — stream ① *ยอดที่ต้องโอนคืนกับคนจ้าง*: generate the SCB Business
//! Net bulk-upload file that actually SENDS a customer their money back. THE MONEY PATH (refund
//! side). Admin-role gated.
//!
//! - `GET  /admin/refunds/preview` — the unrefunded backlog aggregated per CUSTOMER (who gets back
//!   what) + the customers EXCLUDED, each with a Thai reason. Optional `from`/`to` day window.
//! - `POST /admin/refunds/export` — build the file, PERSIST the batch (marking those obligations
//!   `processed`), return the text as UTF-8 (no BOM) for download. Optional body selects WHICH
//!   customers (and which day window) to refund and may pin the value date.
//! - `GET  /admin/refunds/batches` · `…/{id}` · `…/{id}/file` — the history of generated files, one
//!   batch's drill-down, and the RE-DOWNLOAD of the stored text.
//! - `POST …/{id}/status` · `…/{id}/void` · `…/{id}/items/void` — where the file got to at the bank,
//!   and the two escape hatches.
//!
//! WHAT WAS BROKEN. Money owed back to a customer was computed, written as
//! `refund_status = 'pending'`, and announced to them by push — and then never left the building.
//! NOTHING in the codebase had ever written `refund_status = 'processed'`; the queue behind
//! `GET /admin/refunds/queue` only ever gained rows, and its handler's note that "v2 refunds are
//! event-driven" was aspirational. These endpoints are what drains it.
//!
//! TWO LANES OWE THE MONEY and the export covers BOTH — a missed lane is unrefunded money nobody is
//! looking for. Lane A is `payment.payments` (`refund_status = 'pending'`, `refund_amount > 0`: the
//! completion-reconcile overpay, the cancellation refund, the race-lost pre-pay compensator); lane B
//! is `payment.payment_slips` (`applied = FALSE AND refund_status = 'pending'`: a genuine
//! double-transfer for an already-paid booking). They are a different table, a different id and a
//! different amount column, so an obligation is identified by a (kind, id) PAIR throughout — see
//! [`crate::domain::refund_export`].
//!
//! ONE FILE PER STREAM, AND NO WITHHOLDING. A `BCHDET` carries exactly one product code, so this is
//! its own upload — never merged with the guard payout, even though both ride PromptPay. Every
//! recipient carries `wht = 0`: a refund is the customer's own money coming back, not assessable
//! income, so [`scb_export::generate`] emits no `WHTCER` and no `WHTDET`, and the ภ.ง.ด. payer block
//! is [`WhtPayer::none`]. An admin must not have to configure a tax-payer block to refund a customer,
//! so this module reads only the DEBIT accounts + fee-charge code
//! ([`crate::api::payouts::build_transfer_config`]) and never touches `/internal/org-settings`.
//!
//! WHERE THE MONEY GOES comes from what REGISTRATION already captured — profile's
//! `GET /internal/customers/{user_id}/payout-profile` returns the customer's name, address and the
//! phone (their `contact_phone`, else their identity LOGIN phone) that becomes the PromptPay `MOB`
//! proxy. No new PII is collected for refunds and no new profile column exists.
//!
//! …and it goes there ONLY if that phone is a genuine Thai MOBILE. This stream refuses the `NAT` and
//! `EWL` proxies the guard payout accepts, because a guard's proxy is a tax id supplied *as a payment
//! address* while a customer's phone is contact data that was never meant to be one — a stored value
//! that merely normalises to 13 digits would otherwise be PromptPay'd, irreversibly, to whoever owns
//! that national id. See [`crate::domain::refund_export::classify_refund_destination`].
//!
//! EXCLUSION, NOT FAILURE, is the rule for one unreachable customer: a missing profile, a missing
//! name, no usable proxy, or an amount outside SCB's per-transaction bounds takes THAT customer out
//! of the batch with a reason the admin can act on — and their obligations are NOT marked processed.
//! One broken profile must never stop everyone else's refund, and an out-of-bounds line must never
//! reach the bank (SCB rejects the whole file — by which time these obligations are already marked).

use axum::extract::{Path, Query, State};
use axum::response::Response;
use axum::Json;
use chrono::{NaiveDate, Utc};
use futures::stream::{StreamExt, TryStreamExt};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;

use crate::api::payouts::{
    build_transfer_config, clean_note, file_download_response, mask_proxy, require_admin,
    ListBatchesQuery,
};
use crate::domain::batch_status::{self, BatchStatus};
use crate::domain::refund_export::{
    classify_refund_destination, normalize_voided_refund_sources, RefundDestination,
    RefundSelection,
};
use crate::domain::scb_export::{
    self, format_amount, CreditDestination, PayoutBatch, PayoutRecipient, ScbProduct, WhtPayer,
};
use crate::models::{
    NewRefundBatch, NewRefundItem, RefundBatchDetail, RefundBatchList, RefundBatchRow,
    SetRefundBatchStatusRequest, VoidRefundBatchItemsRequest, VoidRefundBatchRequest,
};
use crate::profile_client::{CustomerPayoutProfile, ProfileReader};
use crate::repo;
use crate::state::PaymentDeps;

/// Customer refunds are stream ①, and they go back over PromptPay — so this whole module builds
/// `PPY` files. The other two streams get their OWN files with their own product code: one `BCHDET`
/// carries exactly one product.
const REFUND_PRODUCT: ScbProduct = ScbProduct::PromptPay;

/// `HEADER` field 2 — our own system reference for a refund file. Distinct from the payout's
/// (`PGUARD-PAYOUT`) so a file recovered from a bank mailbox says which stream it came from without
/// being parsed.
const REFUND_SYSTEM_REF: &str = "PGUARD-REFUND";

// ----- preview + export shared aggregation -----

/// The `from`/`to` day window a preview may be narrowed to (both optional, inclusive, Thai days).
#[derive(Debug, Default, Deserialize)]
pub struct RefundWindowQuery {
    pub from: Option<NaiveDate>,
    pub to: Option<NaiveDate>,
}

/// `POST /admin/refunds/export` body — ALL fields optional, and an absent body means "refund the
/// whole backlog for every reachable customer". `customer_ids` is the admin's tick list from the
/// preview screen (MANY customers ride one file); `from`/`to` bound the days the refunds became owed.
#[derive(Debug, Default, Deserialize)]
pub struct ExportRefundRequest {
    #[serde(default)]
    pub customer_ids: Option<Vec<Uuid>>,
    #[serde(default)]
    pub from: Option<NaiveDate>,
    #[serde(default)]
    pub to: Option<NaiveDate>,
    /// The batch's effective/value date. Omit for "today in Bangkok, rolled off a weekend"; set it
    /// to schedule a later settlement day or to step over a Thai public holiday (the platform has no
    /// holiday calendar). A PAST date is a 400 — SCB rejects a back-dated batch (doc §15.11).
    #[serde(default)]
    pub value_date: Option<NaiveDate>,
}

/// One customer EXCLUDED from the batch, with why (so the admin can fix the profile and re-run).
/// Their obligations stay `pending` — nothing about them is marked processed.
#[derive(Debug, Serialize)]
pub struct ExcludedCustomer {
    pub customer_id: Uuid,
    pub reason: String,
    /// How many pending refund obligations this customer is owed (across both lanes).
    pub obligation_count: usize,
}

/// One refundable customer: the SCB recipient plus the identity the preview screen needs to let an
/// admin tick them (`customer_id` is what `export`'s `customer_ids` selects on) and how many
/// obligations the single credit line covers.
struct AggregatedRefund {
    customer_id: Uuid,
    obligation_count: usize,
    recipient: PayoutRecipient,
}

/// The aggregation result: the SCB recipients to pay, the per-obligation marker items, and the
/// customers excluded with reasons.
struct AggregatedRefunds {
    recipients: Vec<AggregatedRefund>,
    items: Vec<NewRefundItem>,
    excluded: Vec<ExcludedCustomer>,
}

/// How many profile reads the aggregation keeps in flight at once.
///
/// The preview is the FIRST screen an admin lands on, and one sequential cross-service read per
/// customer made its latency O(customers) × RTT — which only ever got worse, because customers who
/// cannot be refunded (no phone, a phone that is not a mobile) accumulate in the backlog
/// permanently. Small on purpose: profile is a shared service on a modest connection pool, and 8
/// concurrent internal reads cut a 200-customer preview from ~200 round trips to ~25 without turning
/// one admin's click into a burst that hurts the customer-facing traffic on the same service.
const PROFILE_FANOUT: usize = 8;

/// Resolve the refund PII for every customer in the run ONCE, at most [`PROFILE_FANOUT`] reads in
/// flight, into a map the grouping loop then reads with no further I/O.
///
/// THE ERROR SEMANTICS ARE THE POINT, and they are exactly the sequential version's: a `NotFound`
/// becomes `None` and excludes that ONE customer further down (with a reason the admin can act on),
/// while ANY other error — transport, 5xx, decode — aborts the whole run loudly. Silently skipping
/// someone on a network blip would leave them unrefunded with nobody told, which is worse than a
/// failed export the admin retries. `try_collect` is what preserves the split: only the hard errors
/// are `Err`, so only they short-circuit; a `NotFound` rides through as an ordinary value.
///
/// NO DB TRANSACTION IS HELD ACROSS THIS FAN-OUT — the backlog read has already returned its rows.
async fn load_customer_profiles<S: PaymentDeps>(
    state: &S,
    customer_ids: Vec<Uuid>,
) -> Result<HashMap<Uuid, Option<CustomerPayoutProfile>>, AppError> {
    let fetched: Vec<(Uuid, Option<CustomerPayoutProfile>)> = futures::stream::iter(customer_ids)
        .map(|customer_id| async move {
            match state
                .profile_reader()
                .get_customer_payout_profile(customer_id)
                .await
            {
                Ok(p) => Ok((customer_id, Some(p))),
                Err(AppError::NotFound(_)) => Ok((customer_id, None)),
                Err(e) => Err(e),
            }
        })
        .buffer_unordered(PROFILE_FANOUT)
        .try_collect()
        .await?;
    Ok(fetched.into_iter().collect())
}

/// Build the refund recipients + paid-marker items from the unrefunded backlog, narrowed by `sel`
/// (the ticked customers and/or the day window; an all-`None` selection = the whole backlog).
/// Groups BOTH lanes by customer — one `TXNDET` per person summing every refund they are owed.
///
/// A customer is EXCLUDED (with a Thai reason the preview screen shows, so the admin can fix the
/// profile and re-run) rather than paid with blanks or written as a line SCB will reject, when they
/// have no profile row at all, no name, no stored phone that is a genuine Thai MOBILE, or a total
/// outside SCB's per-transaction bounds. An excluded customer contributes NO item — the marker items
/// are built from this same filtered pass — so nothing about them is ever marked processed.
///
/// The exclusion ladder mirrors the payout's on purpose, minus everything that only a WITHHOLDING
/// file needs: no tax id is required (nothing is withheld) and the address is optional (`TXNDET`
/// field 14 is not mandatory without a certificate). Adding a tax-id gate here would block refunds on
/// PII we deliberately never collect from customers. It is STRICTER in exactly one place — the
/// destination is MOB-only — for the reason spelled out at the `classify_refund_destination` call.
///
/// The cross-service PII reads are fanned out with bounded concurrency BEFORE the grouping loop (see
/// [`load_customer_profiles`]); the loop itself performs no I/O and holds no transaction.
///
/// THE BACKLOG IS READ FROM THE PRIMARY — see [`repo::unpaid_refund_rows`] for why that is a money
/// requirement rather than a preference.
///
/// Both callers (preview AND export) use this one function precisely so they cannot disagree: the
/// admin ticks customers off the preview, and a preview describing a different backlog than the
/// export it precedes is its own money bug.
async fn aggregate<S: PaymentDeps>(
    state: &S,
    max_transfer_per_txn: Option<Decimal>,
    sel: &RefundSelection,
) -> Result<AggregatedRefunds, AppError> {
    let rows = repo::unpaid_refund_rows(state.db(), sel).await?;

    // Group consecutive rows by customer (the query orders by customer_id).
    let mut by_customer: Vec<(Uuid, Vec<crate::models::UnpaidRefundRow>)> = Vec::new();
    for row in rows {
        match by_customer.last_mut() {
            Some((c, owed)) if *c == row.customer_id => owed.push(row),
            _ => by_customer.push((row.customer_id, vec![row])),
        }
    }

    // Resolve EVERY customer's PII up front with bounded concurrency, then group against the map:
    // the loop below does no I/O at all. The id list is DE-DUPLICATED rather than trusted to be
    // distinct — the grouping above is consecutive, so it only yields each customer once while the
    // backlog query's `ORDER BY customer_id` holds; sorting here means a future change to that
    // ORDER BY costs a wrong grouping, never a doubled request rate against profile.
    let mut customer_ids: Vec<Uuid> = by_customer.iter().map(|(c, _)| *c).collect();
    customer_ids.sort_unstable();
    customer_ids.dedup();
    let profiles = load_customer_profiles(state, customer_ids).await?;

    let mut recipients = Vec::new();
    let mut items = Vec::new();
    let mut excluded = Vec::new();

    for (customer_id, owed) in by_customer {
        // Sum this customer's obligations, and build the marker item for each — the SUM is one
        // credit line, but the markers are PER OBLIGATION so a void can return them individually.
        let mut total = Decimal::ZERO;
        let mut customer_items = Vec::with_capacity(owed.len());
        for row in &owed {
            // Round at the source, not at the sum: the columns are NUMERIC(12,2) already, and
            // rounding each share keeps the file total equal to Σ(items) exactly.
            let amount = row.amount.round_dp(2);
            total += amount;
            customer_items.push(NewRefundItem {
                source_kind: row.source_kind.clone(),
                source_id: row.source_id,
                booking_id: row.booking_id,
                customer_id,
                amount,
            });
        }

        // ONE broken profile must cost ONE customer, not the whole run — that split was decided in
        // `load_customer_profiles`, which already failed the run loudly on any error that is not a
        // NotFound. A `None` here is therefore precisely "profile has no row for this customer", and
        // a MISSING key is the same thing (the map is built from these very ids, so it cannot
        // happen; treating it as an exclusion rather than an `expect` keeps the money path
        // panic-free and still tells the admin about them instead of dropping them silently).
        let Some(Some(pii)) = profiles.get(&customer_id) else {
            excluded.push(ExcludedCustomer {
                customer_id,
                reason: "ไม่พบโปรไฟล์ลูกค้าในระบบ — คืนเงินไม่ได้จนกว่าจะมีข้อมูลผู้รับ".to_string(),
                obligation_count: owed.len(),
            });
            continue;
        };

        // Test the PII in the shape it will actually be WRITTEN: a name of `|||` is non-empty but
        // sanitises to nothing, and a blank mandatory field fails the upload just as surely as a
        // missing one. Each field uses the rule its OWN column is validated with — a NAME loses the
        // characters in `validateTextWithSpecialChar` (doc lines 925-932), an ADDRESS keeps its
        // special characters (doc line 2504).
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
        // WHERE THE MONEY GOES — and the gate that keeps it from going to a stranger.
        //
        // THE REFUND STREAM IS MOB-ONLY, deliberately stricter than the guard payout, which
        // legitimately pays a 13-digit `NAT` proxy. The asymmetry is not an oversight: a guard's
        // proxy is a TAX ID THE GUARD SUPPLIED AS A PAYMENT ADDRESS (validated at profile's write
        // boundary, then re-checked against the national-ID check digit before it may address
        // money), whereas a customer's phone is CONTACT DATA that was never offered as a payment
        // address and that registration accepts as typed. Classifying it the way SCB does — by digit
        // count (`CreditDestination::proxy_type_code`: 15→EWL, 13→NAT, 10→MOB, correct for what IT
        // models) — would stamp a country-coded/typo'd/pasted 13-digit value `NAT` and PromptPay it
        // to whoever owns that national id. Irreversible, and by then the obligation is marked
        // `processed`: the real customer is neither refunded nor still visible in the queue.
        //
        // `classify_refund_destination` is pure and unit-tested, and reuses `classify_proxy` so the
        // Thai mobile RULE (leading 0, ten digits) decides — never a bare length.
        let phone = classify_refund_destination(pii.phone.as_deref());
        let destination = match &phone {
            RefundDestination::Mobile(digits) => Some(CreditDestination::promptpay(digits.clone())),
            RefundDestination::NoPhone | RefundDestination::NotAMobile => None,
        };

        let reason: Option<String> = if name.is_none() {
            // `TXNDET` field 13 is the recipient name SCB prints on the credit; a blank one fails
            // the upload for the WHOLE file.
            Some("ไม่มีชื่อในโปรไฟล์ลูกค้า (ธนาคารต้องการชื่อผู้รับเงิน)".to_string())
        } else {
            match destination.as_ref() {
                Some(dest) => {
                    // `destination_rejection` first (is this addressable the way a `PPY` line
                    // demands?), then the amount bounds — reading the ceiling off the DESTINATION,
                    // because it genuinely differs by proxy type, and only tightening it with the
                    // operator's configured cap. An out-of-bounds line makes SCB reject the ENTIRE
                    // file, and by then these obligations are already marked processed.
                    scb_export::destination_rejection(REFUND_PRODUCT, dest).or_else(|| {
                        scb_export::transfer_bound_rejection(dest, total, max_transfer_per_txn)
                    })
                }
                // WHICH of the two "no destination" cases it is changes what the admin has to DO, so
                // they get different sentences: a stored value that cannot receive a PromptPay
                // transfer must be CORRECTED (and is the one that would otherwise have paid a
                // stranger), while a customer with no phone at all has to be contacted.
                None => Some(if matches!(phone, RefundDestination::NotAMobile) {
                    "เบอร์ที่บันทึกไว้ในโปรไฟล์ลูกค้ารับโอนพร้อมเพย์ไม่ได้ — ต้องเป็นเบอร์มือถือไทย 10 หลักที่ขึ้นต้นด้วย 0 \
                     กรุณาแก้ไขเบอร์ให้ถูกต้องก่อนคืนเงิน"
                        .to_string()
                } else {
                    "ไม่มีเบอร์พร้อมเพย์ที่ใช้โอนคืนได้ — ลูกค้ายังไม่มีเบอร์ติดต่อและระบบหาเบอร์ที่ใช้สมัครไม่พบ"
                        .to_string()
                }),
            }
        };

        if let Some(reason) = reason {
            excluded.push(ExcludedCustomer {
                customer_id,
                reason,
                obligation_count: owed.len(),
            });
            continue;
        }

        // Unreachable — the ladder above already excluded a missing name/destination. Expressed as
        // one more exclusion rather than `expect`, because a panic in the money path is never the
        // right answer and a silent `continue` would drop a refundable customer without telling
        // anyone.
        let (Some(name), Some(destination)) = (name, destination) else {
            excluded.push(ExcludedCustomer {
                customer_id,
                reason: "ข้อมูลโปรไฟล์ลูกค้าไม่ครบ (ชื่อ/พร้อมเพย์)".to_string(),
                obligation_count: owed.len(),
            });
            continue;
        };
        recipients.push(AggregatedRefund {
            customer_id,
            obligation_count: owed.len(),
            recipient: PayoutRecipient {
                // PROVISIONAL: the export stamps the real, file-unique customer transaction ref
                // (`scb_export::transaction_ref`) once the batch ref exists — a ref derived from the
                // customer alone repeats across files. Preview never shows this field.
                transaction_ref: format!("RF-{}", &customer_id.simple().to_string()[..12]),
                destination,
                // NO TAX ID, and NO WITHHOLDING. A refund is returned capital, not assessable
                // income: `wht = 0` makes `has_wht()` false for every recipient, so the writer emits
                // no `WHTCER`/`WHTDET` and there is no certificate for a TIN to appear on. This is
                // the ONE place a refund recipient is constructed — keep it that way, and see the
                // scb_export test that asserts the rendered file carries neither record.
                tax_id: String::new(),
                name,
                address: address.unwrap_or_default(),
                income: total,
                wht: Decimal::ZERO,
                // No SMS and no e-mail: SCB bills per SMS, and the customer already gets the
                // platform's own refund notification. The same phone still ADDRESSES the money
                // (it went into `destination` above) — the two uses are unrelated.
                phone: None,
                email: None,
            },
        });
        items.extend(customer_items);
    }

    Ok(AggregatedRefunds {
        recipients,
        items,
        excluded,
    })
}

// ----- preview -----

#[derive(Debug, Serialize)]
pub struct PreviewRefundRecipient {
    /// The customer this row refunds — the id an admin sends back in `export`'s `customer_ids` to
    /// refund exactly this subset.
    pub customer_id: Uuid,
    pub name: String,
    /// The PromptPay proxy masked to its last 4 — a phone number is PII and this screen is a list.
    pub proxy_masked: String,
    /// How many pending obligations this row's amount adds up (one `TXNDET` returns them all).
    pub obligation_count: usize,
    pub amount: String,
}

#[derive(Debug, Serialize)]
pub struct RefundPreview {
    pub recipients: Vec<PreviewRefundRecipient>,
    pub excluded: Vec<ExcludedCustomer>,
    pub recipient_count: usize,
    pub total_amount: String,
}

/// GET /admin/refunds/preview — the unrefunded backlog aggregated per customer (who gets back what)
/// + the excluded customers, optionally narrowed to a day window (`from`/`to`). Read-only: computes
/// but does NOT persist or mark anything processed. Each row carries its `customer_id` so the screen
/// can tick a subset and pass those ids to `export`. Admin only.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn preview<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(window): Query<RefundWindowQuery>,
) -> Result<Json<ApiResponse<RefundPreview>>, AppError> {
    require_admin(&user)?;
    let sel = RefundSelection {
        customer_ids: None,
        from: window.from,
        to: window.to,
    };
    sel.validate()?;
    // Only the per-transaction cap is read from the payout config — the refund file shares the
    // company's debit accounts and SCB's own bounds, not its ภ.ง.ด. terms.
    let cfg = repo::get_payout_config(state.db()).await?;
    let agg = aggregate(&state, cfg.max_transfer_per_txn, &sel).await?;

    // `transfer_amount()` (income − wht), not `income`: identical here because every refund
    // withholds nothing, and reading the ACTUAL transferred figure is what keeps this total equal to
    // the file's `BCHDET`/`TRAILR` if that ever stops being true.
    let total: Decimal = agg
        .recipients
        .iter()
        .map(|r| r.recipient.transfer_amount())
        .sum();
    let recipients = agg
        .recipients
        .iter()
        .map(|r| PreviewRefundRecipient {
            customer_id: r.customer_id,
            name: r.recipient.name.clone(),
            proxy_masked: mask_proxy(r.recipient.destination.credit_account()),
            obligation_count: r.obligation_count,
            amount: format_amount(r.recipient.transfer_amount()),
        })
        .collect();

    Ok(Json(ApiResponse::success(RefundPreview {
        recipient_count: agg.recipients.len(),
        recipients,
        excluded: agg.excluded,
        total_amount: format_amount(total),
    })))
}

// ----- export -----

/// POST /admin/refunds/export — build ONE SCB upload file refunding MANY customers (one `TXNDET` per
/// customer inside a single batch), PERSIST the batch + its per-obligation markers AND advance those
/// obligations to `refund_status = 'processed'` in the same transaction, then return the file text as
/// UTF-8 (no BOM) for download.
///
/// The optional body narrows the run: `customer_ids` = refund only these customers (the preview
/// screen's tick list), `from`/`to` = only obligations that became owed in that day window. No body
/// (or an all-null one) refunds the whole backlog. Unselected customers are neither written to the
/// file NOR marked processed — they simply stay in the queue for the next run.
///
/// 409 `REFUND_ALREADY_EXPORTED` if a concurrent export claimed an obligation; 409
/// `REFUND_BATCH_REF_TAKEN` if another refund export committed in the SAME Bangkok second (the batch
/// ref has one-second resolution, so the two files would share the customer transaction refs the bank
/// de-dups on — the loser's whole transaction rolls back, marking nothing, and the admin simply
/// clicks again); 409 `REFUND_QUEUE_CHANGED` if a source row moved underneath the run; 400 when the
/// selection is empty/invalid, there is nothing to refund, or the debit config is incomplete.
#[tracing::instrument(skip(state, body), fields(user = %user.user_id))]
pub async fn export<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    body: Option<Json<ExportRefundRequest>>,
) -> Result<Response, AppError> {
    require_admin(&user)?;
    let req = body.map(|Json(b)| b).unwrap_or_default();
    let sel = RefundSelection {
        customer_ids: req.customer_ids,
        from: req.from,
        to: req.to,
    };
    sel.validate()?;

    // The value date is a THAI banking day: today in Asia/Bangkok rolled off a weekend, or the
    // admin's explicit pick (rejected when back-dated — doc §15.11).
    let now = Utc::now();
    let value_date = scb_export::resolve_value_date(req.value_date, now)?;

    let cfg = repo::get_payout_config(state.db()).await?;
    // DEBIT ACCOUNTS + FEE-CHARGE CODE ONLY. No org read, no ภ.ง.ด. codes, no company TIN: this file
    // withholds nothing, so it carries no certificate for any of that to appear on, and requiring a
    // tax block before a customer can be refunded would be a bug rather than a safeguard.
    let config = build_transfer_config(&cfg, value_date)?;

    let agg = aggregate(&state, cfg.max_transfer_per_txn, &sel).await?;
    if agg.recipients.is_empty() {
        return Err(AppError::BadRequest(
            "ไม่มีรายการคืนเงินที่โอนคืนได้ในขณะนี้".to_string(),
        ));
    }

    // The two references are DIFFERENT things: `batch_ref` is the bare 12-digit Bangkok timestamp
    // (capped at 12 chars) and `file_ref` is `batchRef & productCode`. The human-readable
    // `SCB_file_reference_…` string is only the DOWNLOAD NAME.
    let batch_ref = scb_export::batch_ref(now);
    let file_ref = scb_export::file_ref(&batch_ref, REFUND_PRODUCT);

    let batch = PayoutBatch {
        file_ref: file_ref.clone(),
        system_ref: REFUND_SYSTEM_REF.to_string(),
        batch_ref: batch_ref.clone(),
        product: REFUND_PRODUCT,
        // No transaction purpose is configured, so `TXNDET` field 7 stays blank (SCB passes it
        // straight through for `PPY` — doc line 2035).
        service_type_code: String::new(),
        // NO ภ.ง.ด. PAYER — every recipient's `wht` is 0, so no `WHTCER`/`WHTDET` is emitted and this
        // block reaches no record in the file. See `WhtPayer::none`.
        payer: WhtPayer::none(),
        config: config.clone(),
        // One recipient per customer. The customer transaction ref is stamped HERE, from the batch
        // ref + the customer's position + the REFUND stream prefix — the prefix is what keeps a
        // refund and a payout generated in the same Bangkok second from carrying identical refs.
        recipients: agg
            .recipients
            .into_iter()
            .enumerate()
            .map(|(i, r)| PayoutRecipient {
                transaction_ref: scb_export::transaction_ref(
                    scb_export::TXN_REF_PREFIX_REFUND,
                    &batch_ref,
                    i + 1,
                ),
                ..r.recipient
            })
            .collect(),
    };
    let file_text = scb_export::generate(&batch);
    let total_amount: Decimal = batch.recipients.iter().map(|r| r.transfer_amount()).sum();

    // Persist the batch + markers + the FILE TEXT + the `refund_status → 'processed'` advance + the
    // money-audit row, in ONE transaction (the partial UNIQUE(source_kind, source_id) WHERE
    // voided_at IS NULL is the atomic double-refund guard).
    //
    // Storing the text is what makes this reversible: the response below is streamed exactly once,
    // so without it a failed download / closed tab / proxy timeout would leave these obligations
    // marked processed forever with no copy of the file meant to settle them. Now the batch can be
    // re-downloaded from `/admin/refunds/batches/{id}/file` and, if the upload never lands, voided —
    // which returns every obligation in it to the refundable queue.
    repo::insert_refund_batch(
        state.db(),
        &NewRefundBatch {
            file_ref,
            system_ref: batch.system_ref.clone(),
            batch_ref,
            value_date: config.value_date,
            total_amount,
            // CUSTOMERS (one TXNDET each), not obligations — `agg.items` holds one row per
            // obligation and a customer can carry several into the same credit line.
            recipient_count: batch.recipients.len(),
            file_text: file_text.clone(),
            created_by: Some(user.user_id),
            items: agg.items,
        },
    )
    .await?;

    Ok(file_download_response(&batch.file_ref, file_text))
}

// ----- batch history · re-download · lifecycle -----

/// GET /admin/refunds/batches — the refund-file history, newest first, with the total count for
/// paging. Header rows only: the stored file text is served by its own endpoint. Admin only.
///
/// PRIMARY, not the replica: the admin lands here seconds after an export, usually because the
/// download went wrong, and a replica-lagged list that does not yet show the batch they just
/// generated would send them to re-export — refunding nobody twice, but leaving the real file lost.
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn list_batches<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<ListBatchesQuery>,
) -> Result<Json<ApiResponse<RefundBatchList>>, AppError> {
    require_admin(&user)?;
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);
    let page = repo::list_refund_batches(state.db(), limit, offset).await?;
    Ok(Json(ApiResponse::success(page)))
}

/// GET /admin/refunds/batches/{id} — one batch header + every obligation it settled (an item showing
/// `voided_at` is back in the refundable queue). Admin only. PRIMARY read, for the same
/// read-after-write reason as the history list.
#[tracing::instrument(skip(state), fields(user = %user.user_id, batch = %batch_id))]
pub async fn get_batch<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
) -> Result<Json<ApiResponse<RefundBatchDetail>>, AppError> {
    require_admin(&user)?;
    let detail = repo::get_refund_batch(state.db(), batch_id).await?;
    Ok(Json(ApiResponse::success(detail)))
}

/// GET /admin/refunds/batches/{id}/file — re-download the STORED file text, byte for byte, with the
/// same content type and filename the export served. Admin only.
///
/// Read from the PRIMARY, not the replica: an admin whose download failed retries within seconds of
/// the export that wrote it, and replica lag would answer "no such batch" for the one file they are
/// standing here to rescue. The text is never REGENERATED — the backlog has moved on since, so a
/// regenerated file would differ under the same batch ref.
#[tracing::instrument(skip(state), fields(user = %user.user_id, batch = %batch_id))]
pub async fn get_batch_file<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
) -> Result<Response, AppError> {
    require_admin(&user)?;
    let file = repo::get_refund_batch_file(state.db(), batch_id).await?;
    Ok(file_download_response(&file.file_ref, file.file_text))
}

/// POST /admin/refunds/batches/{id}/status — record where the file got to at the bank
/// (`uploaded` → `confirmed` | `rejected`). Admin only. Illegal steps are a typed Thai 409 from the
/// shared pure transition table.
///
/// `voided` is the ONE value rejected here by name (400), because it is the one the transition table
/// would otherwise WAVE THROUGH: voiding must also un-mark every item AND flip its source row back
/// to `pending` — that is what returns the money to the queue — and must carry a reason, so it has
/// its own endpoint. Coming through this door it would flip the header while leaving the obligations
/// claimed and marked processed, i.e. never refundable again: the exact bug the void path exists to
/// prevent.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, batch = %batch_id))]
pub async fn set_batch_status<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
    Json(req): Json<SetRefundBatchStatusRequest>,
) -> Result<Json<ApiResponse<RefundBatchRow>>, AppError> {
    require_admin(&user)?;
    let Some(status) = BatchStatus::parse(req.status.trim()) else {
        return Err(AppError::BadRequest(format!(
            "สถานะไม่ถูกต้อง — ต้องเป็นหนึ่งใน {}",
            batch_status::BATCH_STATUSES.join(", ")
        )));
    };
    if status == BatchStatus::Voided {
        return Err(AppError::BadRequest(
            "การยกเลิกไฟล์ต้องใช้ปุ่มยกเลิก (ระบุเหตุผล) เพื่อให้รายการกลับเข้าคิวรอคืนเงิน".to_string(),
        ));
    }
    let note = match req.note.as_deref() {
        Some(n) => clean_note("หมายเหตุ", n, false)?,
        None => None,
    };
    let row =
        repo::set_refund_batch_status(state.db(), batch_id, status, note.as_deref(), user.user_id)
            .await?;
    Ok(Json(ApiResponse::success(row)))
}

/// POST /admin/refunds/batches/{id}/void — cancel a refund file that never reached the bank (or that
/// the bank refused) and RETURN every obligation in it to the refundable queue. Admin only.
///
/// This is the escape hatch from the one-way door: without it, a batch whose file was lost left its
/// customers permanently unrefunded — marked `processed` with no money sent — and only a
/// hand-written UPDATE in production could undo it. The reason is mandatory. A batch the bank
/// CONFIRMED cannot be voided (the money moved — un-marking it would refund those customers twice);
/// a second void is a typed 409, not a silent success.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, batch = %batch_id))]
pub async fn void_batch<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
    Json(req): Json<VoidRefundBatchRequest>,
) -> Result<Json<ApiResponse<RefundBatchRow>>, AppError> {
    require_admin(&user)?;
    let Some(reason) = clean_note("เหตุผลในการยกเลิก", &req.reason, true)?
    else {
        // `clean_note(.., required = true)` already returned the 400 for a blank reason; this arm is
        // unreachable and is written as an error rather than an `expect` (no panics in the money path).
        return Err(AppError::BadRequest("กรุณาระบุเหตุผลในการยกเลิก".to_string()));
    };
    let row = repo::void_refund_batch(state.db(), batch_id, user.user_id, &reason).await?;
    Ok(Json(ApiResponse::success(row)))
}

/// POST /admin/refunds/batches/{id}/items/void — return SOME of a batch's obligations to the
/// refundable queue (the customers whose credit lines the bank could not deliver), leaving every
/// other obligation in the file settled and the batch's own status untouched. Admin only.
///
/// WHY THIS IS SEPARATE FROM THE WHOLE-BATCH VOID. SCB can ACCEPT a bulk file and still fail
/// individual credit lines — a PromptPay proxy not linked to a receiving account is the everyday
/// case. The file is structurally valid, so it passes the whole-file check and the batch is honestly
/// `confirmed`: most customers got their money, a handful did not. Voiding the whole batch would
/// un-settle the ones who DID, and `confirmed` is terminal so it is not even offered — which would
/// leave a hand-written UPDATE in production as the only remedy.
///
/// It therefore DELIBERATELY BYPASSES the transition table: the status machine describes what
/// happened to the FILE at the bank (still true — it was uploaded and accepted), while this action
/// corrects which OBLIGATIONS the file actually settled. The audit row names them and carries the
/// (mandatory) reason.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, batch = %batch_id))]
pub async fn void_batch_items<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(batch_id): Path<Uuid>,
    Json(req): Json<VoidRefundBatchItemsRequest>,
) -> Result<Json<ApiResponse<RefundBatchDetail>>, AppError> {
    require_admin(&user)?;
    // Pure validation first (non-empty, capped, de-duplicated, every lane parsed) — no DB round trip
    // for a client bug.
    let pairs: Vec<(String, Uuid)> = req
        .sources
        .iter()
        .map(|s| (s.source_kind.clone(), s.source_id))
        .collect();
    let sources = normalize_voided_refund_sources(&pairs)?;
    let Some(reason) = clean_note("เหตุผลในการดึงรายการกลับ", &req.reason, true)?
    else {
        // Unreachable — `clean_note(.., required = true)` already 400'd a blank reason. An error
        // rather than an `expect`: no panics in the money path.
        return Err(AppError::BadRequest(
            "กรุณาระบุเหตุผลในการดึงรายการกลับ".to_string(),
        ));
    };
    let detail =
        repo::void_refund_batch_items(state.db(), batch_id, &sources, user.user_id, &reason)
            .await?;
    Ok(Json(ApiResponse::success(detail)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::PayoutConfigRow;

    /// `1234567896` passes SCB's §14 check digit; `1234567890` — the same number with the check
    /// digit typo'd — does not.
    const GOOD_ACCOUNT: &str = "1234567896";

    fn today() -> NaiveDate {
        scb_export::bangkok_today(Utc::now())
    }

    fn cfg(debit: Option<&str>) -> PayoutConfigRow {
        PayoutConfigRow {
            debit_account: debit.map(str::to_string),
            ..PayoutConfigRow::unset()
        }
    }

    /// THE POINT OF THE SPLIT HELPER: a refund needs the DEBIT accounts and nothing else. An admin
    /// must never have to configure a ภ.ง.ด. payer block — a company TIN, a form code, an income
    /// type — before they can send a customer their own money back, because none of it reaches a
    /// file that emits no certificate.
    #[test]
    fn a_refund_file_needs_the_debit_accounts_and_no_tax_block_at_all() {
        let config = build_transfer_config(&cfg(Some(GOOD_ACCOUNT)), today())
            .expect("a debit account is all a refund needs");
        assert_eq!(config.debit_account, GOOD_ACCOUNT);
        assert_eq!(config.fee_debit_account, GOOD_ACCOUNT, "defaults to debit");
        assert_eq!(config.fee_charge_code, "OUR", "the company bears the fee");

        // Even with EVERY ภ.ง.ด. code stored as garbage — a state the payout export refuses outright
        // — the refund file still builds, because those fields can only be written onto a `WHTCER`
        // or a `WHTDET` and this file emits neither.
        let mut junk = cfg(Some(GOOD_ACCOUNT));
        junk.wht_form_type_code = "02".to_string(); // not one of the seven
        junk.wht_pay_type_code = "4".to_string(); // real, but needs a remark we cannot supply
        junk.wht_income_type_code = "nope".to_string();
        assert!(
            build_transfer_config(&junk, today()).is_ok(),
            "a stored tax code must not block a refund"
        );
    }

    /// …but the things the refund file DOES carry are still enforced: `BCHDET` fields 4/5 head the
    /// file (a typo bounces the whole batch at the header) and `TXNDET` field 8 is mandatory on every
    /// credit row.
    #[test]
    fn the_refund_file_still_refuses_a_bad_debit_account_or_fee_code() {
        assert!(
            build_transfer_config(&cfg(None), today()).is_err(),
            "an unset debit account is a 400, not a blank BCHDET"
        );
        for typo in ["1234567890", "123456789", "12345678960"] {
            assert!(
                build_transfer_config(&cfg(Some(typo)), today()).is_err(),
                "{typo} is not a 10-digit SCB account that passes the check digit"
            );
        }
        let mut bad_fee = cfg(Some(GOOD_ACCOUNT));
        bad_fee.fee_charge_code = "SHA".to_string(); // BAHTNET's code, not TBFeeOther's
        assert!(build_transfer_config(&bad_fee, today()).is_err());
    }

    /// The refund file is `PPY` and its destination is a PHONE. A 10-digit Thai mobile is the `MOB`
    /// proxy; anything SCB cannot stamp a type from is REFUSED, so a stray landline or a truncated
    /// number excludes that one customer instead of addressing money at nothing.
    #[test]
    fn only_a_classifiable_promptpay_proxy_can_receive_a_refund() {
        let dest = CreditDestination::promptpay(scb_export::digits_only("081-234-5678"));
        assert_eq!(dest.credit_account(), "0812345678");
        assert!(scb_export::destination_rejection(REFUND_PRODUCT, &dest).is_none());
        assert_eq!(dest.proxy_type_code(), Some("MOB"));

        for unusable in ["021234567", "12345", "08123456789012345678"] {
            let dest = CreditDestination::promptpay(scb_export::digits_only(unusable));
            assert!(
                scb_export::destination_rejection(REFUND_PRODUCT, &dest).is_some(),
                "{unusable} is not a PromptPay proxy SCB can stamp a type from"
            );
        }
    }
}
