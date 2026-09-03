//! PURE generator for the **SCB Business Net "Excel Toolkit" upload file** — the guard-payout
//! variant (PromptPay credit + ภ.ง.ด.53 withholding-tax certificate). No DB/HTTP/NATS; 100%
//! unit-testable. This is the ONE authoritative place the pipe-delimited upload text is assembled,
//! mirroring the format reverse-engineered from `CPX_Toolkit_Template.xlsm` v1.3.8 (see
//! `docs/reviews/CPX_Toolkit_Reverse_Engineering.md`).
//!
//! File shape (records separated by CRLF, NO trailing newline; delimiter `|`):
//! ```text
//! HEADER|fileRef|systemRef
//! BCHDET|batchRef|PPY|valueDate(YYYYMMDD)|debitAcc|feeDebitAcc|totalTransfer|creditCount||
//!   TXNDET|... 28 fields (one per guard; PromptPay proxy = national id NAT / phone MOB)
//!   WHTCER|... 19 header + 1 income-detail block of 7 (only when the batch withholds tax)
//! TRAILR|1|creditCount|totalTransfer
//! ```
//! The **amount transferred** to a guard is `income − wht` (the WHT is withheld and remitted to the
//! Revenue Department separately); the `WHTCER` records the gross `income` and the withheld `wht`.
//! The DEBIT total and the TRAILR total are the sum of the actual transfers (net of WHT).

use chrono::NaiveDate;
use rust_decimal::Decimal;

use crate::domain::promptpay::{classify_proxy, PromptPayProxy};

/// Field delimiter — the whole file is pipe-separated (SCB toolkit `Public Const delim`).
pub const DELIM: char = '|';
/// Record identifiers (column 0 of every line).
pub const HEADER_CODE: &str = "HEADER";
pub const BATCH_CODE: &str = "BCHDET";
pub const CREDIT_CODE: &str = "TXNDET";
pub const WHT_CODE: &str = "WHTCER";
pub const TRAILER_CODE: &str = "TRAILR";
/// Product code for a PromptPay credit transfer (SCB Master_data `PPY`).
pub const PRODUCT_PROMPTPAY: &str = "PPY";
/// SCB PromptPay proxy-type codes (`colProxyTypeCode`): national/tax id vs mobile number.
pub const PROXY_NATIONAL_ID: &str = "NAT";
pub const PROXY_MOBILE: &str = "MOB";
/// Y/N flag literals (SCB toolkit `FLAG_Y`/`FLAG_N`).
pub const FLAG_Y: &str = "Y";
pub const FLAG_N: &str = "N";
/// SCB uses CRLF between records; the trailer carries NO trailing newline.
const NEWLINE: &str = "\r\n";

/// The withholding-tax PAYER — the company doing the withholding. Sourced from
/// `profile.org_settings` (`company_name` / `tax_id` / `address`), reused as the ภ.ง.ด. payer block.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WhtPayer {
    pub tax_id: String,
    pub name: String,
    pub address: String,
}

/// Batch-level configuration an admin sets once (company debit account + the ภ.ง.ด. terms). These
/// are NOT per-guard — they head the file (`BCHDET`) or repeat verbatim on every `WHTCER`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PayoutConfig {
    /// Company account the transfers are DEBITED from.
    pub debit_account: String,
    /// Account the transfer FEES are debited from (often the same as `debit_account`).
    pub fee_debit_account: String,
    /// Effective/value date of the batch (rendered `YYYYMMDD`, Gregorian).
    pub value_date: NaiveDate,
    /// WHT form-type code (ภ.ง.ด.53 for payments to a company; ภ.ง.ด.3 for an individual). Kept
    /// as the SCB code string so the caller picks the right form per the guard's entity type.
    pub wht_form_type_code: String,
    /// WHT pay-type code (how/why the tax is paid — SCB `WHT Pay Type Code`).
    pub wht_pay_type_code: String,
    /// The assessable-income TYPE code (e.g. service fee / ค่าจ้างทำของ) + its Thai description.
    pub wht_income_type_code: String,
    pub wht_income_desc: String,
    /// Withholding rate percent (e.g. `3` for the standard service-fee rate).
    pub wht_rate_percent: Decimal,
}

