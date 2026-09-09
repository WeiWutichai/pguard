//! The two TAX REPORTS behind stream ② — the half of *ยอดที่โดนหักเข้าระบบ* that must NOT be swept
//! into the company revenue account. Admin-role gated.
//!
//! - `GET /admin/reports/vat-register` — the OUTPUT-VAT register (รายงานภาษีขาย) backing a **ภ.พ.30**
//!   filing for one month.
//! - `GET /admin/reports/wht-payees` — the **ภ.ง.ด.3/53** payee list for one month.
//!
//! # Why these are REPORTS and the platform cut is a FILE
//!
//! VAT (7%) and the WHT withheld from guards sit in the same bank account as the platform's own cut,
//! and it is tempting to sweep all three together. They are not ours: VAT is collected FOR the
//! Revenue Department (a liability from the moment we take it — the repo's `NET_REVENUE_EXPR`
//! already subtracts it from revenue for exactly this reason), and the withheld WHT is the guard's
//! tax that we hold on the Revenue Department's behalf. Both are remitted by **e-filing** — ภ.พ.30
//! monthly, ภ.ง.ด.3/53 by the 7th of the following month — not by a bulk transfer file. So they get
//! a report that backs a filing, and the `OAT` sweep carries the platform's cut alone.
//!
//! # The one figure that was unreachable
//!
//! `payout_batch_items.wht` has been WRITE-ONLY since migration 0007: the payout export computes and
//! stores it on every certificate line, and no endpoint has ever read it back. The single figure Thai
//! law requires us to report was, until this module, not obtainable from the running system at all.
//!
//! # Bucketing, stated because the three streams cannot otherwise be tied out
//!
//! Each report says which timestamp it buckets on, and the choices are not interchangeable:
//!  * the VAT register buckets on **`paid_at`** — Thai VAT on a service has its tax point at receipt
//!    of payment, and it is the same basis `repo::revenue_series` uses, so the register and the
//!    revenue chart tie out line for line;
//!  * the WHT payee list buckets on **`payout_batches.value_date`** — the day the transfer settles is
//!    the day the payment to the payee is made, which is the month the filing covers;
//!  * the platform-cut sweep buckets on **`payments.updated_at`** — when the cut became final, the
//!    same basis the guard-payout backlog uses so the two halves of one job move together.
//!
//! # CSV
//!
//! Both reports serve `?format=csv`, rendered SERVER-SIDE by [`crate::domain::csv`]: RFC 4180
//! quoting, a UTF-8 BOM (without it Excel on Thai Windows renders every Thai name as mojibake) and
//! formula neutralisation on the free-text columns. A browser cannot escape what it never sees, and
//! a comma inside a Thai company name silently shifts every later column of that row.

use axum::extract::{Query, State};
use axum::http::header;
use axum::response::{IntoResponse, Response};
use axum::Json;
use chrono::{DateTime, NaiveDate, TimeZone, Utc};
use futures::stream::{StreamExt, TryStreamExt};
use rust_decimal::Decimal;
use serde::Deserialize;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;

use crate::api::payouts::require_admin;
use crate::domain::csv;
use crate::domain::scb_export::format_amount;
use crate::models::{VatRegisterReport, WhtPayeeReport, WhtPayeeRow};
use crate::profile_client::ProfileReader;
use crate::repo;
use crate::state::PaymentDeps;

/// How many payee PII reads the WHT report keeps in flight at once. Bounded for the same reason the
/// payout/refund aggregations bound theirs: profile is a shared service on a modest pool, and one
/// admin's click must not become a burst against the customer-facing traffic on it. A month's payee
/// list is tens of guards, not thousands, so this is ample.
const PROFILE_FANOUT: usize = 8;

/// `?month=YYYY-MM` — the filing period. Required, because both of these back a MONTHLY return and a
/// silently-defaulted period on a tax report is a filing for the wrong month.
#[derive(Debug, Deserialize)]
pub struct MonthQuery {
    pub month: String,
    /// `csv` renders the spreadsheet an accountant actually works in; anything else (including
    /// absent) returns JSON.
    #[serde(default)]
    pub format: Option<String>,
}

impl MonthQuery {
    /// Whether the caller asked for the spreadsheet.
    fn wants_csv(&self) -> bool {
        self.format.as_deref().map(str::trim) == Some("csv")
    }
}

