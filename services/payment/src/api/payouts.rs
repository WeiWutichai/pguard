//! Guard-payout admin endpoints — generate the SCB Business Net bulk-upload file (PromptPay credit
//! + ภ.ง.ด.53 WHT) that pays guards. THE MONEY PATH (payout side). Admin-role gated.
//!
//! - `GET /admin/payouts/config` — the single-row payout settings (debit accounts + WHT terms).
//! - `PUT /admin/payouts/config` — save them (incremental).
//! - `GET /admin/payouts/preview` — the unpaid backlog aggregated per guard (who gets paid what) +
//!   the guards EXCLUDED (missing tax id / PromptPay proxy).
//! - `POST /admin/payouts/export` — build the file, PERSIST the batch (marking those bookings paid),
//!   return the text as UTF-8 (no BOM) for download.
//!
//! The aggregation reads the authoritative `base_fee` per booking from booking's internal read, the
//! guard PII + the company WHT-payer block from profile's internal reads, and computes the payout
//! with the pure [`crate::domain::payout`] math + the pure [`crate::domain::scb_export`] file writer.

use axum::extract::State;
use axum::http::header;
use axum::response::{IntoResponse, Response};
use axum::Json;
use chrono::Utc;
use serde::Serialize;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;

use crate::booking_client::BookingReader;
use crate::domain::payout::compute_payout;
use crate::domain::promptpay::{classify_proxy, PromptPayProxy};
use crate::domain::scb_export::{
    self, format_amount, PayoutBatch, PayoutConfig, PayoutRecipient, WhtPayer,
};
use crate::models::{NewPayoutBatch, NewPayoutItem, PayoutConfigRow, UpdatePayoutConfigRequest};
use crate::profile_client::{OrgTaxInfo, ProfileReader};
use crate::repo;
use crate::state::PaymentDeps;

fn require_admin(user: &AuthUser) -> Result<(), AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
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
    let cfg = repo::upsert_payout_config(state.db(), &req, user.user_id).await?;
    Ok(Json(ApiResponse::success(cfg)))
}

// ----- preview + export shared aggregation -----

/// One guard EXCLUDED from the batch, with why (so the admin can fix the profile and re-run).
#[derive(Debug, Serialize)]
pub struct ExcludedGuard {
    pub guard_id: Uuid,
    pub reason: String,
    pub job_count: usize,
}

/// The aggregation result: the SCB recipients to pay, the per-booking paid-marker items, and the
/// guards excluded with reasons.
struct Aggregated {
    recipients: Vec<PayoutRecipient>,
    items: Vec<NewPayoutItem>,
    excluded: Vec<ExcludedGuard>,
}

/// SCB proxy value + type for a guard: prefer the national/tax id (`NAT`), fall back to the phone
/// (`MOB`). `None` when neither is a valid PromptPay proxy.
fn resolve_proxy(tax_id: Option<&str>, phone: Option<&str>) -> Option<(String, PromptPayProxy)> {
    if let Some(t) = tax_id.map(str::trim).filter(|s| !s.is_empty()) {
        if let Some(p) = classify_proxy(t) {
            return Some((t.to_string(), p));
        }
    }
    if let Some(ph) = phone.map(str::trim).filter(|s| !s.is_empty()) {
        if let Some(p) = classify_proxy(ph) {
            return Some((ph.to_string(), p));
        }
    }
    None
}