/// One guard to pay in this batch. `income` is the assessable income (the guard's pay basis, net of
/// the platform commission); `wht` is the tax withheld from it. The ACTUAL PromptPay transfer is
/// `income − wht` (see [`PayoutRecipient::transfer_amount`]). `proxy` is the guard's PromptPay id —
/// a 13-digit national/tax id (→ `NAT`) or a 10-digit Thai mobile (→ `MOB`), classified by the
/// existing [`classify_proxy`]. For a WHT batch the national/tax id is REQUIRED (it is the ภ.ง.ด.
/// recipient tax id); a phone-only guard cannot ride a WHT batch.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PayoutRecipient {
    /// Per-guard reference echoed on the transfer (customer transaction ref).
    pub transaction_ref: String,
    /// PromptPay proxy value — the national/tax id (13 digits) or the mobile (10 digits).
    pub proxy: String,
    /// The guard's national/tax id — the ภ.ง.ด. recipient tax id. Usually == `proxy` for a NAT
    /// batch; carried separately so a MOB-proxy guard can still have a tax id for the WHT cert.
    pub tax_id: String,
    pub name: String,
    pub address: String,
    /// Assessable income (guard pay basis, VAT-exclusive, net of commission).
    pub income: Decimal,
    /// Tax withheld from `income` (0 when the batch does not withhold).
    pub wht: Decimal,
    /// Optional SMS-notify phone and email-notify address (drive the notification flags).
    pub phone: Option<String>,
    pub email: Option<String>,
}

impl PayoutRecipient {
    /// The money actually transferred via PromptPay: gross income minus the withheld tax.
    pub fn transfer_amount(&self) -> Decimal {
        self.income - self.wht
    }

    /// Whether tax is withheld from this recipient (drives the `WHTCER` row + `TXNDET` WHT flags).
    pub fn has_wht(&self) -> bool {
        self.wht > Decimal::ZERO
    }

    /// SCB proxy-type code for `proxy` (`NAT` for a 13-digit id, `MOB` for a 10-digit phone).
    /// `None` when the proxy is not PromptPay-addressable — such a recipient must be rejected
    /// upstream (never silently dropped from a money file).
    pub fn proxy_type_code(&self) -> Option<&'static str> {
        match classify_proxy(&self.proxy)? {
            PromptPayProxy::NationalId => Some(PROXY_NATIONAL_ID),
            PromptPayProxy::Mobile => Some(PROXY_MOBILE),
        }
    }
}

/// A whole export batch: file/system/batch references, the WHT payer + config, and the recipients.
/// Withholding is PER RECIPIENT — a `WHTCER` row (and the `TXNDET` WHT flags) is emitted for a guard
/// exactly when their `wht > 0`, so a mixed batch (some withheld, some not) is expressed by the
/// recipient amounts alone, with no separate toggle to drift out of sync. Build it in the repo/api
/// layer from the unpaid guard-earnings ledger + `org_settings`, then call [`generate`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PayoutBatch {
    pub file_ref: String,
    pub system_ref: String,
    pub batch_ref: String,
    pub payer: WhtPayer,
    pub config: PayoutConfig,
    pub recipients: Vec<PayoutRecipient>,
}

/// Format a money amount the SCB way: exactly 2 decimals, a plain `.` point, NO thousands
/// separators (mirrors the toolkit's `FormatNumber(x,2)` then strip-commas). Negative is preserved
/// (never expected in a payout, but not silently masked). Rounds to 2 dp with banker's rounding
/// (round-half-to-even) — matching VBA `FormatNumber`. In practice the amounts are already 2 dp
/// (the aggregation layer rounds income/WHT), so this only guards against a stray extra place.
pub fn format_amount(amount: Decimal) -> String {
    format!("{:.2}", amount.round_dp(2))
}

/// Format a date as `YYYYMMDD` (Gregorian) — the SCB `convertDateFormat` output shape.
pub fn format_date(date: NaiveDate) -> String {
    date.format("%Y%m%d").to_string()
}