/// Parse `YYYY-MM` into the half-open Thai-local month `[first, next_first)`.
///
/// The window is built on the BANGKOK calendar and then converted to UTC instants, because a filing
/// period is a Thai calendar month: a payment taken at 06:00 Bangkok on the 1st is 23:00 UTC on the
/// PREVIOUS day, and bucketing it in UTC would file it in the wrong month. Returns the two UTC
/// instants plus the two Bangkok dates (the WHT report windows on a `DATE` column, which needs the
/// dates rather than the instants).
fn month_window(
    month: &str,
) -> Result<(DateTime<Utc>, DateTime<Utc>, NaiveDate, NaiveDate), AppError> {
    let bad = || AppError::BadRequest("รูปแบบเดือนไม่ถูกต้อง — ต้องเป็น YYYY-MM เช่น 2026-09".to_string());
    let (year, rest) = month.trim().split_once('-').ok_or_else(bad)?;
    let year: i32 = year.parse().map_err(|_| bad())?;
    let month_no: u32 = rest.parse().map_err(|_| bad())?;
    // A four-digit Gregorian year: a Buddhist-era year (2569) typed by mistake must be refused, not
    // filed as the year 2569.
    if !(2000..=2100).contains(&year) || !(1..=12).contains(&month_no) {
        return Err(bad());
    }
    let first = NaiveDate::from_ymd_opt(year, month_no, 1).ok_or_else(bad)?;
    let next_first = if month_no == 12 {
        NaiveDate::from_ymd_opt(year + 1, 1, 1)
    } else {
        NaiveDate::from_ymd_opt(year, month_no + 1, 1)
    }
    .ok_or_else(bad)?;

    // Asia/Bangkok is UTC+7 year-round (no DST since 1941), so a fixed offset is EXACT.
    let tz = chrono::FixedOffset::east_opt(7 * 3600).ok_or_else(|| {
        // Unreachable: a compile-time constant well inside ±24h. An error rather than an `expect` —
        // no panics in a request path.
        AppError::Internal("bangkok offset".to_string())
    })?;
    let to_utc = |d: NaiveDate| -> Result<DateTime<Utc>, AppError> {
        tz.from_local_datetime(&d.and_hms_opt(0, 0, 0).ok_or_else(bad)?)
            .single()
            .map(|dt| dt.with_timezone(&Utc))
            .ok_or_else(|| AppError::Internal("bangkok midnight".to_string()))
    };
    Ok((to_utc(first)?, to_utc(next_first)?, first, next_first))
}

/// A CSV download: the rendered document (BOM included) with the `attachment` disposition.
///
/// ONE helper for both reports so the two can never disagree about the content type or how the
/// filename is built. `text/csv; charset=utf-8` is declared even though the BOM makes the encoding
/// self-describing — a header a proxy can read beats a byte-order mark only the opener sees.
fn csv_download(filename: &str, body: String) -> Response {
    (
        [
            (header::CONTENT_TYPE, "text/csv; charset=utf-8".to_string()),
            (
                header::CONTENT_DISPOSITION,
                format!("attachment; filename=\"{filename}\""),
            ),
        ],
        body,
    )
        .into_response()
}

// ----- ภ.พ.30 — the output-VAT register -----

/// GET /admin/reports/vat-register?month=YYYY-MM[&format=csv] — the output-VAT register
/// (รายงานภาษีขาย) for one month: per settled payment, the day the customer paid, the customer, the
/// VAT-exclusive subtotal and the VAT charged; plus the period totals an accountant transcribes onto
/// the ภ.พ.30. Admin only.
///
/// BUCKETED ON `paid_at` (Thai calendar days) — the VAT tax point for a service is receipt of
/// payment, and it is the basis the revenue report uses, so the two tie out. The AMOUNTS are the
/// SETTLED split, so a job paid in one month and prorated in the next reports its final VAT in the
/// month it was paid. See [`repo::vat_register`].
///
/// The customer is reported as an ID, not a name: resolving names would be a cross-service fan-out
/// per row on a report that runs to thousands of rows a month, and the admin panel already has a
/// BATCH resolver (`POST /admin/users/resolve`) for exactly this.
///
/// Read from the REPLICA — a read-only analytics query over a closed month, with no read-after-write
/// relationship to anything (unlike the sweep backlog, which must be primary).
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn vat_register<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<MonthQuery>,
) -> Result<Response, AppError> {
    require_admin(&user)?;
    let (from, to, _, _) = month_window(&q.month)?;
    let rows = repo::vat_register(state.db_read(), from, to).await?;

    let total_subtotal: Decimal = rows.iter().map(|r| r.subtotal).sum();
    let total_vat: Decimal = rows.iter().map(|r| r.vat).sum();
    let month = q.month.trim().to_string();

    if q.wants_csv() {
        // The header is Thai + English so the file reads on its own to both the accountant and
        // whoever set it up. The TOTAL row is included: it is what gets transcribed onto the form,
        // and an accountant re-summing 3000 rows by hand to get it would be the point of the export
        // defeated.
        let mut csv_rows: Vec<Vec<String>> = rows
            .iter()
            .map(|r| {
                vec![
                    r.date.to_string(),
                    r.payment_id.to_string(),
                    r.booking_id.to_string(),
                    r.customer_id.to_string(),
                    format_amount(r.subtotal),
                    format_amount(r.vat),
                    format_amount(r.total),
                ]
            })
            .collect();
        csv_rows.push(vec![
            "รวม / TOTAL".to_string(),
            String::new(),
            String::new(),
            String::new(),
            format_amount(total_subtotal),
            format_amount(total_vat),
            format_amount(total_subtotal + total_vat),
        ]);
        let body = csv::document(
            &[
                "วันที่ / Date",
                "รหัสการชำระเงิน / Payment ID",
                "รหัสงาน / Booking ID",
                "รหัสลูกค้า / Customer ID",
                "มูลค่าก่อนภาษี / Subtotal",
                "ภาษีขาย / VAT",
                "รวม / Total",
            ],
            &csv_rows,
        );
        return Ok(csv_download(&format!("vat-register-{month}.csv"), body));
    }

    Ok(Json(ApiResponse::success(VatRegisterReport {
        month,
        row_count: rows.len(),
        rows,
        total_subtotal,
        total_vat,
        total_amount: total_subtotal + total_vat,
    }))
    .into_response())
}