/// Build the payout recipients + paid-marker items from the unpaid backlog. `wht_rate` drives the
/// withholding (0 → no WHT). Fetches `base_fee` per booking (booking reader) + guard PII (profile
/// reader); groups by guard; EXCLUDES a guard missing a name, a valid proxy, or — when withholding
/// — a tax id (the ภ.ง.ด. recipient TIN), never silently paying blanks.
async fn aggregate<S: PaymentDeps>(
    state: &S,
    wht_rate: rust_decimal::Decimal,
) -> Result<Aggregated, AppError> {
    let rows = repo::unpaid_payout_rows(state.db_read()).await?;

    // Group consecutive rows by guard (the query orders by guard_id).
    let mut by_guard: Vec<(Uuid, Vec<crate::models::UnpaidPayoutRow>)> = Vec::new();
    for row in rows {
        match by_guard.last_mut() {
            Some((g, jobs)) if *g == row.guard_id => jobs.push(row),
            _ => by_guard.push((row.guard_id, vec![row])),
        }
    }

    let mut recipients = Vec::new();
    let mut items = Vec::new();
    let mut excluded = Vec::new();

    for (guard_id, jobs) in by_guard {
        // Sum this guard's jobs (per-job compute → sum, so per-job rounding is preserved).
        let mut income = rust_decimal::Decimal::ZERO;
        let mut wht = rust_decimal::Decimal::ZERO;
        let mut guard_items = Vec::new();
        for job in &jobs {
            let booking = state.booking_reader().get_booking(job.booking_id).await?;
            let hours = job
                .actual_hours
                .unwrap_or_else(|| rust_decimal::Decimal::from(booking.hours.max(0)));
            let amt = compute_payout(booking.base_fee, hours, job.commission_percent, wht_rate);
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

        let pii = state
            .profile_reader()
            .get_guard_payout_profile(guard_id)
            .await?;
        let name = pii
            .full_name
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty());
        let proxy = resolve_proxy(pii.tax_id.as_deref(), pii.phone.as_deref());
        let has_tax_id = pii
            .tax_id
            .as_deref()
            .map(str::trim)
            .is_some_and(|s| !s.is_empty());

        let reason = if name.is_none() {
            Some("ไม่มีชื่อในโปรไฟล์ (จำเป็นสำหรับใบหัก ณ ที่จ่าย)")
        } else if proxy.is_none() {
            Some("ไม่มีพร้อมเพย์ (เลขบัตร ปชช./เบอร์) ที่ใช้โอนได้")
        } else if wht_rate > rust_decimal::Decimal::ZERO && !has_tax_id {
            Some("ไม่มีเลขบัตรประชาชน/เลขผู้เสียภาษี (จำเป็นสำหรับหัก ณ ที่จ่าย)")
        } else {
            None
        };

        if let Some(reason) = reason {
            excluded.push(ExcludedGuard {
                guard_id,
                reason: reason.to_string(),
                job_count: jobs.len(),
            });
            continue;
        }

        let (proxy_value, _) = proxy.expect("checked above");
        recipients.push(PayoutRecipient {
            transaction_ref: format!("PO-{}", &guard_id.simple().to_string()[..12]),
            proxy: proxy_value,
            tax_id: pii.tax_id.clone().unwrap_or_default(),
            name: name.expect("checked above").to_string(),
            address: pii.address.clone().unwrap_or_default(),
            income,
            wht,
            phone: pii.phone.clone(),
            email: None,
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
    pub name: String,
    pub proxy_masked: String,
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
fn mask_proxy(proxy: &str) -> String {
    let n = proxy.chars().count();
    if n <= 4 {
        return proxy.to_string();
    }
    let last4: String = proxy.chars().skip(n - 4).collect();
    format!("{}{last4}", "*".repeat(n - 4))
}

/// GET /admin/payouts/preview — the unpaid backlog aggregated per guard (who gets paid what) +
/// the excluded guards. Read-only: computes but does NOT persist or mark anything paid.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn preview<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<PayoutPreview>>, AppError> {
    require_admin(&user)?;
    let cfg = repo::get_payout_config(state.db()).await?;
    let agg = aggregate(&state, cfg.wht_rate_percent).await?;

    let total_transfer: rust_decimal::Decimal =
        agg.recipients.iter().map(|r| r.transfer_amount()).sum();
    let total_wht: rust_decimal::Decimal = agg.recipients.iter().map(|r| r.wht).sum();
    let recipients = agg
        .recipients
        .iter()
        .map(|r| PreviewRecipient {
            name: r.name.clone(),
            proxy_masked: mask_proxy(&r.proxy),
            income: format_amount(r.income),
            wht: format_amount(r.wht),
            transfer: format_amount(r.transfer_amount()),
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

/// Build the SCB `PayoutConfig` + `WhtPayer` from the stored config + the company org block, failing
/// with a typed 400 when a required field (debit account, company tax id/name) is unset.
fn build_payer_and_config(
    cfg: &PayoutConfigRow,
    org: &OrgTaxInfo,
) -> Result<(WhtPayer, PayoutConfig), AppError> {
    let debit = cfg
        .debit_account
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| {
            AppError::BadRequest("ยังไม่ได้ตั้งค่าบัญชีตัดเงินบริษัท (payout config)".to_string())
        })?;
    let fee = cfg
        .fee_debit_account
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or(debit);

    let payer = WhtPayer {
        tax_id: org
            .tax_id
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .ok_or_else(|| {
                AppError::BadRequest("ยังไม่ได้ตั้งเลขผู้เสียภาษีบริษัท (Settings → บริษัท)".to_string())
            })?
            .to_string(),
        name: org
            .company_name
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .ok_or_else(|| AppError::BadRequest("ยังไม่ได้ตั้งชื่อบริษัท (Settings → บริษัท)".to_string()))?
            .to_string(),
        address: org.address.clone().unwrap_or_default(),
    };

    let config = PayoutConfig {
        debit_account: debit.to_string(),
        fee_debit_account: fee.to_string(),
        value_date: Utc::now().date_naive(),
        wht_form_type_code: cfg.wht_form_type_code.clone(),
        wht_pay_type_code: cfg.wht_pay_type_code.clone(),
        wht_income_type_code: cfg.wht_income_type_code.clone(),
        wht_income_desc: cfg.wht_income_desc.clone(),
        wht_rate_percent: cfg.wht_rate_percent,
    };
    Ok((payer, config))
}

/// POST /admin/payouts/export — build the SCB upload file for the whole unpaid backlog, PERSIST the
/// batch + its per-booking paid-markers (so no job is ever paid twice), and return the file text as
/// UTF-8 (no BOM) for download. 409 `PAYOUT_ALREADY_PAID` if a concurrent export won a booking; 400
/// when there is nothing to pay or the company/debit config is incomplete.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn export<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Response, AppError> {
    require_admin(&user)?;
    let cfg = repo::get_payout_config(state.db()).await?;
    let org = state.profile_reader().get_org_settings().await?;
    let (payer, config) = build_payer_and_config(&cfg, &org)?;

    let agg = aggregate(&state, cfg.wht_rate_percent).await?;
    if agg.recipients.is_empty() {
        return Err(AppError::BadRequest(
            "ไม่มีรายการค้างจ่ายที่จ่ายได้ในขณะนี้".to_string(),
        ));
    }

    // batch_ref = <DDMMYYHHMMSS>PPY (the toolkit shape); file name = SCB_file_reference_<first 12>.
    let now = Utc::now();
    let batch_ref = format!(
        "{}{}",
        now.format("%d%m%y%H%M%S"),
        scb_export::PRODUCT_PROMPTPAY
    );
    let file_ref = format!(
        "SCB_file_reference_{}",
        &batch_ref[..12.min(batch_ref.len())]
    );

    let batch = PayoutBatch {
        file_ref: file_ref.clone(),
        system_ref: "PGUARD-PAYOUT".to_string(),
        batch_ref: batch_ref.clone(),
        payer,
        config: config.clone(),
        recipients: agg.recipients,
    };
    let file_text = scb_export::generate(&batch);
    let total_transfer: rust_decimal::Decimal =
        batch.recipients.iter().map(|r| r.transfer_amount()).sum();

    // Persist the batch + paid-markers (the UNIQUE(booking_id) is the atomic double-pay guard).
    repo::insert_payout_batch(
        state.db(),
        &NewPayoutBatch {
            file_ref,
            system_ref: batch.system_ref.clone(),
            batch_ref,
            value_date: config.value_date,
            total_amount: total_transfer,
            created_by: Some(user.user_id),
            items: agg.items,
        },
    )
    .await?;

    let filename = format!("{}.txt", batch.file_ref);
    Ok((
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
        .into_response())
}