/// A `Y`/`N` flag: `Y` when the optional value is present and non-blank, else `N`.
fn flag(value: &Option<String>) -> &'static str {
    match value {
        Some(v) if !v.trim().is_empty() => FLAG_Y,
        _ => FLAG_N,
    }
}

/// The optional value trimmed, or empty string when absent/blank.
fn opt(value: &Option<String>) -> String {
    value
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or("")
        .to_string()
}

/// Join a record's fields with the delimiter.
fn join(fields: &[String]) -> String {
    fields.join(&DELIM.to_string())
}

/// Build the `BCHDET` (batch/debit) record — 10 fields. `total_transfer` is the sum of the actual
/// PromptPay transfers (net of WHT); `credit_count` is the number of recipients.
fn batch_row(batch: &PayoutBatch, total_transfer: Decimal, credit_count: usize) -> String {
    join(&[
        BATCH_CODE.to_string(),                 // 0 record id
        batch.batch_ref.clone(),                // 1 customer batch ref
        PRODUCT_PROMPTPAY.to_string(),          // 2 product code
        format_date(batch.config.value_date),   // 3 value date YYYYMMDD
        batch.config.debit_account.clone(),     // 4 debit account
        batch.config.fee_debit_account.clone(), // 5 fee debit account
        format_amount(total_transfer),          // 6 total debit amount
        credit_count.to_string(),               // 7 total no. of credits
        String::new(),                          // 8 internal debit note
        String::new(),                          // 9 payment advice remark (batch level)
    ])
}

/// Build one `TXNDET` (credit) record — 28 fields — for a PromptPay guard payout. The WHT flag/
/// count/amount fields are populated exactly when this recipient has tax withheld (`wht > 0`).
fn credit_row(r: &PayoutRecipient) -> String {
    let proxy_type = r.proxy_type_code().unwrap_or("").to_string();
    let (wht_flag, wht_count, wht_amount) = if r.has_wht() {
        (FLAG_Y.to_string(), "1".to_string(), format_amount(r.wht))
    } else {
        (FLAG_N.to_string(), String::new(), String::new())
    };
    join(&[
        CREDIT_CODE.to_string(),            // 0  record id
        r.transaction_ref.clone(),          // 1  customer transaction ref
        r.proxy.clone(),                    // 2  credit account / PromptPay proxy value
        proxy_type,                         // 3  proxy type (NAT/MOB) — PromptPay only
        "111".to_string(),                  // 4  bank/clearing code — fixed "111" for PromptPay
        "0000".to_string(),                 // 5  branch — fixed "0000" for PromptPay
        format_amount(r.transfer_amount()), // 6  amount transferred (income − WHT)
        String::new(),                      // 7  service type (n/a for PromptPay)
        String::new(),                      // 8  fee charge code
        flag(&r.phone).to_string(),         // 9  SMS notify flag
        opt(&r.phone).replace('-', ""),     // 10 SMS phone (dashes stripped)
        flag(&r.email).to_string(),         // 11 email notify flag
        opt(&r.email),                      // 12 email
        r.name.clone(),                     // 13 recipient name
        r.address.clone(),                  // 14 recipient address line 1
        String::new(),                      // 15 recipient address line 2
        String::new(),                      // 16 recipient address line 3
        wht_flag,                           // 17 WHT required flag
        wht_count,                          // 18 WHT cert count
        wht_amount,                         // 19 WHT total amount
        FLAG_N.to_string(),                 // 20 payment advice remark flag
        FLAG_N.to_string(),                 // 21 invoice flag (no invoices for a payout)
        String::new(),                      // 22 invoice detail count
        String::new(),                      // 23 invoice total amount
        String::new(),                      // 24 VAT total amount
        flag(&r.email).to_string(),         // 25 WHT delivery method (email)
        opt(&r.email),                      // 26 recipient email for the WHT cert
        String::new(),                      // 27 payment advice remark (txn level)
    ])
}