// ----- ภ.ง.ด.3/53 — the payee list -----

/// GET /admin/reports/wht-payees?month=YYYY-MM[&format=csv] — the ภ.ง.ด.3/53 payee list for one
/// month: per payee, their TIN, name, address, the income type, the gross assessable income paid and
/// the tax withheld; plus the period totals. Admin only.
///
/// READ FROM `payout_batch_items`, whose `wht` column has been WRITE-ONLY since migration 0007 — the
/// one figure the law requires us to report was previously unreachable from the running system.
///
/// BUCKETED ON `payout_batches.value_date` — the day the transfer settles is the day the payment to
/// the payee is made, which is the month the filing covers (due by the 7th of the following month).
///
/// VOIDED ITEMS ARE EXCLUDED: money that was never actually paid was never actually withheld, so a
/// voided batch — or a per-item void on a confirmed one — must not appear on a tax return. See
/// [`repo::wht_payees`].
///
/// The FORM CODE and the INCOME TYPE come from the stored `payout_config` and are reported exactly as
/// stored: which ภ.ง.ด. form applies is the operator's TAX decision, and a report that silently
/// "corrected" it would be filing something other than what was certified to the payee.
///
/// The payee PII is resolved from profile with bounded concurrency; a guard whose profile is missing
/// is STILL LISTED, with the fields blank, because the withholding happened and the filing has to
/// account for it — dropping the row would under-report a tax return.
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn wht_payees<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<MonthQuery>,
) -> Result<Response, AppError> {
    require_admin(&user)?;
    let (_, _, from, to) = month_window(&q.month)?;
    let totals = repo::wht_payees(state.db_read(), from, to).await?;
    // The CONFIG comes off the PRIMARY even though the rows come off the replica. The two ภ.ง.ด.
    // codes below are a TAX DECISION an admin may have corrected minutes before running this, and a
    // replica-lagged read would print the superseded form code on a document that goes to the
    // Revenue Department. One extra single-row read on the primary is a cheap price for that.
    let cfg = repo::get_payout_config(state.db()).await?;

    // Resolve every payee's PII with bounded concurrency. A `NotFound` becomes blank fields on a row
    // that is still reported; ANY other error (transport, 5xx, decode) fails the whole report loudly
    // — a tax return silently missing a payee because of a network blip is worse than a retry.
    let guards: Vec<Uuid> = totals.iter().map(|t| t.guard_id).collect();
    // `buffered` (not `buffer_unordered`) so the results come back in the SAME order as `totals` —
    // the two are zipped below, and an unordered join would attach one guard's name to another
    // guard's withholding on a document that goes to the Revenue Department.
    let reader = state.profile_reader();
    let pii: Vec<Option<crate::profile_client::GuardPayoutProfile>> = futures::stream::iter(guards)
        .map(|guard_id| async move {
            match reader.get_guard_payout_profile(guard_id).await {
                Ok(p) => Ok(Some(p)),
                Err(AppError::NotFound(_)) => Ok(None),
                Err(e) => Err(e),
            }
        })
        .buffered(PROFILE_FANOUT)
        .try_collect()
        .await?;

    let rows: Vec<WhtPayeeRow> = totals
        .iter()
        .zip(pii)
        .map(|(t, p)| WhtPayeeRow {
            guard_id: t.guard_id,
            // The TIN is reported as STORED (digits and any separators the profile holds) rather than
            // normalised here: this column is transcribed onto a government form, and a report is the
            // wrong place to silently reshape an identifier. The SCB writer normalises for the FILE.
            tax_id: p.as_ref().and_then(|p| p.tax_id.clone()),
            name: p.as_ref().and_then(|p| p.full_name.clone()),
            address: p.as_ref().and_then(|p| p.address.clone()),
            job_count: t.job_count,
            income: t.income,
            wht: t.wht,
        })
        .collect();

    let total_income: Decimal = rows.iter().map(|r| r.income).sum();
    let total_wht: Decimal = rows.iter().map(|r| r.wht).sum();
    let month = q.month.trim().to_string();

    if q.wants_csv() {
        let mut csv_rows: Vec<Vec<String>> = rows
            .iter()
            .map(|r| {
                vec![
                    r.guard_id.to_string(),
                    r.tax_id.clone().unwrap_or_default(),
                    r.name.clone().unwrap_or_default(),
                    r.address.clone().unwrap_or_default(),
                    cfg.wht_income_type_code.clone(),
                    cfg.wht_income_desc.clone(),
                    r.job_count.to_string(),
                    format_amount(r.income),
                    format_amount(r.wht),
                ]
            })
            .collect();
        csv_rows.push(vec![
            "รวม / TOTAL".to_string(),
            String::new(),
            String::new(),
            String::new(),
            String::new(),
            String::new(),
            rows.iter().map(|r| r.job_count).sum::<i64>().to_string(),
            format_amount(total_income),
            format_amount(total_wht),
        ]);
        let body = csv::document(
            &[
                "รหัส รปภ / Guard ID",
                "เลขประจำตัวผู้เสียภาษี / TIN",
                "ชื่อผู้ถูกหักภาษี / Payee name",
                "ที่อยู่ / Address",
                "ประเภทเงินได้ / Income type",
                "รายละเอียดเงินได้ / Income description",
                "จำนวนงาน / Jobs",
                "จำนวนเงินที่จ่าย / Gross income",
                "ภาษีที่หัก / Tax withheld",
            ],
            &csv_rows,
        );
        return Ok(csv_download(
            &format!("wht-payees-{}-{month}.csv", cfg.wht_form_type_code),
            body,
        ));
    }

    Ok(Json(ApiResponse::success(WhtPayeeReport {
        month,
        // The user's TAX DECISION, reported as stored — never derived and never "corrected" here.
        form_type_code: cfg.wht_form_type_code.clone(),
        income_type_code: cfg.wht_income_type_code.clone(),
        income_description: cfg.wht_income_desc.clone(),
        payee_count: rows.len(),
        rows,
        total_income,
        total_wht,
    }))
    .into_response())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn day(y: i32, m: u32, d: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, d).expect("valid date")
    }

    /// THE BUCKETING TEST. A filing period is a THAI calendar month, so the window's edges are
    /// Bangkok midnights — 17:00 UTC the previous day. Bucketing on UTC midnights instead would file
    /// every payment taken between 00:00 and 07:00 Bangkok on the 1st into the PREVIOUS month's
    /// return.
    #[test]
    fn a_month_window_runs_from_bangkok_midnight_to_bangkok_midnight() {
        let (from, to, first, next) = month_window("2026-09").expect("valid month");
        assert_eq!(first, day(2026, 9, 1));
        assert_eq!(next, day(2026, 10, 1));
        assert_eq!(from.to_rfc3339(), "2026-08-31T17:00:00+00:00");
        assert_eq!(to.to_rfc3339(), "2026-09-30T17:00:00+00:00");
        // December rolls the YEAR, not the month number.
        let (_, _, dec_first, dec_next) = month_window("2026-12").expect("valid month");
        assert_eq!(dec_first, day(2026, 12, 1));
        assert_eq!(dec_next, day(2027, 1, 1));
        // Whitespace off a query string is tolerated.
        assert!(month_window(" 2026-09 ").is_ok());
    }

    /// A tax report must never silently file the wrong period, so an unparseable month is a 400
    /// rather than a default.
    #[test]
    fn an_unparseable_or_out_of_range_month_is_refused() {
        for bad in [
            "", "2026", "2026-", "-09", "2026-00", "2026-13", "26-09", "2026/09", "abcd-ef",
            // A Buddhist-era year typed by mistake: 2569 BE is 2026 CE, and filing it as the year
            // 2569 would be a report nobody could reconcile.
            "2569-09",
            // A year before the platform existed is a typo, not a period.
            "1999-09",
        ] {
            assert!(month_window(bad).is_err(), "{bad:?} must be refused");
        }
    }

    #[test]
    fn csv_is_opt_in_and_everything_else_is_json() {
        let csv = MonthQuery {
            month: "2026-09".to_string(),
            format: Some("csv".to_string()),
        };
        assert!(csv.wants_csv());
        for other in [None, Some("json".to_string()), Some("CSV".to_string())] {
            let q = MonthQuery {
                month: "2026-09".to_string(),
                format: other.clone(),
            };
            assert!(!q.wants_csv(), "{other:?} is not the CSV opt-in");
        }
    }
}