/// Build one `WHTCER` (withholding-tax certificate) record: 19 header fields + one 7-field income
/// detail block. One income type (the guard's service fee), one rate.
fn wht_row(batch: &PayoutBatch, r: &PayoutRecipient, seq: usize) -> String {
    let cfg = &batch.config;
    let payer = &batch.payer;
    let mut fields = vec![
        WHT_CODE.to_string(),           // 0  record id
        String::new(),                  // 1  WHT book no (assigned by the bank/none)
        payer.tax_id.clone(),           // 2  payer tax id
        payer.name.clone(),             // 3  payer name
        payer.address.clone(),          // 4  payer address line 1
        String::new(),                  // 5  payer address line 2
        String::new(),                  // 6  payer address line 3
        r.tax_id.clone(),               // 7  recipient tax id
        r.name.clone(),                 // 8  recipient name
        r.address.clone(),              // 9  recipient address line 1
        String::new(),                  // 10 recipient address line 2
        String::new(),                  // 11 recipient address line 3
        seq.to_string(),                // 12 WHT seq no (per-recipient index)
        cfg.wht_form_type_code.clone(), // 13 form-type code (ภ.ง.ด.53/3)
        format_date(cfg.value_date),    // 14 deduct date YYYYMMDD
        cfg.wht_pay_type_code.clone(),  // 15 pay-type code
        String::new(),                  // 16 pay-type remark
        "1".to_string(),                // 17 no. of WHT detail blocks
        format_amount(r.wht),           // 18 total WHT detail amount
    ];
    // One income-detail block (7 fields): detail id, income type, description, rate%, dividend%,
    // income amount, WHT amount.
    fields.extend([
        "1".to_string(),                     // detail record id
        cfg.wht_income_type_code.clone(),    // income type code
        cfg.wht_income_desc.clone(),         // income description
        format_amount(cfg.wht_rate_percent), // WHT rate %
        String::new(),                       // dividend-to-net-profit % (n/a)
        format_amount(r.income),             // income (assessable) amount
        format_amount(r.wht),                // WHT amount withheld
    ]);
    join(&fields)
}

/// Generate the full pipe-delimited SCB upload text for a guard-payout batch. Records are joined by
/// CRLF with NO trailing newline (SCB shape). The caller writes it as **UTF-8 without BOM**.
///
/// Order: `HEADER` → `BCHDET` → for each recipient (`TXNDET` [+ `WHTCER` when that recipient has
/// `wht > 0`]) → `TRAILR`. The `BCHDET` and `TRAILR` totals are the sum of the actual transfers
/// (`income − wht`).
pub fn generate(batch: &PayoutBatch) -> String {
    let total_transfer: Decimal = batch.recipients.iter().map(|r| r.transfer_amount()).sum();
    let credit_count = batch.recipients.len();

    let mut lines = Vec::with_capacity(3 + credit_count * 2);
    lines.push(join(&[
        HEADER_CODE.to_string(),
        batch.file_ref.clone(),
        batch.system_ref.clone(),
    ]));
    lines.push(batch_row(batch, total_transfer, credit_count));
    for (i, r) in batch.recipients.iter().enumerate() {
        lines.push(credit_row(r));
        if r.has_wht() {
            lines.push(wht_row(batch, r, i + 1));
        }
    }
    lines.push(join(&[
        TRAILER_CODE.to_string(),
        "1".to_string(), // total debit records (always 1 batch)
        credit_count.to_string(),
        format_amount(total_transfer),
    ]));
    lines.join(NEWLINE)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn d(s: &str) -> Decimal {
        s.parse().unwrap()
    }

    fn payer() -> WhtPayer {
        WhtPayer {
            tax_id: "0105551234567".to_string(),
            name: "PGuard Co., Ltd.".to_string(),
            address: "1 Sathorn Rd, Bangkok 10120".to_string(),
        }
    }

    fn config() -> PayoutConfig {
        PayoutConfig {
            debit_account: "1234567890".to_string(),
            fee_debit_account: "1234567890".to_string(),
            value_date: NaiveDate::from_ymd_opt(2026, 9, 5).unwrap(),
            wht_form_type_code: "53".to_string(),
            wht_pay_type_code: "1".to_string(),
            wht_income_type_code: "5".to_string(),
            wht_income_desc: "ค่าบริการรักษาความปลอดภัย".to_string(),
            wht_rate_percent: d("3"),
        }
    }

    /// A guard with a 13-digit national id (→ NAT proxy) and a 3% WHT on 1000 income.
    fn guard_nat() -> PayoutRecipient {
        PayoutRecipient {
            transaction_ref: "PAY-0001".to_string(),
            proxy: "1234567890123".to_string(),
            tax_id: "1234567890123".to_string(),
            name: "สมชาย รปภ".to_string(),
            address: "99 Rama IX Rd, Bangkok".to_string(),
            income: d("1000.00"),
            wht: d("30.00"),
            phone: Some("081-234-5678".to_string()),
            email: None,
        }
    }

    fn batch(recipients: Vec<PayoutRecipient>) -> PayoutBatch {
        PayoutBatch {
            file_ref: "REF20260905".to_string(),
            system_ref: "SYS-1".to_string(),
            batch_ref: "050926120000PPY".to_string(),
            payer: payer(),
            config: config(),
            recipients,
        }
    }

    // ----- format helpers -----

    #[test]
    fn amount_is_two_dp_no_separators() {
        assert_eq!(format_amount(d("1000")), "1000.00");
        assert_eq!(format_amount(d("1234567.5")), "1234567.50");
        assert_eq!(format_amount(d("0.1")), "0.10");
        // banker's rounding to 2dp (VBA FormatNumber): .005 with an even preceding digit → down.
        assert_eq!(format_amount(d("970.005")), "970.00");
        assert_eq!(format_amount(d("970.015")), "970.02"); // odd preceding digit → up
    }

    #[test]
    fn date_is_yyyymmdd() {
        assert_eq!(
            format_date(NaiveDate::from_ymd_opt(2026, 9, 5).unwrap()),
            "20260905"
        );
    }

    #[test]
    fn proxy_type_classifies_nat_and_mob() {
        assert_eq!(guard_nat().proxy_type_code(), Some(PROXY_NATIONAL_ID));
        let mut mob = guard_nat();
        mob.proxy = "0812345678".to_string();
        assert_eq!(mob.proxy_type_code(), Some(PROXY_MOBILE));
        let mut bad = guard_nat();
        bad.proxy = "12345".to_string();
        assert_eq!(bad.proxy_type_code(), None);
    }

    #[test]
    fn transfer_is_income_minus_wht() {
        assert_eq!(guard_nat().transfer_amount(), d("970.00"));
    }

    // ----- record layout -----

    #[test]
    fn header_batch_trailer_shape() {
        let out = generate(&batch(vec![guard_nat()]));
        let lines: Vec<&str> = out.split("\r\n").collect();
        // HEADER | BCHDET | TXNDET | WHTCER | TRAILR
        assert_eq!(lines.len(), 5);

        let header: Vec<&str> = lines[0].split('|').collect();
        assert_eq!(header, vec!["HEADER", "REF20260905", "SYS-1"]);

        let bch: Vec<&str> = lines[1].split('|').collect();
        assert_eq!(bch.len(), 10);
        assert_eq!(bch[0], "BCHDET");
        assert_eq!(bch[2], "PPY");
        assert_eq!(bch[3], "20260905");
        assert_eq!(bch[6], "970.00", "batch total = net transfer");
        assert_eq!(bch[7], "1", "one credit");

        let trailer: Vec<&str> = lines[4].split('|').collect();
        assert_eq!(trailer, vec!["TRAILR", "1", "1", "970.00"]);
    }

    #[test]
    fn txndet_has_28_fields_and_promptpay_layout() {
        let out = generate(&batch(vec![guard_nat()]));
        let txn: Vec<&str> = out.split("\r\n").nth(2).unwrap().split('|').collect();
        assert_eq!(txn.len(), 28);
        assert_eq!(txn[0], "TXNDET");
        assert_eq!(txn[1], "PAY-0001");
        assert_eq!(txn[2], "1234567890123", "credit account = PromptPay proxy");
        assert_eq!(txn[3], "NAT");
        assert_eq!(txn[4], "111");
        assert_eq!(txn[5], "0000");
        assert_eq!(txn[6], "970.00", "amount = income − WHT");
        assert_eq!(txn[9], "Y", "SMS flag on (phone present)");
        assert_eq!(txn[10], "0812345678", "phone dashes stripped");
        assert_eq!(txn[11], "N", "email flag off");
        assert_eq!(txn[13], "สมชาย รปภ");
        assert_eq!(txn[17], "Y", "WHT flag");
        assert_eq!(txn[18], "1");
        assert_eq!(txn[19], "30.00");
    }

    #[test]
    fn whtcer_carries_payer_recipient_and_income_detail() {
        let out = generate(&batch(vec![guard_nat()]));
        let wht: Vec<&str> = out.split("\r\n").nth(3).unwrap().split('|').collect();
        // 19 header fields + 7 detail = 26
        assert_eq!(wht.len(), 26);
        assert_eq!(wht[0], "WHTCER");
        assert_eq!(wht[2], "0105551234567", "payer tax id (org)");
        assert_eq!(wht[3], "PGuard Co., Ltd.");
        assert_eq!(wht[7], "1234567890123", "recipient tax id (guard)");
        assert_eq!(wht[8], "สมชาย รปภ");
        assert_eq!(wht[13], "53", "ภ.ง.ด.53 form code");
        assert_eq!(wht[14], "20260905", "deduct date");
        assert_eq!(wht[17], "1", "one detail block");
        assert_eq!(wht[18], "30.00", "total WHT");
        // detail block (indices 19..26): id, incomeType, desc, rate, dividend%, income, wht
        assert_eq!(wht[19], "1");
        assert_eq!(wht[20], "5", "income type code");
        assert_eq!(wht[22], "3.00", "rate %");
        assert_eq!(wht[24], "1000.00", "gross income");
        assert_eq!(wht[25], "30.00", "wht amount");
    }

    #[test]
    fn without_wht_emits_no_whtcer_and_flags_off() {
        // A recipient with zero WHT (e.g. under the withholding threshold) → no WHTCER, full income.
        let mut g = guard_nat();
        g.wht = d("0");
        let out = generate(&batch(vec![g]));
        let lines: Vec<&str> = out.split("\r\n").collect();
        // HEADER | BCHDET | TXNDET | TRAILR — no WHTCER
        assert_eq!(lines.len(), 4);
        assert!(!out.contains("WHTCER"));
        let txn: Vec<&str> = lines[2].split('|').collect();
        assert_eq!(
            txn[6], "1000.00",
            "no WHT withheld → full income transferred"
        );
        assert_eq!(txn[17], "N", "WHT flag off");
        assert_eq!(txn[18], "", "no WHT count");
        assert_eq!(txn[19], "", "no WHT amount");
    }

    #[test]
    fn multi_recipient_totals_and_ordering() {
        let mut g2 = guard_nat();
        g2.transaction_ref = "PAY-0002".to_string();
        g2.proxy = "0899999999".to_string(); // mobile
        g2.tax_id = "9876543210987".to_string();
        g2.income = d("500.00");
        g2.wht = d("15.00");
        g2.phone = None;
        let out = generate(&batch(vec![guard_nat(), g2]));
        let lines: Vec<&str> = out.split("\r\n").collect();
        // HEADER, BCHDET, (TXNDET, WHTCER)×2, TRAILR = 7
        assert_eq!(lines.len(), 7);
        let bch: Vec<&str> = lines[1].split('|').collect();
        assert_eq!(bch[6], "1455.00", "970 + 485");
        assert_eq!(bch[7], "2");
        // second recipient is MOB
        let txn2: Vec<&str> = lines[4].split('|').collect();
        assert_eq!(txn2[3], "MOB");
        assert_eq!(txn2[9], "N", "no phone → SMS flag off");
        let trailer: Vec<&str> = lines[6].split('|').collect();
        assert_eq!(trailer, vec!["TRAILR", "1", "2", "1455.00"]);
    }

    #[test]
    fn empty_batch_is_header_batch_trailer_only() {
        let out = generate(&batch(vec![]));
        let lines: Vec<&str> = out.split("\r\n").collect();
        assert_eq!(lines.len(), 3);
        let bch: Vec<&str> = lines[1].split('|').collect();
        assert_eq!(bch[6], "0.00");
        assert_eq!(bch[7], "0");
    }
}
