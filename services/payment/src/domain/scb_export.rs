//! PURE generator for the **SCB Business Net "Excel Toolkit" upload file** — the guard-payout
//! variant (PromptPay credit + ภ.ง.ด.53 withholding-tax certificate). No DB/HTTP/NATS; 100%
//! unit-testable. This is the ONE authoritative place the pipe-delimited upload text is assembled,
//! mirroring the format reverse-engineered from `CPX_Toolkit_Template.xlsm` v1.3.8 (see
//! `docs/reviews/CPX_Toolkit_Reverse_Engineering.md`).
//!
//! File shape (records separated by CRLF, NO trailing newline; delimiter `|`):
//! ```text
//! HEADER|fileRef|systemRef
//! BCHDET|batchRef|productCode|valueDate(YYYYMMDD)|debitAcc|feeDebitAcc|totalTransfer|creditCount||
//!   TXNDET|... 28 fields (one per recipient; fields 3/4/5/7 are PRODUCT-branched)
//!   WHTCER|... 19 header fields      (only when the batch withholds tax from that recipient)
//!   WHTDET|... 7 income-detail fields (its OWN physical record — doc line 2592)
//! TRAILR|1|creditCount|totalTransfer
//! ```
//! The **amount transferred** to a guard is `income − wht` (the WHT is withheld and remitted to the
//! Revenue Department separately); the `WHTCER` records the gross `income` and the withheld `wht`.
//! The DEBIT total and the TRAILR total are the sum of the actual transfers (net of WHT).
//!
//! **One file = one product.** `BCHDET` field 2 carries exactly ONE product code, and that code
//! re-shapes every credit line under it (`TXNDET` fields 3/4/5/7 — doc §7.2, doc lines 2004-2014).
//! pguard has three money streams and therefore three SEPARATE files, never a merged one:
//! ① customer refunds and ③ guard payout both ride PromptPay ([`ScbProduct::PromptPay`]);
//! ② the platform's own cut is swept to the company revenue account as an own-account transfer
//! ([`ScbProduct::OwnAccount`]). The branch lives on [`ScbProduct`] + [`CreditDestination`] so
//! adding `3PT`/`RFT`/the payroll family is one match arm each — NOT a new `if` inside
//! [`credit_row`], which is how a positional money file quietly starts addressing the wrong thing.
//!
//! Every value that reaches this module is SANITISED here and nowhere else: the file is positional
//! and pipe-delimited, so one `|` inside a Thai name would silently shift every later field of that
//! record (and every field SCB parses as a number is written digits-only). This is the last line of
//! defence — callers may pass raw profile PII. Sanitising is THREE rules, not one, because SCB
//! validates names, addresses and references differently — see the "text sanitising" section below
//! before touching any of them.
//!
//! What this module does NOT do is decide who is payable: the bounds it exposes as pure predicates
//! ([`transfer_bound_rejection`], [`destination_rejection`], [`tax_id_over_cap`],
//! [`is_valid_scb_account`]) are applied by `api::payouts`, which excludes one recipient or refuses
//! the run. Nothing here truncates or drops a value SCB would reject — a rejected file arrives
//! AFTER `payout_batch_items` marked its bookings paid, so a bad value must stop the batch, never
//! ride it.

use chrono::{DateTime, Datelike, FixedOffset, NaiveDate, NaiveDateTime, Utc, Weekday};
use rust_decimal::Decimal;
use shared::error::AppError;

/// Field delimiter — the whole file is pipe-separated (SCB toolkit `Public Const delim`).
pub const DELIM: char = '|';
/// Record identifiers (column 0 of every line).
pub const HEADER_CODE: &str = "HEADER";
pub const BATCH_CODE: &str = "BCHDET";
pub const CREDIT_CODE: &str = "TXNDET";
pub const WHT_CODE: &str = "WHTCER";
/// Record id of a WHT **income-detail** line. It is its OWN physical record (field 0 is the literal
/// `WHTDET`), NOT extra fields appended to the `WHTCER` line — doc line 2592 calls this "the single
/// most important structural fact", and doc lines 2283-2290 show the on-disk two-line shape.
pub const WHT_DETAIL_CODE: &str = "WHTDET";
pub const TRAILER_CODE: &str = "TRAILR";
/// SCB PromptPay proxy-type codes (`colProxyTypeCode`, `Master_data!TBPromptPayPoxcy` — doc lines
/// 137-140): national/tax id, mobile number, e-wallet id.
pub const PROXY_NATIONAL_ID: &str = "NAT";
pub const PROXY_MOBILE: &str = "MOB";
pub const PROXY_EWALLET: &str = "EWL";
/// The proxy LENGTHS those three codes are stamped from. SCB does not look at the value, only at
/// how many digits it has (doc §7.4, doc line 2055) — see [`CreditDestination::proxy_type_code`].
const PROXY_LEN_EWALLET: usize = 15;
const PROXY_LEN_NATIONAL_ID: usize = 13;
const PROXY_LEN_MOBILE: usize = 10;
/// Y/N flag literals (SCB toolkit `FLAG_Y`/`FLAG_N`).
pub const FLAG_Y: &str = "Y";
pub const FLAG_N: &str = "N";
/// The WHT delivery-method literal — `E` (e-mail), not `Y` (SCB `checkFlagHaveEmailWHT`, doc 2736).
pub const FLAG_EMAIL: &str = "E";
/// SCB uses CRLF between records; the trailer carries NO trailing newline.
const NEWLINE: &str = "\r\n";

// ----- the product branch: ONE product per file, and it re-shapes every credit line -----

/// SCB **product code** — `BCHDET` field 2, the suffix of the customer file ref, and the switch that
/// decides `TXNDET` fields 3/4/5/7 (doc §7.2, doc lines 2004-2014).
///
/// The full `Master_data!TBProductCode` table (doc lines 115-130) is: `PAY`/`PA2`/`PA3` (SCB Payroll
/// 1-3) · `SPN`/`SPS`/`SPN2`/`SPS2`/`SPN3`/`SPS3` (payroll SMART credit) · `SCN`/`SCS` (SMART
/// credit) · `OAT` (own-account transfer) · `3PT` (3rd-party transfer) · `BNT` (BAHTNET) · `RFT`
/// (other-bank ORFT) · `PPY` (PromptPay). Only the two pguard actually moves money with are
/// modelled — sixteen variants would be fourteen branches no test ever walks.
///
/// To add one, add an arm to [`Self::code`], [`Self::branch_code`] and [`Self::service_type_code`]
/// (and to [`destination_rejection`] for its credit-account rule). That is the WHOLE contract: the
/// branch must never leak back into [`credit_row`] as an `if`, or the four fields drift apart.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScbProduct {
    /// `PPY` — PromptPay credit, addressed by a proxy (national id / mobile / e-wallet id).
    /// Streams ① *ยอดที่ต้องโอนคืนคนจ้าง* (customer refunds) and ③ *ยอดที่โอนให้ รปภ* (guard payout).
    PromptPay,
    /// `OAT` — own-account transfer: an SCB account to another SCB account, both the company's.
    /// Stream ② *ยอดที่โดนหักเข้าระบบ* — sweeping the platform's cut into the revenue account.
    /// Constructed by `api::deductions`, which builds one credit line summing the whole sweep.
    OwnAccount,
}

impl ScbProduct {
    /// `BCHDET` field 2, and the suffix the customer FILE ref carries (`fileRef = batchRef &
    /// productCode`, doc line 1420).
    pub const fn code(self) -> &'static str {
        match self {
            ScbProduct::PromptPay => "PPY",
            ScbProduct::OwnAccount => "OAT",
        }
    }

    /// `TXNDET` field 5 — the branch code (doc §7.2, doc lines 2007-2010 + the VBA at 2018-2027).
    /// `PPY` → `"0000"`; `OAT`/`3PT` and the PAY family → `"0111"`; `RFT` → `"0000"`.
    ///
    /// A per-product CONSTANT for every product pguard can ship: only the SMART/BAHTNET families
    /// take the credit row's own branch column, and pguard has no source for one.
    pub const fn branch_code(self) -> &'static str {
        match self {
            ScbProduct::PromptPay => "0000",
            ScbProduct::OwnAccount => "0111",
        }
    }

    /// `TXNDET` field 7 — the service type / transaction purpose (`Master_data!TBServiceType`, doc
    /// lines 190-218). Neither `PPY` nor `OAT` is one of the special arms of `ExportCreditRow`'s f7
    /// `Select Case`, so both fall to `Case Else` = the row's own code (doc line 2035). pguard
    /// configures no purpose, so the field goes out blank.
    ///
    /// The method exists for the products that do NOT pass it through: `PAY`/`PA2`/`PA3` force `""`
    /// (doc line 2034) and the SMART/BAHTNET families substitute a default (`01`/`04`/`00`). One arm
    /// each when they arrive — never a second `if` at the write site.
    pub fn service_type_code(self, configured: &str) -> &str {
        match self {
            ScbProduct::PromptPay | ScbProduct::OwnAccount => configured,
        }
    }
}

/// SCB's own 3-digit bank code — `014` ไทยพาณิชย์ (`Master_data!TBBank`, doc line 241).
pub const BANK_CODE_SCB: &str = "014";

/// The pseudo-bank code a PromptPay line carries in `TXNDET` field 4 — `111` (`TBBankPPY` holds
/// exactly one row, `111 พร้อมเพย์`, doc line 282; `ExportCreditRow`'s PPY branch hard-codes the same
/// literal, doc line 2020).
pub const CLEARING_CODE_PROMPTPAY: &str = "111";

/// A validated bank/clearing code for `TXNDET` field 4, stored the way the file writes it: exactly
/// 3 digits, zero-padded (`Trim(Format(colBankCode,"000"))` — doc §7.2, doc line 2009).
///
/// Deliberately NOT the whole 38-bank table (`Master_data!TBBank`, doc lines 234-271): both products
/// pguard ships are SCB-only (`TBBankPAY` contains exactly `014`, doc line 281), so a constant plus a
/// validated string beats a 38-variant enum nothing exercises. Model the table when a product that
/// credits OTHER banks lands (`RFT` = ORFT, or `3PT`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScbBankCode(String);

impl ScbBankCode {
    /// ไทยพาณิชย์ (`014`) — the only bank an own-account transfer may credit.
    pub fn scb() -> Self {
        ScbBankCode(BANK_CODE_SCB.to_string())
    }

    /// Parse a bank code, zero-padding to 3 digits the way `Format(x,"000")` does. `None` when it is
    /// not 1-3 digits, or is all zeros: field 4 is how SCB routes the money, and `000` is no bank.
    ///
    /// No PRODUCTION caller yet — every product pguard ships credits SCB itself, so [`Self::scb`] is
    /// what the sweep constructs. This is the entry point for the day an OTHER-bank product lands
    /// (`RFT` = ORFT, `3PT`), and it is unit-tested against the padding and the all-zero rule, so it
    /// is kept rather than deleted-and-rewritten-from-memory when that happens.
    #[allow(dead_code)]
    pub fn parse(raw: &str) -> Option<Self> {
        let digits = digits_only(raw);
        let len = digits.chars().count();
        if len == 0 || len > 3 || !digits.chars().any(|c| c != '0') {
            return None;
        }
        Some(ScbBankCode(format!("{digits:0>3}")))
    }

    /// The 3-digit code exactly as `TXNDET` field 4 carries it.
    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Whether this is SCB itself — the only bank `OAT` (and the PAY family) may credit.
    pub fn is_scb(&self) -> bool {
        self.0 == BANK_CODE_SCB
    }
}

/// WHERE one credit line sends its money — a SUM type, never a bag of `Option`s.
///
/// A PromptPay line is addressed by a PROXY; a transfer line by a (bank code, account number) pair.
/// The two share no field, so four `Option`s could express "a proxy AND a bank code" or — far worse
/// — neither, which the positional format renders as a row of blanks: a money line addressed to
/// nothing, discovered only when the bank rejects the file, by which time `payout_batch_items` has
/// marked every booking in it paid. Making that unrepresentable is worth the extra type.
///
/// The variant fixes `TXNDET` fields 3 and 4 ([`Self::proxy_type_code`], [`Self::clearing_code`])
/// and the per-transaction ceiling ([`Self::scb_max_transfer`]); the batch's [`ScbProduct`] fixes
/// fields 5 and 7. The two must AGREE — [`destination_rejection`] is the pure predicate that says
/// so, and (as everywhere in this module) the caller applies it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CreditDestination {
    /// Product `PPY`. `proxy` is the PromptPay id — a 13-digit national/tax id (`NAT`), a 10-digit
    /// Thai mobile (`MOB`) or a 15-digit e-wallet id (`EWL`). Stored as given, dashes and all;
    /// [`digits_only`] normalises it at write time.
    PromptPay { proxy: String },
    /// Product `OAT` today (`3PT`/`RFT`/the payroll family later): a bank account, addressed by its
    /// clearing code + account number. Constructed by the platform-cut sweep (`api::deductions`).
    BankAccount {
        bank_code: ScbBankCode,
        account_number: String,
    },
}

impl CreditDestination {
    /// A PromptPay destination (streams ① customer refunds and ③ guard payout).
    pub fn promptpay(proxy: impl Into<String>) -> Self {
        CreditDestination::PromptPay {
            proxy: proxy.into(),
        }
    }

    /// An SCB own-account destination (stream ② — the platform-cut sweep). The bank code is `014`
    /// by construction: an `OAT` line may credit no other bank (doc line 281).
    pub fn scb_account(account_number: impl Into<String>) -> Self {
        CreditDestination::BankAccount {
            bank_code: ScbBankCode::scb(),
            account_number: account_number.into(),
        }
    }

    /// `TXNDET` field 2 — the credit account / proxy VALUE, raw. The writer puts it through
    /// [`digits_only`] (SCB parses this field as a number).
    pub fn credit_account(&self) -> &str {
        match self {
            CreditDestination::PromptPay { proxy } => proxy,
            CreditDestination::BankAccount { account_number, .. } => account_number,
        }
    }

    /// `TXNDET` field 3 — the PromptPay proxy TYPE, or `None` when the destination has none. Every
    /// non-`PPY` product leaves field 3 unassigned, which `Join` renders as an empty string, so the
    /// field is present-but-blank rather than dropped (doc line 1745) — writing `""` matches it.
    ///
    /// SCB stamps the type from the proxy's LENGTH alone, never from its value (doc §7.4, doc line
    /// 2055): 15→`EWL`, 13→`NAT`, 10→`MOB`. Lengths 11/12/14 are re-validated as national-id ranges
    /// and anything else is stamped `TAX` (which the master-data table spells `AX` — doc line 137,
    /// the two disagree). pguard emits neither, so an unclassifiable proxy is `None` here and is
    /// REFUSED by [`destination_rejection`] rather than guessed at on a money line.
    pub fn proxy_type_code(&self) -> Option<&'static str> {
        let CreditDestination::PromptPay { proxy } = self else {
            return None;
        };
        match digits_only(proxy).chars().count() {
            PROXY_LEN_EWALLET => Some(PROXY_EWALLET),
            PROXY_LEN_NATIONAL_ID => Some(PROXY_NATIONAL_ID),
            PROXY_LEN_MOBILE => Some(PROXY_MOBILE),
            _ => None,
        }
    }

    /// `TXNDET` field 4 — the bank/clearing code: the fixed `111` for PromptPay (doc line 2020), the
    /// zero-padded 3-digit bank code for a transfer (doc line 2022).
    pub fn clearing_code(&self) -> &str {
        match self {
            CreditDestination::PromptPay { .. } => CLEARING_CODE_PROMPTPAY,
            CreditDestination::BankAccount { bank_code, .. } => bank_code.as_str(),
        }
    }

    /// The per-transaction ceiling SCB ITSELF enforces for this destination — the bound that exists
    /// whether or not an admin configured one (doc §7.5, doc lines 2057-2061; the validator table is
    /// doc lines 899-902).
    ///
    /// It genuinely varies by destination, which is exactly why it hangs off the sum type rather
    /// than off a lone constant: a 15-digit `EWL` proxy is the ONE PromptPay case routed to
    /// `ValidateAmountPromptpay(0.01, 10000)` (doc lines 901, 2058) while `NAT`/`MOB` take
    /// `ValidateAmountSmart` = ฿2,000,000 (doc line 902). A bank transfer falls to `Case Else` =
    /// `ValidateAmountCredit` (doc line 2061), whose ceiling is ฿9,999,999,999,999.99 (doc line
    /// 900) — effectively "no bank limit", so a sweep is bounded by the configured cap alone.
    pub fn scb_max_transfer(&self) -> Decimal {
        let literal = match self {
            CreditDestination::PromptPay { .. } => {
                if self.proxy_type_code() == Some(PROXY_EWALLET) {
                    MAX_TRANSFER_EWALLET
                } else {
                    DEFAULT_MAX_TRANSFER_PER_TXN
                }
            }
            CreditDestination::BankAccount { .. } => MAX_TRANSFER_BANK_ACCOUNT,
        };
        // These are compile-time literals: a parse failure would be a bug in THIS file, not in the
        // data. Degrade to a ZERO ceiling — every line loudly excluded — rather than panic in the
        // money path or, worse, silently uncap it.
        literal.parse().unwrap_or(Decimal::ZERO)
    }
}

/// Whether `dest` can legally ride a credit line of `product`, and if not, the Thai reason (naming
/// the rule) the preview screen shows the admin. `None` = payable.
///
/// Two things are checked, because either one makes SCB reject the whole FILE — after the rows
/// behind it were already marked paid:
///  * the destination must MATCH the batch product. One `BCHDET` carries exactly one product code,
///    so a PromptPay proxy cannot ride an `OAT` file and an account number cannot ride a `PPY` one;
///    the mismatch would emit a well-formed record pointing at nothing.
///  * the account must satisfy that product's own rule (doc §7.4, doc lines 2052-2055): `PPY` takes
///    a proxy SCB can stamp a type from (10/13/15 digits); `OAT` (like `3PT` and the PAY family, doc
///    line 2053) takes an SCB account — 10 digits passing the §14 check digit — at SCB itself, since
///    `TBBankPAY` contains only `014` (doc line 281).
///
/// A PREDICATE, not an action, exactly like [`transfer_bound_rejection`]: the caller excludes that
/// one recipient (or refuses the run). Pure.
pub fn destination_rejection(product: ScbProduct, dest: &CreditDestination) -> Option<String> {
    match (product, dest) {
        (ScbProduct::PromptPay, CreditDestination::PromptPay { .. }) => {
            if dest.proxy_type_code().is_none() {
                return Some(format!(
                    "พร้อมเพย์ไม่ถูกต้อง — ต้องเป็นตัวเลข {PROXY_LEN_MOBILE} หลัก (เบอร์มือถือ), {PROXY_LEN_NATIONAL_ID} หลัก (เลขบัตรประชาชน/ผู้เสียภาษี) หรือ {PROXY_LEN_EWALLET} หลัก (e-wallet)"
                ));
            }
            None
        }
        (
            ScbProduct::OwnAccount,
            CreditDestination::BankAccount {
                bank_code,
                account_number,
            },
        ) => {
            if !bank_code.is_scb() {
                Some(format!(
                    "การโอนเข้าบัญชีตัวเอง (OAT) ต้องเป็นบัญชีไทยพาณิชย์ (รหัสธนาคาร {BANK_CODE_SCB}) เท่านั้น"
                ))
            } else if !is_valid_scb_account(account_number) {
                Some(format!(
                    "เลขบัญชีปลายทางไม่ใช่บัญชีไทยพาณิชย์ที่ถูกต้อง — ต้องเป็นตัวเลข {SCB_ACCOUNT_DIGITS} หลักและผ่านการตรวจเลขหลักสุดท้าย"
                ))
            } else {
                None
            }
        }
        (ScbProduct::PromptPay, CreditDestination::BankAccount { .. }) => Some(
            "ปลายทางเป็นเลขบัญชีธนาคาร แต่ไฟล์นี้เป็นแบบพร้อมเพย์ (PPY) — ต้องแยกไฟล์ตามประเภทการโอน"
                .to_string(),
        ),
        (ScbProduct::OwnAccount, CreditDestination::PromptPay { .. }) => Some(
            "ปลายทางเป็นพร้อมเพย์ แต่ไฟล์นี้เป็นแบบโอนเข้าบัญชี (OAT) — ต้องแยกไฟล์ตามประเภทการโอน".to_string(),
        ),
    }
}

// ----- field-length caps -----
//
// The toolkit validates every free-text field for length; over-long input is REJECTED at upload,
// so we truncate here instead of shipping a file the bank bounces. Sources: doc line 409 (the
// derived business rules: batch ref ≤12, system ref ≤18, customer txn ref ≤20, address ≤70,
// name ≤140) and the WHT column table at doc lines 2500-2508 (tax id ≤15, income desc ≤80).

/// `BCHDET` customer batch ref — ≤12 chars, and no `|`/`#`/`^` (doc lines 405, 736, 886).
pub const MAX_BATCH_REF: usize = 12;
/// `HEADER` system reference id — ≤18 chars (doc line 409).
pub const MAX_SYSTEM_REF: usize = 18;
/// `HEADER` customer file ref = batch ref + product code (doc line 1420). The toolkit documents no
/// explicit cap for this one; the batch-ref cap (12) plus a 3-letter product code bounds it at 15
/// in practice (the workbook's stored sample `050526154634RFT` is exactly that), so 20 is headroom
/// rather than an invented rule.
pub const MAX_FILE_REF: usize = 20;
/// `TXNDET` customer transaction ref — ≤20 chars (doc line 409).
pub const MAX_TXN_REF: usize = 20;
/// Recipient/payer name — ≤140 chars (doc line 409, doc line 2503).
pub const MAX_NAME: usize = 140;
/// Recipient/payer address line — ≤70 chars (doc line 409, doc line 2504).
pub const MAX_ADDRESS: usize = 70;
/// WHT tax id — ≤15 chars (`ValidateTextFormatRecipientTax("NO_SPECIAL_CHAR", v, 1, 15)`, doc
/// line 2502). Both ends of a certificate are bounded by it: `WHTCER` field 2 (the PAYER's TIN)
/// and field 7 (the RECIPIENT's).
///
/// This cap is enforced by REJECTING, never by truncating — a truncated TIN is the WRONG NUMBER on
/// a tax certificate, which is worse than not paying at all. Profile's own `validate_tax_id` accepts
/// 8-20 digits, so a 16-20-digit id is reachable from the admin panel today; the caller's exclusion
/// ladder (`api::payouts::aggregate`) drops that ONE guard with a Thai reason, and a company TIN over
/// the cap is a typed 400 on the whole run (`build_payer_and_config`).
pub const MAX_TAX_ID: usize = 15;
/// WHT income description — ≤80 chars (doc line 2510).
pub const MAX_INCOME_DESC: usize = 80;
/// SCB master-data LOOKUP CODES on the certificate (ภ.ง.ด. form type / pay type / income type).
/// The toolkit documents no explicit length for them (they are picklist keys resolved from
/// `Master_data`, doc lines 2505-2509), so this is a generic short-code guard, NOT the tax-id rule —
/// they are separate fields and must not share [`MAX_TAX_ID`], whose bound is a *tax* rule.
pub const MAX_WHT_CODE: usize = 15;
/// The credit line's FEE-CHARGE code (`TXNDET` field 8) — a `Master_data!TBFeeOther` key (doc line
/// 314), the same shape of short lookup code as the WHT ones. Its OWN constant rather than a shared
/// [`MAX_WHT_CODE`]: that bound documents the ภ.ง.ด. certificate's picklists, and tying two
/// unrelated SCB tables to one number is how a cap ends up "corrected" for the wrong reason.
pub const MAX_FEE_CHARGE_CODE: usize = 15;
/// E-mail fields. The toolkit documents no explicit cap for them, so the generic 140-char text cap
/// is applied rather than inventing one.
pub const MAX_EMAIL: usize = 140;

/// The ONLY ภ.ง.ด. form-type codes SCB accepts (`Master_data!TBWHTType`, doc lines 142-155). They are
/// **NOT sequential** (01, 03, 04, 11, 12, 13, 53) — always an explicit lookup, never a range check.
///
/// Which one applies is a TAX decision, not a code decision: `53` is ภ.ง.ด.53 (payments to a juristic
/// person) while `04` is ภ.ง.ด.3 (payments to an individual). A guard whose PromptPay proxy is a
/// 13-digit national id is an INDIVIDUAL, which implies ภ.ง.ด.3 = `04` — so the stored `53` default is
/// likely wrong for guards. We deliberately do NOT change it here: the admin picks the form in the UI.
pub const WHT_FORM_TYPE_CODES: [&str; 7] = ["01", "03", "04", "11", "12", "13", "53"];

/// Whether `code` is one of the seven ภ.ง.ด. form-type codes SCB accepts. Pure.
pub fn is_valid_wht_form_type_code(code: &str) -> bool {
    WHT_FORM_TYPE_CODES.contains(&code.trim())
}

/// The ONLY WHT pay-type codes SCB accepts — `Master_data!TBWHTPayType` (doc lines 157-166):
/// `1` ผู้จ่ายออกครั้งเดียว · `2` ออกให้ตลอดไป · `3` หักภาษี ณ ที่จ่าย · `4` อื่นๆ.
///
/// This is the WHOLE table, including the one code we refuse to write (see
/// [`WHT_PAY_TYPE_CODE_OTHER`]) — the predicate answers "would SCB recognise this?", and the
/// separate policy check answers "can we produce a valid certificate with it?". Conflating the two
/// would leave the error message unable to explain WHICH of the two rules the admin tripped.
pub const WHT_PAY_TYPE_CODES: [&str; 4] = ["1", "2", "3", "4"];

/// Pay-type `4` (อื่นๆ / "other") — a legitimate SCB choice that we deliberately do NOT support.
///
/// `ValidWHTMandatory` requires a free-text REMARK (`colWHTRemarkPayType`, `WHTCER` field 16) on
/// every certificate whose pay-type code is `4` (doc lines 2582, 2219); the field is validated
/// `ValidateTextFormat("NO_SPECIAL_CHAR", v, 1, 40)` (doc line 2508). pguard models no such remark —
/// there is nowhere for an admin to type one — so a `4` here would emit a certificate with field 16
/// blank and bounce the upload AFTER the bookings were marked paid. The config API refuses `4` with
/// a Thai message instead; adding the remark column is the change that lifts this restriction.
pub const WHT_PAY_TYPE_CODE_OTHER: &str = "4";

/// Whether `code` is one of the four WHT pay-type codes SCB's table knows. Pure.
pub fn is_valid_wht_pay_type_code(code: &str) -> bool {
    WHT_PAY_TYPE_CODES.contains(&code.trim())
}

/// The ONLY assessable-income type codes SCB accepts — `Master_data!TBIncomeType` (doc lines
/// 167-190). Fifteen entries whose label IS the code, and they are NOT plain integers: `4a`,
/// `4b1.1` … `4b2.5` are codes in their own right, so this must stay a lookup and never become a
/// numeric range or a `parse::<u8>()`.
///
/// A guard's security-service fee is `5` (the stored default). Two of these carry extra obligations
/// pguard does not model — `4b1.4` needs the "% dividend to net profit" field (doc line 2456, our
/// `WHTDET` field 4 is always blank) and `4b2.5`/`6` need an income DESCRIPTION (doc lines 2454-2455,
/// which `wht_income_desc` always supplies) — so the validation admits the whole table and the
/// description default keeps the second pair honest.
pub const WHT_INCOME_TYPE_CODES: [&str; 15] = [
    "1", "2", "3", "4a", "4b1.1", "4b1.2", "4b1.3", "4b1.4", "4b2.1", "4b2.2", "4b2.3", "4b2.4",
    "4b2.5", "5", "6",
];

/// Whether `code` is one of the fifteen assessable-income type codes. Pure.
pub fn is_valid_wht_income_type_code(code: &str) -> bool {
    WHT_INCOME_TYPE_CODES.contains(&code.trim())
}

/// The fee-charge codes a `PPY` credit line may carry — `Master_data!TBFeeOther` (doc line 314),
/// the table the toolkit binds for every product outside BAHTNET and the payroll family (doc line
/// 1997): `OUR` = the PAYER bears the transfer fee, `BEN` = the RECIPIENT does.
///
/// `SHA` (shared) is deliberately absent: it belongs to `TBFeeBNT` (BAHTNET, doc line 312), a
/// product pguard does not ship, and writing it on a `PPY` line would be a code the parser's fee
/// table has never heard of.
///
/// For a guard payout the answer is `OUR` and the reason is a LEDGER one, not a preference: with
/// `BEN` the bank deducts its fee from the credit, so the guard receives LESS than
/// `payout_batch_items.transfer_amount` says we paid them — our books and the bank's would disagree
/// about the same transfer, permanently, with no record of the difference on our side.
pub const FEE_CHARGE_CODES: [&str; 2] = ["OUR", "BEN"];

/// Whether `code` is one of the two `TBFeeOther` fee-charge codes. Pure.
pub fn is_valid_fee_charge_code(code: &str) -> bool {
    FEE_CHARGE_CODES.contains(&code.trim())
}

/// Whether a DIGITS-ONLY tax id is too long for a `WHTCER` tax-id field — SCB caps both the payer
/// (field 2) and the recipient (field 7) at [`MAX_TAX_ID`] characters (doc line 2502).
///
/// The answer drives a REJECTION (one excluded guard, or a 400 on the company TIN), never a
/// truncation: a cut TIN is a valid-looking but WRONG number on a tax certificate. Pure.
pub fn tax_id_over_cap(tax_id: &str) -> bool {
    tax_id.chars().count() > MAX_TAX_ID
}

/// Per-transaction transfer cap for a PromptPay `NAT`/`MOB` proxy: ฿2,000,000. Also the default
/// `payout_config.max_transfer_per_txn` (`models::PayoutConfigRow`).
///
/// The doc reads as a contradiction (§15.10 / doc line 723 say ฿10,000; doc line 409 / 722 say
/// ฿2,000,000) but §7.4/§7.5 (doc lines 2052-2060) resolve it: the toolkit stamps the proxy TYPE from
/// the credit-account LENGTH (15→`EWL`, 13→`NAT`, 10→`MOB`) and only a 15-digit `EWL` proxy is routed
/// to `ValidateAmountPromptpay(0.01, 10000)`; everything else takes `ValidateAmountSmart` = ฿2,000,000.
/// Guards are paid on a 13-digit `NAT` or a 10-digit `MOB` proxy, so ฿2,000,000 is their cap. It stays
/// CONFIGURABLE (`payout_config.max_transfer_per_txn`) so it can be tightened without a deploy.
///
/// Now that the product is a VARIABLE, this is one of three ceilings and no longer "the" cap — read
/// the right one off the destination via [`CreditDestination::scb_max_transfer`].
pub const DEFAULT_MAX_TRANSFER_PER_TXN: &str = "2000000";

/// Ceiling for a 15-digit `EWL` (e-wallet) PromptPay proxy: ฿10,000 — `ValidateAmountPromptpay`
/// (doc lines 901, 2058). pguard pays no e-wallets today; the bound exists so that the day one is
/// addressable the file does not silently carry ten times the legal amount.
const MAX_TRANSFER_EWALLET: &str = "10000";

/// Ceiling for a bank-account credit (`OAT` and every other `Case Else` product): the
/// `ValidateAmountCredit` maximum ฿9,999,999,999,999.99 (doc lines 900, 2061). Effectively "no bank
/// limit" — a platform-cut sweep is bounded by `payout_config.max_transfer_per_txn` alone.
const MAX_TRANSFER_BANK_ACCOUNT: &str = "9999999999999.99";

/// Minimum a credit line may carry: SCB rejects a zero/negative amount (`AMOUNT_CREDIT` — "credit
/// amount must be more than zero"; both amount validators floor at `0.01`, doc lines 901-902).
pub const MIN_TRANSFER_PER_TXN: &str = "0.01";

/// Whether a recipient's TRANSFER amount can legally ride an SCB credit line to `dest`, and if not,
/// the Thai reason (naming the bound) the preview screen shows the admin.
///
/// `None` = payable. `Some(reason)` = EXCLUDE this recipient from the batch. Excluding is the whole
/// point: an out-of-bounds line makes SCB reject the *entire file*, and by then the bookings in it
/// have already been marked paid — so the money never moves but the backlog says it did. Dropping
/// the recipient silently would be just as bad (they simply never get paid, with nobody told), hence
/// a reason string rather than a bare bool. Pure.
///
/// Bounds: a credit amount must be at least ฿0.01 (`AMOUNT_CREDIT`, "must be more than zero" — both
/// amount validators floor there, doc lines 901-902), and at most the TIGHTER of
///  * what SCB itself allows for this destination ([`CreditDestination::scb_max_transfer`] —
///    ฿10,000 for an `EWL` proxy, ฿2,000,000 for `NAT`/`MOB`, ฿9,999,999,999,999.99 to an account),
///    which applies whether or not an admin configured anything, and
///  * `max_per_txn`, the operator's own tightening (`None` = no EXTRA cap, never "uncapped": the
///    bank's ceiling is not ours to lift).
///
/// The bank's half is why `dest` is a parameter at all — before the product was a variable, one
/// constant could stand in for it; now the ceiling genuinely differs per destination, and reading it
/// from the config alone would let an unset column ship a line the bank bounces.
pub fn transfer_bound_rejection(
    dest: &CreditDestination,
    transfer: Decimal,
    max_per_txn: Option<Decimal>,
) -> Option<String> {
    // The minimum is a fixed part of the format, so an unparseable literal here would be a bug in
    // this file, not in the data — degrade to "no minimum" rather than panic in the money path.
    let min = MIN_TRANSFER_PER_TXN.parse().unwrap_or(Decimal::ZERO);
    if transfer < min {
        return Some(format!(
            "ยอดโอนสุทธิ {} บาท ต่ำกว่าขั้นต่ำของธนาคาร ({} บาท)",
            format_amount(transfer),
            format_amount(min)
        ));
    }
    let bank_cap = dest.scb_max_transfer();
    let cap = match max_per_txn {
        Some(configured) if configured < bank_cap => configured,
        _ => bank_cap,
    };
    if transfer > cap {
        return Some(format!(
            "ยอดโอนเกินเพดานต่อรายการ ({} บาท) — แบ่งจ่ายเป็นหลายรอบ",
            format_amount(cap)
        ));
    }
    None
}

/// Asia/Bangkok is UTC+7 the whole year. Thailand has observed **no** daylight saving since 1941, so
/// a fixed offset is EXACT here — no tz database, and `chrono-tz` stays out of the dependency tree.
const BANGKOK_UTC_OFFSET_SECS: i32 = 7 * 3600;

/// The withholding-tax PAYER — the company doing the withholding. Sourced from
/// `profile.org_settings` (`company_name` / `tax_id` / `address`), reused as the ภ.ง.ด. payer block.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct WhtPayer {
    pub tax_id: String,
    pub name: String,
    pub address: String,
}

impl WhtPayer {
    /// The payer block for a file that withholds NOTHING — stream ① *ยอดที่ต้องโอนคืนกับคนจ้าง*, the
    /// customer refunds.
    ///
    /// A refund is the customer's own money coming back, not assessable income, so every recipient
    /// carries `wht = 0`, [`PayoutRecipient::has_wht`] is false for all of them, and [`generate`]
    /// therefore emits NO `WHTCER` and NO `WHTDET` — the only two records this block can reach. It
    /// is blank because there is no certificate to put a payer on, NOT because the company TIN is
    /// unknown: demanding a configured ภ.ง.ด. payer before an admin can refund a customer would
    /// block a refund on a tax setting that the file never carries.
    pub fn none() -> Self {
        Self::default()
    }
}

/// Batch-level configuration an admin sets once (company debit account + the ภ.ง.ด. terms). These
/// are NOT per-guard — they head the file (`BCHDET`) or repeat verbatim on every `WHTCER`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PayoutConfig {
    /// Company account the transfers are DEBITED from.
    pub debit_account: String,
    /// Account the transfer FEES are debited from (often the same as `debit_account`).
    pub fee_debit_account: String,
    /// `TXNDET` field 8 — WHO BEARS the transfer fee ([`FEE_CHARGE_CODES`]: `OUR` = the company,
    /// `BEN` = the guard). Batch-level here because one pguard file pays one way; SCB models it per
    /// credit row. It is MANDATORY on every credit line (`ValidCreditMandatory`, doc line 1915), so
    /// it must never be left blank — see [`FEE_CHARGE_CODES`] for why `OUR` is the payout answer.
    pub fee_charge_code: String,
    /// Effective/value date of the batch (rendered `YYYYMMDD`, Gregorian). Build it with
    /// [`resolve_value_date`] — a Bangkok business day, never back-dated (doc §15.11).
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

/// One recipient to pay in this batch. `income` is the assessable income (for a guard: the pay
/// basis, net of the platform commission); `wht` is the tax withheld from it. The ACTUAL transfer is
/// `income − wht` (see [`PayoutRecipient::transfer_amount`]). For a WHT batch the national/tax id is
/// REQUIRED (it is the ภ.ง.ด. recipient tax id); a phone-only guard cannot ride a WHT batch.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PayoutRecipient {
    /// Per-recipient reference echoed on the transfer (customer transaction ref).
    pub transaction_ref: String,
    /// WHERE the money goes — a PromptPay proxy (`PPY`) or a bank account (`OAT`). It must match the
    /// batch's [`ScbProduct`]; [`destination_rejection`] is the check, applied by the caller.
    pub destination: CreditDestination,
    /// The recipient's national/tax id — the ภ.ง.ด. recipient tax id. Usually the same digits as a
    /// `NAT` proxy; carried separately so a `MOB`-proxy guard can still have a tax id for the cert.
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
}

/// A whole export batch: file/system/batch references, the WHT payer + config, and the recipients.
/// Withholding is PER RECIPIENT — a `WHTCER`+`WHTDET` certificate pair (and the `TXNDET` WHT flags)
/// is emitted for a guard exactly when their `wht > 0`, so a mixed batch (some withheld, some not) is
/// expressed by the recipient amounts alone, with no separate toggle to drift out of sync. Build it
/// in the repo/api layer from the unpaid guard-earnings ledger + `org_settings`, then call
/// [`generate`]; use [`batch_ref`] / [`file_ref`] for the two references (they are NOT interchangeable).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PayoutBatch {
    /// `HEADER` field 1 — the customer FILE ref, which the toolkit derives as
    /// `batch_ref & product_code` (doc line 1420). NOT the download filename (that is
    /// `SCB_file_reference_<first 12 of file_ref>`, doc line 58) — mixing the two puts a
    /// human-readable string where SCB expects the reference.
    pub file_ref: String,
    /// `HEADER` field 2 — the company's own system reference id (≤18, doc line 409).
    pub system_ref: String,
    /// `BCHDET` field 1 — the customer BATCH ref: the bare 12-digit `DDMMYYHHMMSS` timestamp
    /// (doc lines 1420, 2967-2972). ≤12 chars, so the product code must NOT be appended here.
    pub batch_ref: String,
    /// `BCHDET` field 2 — the ONE product this whole file is, and the switch behind every credit
    /// line's fields 3/4/5/7 (doc §7.2). A stream that pays a different way needs its own FILE:
    /// one `BCHDET` carries exactly one product code, so there is nowhere to put a second.
    ///
    /// Every recipient must be addressed the way it demands — [`destination_rejection`] is the
    /// per-recipient check, and nothing here enforces it (this module rejects nothing on its own).
    pub product: ScbProduct,
    /// `TXNDET` field 7 — the service type / transaction purpose shared by every line in the file
    /// (`Master_data!TBServiceType`, doc lines 190-218). SCB models it per credit ROW; a pguard file
    /// pays exactly one purpose, so it is batch-level here. Blank for both products we ship, and
    /// blank is what the file then carries.
    pub service_type_code: String,
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

// ----- text sanitising: THREE rules, deliberately NOT one -----
//
// SCB does not police every free-text field the same way, and merging the rules breaks a field at
// one end or the other. Do not "helpfully" collapse these back into one function:
//
// * NAMES / income description / WHT remark → `validateTextWithSpecialChar` (doc lines 925-932):
//   a big disallowed set, listed in [`NO_SPECIAL_CHARS`]. A guard called `สมชาย & สมหญิง` bounces
//   the FILE today, so the offending characters are dropped here.
// * ADDRESSES → `ValidateTextFormatRecipientAdds("SPECIAL_CHAR", v, 1, 70)` (doc line 2504):
//   special characters are explicitly **ALLOWED**, so an address stays permissive — see
//   [`sanitize_allow_special_char`] for the one character we still remove and why.
// * REFERENCES (batch/file/system/txn ref) and E-MAIL → the batch-ref rule `| # ^` (doc line 886).
//   An e-mail must keep `@`, `_` and `+` (all in the names set, all legal per `IsEmailValid`,
//   doc §9), so it can never ride the strict rule.
//
// Every rule shares the same hygiene: control characters out, whitespace runs collapsed, no leading
// space (which alone fails SCB's validators, doc lines 929/954), and a CHARACTER-based cap.

/// The characters `validateTextWithSpecialChar` rejects (doc lines 925-932):
/// ``! " # $ % & * + ; < = > ? @ [ ] ^ _ ` { | } ~ \``.
///
/// Explicitly ALLOWED, i.e. deliberately NOT in this set (doc line 932): `( ) - . / , ' :` plus
/// digits and letters. Keep this a BLACKLIST — SCB's own rule is one, and a whitelist would eat
/// every Thai code point in a guard's name.
const NO_SPECIAL_CHARS: [char; 24] = [
    '!', '"', '#', '$', '%', '&', '*', '+', ';', '<', '=', '>', '?', '@', '[', ']', '^', '_', '`',
    '{', DELIM, '}', '~', '\\',
];

/// The three characters the toolkit's batch-ref validator forbids — `|`, `#`, `^` (doc line 886).
const BATCH_REF_CHARS: [char; 3] = [DELIM, '#', '^'];

/// Shared sanitiser core: drop `disallowed` + every control character, collapse whitespace runs to a
/// single space with no leading/trailing one, then cap at `max_len` **characters**.
///
/// The cap is deliberately char-based, not byte-based: every name/address here is Thai, and slicing
/// UTF-8 by byte index would panic or emit mojibake.
fn sanitize_with(value: &str, max_len: usize, disallowed: &[char]) -> String {
    let mut out = String::with_capacity(value.len());
    let mut pending_space = false;
    for ch in value.chars() {
        if disallowed.contains(&ch) {
            continue;
        }
        if ch.is_whitespace() || ch.is_control() {
            // Defer the space: never emitted leading, and dropped entirely if nothing follows.
            pending_space = !out.is_empty();
            continue;
        }
        if pending_space {
            out.push(' ');
            pending_space = false;
        }
        out.push(ch);
    }
    let capped: String = out.chars().take(max_len).collect();
    // A cut landing right after a space would leave a trailing one — trim it back off.
    capped.trim_end().to_string()
}

/// Sanitise a REFERENCE or an E-MAIL: the batch-ref rule (`|`, `#`, `^` — doc line 886) plus the
/// shared hygiene. This is the LOOSEST rule; a name or an income description needs
/// [`sanitize_no_special_char`] and an address [`sanitize_allow_special_char`].
///
/// The `|` strip is the load-bearing part everywhere: a single pipe inside a value would shift every
/// later field of that positional record and the bank would silently credit the wrong thing.
pub fn sanitize_text(value: &str, max_len: usize) -> String {
    sanitize_with(value, max_len, &BATCH_REF_CHARS)
}

/// Sanitise a field SCB gates with `validateTextWithSpecialChar` — the recipient/payer NAMES
/// (`TXNDET` field 13, `WHTCER` fields 3 and 8), the WHT income description (`WHTDET` field 2) and
/// the pay-type remark. Drops every character in [`NO_SPECIAL_CHARS`] (doc lines 925-932).
///
/// Dropping beats rejecting here: a stripped `&` still credits the RIGHT PromptPay id, whereas
/// excluding the guard would not pay them at all. Nothing upstream constrains the character set —
/// profile's `validate_guard_req` only length-checks a name — so this is the only guard against a
/// guard named `สมชาย & Co.` bouncing the whole file.
pub fn sanitize_no_special_char(value: &str, max_len: usize) -> String {
    sanitize_with(value, max_len, &NO_SPECIAL_CHARS)
}

/// Sanitise an ADDRESS line. `ValidateTextFormatRecipientAdds("SPECIAL_CHAR", v, 1, 70)` (doc line
/// 2504) explicitly ALLOWS special characters, so `( ) - . / , ' : # & …` all survive — an address
/// like `99/1 ซ.รามคำแหง 24 (แยก 5)` must not be mangled.
///
/// The ONE character still removed is the delimiter `|` itself: whatever SCB's validator permits, a
/// literal pipe would shift every later field of the record, so delimiter safety outranks fidelity.
pub fn sanitize_allow_special_char(value: &str, max_len: usize) -> String {
    sanitize_with(value, max_len, &[DELIM])
}

/// Keep only ASCII digits. Every field SCB parses as a NUMBER (the PromptPay proxy / credit account,
/// the WHT payer + recipient tax ids, the SMS phone) must be digits-only: profile's tax-id validator
/// accepts the human form `1-2345-67890-12-3`, and writing that verbatim into `TXNDET` field 2 —
/// where SCB requires 10-15 numeric characters (doc lines 2052-2055) — fails the upload. Pure.
pub fn digits_only(value: &str) -> String {
    value.chars().filter(|c| c.is_ascii_digit()).collect()
}

/// The nine positional weights of the SCB account check digit (`Const sKeySCB = "432765432"`,
/// doc line 1023). Their count also fixes the account length: `Len(sKeySCB) + 1` = 10.
const SCB_ACCOUNT_WEIGHTS: [u32; 9] = [4, 3, 2, 7, 6, 5, 4, 3, 2];

/// Number of digits in an SCB account (the 9 weighted digits + the check digit) — doc line 1027.
pub const SCB_ACCOUNT_DIGITS: usize = SCB_ACCOUNT_WEIGHTS.len() + 1;

/// SCB's own `CheckScbDigit` (doc §14, doc lines 1020-1035), re-implemented verbatim. Pure.
///
/// This is the ONE field where a plausible-looking typo is BATCH-FATAL: `BCHDET` fields 4 and 5 (the
/// debit + fee-debit accounts) are validated with `ValidateTextFormatSCBAccount("DEBIT_ACC", …,10,10)`
/// (doc line 1847), whose check-digit failure is `SCB_CHECK_DIGIT` (doc line 729). A rejected batch
/// HEADER means SCB never reads a single transaction — while `payout_batch_items` has already marked
/// every booking in the file paid.
///
/// Algorithm, step for step:
/// 1. strip `-` from the trimmed input; require exactly 10 ASCII digits (anything else → `false`),
/// 2. multiply digit *i* by weight *i* for the first nine, keeping the product's LAST decimal digit,
/// 3. sum those nine, keep the sum's last decimal digit → `k`,
/// 4. `j = 10 − k`, keeping ITS last digit (so `k == 0` → `j == 0`, not 10),
/// 5. valid iff the 10th digit equals `j`.
pub fn scb_account_check_digit_ok(account: &str) -> bool {
    // `Replace(Trim(AcctNo), "-", "")` — dashes only; a space or a letter must still FAIL below,
    // which is the whole point (a `digits_only` here would happily "fix" `12 34 5678 90`).
    let cleaned: String = account.trim().chars().filter(|c| *c != '-').collect();
    if cleaned.chars().count() != SCB_ACCOUNT_DIGITS || !cleaned.chars().all(|c| c.is_ascii_digit())
    {
        return false;
    }
    let digits: Vec<u32> = cleaned.chars().filter_map(|c| c.to_digit(10)).collect();
    // Step 2+3: `ir = digit * weight`, keep its last digit; then the last digit of the sum.
    let k: u32 = SCB_ACCOUNT_WEIGHTS
        .iter()
        .zip(&digits)
        .map(|(w, d)| (w * d) % 10)
        .sum::<u32>()
        % 10;
    // Step 4: `j = 10 - k`, and `Right(j, 1)` when that is two digits — i.e. 10 → 0.
    let check = (10 - k) % 10;
    // `get` rather than `digits[9]`: the length is already proven, but a money path never indexes.
    digits.get(SCB_ACCOUNT_DIGITS - 1) == Some(&check)
}

/// Whether `account` is usable as an SCB debit / fee-debit account: a 10-digit number that passes
/// [`scb_account_check_digit_ok`] **and** is not the all-zero account.
///
/// The zero case is a SEPARATE SCB rule, not part of §14: `ValidateTextFormatSCBAccount` fails
/// `strInput = 0` with its own `ACCOUNT_NUMBER_DEBIT_ACC_NO` / `…_DEBIT_FEE_ACC_NO` code (doc lines
/// 877, 734-735) — and `0000000000` happens to satisfy the check digit (0 → k=0 → j=0), so without
/// this a blank-ish placeholder account would sail through. Pure.
pub fn is_valid_scb_account(account: &str) -> bool {
    scb_account_check_digit_ok(account) && account.chars().any(|c| c.is_ascii_digit() && c != '0')
}

/// The customer-transaction-ref prefix of stream ③ *ยอดที่โอนให้ รปภ* (the guard payout).
pub const TXN_REF_PREFIX_PAYOUT: &str = "PO";
/// The customer-transaction-ref prefix of stream ① *ยอดที่ต้องโอนคืนกับคนจ้าง* (customer refunds).
///
/// A DIFFERENT prefix per stream, and it is load-bearing rather than cosmetic. Both streams are
/// PromptPay, so both derive their refs from the same 12-digit Bangkok stamp — a payout and a refund
/// generated in the SAME second would otherwise emit byte-identical customer transaction refs on two
/// separate uploads, which is exactly the key SCB de-dups on. The prefix makes that collision
/// impossible without stealing digits from the timestamp.
pub const TXN_REF_PREFIX_REFUND: &str = "RF";
/// The customer-transaction-ref prefix of stream ② *ยอดที่โดนหักเข้าระบบ* (the platform-cut sweep).
///
/// This file rides a DIFFERENT product (`OAT`), so its file ref already differs by suffix — but the
/// BATCH ref it derives the transaction ref from is the same 12-digit Bangkok stamp all three
/// streams read off the same clock, so without its own prefix a sweep and a payout generated in the
/// same second would emit identical customer transaction refs on two uploads.
pub const TXN_REF_PREFIX_DEDUCTION: &str = "DD";

/// The customer transaction ref for one recipient: the stream's `prefix` + the batch ref + a 1-based
/// sequence, capped at 20 chars (doc line 409).
///
/// The batch ref is folded in ON PURPOSE. A ref derived from the recipient alone is stable across
/// runs, so two different files would reuse the same customer transaction ref for the same person —
/// the bank's own de-dup key. `batch_ref` is unique per file (a 12-digit timestamp), `seq` is unique
/// within it and `prefix` is unique per STREAM, so the triple is unique everywhere. Pure.
pub fn transaction_ref(prefix: &str, batch_ref: &str, seq: usize) -> String {
    let base = sanitize_text(batch_ref, MAX_BATCH_REF);
    let prefix = sanitize_text(prefix, MAX_TXN_REF);
    // 2 + 12 + 4 = 18 ≤ MAX_TXN_REF; the outer cap is belt-and-braces for an odd batch ref.
    sanitize_text(&format!("{prefix}{base}{seq:04}"), MAX_TXN_REF)
}

/// `now` on the Bangkok wall clock, as a naive local date-time. Everything the file dates or stamps
/// is a THAI banking artefact, so it is derived from here rather than from UTC.
pub fn bangkok_naive(now: DateTime<Utc>) -> NaiveDateTime {
    match FixedOffset::east_opt(BANGKOK_UTC_OFFSET_SECS) {
        Some(tz) => now.with_timezone(&tz).naive_local(),
        // Unreachable (the offset is a compile-time constant well inside ±24h) — degrade to UTC
        // rather than panic in the request path.
        None => now.naive_utc(),
    }
}

/// Today's date in Asia/Bangkok. The value date is a THAI banking day, so deriving it from
/// `Utc::now().date_naive()` back-dates every export run between 00:00 and 07:00 Bangkok time —
/// and SCB rejects a back-dated value date outright (doc §15.11, doc line 1052).
pub fn bangkok_today(now: DateTime<Utc>) -> NaiveDate {
    bangkok_naive(now).date()
}

/// The customer BATCH ref for a file generated at `now`: the BARE 12-digit `DDMMYYHHMMSS` stamp on
/// the Bangkok clock (`generateCustomerBatchReferanceName` = `Format(Now(),"DDMMYYHHMMSS")`, doc
/// lines 1420, 2967-2972 — the toolkit reads the workstation's local time, which is Bangkok here).
///
/// The product code must NOT be appended: the Customer Batch Ref is capped at 12 characters (doc
/// lines 405, 736), so a `<stamp>PPY` ref is rejected at the BATCH header — before SCB reads a single
/// transaction. VBA `Format` treats `MM` after `HH` as MINUTES (doc line 2972), so the token stream
/// is Day-Month-Year(2)-Hour-Minute-Second, which is exactly `%d%m%y%H%M%S`.
pub fn batch_ref(now: DateTime<Utc>) -> String {
    bangkok_naive(now).format("%d%m%y%H%M%S").to_string()
}

/// The customer FILE ref: `batchRef & productCode` (doc line 1420). This is `HEADER` field 1 — a
/// reference, NOT the download filename (see [`download_filename`]).
///
/// The product code is part of the REFERENCE, so the three streams' files are distinguishable to the
/// bank (and to us) even when two are generated in the same second: `…PPY` vs `…OAT`.
pub fn file_ref(batch_ref: &str, product: ScbProduct) -> String {
    format!("{batch_ref}{}", product.code())
}

/// The suggested DOWNLOAD filename: `SCB_file_reference_<first 12 chars of the file ref>.txt`
/// (`generateCustomerFileReferanceName`, doc line 58). Kept separate from the reference itself,
/// because putting this human-readable string into `HEADER` field 1 is what the bank chokes on.
pub fn download_filename(file_ref: &str) -> String {
    let stem: String = file_ref.chars().take(12).collect();
    format!("SCB_file_reference_{stem}.txt")
}

/// Roll a date forward to the next weekday. A Saturday/Sunday value date does not settle (doc §15.11:
/// "business day only"), so the batch would sit or be rejected.
///
/// Thai PUBLIC HOLIDAYS are NOT handled: there is no holiday calendar in this repo and inventing one
/// would be worse than not having it (a wrong table silently mis-dates money). A holiday therefore
/// lands as a non-settling date; the admin's explicit `value_date` override is the escape hatch.
pub fn next_business_day(date: NaiveDate) -> NaiveDate {
    let mut d = date;
    // At most two rolls (Sat→Sun→Mon). `succ_opt` only returns None at `NaiveDate::MAX`, which a
    // value date can never reach — fall back to the input rather than panic.
    for _ in 0..2 {
        if !matches!(d.weekday(), Weekday::Sat | Weekday::Sun) {
            break;
        }
        match d.succ_opt() {
            Some(next) => d = next,
            None => break,
        }
    }
    d
}

/// Resolve the batch value date. `requested` is the admin's explicit pick (the override that covers
/// a public holiday, or a deliberately future settlement day); `None` = today in Bangkok, rolled off
/// a weekend.
///
/// A PAST date is a typed 400 rather than a silently corrected one: back-dating is rejected by every
/// SCB product (doc §15.11), and quietly moving the admin's date would hide that the run they think
/// they scheduled is not the run they got. An explicit date is otherwise honoured VERBATIM (weekend
/// included) — the override exists precisely to say "this exact day".
pub fn resolve_value_date(
    requested: Option<NaiveDate>,
    now: DateTime<Utc>,
) -> Result<NaiveDate, AppError> {
    let today = bangkok_today(now);
    match requested {
        Some(d) if d < today => Err(AppError::BadRequest(format!(
            "วันที่มีผล (value date) ย้อนหลังไม่ได้ ธนาคารจะตีกลับ — วันนี้คือ {today}"
        ))),
        Some(d) => Ok(d),
        None => Ok(next_business_day(today)),
    }
}

/// A `Y`/`N` flag: `Y` when the optional value is present and non-blank, else `N`.
fn flag(value: &Option<String>) -> &'static str {
    match value {
        Some(v) if !v.trim().is_empty() => FLAG_Y,
        _ => FLAG_N,
    }
}

/// The WHT-certificate DELIVERY-METHOD flag (`TXNDET` field 25). Unlike every other flag in the
/// record this one is not `Y`/`N`: SCB's `checkFlagHaveEmailWHT` emits `E` ("deliver by e-mail")
/// when an address is present, else `N` (doc lines 1738, 2736, 2741).
fn wht_delivery_flag(email: &Option<String>) -> &'static str {
    match email {
        Some(v) if !v.trim().is_empty() => FLAG_EMAIL,
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
        BATCH_CODE.to_string(), // 0 record id
        // 1 customer batch ref — ≤12 chars, no `| # ^` (doc lines 405/736/886). Over-long here is
        // rejected at the BATCH header, i.e. before SCB even reads a transaction.
        sanitize_text(&batch.batch_ref, MAX_BATCH_REF),
        // 2 product code — ONE per batch (doc line 1699); it also drives every TXNDET below.
        batch.product.code().to_string(),
        format_date(batch.config.value_date), // 3 value date YYYYMMDD
        // 4/5 debit + fee-debit accounts — SCB 10-digit account numbers, digits-only.
        digits_only(&batch.config.debit_account),
        digits_only(&batch.config.fee_debit_account),
        format_amount(total_transfer), // 6 total debit amount
        credit_count.to_string(),      // 7 total no. of credits
        String::new(),                 // 8 internal debit note
        String::new(),                 // 9 payment advice remark (batch level)
    ])
}

/// Build one `TXNDET` (credit) record — 28 fields. The WHT flag/count/amount fields are populated
/// exactly when this recipient has tax withheld (`wht > 0`).
///
/// Fields 3/4/5/7 are PRODUCT-BRANCHED (doc §7.2, doc lines 2004-2014). The branch is split along
/// the only line that keeps a product/destination mismatch from silently re-routing money: fields 3
/// and 4 (proxy type, bank/clearing code) come from the RECIPIENT's [`CreditDestination`] — that is
/// the address, and it is theirs — while fields 5 and 7 (branch, service type) come from the BATCH's
/// [`ScbProduct`]. Neither reads the other's half, so there is no `if product == …` here to fall out
/// of step with the destination when a fourth product lands.
fn credit_row(batch: &PayoutBatch, r: &PayoutRecipient) -> String {
    let dest = &r.destination;
    let (wht_flag, wht_count, wht_amount) = if r.has_wht() {
        (FLAG_Y.to_string(), "1".to_string(), format_amount(r.wht))
    } else {
        (FLAG_N.to_string(), String::new(), String::new())
    };
    join(&[
        CREDIT_CODE.to_string(), // 0  record id
        // 1  customer transaction ref (≤20, doc line 409)
        sanitize_text(&r.transaction_ref, MAX_TXN_REF),
        // 2  credit account / PromptPay proxy value — SCB requires 10-15 NUMERIC characters for a
        //    proxy and a 10-digit SCB number for an account (doc lines 2052-2055), so a stored
        //    `1-2345-67890-12-3` or `123-456789-6` must go out digits-only.
        digits_only(dest.credit_account()),
        // 3  proxy type (NAT/MOB/EWL) — PromptPay only; every other product leaves it blank.
        dest.proxy_type_code().unwrap_or("").to_string(),
        // 4  bank/clearing code — "111" for PromptPay, the 3-digit padded bank code for a transfer.
        dest.clearing_code().to_string(),
        batch.product.branch_code().to_string(), // 5  branch — per product ("0000" PPY / "0111" OAT)
        format_amount(r.transfer_amount()),      // 6  amount transferred (income − WHT)
        // 7  service type (transaction purpose) — passed through for PPY/OAT, blank in practice.
        batch
            .product
            .service_type_code(&batch.service_type_code)
            .to_string(),
        // 8  fee charge code — WHO BEARS the transfer fee (`colFeeChargeCode`, doc line 1721).
        //    This field used to go out BLANK. `ValidCreditMandatory` lists `colFeeCharge` in the
        //    UNCONDITIONAL required set (doc line 1915) — unlike the service type and the branch
        //    code, which get explicit per-product exemptions in the very next lines (doc lines
        //    1916-1922) — so if SCB's parser enforces the same rule, a blank here bounces EVERY
        //    file. It comes from the config (`OUR` by default) and is validated on the way in.
        sanitize_text(&batch.config.fee_charge_code, MAX_FEE_CHARGE_CODE),
        // 9/10 SMS notify flag + number. Driven by `r.phone` ALONE, which is why the caller leaves
        //    that `None` unless the operator opted in: SCB bills per SMS, and the number would be
        //    the guard's login phone. It is NOT the same thing as the phone used to ADDRESS the
        //    money — a `MOB` PromptPay proxy is field 2, built from the same value for a completely
        //    different purpose (see `api::payouts::aggregate`).
        flag(&r.phone).to_string(),               // 9  SMS notify flag
        digits_only(&opt(&r.phone)),              // 10 SMS phone (digits only)
        flag(&r.email).to_string(),               // 11 email notify flag
        sanitize_text(&opt(&r.email), MAX_EMAIL), // 12 email (keeps `@`/`_`/`+` — doc §9)
        // 13 recipient name (≤140) — `validateTextWithSpecialChar` set (doc lines 925-932/2503).
        sanitize_no_special_char(&r.name, MAX_NAME),
        // 14 recipient address line 1 (≤70) — special chars ALLOWED here (doc line 2504).
        sanitize_allow_special_char(&r.address, MAX_ADDRESS),
        String::new(),      // 15 recipient address line 2
        String::new(),      // 16 recipient address line 3
        wht_flag,           // 17 WHT required flag
        wht_count,          // 18 WHT cert count
        wht_amount,         // 19 WHT total amount
        FLAG_N.to_string(), // 20 payment advice remark flag
        FLAG_N.to_string(), // 21 invoice flag (no invoices for a payout)
        String::new(),      // 22 invoice detail count
        String::new(),      // 23 invoice total amount
        String::new(),      // 24 VAT total amount
        // 25 WHT delivery method — `checkFlagHaveEmailWHT` emits "E" (e-mail), NOT "Y", when an
        //    address is present (doc lines 1738, 2736, 2741). "N" = no e-mail delivery.
        wht_delivery_flag(&r.email).to_string(),
        sanitize_text(&opt(&r.email), MAX_EMAIL), // 26 recipient email for the WHT cert
        String::new(),                            // 27 payment advice remark (txn level)
    ])
}

/// Build the `WHTCER` (withholding-tax certificate) HEADER record — exactly 19 fields, field order
/// verbatim from `Sheet4.ExportWHTRow` (doc lines 2295-2340). The income figures are NOT here: they
/// live on the separate `WHTDET` record ([`wht_detail_row`]).
fn wht_header_row(batch: &PayoutBatch, r: &PayoutRecipient) -> String {
    let cfg = &batch.config;
    let payer = &batch.payer;
    join(&[
        WHT_CODE.to_string(), // 0  record id
        String::new(),        // 1  WHT book no (assigned by the bank/none)
        // 2  payer tax id — ≤15 (doc line 2502). NOT truncated here: an over-long company TIN is a
        //    typed 400 in `build_payer_and_config` (a cut TIN is the WRONG number on a certificate).
        digits_only(&payer.tax_id),
        // 3  payer name (≤140) — `validateTextWithSpecialChar` set (doc lines 925-932/2503).
        sanitize_no_special_char(&payer.name, MAX_NAME),
        // 4  payer address line 1 (≤70) — special chars ALLOWED (doc line 2504).
        sanitize_allow_special_char(&payer.address, MAX_ADDRESS),
        String::new(), // 5  payer address line 2
        String::new(), // 6  payer address line 3
        // 7  recipient tax id — ≤15 (doc line 2502); an over-long one EXCLUDES that guard upstream.
        digits_only(&r.tax_id),
        sanitize_no_special_char(&r.name, MAX_NAME), // 8  recipient name (≤140)
        // 9  recipient address line 1 (≤70) — special chars ALLOWED (doc line 2504).
        sanitize_allow_special_char(&r.address, MAX_ADDRESS),
        String::new(), // 10 recipient address line 2
        String::new(), // 11 recipient address line 3
        // 12 DELIBERATELY BLANK — and the doc disagrees with itself about what this column IS:
        //      * doc line 2213 names the constant `colWHTSeqNo` (14) "WHT Sequence No", and doc
        //        line 2308 writes field 12 from that column;
        //      * doc line 513 — the WHT sheet's OWN header row, dumped straight from the workbook —
        //        calls column N (the 14th) "ระบุชื่อผู้รับอื่น / Alternative Recipient Name for WHT".
        //    All 21 other columns line up exactly between those two tables (A→1 … V→22), which makes
        //    the VBA constant's NAME the likelier error and the sheet header the truth.
        //    We used to write the per-recipient index here. If SCB renders that column on the
        //    certificate, every ภ.ง.ด. we issue would name the recipient as a digit — a WRONG
        //    GOVERNMENT TAX FILING, not a cosmetic bug. An OMITTED optional alternative name is
        //    correct under the header reading and harmless under the constant reading (a certificate
        //    already carries its own credit-line join key), so blank is the only value that cannot
        //    be wrong. Do not "restore" the sequence number without new evidence from SCB.
        String::new(),
        // 13 form-type code (ภ.ง.ด.53 = `53` / ภ.ง.ด.3 = `04`) — a master-data CODE, so the
        //    short-code guard, not the tax-id cap; validated against `WHT_FORM_TYPE_CODES` when the
        //    admin saves the config.
        sanitize_text(&cfg.wht_form_type_code, MAX_WHT_CODE),
        format_date(cfg.value_date), // 14 deduct date YYYYMMDD
        sanitize_text(&cfg.wht_pay_type_code, MAX_WHT_CODE), // 15 pay-type code
        // 16 pay-type remark — always blank here (SCB only requires it for pay-type 4, doc line
        //    2582); were it ever populated it would take `sanitize_no_special_char` (doc line 2508).
        String::new(),
        "1".to_string(), // 17 no. of WHT detail blocks (we always emit exactly one)
        format_amount(r.wht), // 18 total WHT detail amount
    ])
}

/// Build the `WHTDET` (income-detail) record — 7 fields, its OWN physical line.
///
/// This is the structural fact doc line 2592 flags as the most important one in the whole format:
/// the detail block is NOT appended to the `WHTCER` line (doc lines 2283-2290 show the on-disk
/// shape), and field 0 is the literal `WHTDET`, not a block index. Field order is verbatim from
/// `Sheet4.ExportWHTDetailRow` (doc lines 2345-2382). We emit exactly one block: one income type
/// (the guard's service fee) at one rate.
fn wht_detail_row(batch: &PayoutBatch, r: &PayoutRecipient) -> String {
    let cfg = &batch.config;
    join(&[
        WHT_DETAIL_CODE.to_string(), // 0 detail record id — the literal "WHTDET"
        sanitize_text(&cfg.wht_income_type_code, MAX_WHT_CODE), // 1 income type code
        // 2 income description (≤80) — `ValidateTextFormatIncomeDesc("NO_SPECIAL_CHAR", v, 1, 80)`
        //   (doc line 2510), so an admin typing `ค่าบริการ รปภ. @ ไซต์งาน` loses the `@` instead of
        //   bouncing the file.
        sanitize_no_special_char(&cfg.wht_income_desc, MAX_INCOME_DESC),
        format_amount(cfg.wht_rate_percent), // 3 WHT deduct rate %
        String::new(), // 4 dividend-to-net-profit % (blank — only for income 4b1.4)
        format_amount(r.income), // 5 income (assessable) amount
        format_amount(r.wht), // 6 WHT amount withheld
    ])
}

/// Generate the full pipe-delimited SCB upload text for ONE batch of ONE product. Records are joined
/// by CRLF with NO trailing newline (SCB shape). The caller writes it as **UTF-8 without BOM**.
///
/// Order: `HEADER` → `BCHDET` → for each recipient (`TXNDET` [+ `WHTCER` then `WHTDET` when that
/// recipient has `wht > 0`]) → `TRAILR`. The `BCHDET` and `TRAILR` totals are the sum of the actual
/// transfers (`income − wht`).
///
/// INFALLIBLE by design, like every writer here: it renders whatever it is handed. The caller must
/// have run [`destination_rejection`] and [`transfer_bound_rejection`] over each recipient first —
/// a destination that does not match `batch.product` produces a well-formed record addressed to
/// nothing, which the bank finds only after those bookings are marked paid.
pub fn generate(batch: &PayoutBatch) -> String {
    let total_transfer: Decimal = batch.recipients.iter().map(|r| r.transfer_amount()).sum();
    let credit_count = batch.recipients.len();

    // Up to 3 lines per recipient (TXNDET + WHTCER + WHTDET) plus HEADER/BCHDET/TRAILR.
    let mut lines = Vec::with_capacity(3 + credit_count * 3);
    lines.push(join(&[
        HEADER_CODE.to_string(),
        // 1 customer file ref — `batchRef & productCode` (doc line 1420); built by the caller.
        sanitize_text(&batch.file_ref, MAX_FILE_REF),
        // 2 system reference id — ≤18 (doc line 409).
        sanitize_text(&batch.system_ref, MAX_SYSTEM_REF),
    ]));
    lines.push(batch_row(batch, total_transfer, credit_count));
    for r in &batch.recipients {
        lines.push(credit_row(batch, r));
        if r.has_wht() {
            // TWO physical records, never one concatenated line (doc line 2592).
            lines.push(wht_header_row(batch, r));
            lines.push(wht_detail_row(batch, r));
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

    fn day(y: i32, m: u32, dd: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, dd).expect("valid date")
    }

    /// A UTC instant from an RFC3339 literal (test-only; the production path takes `Utc::now()`).
    fn utc(s: &str) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(s)
            .expect("rfc3339")
            .with_timezone(&Utc)
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
            // A REAL SCB account: it passes the §14 check digit, which the API layer now enforces
            // at save time and again before generating a file. Do not "simplify" this to
            // 1234567890 — that number fails the check digit and the bank rejects the whole batch.
            debit_account: "1234567896".to_string(),
            fee_debit_account: "1234567896".to_string(),
            // The payout default: the COMPANY bears the transfer fee, so the guard receives exactly
            // the `transfer_amount` our ledger records (doc line 314's `TBFeeOther`).
            fee_charge_code: "OUR".to_string(),
            value_date: day(2026, 9, 5),
            wht_form_type_code: "53".to_string(),
            wht_pay_type_code: "1".to_string(),
            wht_income_type_code: "5".to_string(),
            wht_income_desc: "ค่าบริการรักษาความปลอดภัย".to_string(),
            wht_rate_percent: d("3"),
        }
    }

    /// A guard with a 13-digit national id (→ NAT proxy) and a 3% WHT on 1000 income.
    ///
    /// The id is a GENUINELY VALID Thai national id — it has to be, because `api::payouts` now
    /// re-checks the mod-11 digit before accepting one as a PromptPay destination, and a fixture the
    /// production code would refuse models nothing. Working by hand: the first twelve digits
    /// `123456789012` weighted 13…2 sum to 352; 352 mod 11 = 0; (11 − 0) mod 10 = **1**, so the id
    /// is `1234567890121` (the old fixture ended `…3` and would now be excluded).
    fn guard_nat() -> PayoutRecipient {
        PayoutRecipient {
            transaction_ref: "PAY-0001".to_string(),
            destination: CreditDestination::promptpay("1234567890121"),
            tax_id: "1234567890121".to_string(),
            name: "สมชาย รปภ".to_string(),
            address: "99 Rama IX Rd, Bangkok".to_string(),
            income: d("1000.00"),
            wht: d("30.00"),
            phone: Some("081-234-5678".to_string()),
            email: None,
        }
    }

    /// The SECOND guard of the golden batch: a MOB proxy, an e-mail (so the notify + WHT-delivery
    /// flags are exercised) and no phone.
    ///
    /// Their tax id rides the ภ.ง.ด. certificate rather than the credit line, but it is a real
    /// national id for the same reason [`guard_nat`]'s is. Working by hand: `987654321098` weighted
    /// 13…2 sums to 508; 508 mod 11 = 2; (11 − 2) mod 10 = **9** → `9876543210989`.
    fn guard_mob() -> PayoutRecipient {
        PayoutRecipient {
            transaction_ref: "PAY-0002".to_string(),
            destination: CreditDestination::promptpay("0899999999"),
            tax_id: "9876543210989".to_string(),
            name: "สมหญิง รปภ".to_string(),
            address: "12 Silom Rd, Bangkok".to_string(),
            income: d("500.00"),
            wht: d("15.00"),
            phone: None,
            email: Some("guard2@example.com".to_string()),
        }
    }

    fn batch(recipients: Vec<PayoutRecipient>) -> PayoutBatch {
        PayoutBatch {
            // fileRef = batchRef & productCode (doc line 1420); batchRef is the bare 12-digit
            // DDMMYYHHMMSS timestamp (≤12 chars, doc lines 405/736).
            file_ref: "050926120000PPY".to_string(),
            system_ref: "SYS-1".to_string(),
            batch_ref: "050926120000".to_string(),
            product: ScbProduct::PromptPay,
            service_type_code: String::new(),
            payer: payer(),
            config: config(),
            recipients,
        }
    }

    /// The stream-② shape: an own-account (`OAT`) sweep of the platform's cut into the company
    /// revenue account. No WHT — the company is not withholding tax from itself.
    fn sweep_recipient() -> PayoutRecipient {
        PayoutRecipient {
            transaction_ref: "SW-0001".to_string(),
            // A REAL SCB account (it passes the §14 check digit — see the check-digit tests).
            destination: CreditDestination::scb_account("4051234567"),
            tax_id: "0105551234567".to_string(),
            name: "PGuard Revenue".to_string(),
            address: "1 Sathorn Rd, Bangkok 10120".to_string(),
            income: d("1200.00"),
            wht: d("0"),
            phone: None,
            email: None,
        }
    }

    fn oat_batch(recipients: Vec<PayoutRecipient>) -> PayoutBatch {
        PayoutBatch {
            file_ref: "050926120000OAT".to_string(),
            service_type_code: String::new(),
            product: ScbProduct::OwnAccount,
            recipients,
            ..batch(vec![])
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
        assert_eq!(format_date(day(2026, 9, 5)), "20260905");
    }

    #[test]
    fn proxy_type_is_stamped_from_the_digit_count_alone() {
        // SCB reads only the LENGTH (doc §7.4, doc line 2055) — and the length is counted on the
        // DIGITS, so the human `1-2345-67890-12-3` form classifies the same as the bare id.
        let d13 = CreditDestination::promptpay("1234567890123");
        assert_eq!(d13.proxy_type_code(), Some(PROXY_NATIONAL_ID));
        assert_eq!(
            CreditDestination::promptpay("1-2345-67890-12-3").proxy_type_code(),
            Some(PROXY_NATIONAL_ID)
        );
        assert_eq!(
            CreditDestination::promptpay("0812345678").proxy_type_code(),
            Some(PROXY_MOBILE)
        );
        assert_eq!(
            CreditDestination::promptpay("123456789012345").proxy_type_code(),
            Some(PROXY_EWALLET),
            "15 digits is an e-wallet id"
        );
        // 11/12/14 would be stamped `TAX`/`AX` by the toolkit; pguard emits neither, so they are
        // `None` here and refused by `destination_rejection` — never guessed at on a money line.
        for unstampable in ["12345", "12345678901", "123456789012", "12345678901234", ""] {
            assert_eq!(
                CreditDestination::promptpay(unstampable).proxy_type_code(),
                None,
                "{unstampable} is not a stampable proxy length"
            );
        }
        // A bank account has no proxy type at all — field 3 stays blank for every non-PPY product.
        assert_eq!(
            CreditDestination::scb_account("4051234567").proxy_type_code(),
            None
        );
    }

    // ----- the product branch (P1.5) -----

    #[test]
    fn the_product_branch_matrix_matches_the_doc_table() {
        // doc §7.2 (doc lines 2004-2014): the four fields that change per product.
        assert_eq!(ScbProduct::PromptPay.code(), "PPY");
        assert_eq!(ScbProduct::PromptPay.branch_code(), "0000");
        assert_eq!(ScbProduct::OwnAccount.code(), "OAT");
        assert_eq!(ScbProduct::OwnAccount.branch_code(), "0111");
        // Both fall to the f7 `Case Else` = the row's own service-type code (doc line 2035); neither
        // is one of the arms that blanks or defaults it.
        for p in [ScbProduct::PromptPay, ScbProduct::OwnAccount] {
            assert_eq!(p.service_type_code("07"), "07");
            assert_eq!(p.service_type_code(""), "");
        }
        // Field 4 comes from the DESTINATION: the PromptPay pseudo-bank vs a real clearing code.
        assert_eq!(
            CreditDestination::promptpay("1234567890123").clearing_code(),
            "111"
        );
        assert_eq!(
            CreditDestination::scb_account("4051234567").clearing_code(),
            "014"
        );
    }

    #[test]
    fn a_bank_code_is_three_digits_zero_padded() {
        // `Trim(Format(colBankCode,"000"))` — doc §7.2, doc line 2009.
        assert_eq!(ScbBankCode::scb().as_str(), "014");
        assert!(ScbBankCode::scb().is_scb());
        assert_eq!(
            ScbBankCode::parse("14").map(|b| b.as_str().to_string()),
            Some("014".to_string())
        );
        assert_eq!(
            ScbBankCode::parse("2").map(|b| b.as_str().to_string()),
            Some("002".to_string())
        );
        assert_eq!(
            ScbBankCode::parse("098").map(|b| b.as_str().to_string()),
            Some("098".to_string()),
            "already 3 digits"
        );
        assert!(!ScbBankCode::parse("002").expect("กรุงเทพ").is_scb());
        // A blank / over-long / all-zero code would route the money nowhere.
        for bad in ["", "   ", "abc", "0000", "1234", "0", "000"] {
            assert!(
                ScbBankCode::parse(bad).is_none(),
                "{bad} is not a bank code"
            );
        }
    }

    #[test]
    fn txndet_fields_3_4_5_7_follow_the_product() {
        // PPY: proxy type + "111" + "0000"; OAT: blank + the bank code + "0111". Read straight off
        // the generated line, because that is the only place a drift would actually cost money.
        let ppy = generate(&batch(vec![guard_nat()]));
        let ppy_txn: Vec<&str> = ppy
            .split("\r\n")
            .nth(2)
            .expect("TXNDET")
            .split('|')
            .collect();
        assert_eq!(
            [ppy_txn[3], ppy_txn[4], ppy_txn[5], ppy_txn[7]],
            ["NAT", "111", "0000", ""]
        );

        let oat = generate(&oat_batch(vec![sweep_recipient()]));
        let oat_txn: Vec<&str> = oat
            .split("\r\n")
            .nth(2)
            .expect("TXNDET")
            .split('|')
            .collect();
        assert_eq!(
            [oat_txn[3], oat_txn[4], oat_txn[5], oat_txn[7]],
            ["", "014", "0111", ""]
        );
        assert_eq!(oat_txn.len(), 28, "the record shape is product-independent");

        // A configured service type rides field 7 for BOTH products (doc line 2035, `Case Else`).
        let mut with_service = oat_batch(vec![sweep_recipient()]);
        with_service.service_type_code = "07".to_string();
        let line = generate(&with_service);
        let txn: Vec<&str> = line
            .split("\r\n")
            .nth(2)
            .expect("TXNDET")
            .split('|')
            .collect();
        assert_eq!(txn[7], "07");

        // …and the product reaches BCHDET field 2 + the HEADER file ref, not just the credit lines.
        assert_eq!(
            oat.split("\r\n").nth(1).and_then(|l| l.split('|').nth(2)),
            Some("OAT")
        );
        assert_eq!(
            file_ref("050926120000", ScbProduct::OwnAccount),
            "050926120000OAT"
        );
        assert_eq!(
            file_ref("050926120000", ScbProduct::PromptPay),
            "050926120000PPY"
        );
    }

    #[test]
    fn an_oat_account_that_fails_the_check_digit_is_rejected_and_promptpay_is_untouched() {
        let ok = CreditDestination::scb_account("4051234567");
        assert_eq!(destination_rejection(ScbProduct::OwnAccount, &ok), None);

        // `4051234560` is one wrong digit — a plausible typo that passes every length check and
        // bounces the whole file. §14 catches it; the recipient is excluded, not written.
        let typo = CreditDestination::scb_account("4051234560");
        let msg = destination_rejection(ScbProduct::OwnAccount, &typo).expect("check digit fails");
        assert!(msg.contains("ไทยพาณิชย์"), "the reason is in Thai: {msg}");
        // Length + the all-zero placeholder are refused by the same predicate.
        for bad in ["405123456", "40512345670", "0000000000", "", "abcdefghij"] {
            assert!(
                destination_rejection(ScbProduct::OwnAccount, &CreditDestination::scb_account(bad))
                    .is_some(),
                "{bad} is not an SCB account"
            );
        }
        // An OAT line may only credit SCB itself (`TBBankPAY` holds just `014`, doc line 281).
        let other_bank = CreditDestination::BankAccount {
            bank_code: ScbBankCode::parse("004").expect("กสิกรไทย"),
            account_number: "4051234567".to_string(),
        };
        let msg = destination_rejection(ScbProduct::OwnAccount, &other_bank).expect("not SCB");
        assert!(msg.contains("014"), "the reason names the bank code: {msg}");

        // PromptPay is unaffected by ANY of it: a 13-digit proxy is not a 10-digit SCB account and
        // must never be judged as one (that would exclude every guard in the file).
        let nat = CreditDestination::promptpay("1234567890123");
        assert_eq!(destination_rejection(ScbProduct::PromptPay, &nat), None);
        assert!(!is_valid_scb_account("1234567890123"), "…and it is not one");
        assert_eq!(
            destination_rejection(
                ScbProduct::PromptPay,
                &CreditDestination::promptpay("0899999999")
            ),
            None
        );
        // An 11-digit proxy has no stampable type → refused with the lengths named.
        let odd = destination_rejection(
            ScbProduct::PromptPay,
            &CreditDestination::promptpay("12345678901"),
        )
        .expect("11 digits is unstampable");
        assert!(odd.contains("13"), "the reason names the lengths: {odd}");

        // A destination on the WRONG product is refused both ways — one BCHDET, one product code.
        assert!(destination_rejection(ScbProduct::PromptPay, &ok).is_some());
        assert!(destination_rejection(ScbProduct::OwnAccount, &nat).is_some());
    }

    #[test]
    fn transfer_is_income_minus_wht() {
        assert_eq!(guard_nat().transfer_amount(), d("970.00"));
    }

    // ----- sanitising (F6) + digit normalisation (F5) -----

    #[test]
    fn sanitize_no_special_char_drops_the_whole_disallowed_set_but_keeps_the_allowed_one() {
        // The set SCB's `validateTextWithSpecialChar` rejects (doc lines 925-932). Several at once,
        // because a name like this is exactly what bounced the FILE before the rules were split.
        assert_eq!(
            sanitize_no_special_char("สมชาย & \"บริษัท\" #1 @ไซต์ 50%", MAX_NAME),
            "สมชาย บริษัท 1 ไซต์ 50"
        );
        // Every character of the set, in one go — nothing may survive.
        assert_eq!(
            sanitize_no_special_char("a!\"#$%&*+;<=>?@[]^_`{|}~\\b", MAX_NAME),
            "ab"
        );
        // …and the characters SCB explicitly ALLOWS (doc line 932) must be left alone: a real Thai
        // company name is full of them, and eating them would corrupt the tax certificate.
        let ok = "O'Brien-Smith (Jr.), Co./Ltd: 1";
        assert_eq!(sanitize_no_special_char(ok, MAX_NAME), ok);
        // A leading space alone fails SCB's validators (doc lines 929, 954).
        assert_eq!(
            sanitize_no_special_char("   สมชาย รปภ", MAX_NAME),
            "สมชาย รปภ"
        );
    }

    #[test]
    fn sanitize_no_special_char_truncates_a_long_thai_name_on_a_char_boundary() {
        // Thai is 3 bytes per char: slicing by BYTE index would panic or emit mojibake.
        let long: String = "ก".repeat(200);
        let capped = sanitize_no_special_char(&long, MAX_NAME);
        assert_eq!(capped.chars().count(), MAX_NAME, "capped at 140 CHARS");
        assert_eq!(capped.len(), MAX_NAME * 3, "…which is 420 bytes of Thai");
        assert!(capped.chars().all(|c| c == 'ก'), "no split code point");

        // The income description is the tighter 80-char cap (doc line 2510).
        let desc: String = "ค่าบริการรักษาความปลอดภัย ".repeat(10);
        let capped_desc = sanitize_no_special_char(&desc, MAX_INCOME_DESC);
        assert_eq!(capped_desc.chars().count(), MAX_INCOME_DESC);
        assert!(
            !capped_desc.ends_with(' '),
            "no trailing space after the cut"
        );
    }

    #[test]
    fn sanitize_allow_special_char_keeps_an_address_intact_except_the_delimiter() {
        // `ValidateTextFormatRecipientAdds("SPECIAL_CHAR", …)` ALLOWS special chars (doc line 2504),
        // so a real Thai address keeps its ( ) - . / , ' : — and even the # / & the name rule drops.
        assert_eq!(
            sanitize_allow_special_char("99/1 ซ.รามคำแหง 24 (แยก 5), เขต|บางกะปิ", MAX_ADDRESS),
            "99/1 ซ.รามคำแหง 24 (แยก 5), เขตบางกะปิ",
            "only the delimiter is removed"
        );
        assert_eq!(
            sanitize_allow_special_char("#12 A&B Rd. 'Soi 3': K-1", MAX_ADDRESS),
            "#12 A&B Rd. 'Soi 3': K-1"
        );
        // A leading space still goes (doc line 929), and the cap is still 70 CHARS.
        assert_eq!(
            sanitize_allow_special_char("  99/1 Rama IX", MAX_ADDRESS),
            "99/1 Rama IX"
        );
        assert_eq!(
            sanitize_allow_special_char(&"ก".repeat(200), MAX_ADDRESS)
                .chars()
                .count(),
            MAX_ADDRESS
        );
    }

    #[test]
    fn an_email_keeps_the_characters_the_name_rule_would_eat() {
        // `@`, `_` and `+` are all in the NAMES disallowed set but legal in an address (doc §9), so
        // an e-mail must ride `sanitize_text`, never the strict rule. Re-merging the two would
        // silently mail every WHT certificate to a broken address.
        assert_eq!(
            sanitize_text("guard_1+payout@example.com", MAX_EMAIL),
            "guard_1+payout@example.com"
        );
        assert_eq!(
            sanitize_no_special_char("guard_1+payout@example.com", MAX_EMAIL),
            "guard1payoutexample.com",
            "…which is exactly why the e-mail does NOT use this one"
        );
    }

    #[test]
    fn sanitize_strips_the_delimiter_and_the_forbidden_signs() {
        // A single `|` in a name would shift every later field of the record — it must never survive.
        assert_eq!(sanitize_text("สมชาย|รปภ", MAX_NAME), "สมชายรปภ");
        assert_eq!(sanitize_text("A#B^C", MAX_NAME), "ABC");
        // Control characters (a pasted newline/tab) collapse to a single space, not a broken record.
        assert_eq!(
            sanitize_text("99 Rama\r\nIX\tRd", MAX_ADDRESS),
            "99 Rama IX Rd"
        );
        assert!(!sanitize_text("a|b\nc", MAX_NAME).contains(DELIM));
    }

    #[test]
    fn sanitize_collapses_whitespace_and_trims_both_ends() {
        // A LEADING space alone fails SCB's text validators (doc line 953).
        assert_eq!(sanitize_text("   สมชาย   รปภ   ", MAX_NAME), "สมชาย รปภ");
        assert_eq!(sanitize_text("", MAX_NAME), "");
        assert_eq!(sanitize_text("   ", MAX_NAME), "");
    }

    #[test]
    fn sanitize_truncates_thai_text_on_a_char_boundary() {
        // Thai is 3 bytes per char in UTF-8: slicing by BYTE index would panic or emit mojibake.
        let long: String = "ก".repeat(200);
        let capped = sanitize_text(&long, MAX_NAME);
        assert_eq!(capped.chars().count(), MAX_NAME, "capped at 140 CHARS");
        assert_eq!(capped.len(), MAX_NAME * 3, "…which is 420 bytes of Thai");
        assert!(capped.chars().all(|c| c == 'ก'), "no split code point");
        // An address is the tighter 70-char cap.
        assert_eq!(
            sanitize_text(&long, MAX_ADDRESS).chars().count(),
            MAX_ADDRESS
        );
        // A cut landing right after a space must not leave a trailing one.
        assert_eq!(sanitize_text("ab cdef", 3), "ab");
    }

    #[test]
    fn digits_only_normalises_a_dashed_tax_id() {
        // profile's validator ALLOWS the human form; SCB requires 10-15 numeric characters.
        assert_eq!(digits_only("1-2345-67890-12-3"), "1234567890123");
        assert_eq!(digits_only("081-234-5678"), "0812345678");
        assert_eq!(digits_only(" 66 812 345 678 "), "66812345678");
        assert_eq!(digits_only("abc"), "");
    }

    // ----- SCB account check digit (doc §14) -----

    #[test]
    fn scb_check_digit_accepts_a_valid_account_and_catches_a_transposition() {
        // Hand-computed from doc lines 1023-1034 with weights 4 3 2 7 6 5 4 3 2:
        //   1·4=4 2·3=6 3·2=6 4·7=28→8 5·6=30→0 6·5=30→0 7·4=28→8 8·3=24→4 9·2=18→8
        //   sum = 44 → k = 4 → j = 10−4 = 6 → the 10th digit must be 6.
        assert!(scb_account_check_digit_ok("1234567896"));
        // A second, independent one: 4 0 5 1 2 3 4 5 6 →
        //   16→6, 0, 10→0, 7, 12→2, 15→5, 16→6, 15→5, 12→2 = 33 → k = 3 → j = 7.
        assert!(scb_account_check_digit_ok("4051234567"));

        // TRANSPOSING the first two digits shifts the sum to 45 → k = 5 → j = 5 ≠ 6. This is the
        // typo the whole function exists for: a plausible 10-digit number that bounces the BATCH
        // HEADER, i.e. after `payout_batch_items` already marked every booking in the file paid.
        assert!(!scb_account_check_digit_ok("2134567896"));
        // One wrong digit anywhere is caught the same way.
        assert!(!scb_account_check_digit_ok("1234567890"));
        assert!(!scb_account_check_digit_ok("4051234560"));
    }

    #[test]
    fn scb_check_digit_rejects_anything_that_is_not_ten_digits() {
        assert!(!scb_account_check_digit_ok("123456789"), "9 digits");
        assert!(!scb_account_check_digit_ok("12345678960"), "11 digits");
        assert!(!scb_account_check_digit_ok(""), "empty");
        assert!(!scb_account_check_digit_ok("12345678x6"), "not numeric");
        assert!(!scb_account_check_digit_ok("abcdefghij"), "letters");
        assert!(
            !scb_account_check_digit_ok("12345678 6"),
            "an internal space"
        );
        // Thai digits are not ASCII digits — `to_digit` must not be reached with them.
        assert!(!scb_account_check_digit_ok("๑๒๓๔๕๖๗๘๙๖"));
    }

    #[test]
    fn scb_check_digit_strips_dashes_and_surrounding_space_only() {
        // `Replace(Trim(AcctNo), "-", "")` — the human-written form is accepted verbatim.
        assert!(scb_account_check_digit_ok("123-456789-6"));
        assert!(scb_account_check_digit_ok("  405-1-23456-7  "));
        assert!(
            !scb_account_check_digit_ok("123-456789-0"),
            "dashed but wrong"
        );
    }

    #[test]
    fn the_all_zero_account_passes_the_check_digit_but_is_still_not_usable() {
        // 0 × any weight = 0 → k = 0 → j = 10 → last digit 0 → §14 says VALID.
        assert!(scb_account_check_digit_ok("0000000000"));
        // …but `ValidateTextFormatSCBAccount` fails `strInput = 0` separately (doc lines 877,
        // 734-735), so the account we actually accept must reject that placeholder.
        assert!(!is_valid_scb_account("0000000000"));
        assert!(is_valid_scb_account("1234567896"));
        assert!(!is_valid_scb_account("1234567890"));
    }

    #[test]
    fn transaction_ref_is_file_unique_and_within_the_20_char_cap() {
        let a = transaction_ref(TXN_REF_PREFIX_PAYOUT, "050926120000", 1);
        let b = transaction_ref(TXN_REF_PREFIX_PAYOUT, "050926120000", 2);
        // Same batch, different guards → different refs.
        assert_ne!(a, b);
        assert_eq!(a, "PO0509261200000001");
        // Same guard position, a DIFFERENT file → a different ref (the old guard-only ref repeated).
        assert_ne!(a, transaction_ref(TXN_REF_PREFIX_PAYOUT, "060926090000", 1));
        // …and the SAME position in the SAME second on the OTHER stream: both streams are PromptPay
        // and derive their refs from the same Bangkok stamp, so without the per-stream prefix a
        // payout and a refund uploaded the same second would carry the bank's de-dup key twice.
        assert_ne!(a, transaction_ref(TXN_REF_PREFIX_REFUND, "050926120000", 1));
        assert_eq!(
            transaction_ref(TXN_REF_PREFIX_REFUND, "050926120000", 1),
            "RF0509261200000001"
        );
        for r in [&a, &b] {
            assert!(
                r.chars().count() <= MAX_TXN_REF,
                "{r} exceeds the 20-char cap"
            );
            assert!(!r.contains(DELIM));
        }
    }

    // ----- per-transaction amount bounds (F7) -----

    #[test]
    fn a_transfer_over_the_cap_is_rejected_with_the_cap_in_the_reason() {
        let nat = CreditDestination::promptpay("1234567890123");
        let cap = Some(d("2000000"));
        assert_eq!(transfer_bound_rejection(&nat, d("1999999.99"), cap), None);
        assert_eq!(
            transfer_bound_rejection(&nat, d("2000000.00"), cap),
            None,
            "at the cap is allowed"
        );
        let over = transfer_bound_rejection(&nat, d("2000000.01"), cap).expect("over the cap");
        assert!(
            over.contains("2000000.00"),
            "the reason names the cap: {over}"
        );
        assert!(over.contains("เกินเพดาน"), "…in Thai: {over}");
        // An UNSET config cap is not "uncapped": SCB's own ฿2,000,000 for a NAT/MOB proxy
        // (`ValidateAmountSmart`, doc line 902) still applies, because the bank's ceiling is not
        // ours to lift by leaving a column NULL.
        let uncapped = transfer_bound_rejection(&nat, d("99999999"), None).expect("bank ceiling");
        assert!(uncapped.contains("2000000.00"), "{uncapped}");
        assert_eq!(transfer_bound_rejection(&nat, d("2000000"), None), None);
        // A configured cap only ever TIGHTENS: a looser one cannot raise the bank's.
        assert!(transfer_bound_rejection(&nat, d("2000000.01"), Some(d("9999999999"))).is_some());
        assert!(transfer_bound_rejection(&nat, d("1000"), Some(d("500"))).is_some());
    }

    #[test]
    fn the_per_transaction_ceiling_follows_the_destination() {
        // doc §7.5 (doc lines 2057-2061) + the validator table (doc lines 899-902): the ONE
        // PromptPay case routed to `ValidateAmountPromptpay` is a 15-digit e-wallet proxy.
        let ewl = CreditDestination::promptpay("123456789012345");
        assert_eq!(ewl.scb_max_transfer(), d("10000"));
        let mob = CreditDestination::promptpay("0899999999");
        assert_eq!(mob.scb_max_transfer(), d("2000000"));
        let acct = CreditDestination::scb_account("4051234567");
        assert_eq!(acct.scb_max_transfer(), d("9999999999999.99"));

        // ฿20,000 rides a guard's MOB proxy but NOT an e-wallet — the same amount, two verdicts,
        // which is exactly why the bound hangs off the destination and not off one constant.
        assert_eq!(transfer_bound_rejection(&mob, d("20000"), None), None);
        let over = transfer_bound_rejection(&ewl, d("20000"), None).expect("over the EWL cap");
        assert!(
            over.contains("10000.00"),
            "the reason names ฿10,000: {over}"
        );
        // A sweep to an account is effectively unbounded by the bank, so the config cap is the
        // only one that can bite.
        assert_eq!(transfer_bound_rejection(&acct, d("5000000"), None), None);
        assert!(transfer_bound_rejection(&acct, d("5000000"), Some(d("1000000"))).is_some());
    }

    #[test]
    fn a_zero_or_negative_transfer_is_rejected_below_the_bank_minimum() {
        let nat = CreditDestination::promptpay("1234567890123");
        // A 100% commission snapshot yields a 0.00 transfer; SCB floors a credit line at 0.01.
        let zero =
            transfer_bound_rejection(&nat, d("0"), Some(d("2000000"))).expect("below minimum");
        assert!(zero.contains("0.01"), "the reason names the floor: {zero}");
        assert!(transfer_bound_rejection(&nat, d("-1"), None).is_some());
        assert_eq!(
            transfer_bound_rejection(&nat, d("0.01"), None),
            None,
            "the floor itself is payable"
        );
        // The floor is product-independent — a zero sweep is just as illegal as a zero payout.
        assert!(transfer_bound_rejection(
            &CreditDestination::scb_account("4051234567"),
            d("0"),
            None
        )
        .is_some());
    }

    // ----- batch / file / download references (F2, F3) -----

    #[test]
    fn batch_ref_is_twelve_bangkok_digits_and_file_ref_appends_the_product() {
        // 05:00 UTC on 5 Sep 2026 = 12:00 Bangkok → DD MM YY HH MM SS = 05 09 26 12 00 00.
        let b = batch_ref(utc("2026-09-05T05:00:00Z"));
        assert_eq!(b, "050926120000", "Day-Month-Year(2)-Hour-Minute-Second");
        assert_eq!(
            b.chars().count(),
            MAX_BATCH_REF,
            "the ref IS the 12-char cap"
        );
        assert!(b.chars().all(|c| c.is_ascii_digit()));
        // The stamp follows the BANGKOK clock: 20:30 UTC is already the next day there.
        assert_eq!(batch_ref(utc("2026-09-05T20:30:00Z")), "060926033000");

        // fileRef = batchRef & productCode — the HEADER reference, not a filename.
        assert_eq!(file_ref(&b, ScbProduct::PromptPay), "050926120000PPY");
        // …and the DOWNLOAD name is the third, separate thing.
        assert_eq!(
            download_filename(&file_ref(&b, ScbProduct::PromptPay)),
            "SCB_file_reference_050926120000.txt",
            "first 12 chars of the file ref"
        );
    }

    // ----- ภ.ง.ด. form codes (F8) -----

    #[test]
    fn only_the_seven_documented_wht_form_codes_are_valid() {
        for ok in ["01", "03", "04", "11", "12", "13", "53"] {
            assert!(is_valid_wht_form_type_code(ok), "{ok} is in TBWHTType");
        }
        // The codes are NOT sequential — the gaps must be rejected, not inferred as a range.
        for bad in ["02", "05", "1", "3", "54", "", "530", "abc"] {
            assert!(
                !is_valid_wht_form_type_code(bad),
                "{bad} is not a form code"
            );
        }
    }

    #[test]
    fn a_tax_id_longer_than_fifteen_digits_is_over_the_certificate_cap() {
        // profile's `validate_tax_id` accepts 8-20 DIGITS, so 16-20 is reachable from the admin
        // panel — and `WHTCER` fields 2/7 stop at 15 (doc line 2502).
        assert!(!tax_id_over_cap("1234567890123"), "a 13-digit national id");
        assert!(
            !tax_id_over_cap(&"9".repeat(MAX_TAX_ID)),
            "exactly at the cap"
        );
        assert!(tax_id_over_cap(&"9".repeat(MAX_TAX_ID + 1)));
        assert!(tax_id_over_cap(&"9".repeat(20)), "profile's own maximum");
        assert!(
            !tax_id_over_cap(""),
            "empty is a MISSING id, a different reason"
        );
    }

    // ----- value date (F4) -----

    #[test]
    fn bangkok_today_is_seven_hours_ahead_of_utc() {
        // 17:30 UTC is already 00:30 the NEXT day in Bangkok — the exact window where the old
        // `Utc::now().date_naive()` back-dated the whole file.
        assert_eq!(bangkok_today(utc("2026-09-06T17:30:00Z")), day(2026, 9, 7));
        // …and one minute before the boundary it is still the same Bangkok day.
        assert_eq!(bangkok_today(utc("2026-09-06T16:59:59Z")), day(2026, 9, 6));
    }

    #[test]
    fn value_date_rolls_a_weekend_forward_to_monday() {
        assert_eq!(
            next_business_day(day(2026, 9, 5)),
            day(2026, 9, 7),
            "Sat→Mon"
        );
        assert_eq!(
            next_business_day(day(2026, 9, 6)),
            day(2026, 9, 7),
            "Sun→Mon"
        );
        assert_eq!(
            next_business_day(day(2026, 9, 4)),
            day(2026, 9, 4),
            "Fri stays"
        );
        // End to end: a Saturday-morning Bangkok run dates the batch on the Monday.
        let sat_morning = utc("2026-09-05T02:00:00Z"); // 09:00 Bangkok, Saturday
        assert_eq!(
            resolve_value_date(None, sat_morning).unwrap(),
            day(2026, 9, 7)
        );
    }

    #[test]
    fn value_date_rejects_a_past_date_and_honours_a_future_one() {
        let now = utc("2026-09-07T03:00:00Z"); // 10:00 Bangkok, Monday
                                               // Yesterday → typed 400 (SCB rejects a back-dated value date, doc §15.11).
        let err = resolve_value_date(Some(day(2026, 9, 6)), now).unwrap_err();
        assert!(matches!(err, AppError::BadRequest(_)));
        // TODAY is allowed (only SPN/SCN demand a strictly-future date; PPY does not).
        assert_eq!(
            resolve_value_date(Some(day(2026, 9, 7)), now).unwrap(),
            day(2026, 9, 7)
        );
        // An explicit future date is honoured verbatim — the admin's holiday override.
        assert_eq!(
            resolve_value_date(Some(day(2026, 9, 30)), now).unwrap(),
            day(2026, 9, 30)
        );
        // The past check is on the BANGKOK day: 23:00 UTC on the 6th is already the 7th in Bangkok,
        // so the 7th must not be rejected as "past" — nor the 6th accepted.
        let late = utc("2026-09-06T23:00:00Z");
        assert!(resolve_value_date(Some(day(2026, 9, 7)), late).is_ok());
        assert!(resolve_value_date(Some(day(2026, 9, 6)), late).is_err());
    }

    // ----- record layout -----

    #[test]
    fn header_batch_trailer_shape() {
        let out = generate(&batch(vec![guard_nat()]));
        let lines: Vec<&str> = out.split("\r\n").collect();
        // HEADER | BCHDET | TXNDET | WHTCER | WHTDET | TRAILR
        assert_eq!(lines.len(), 6);

        let header: Vec<&str> = lines[0].split('|').collect();
        assert_eq!(header, vec!["HEADER", "050926120000PPY", "SYS-1"]);

        let bch: Vec<&str> = lines[1].split('|').collect();
        assert_eq!(bch.len(), 10);
        assert_eq!(bch[0], "BCHDET");
        assert_eq!(
            bch[1], "050926120000",
            "batch ref is the bare 12-digit stamp"
        );
        assert!(bch[1].chars().count() <= MAX_BATCH_REF);
        assert_eq!(bch[2], "PPY");
        assert_eq!(bch[3], "20260905");
        assert_eq!(bch[6], "970.00", "batch total = net transfer");
        assert_eq!(bch[7], "1", "one credit");

        let trailer: Vec<&str> = lines[5].split('|').collect();
        assert_eq!(trailer, vec!["TRAILR", "1", "1", "970.00"]);
    }

    #[test]
    fn txndet_has_28_fields_and_promptpay_layout() {
        // A tax id stored in the human form must go out digits-only (F5).
        let mut g = guard_nat();
        g.destination = CreditDestination::promptpay("1-2345-67890-12-1");
        let out = generate(&batch(vec![g]));
        let txn: Vec<&str> = out.split("\r\n").nth(2).unwrap().split('|').collect();
        assert_eq!(txn.len(), 28);
        assert_eq!(txn[0], "TXNDET");
        assert_eq!(txn[1], "PAY-0001");
        assert_eq!(txn[2], "1234567890121", "proxy written digits-only");
        assert_eq!(txn[3], "NAT");
        assert_eq!(txn[4], "111");
        assert_eq!(txn[5], "0000");
        assert_eq!(txn[6], "970.00", "amount = income − WHT");
        assert_eq!(txn[9], "Y", "SMS flag on (phone present)");
        assert_eq!(txn[10], "0812345678", "phone digits only");
        assert_eq!(txn[11], "N", "email flag off");
        assert_eq!(txn[13], "สมชาย รปภ");
        assert_eq!(txn[17], "Y", "WHT flag");
        assert_eq!(txn[18], "1");
        assert_eq!(txn[19], "30.00");
        assert_eq!(txn[25], "N", "no e-mail → no WHT e-mail delivery");
    }

    #[test]
    fn txndet_field_8_carries_the_fee_charge_code_and_is_never_blank() {
        // `ValidCreditMandatory` requires `colFeeCharge` UNCONDITIONALLY (doc line 1915) — the
        // service type and the branch code get per-product exemptions on the next lines, this does
        // not. A blank here plausibly bounces the whole file, so the code must reach field 8.
        let out = generate(&batch(vec![guard_nat()]));
        let txn: Vec<&str> = out.split("\r\n").nth(2).unwrap().split('|').collect();
        assert_eq!(txn[8], "OUR", "the payer (company) bears the fee");
        assert!(
            !txn[8].is_empty(),
            "field 8 is mandatory on every credit row"
        );

        // `BEN` is the other legal value and rides the same field (it is a TAX/LEDGER decision, not
        // a format one — see FEE_CHARGE_CODES for why the payout default is OUR).
        let mut ben = batch(vec![guard_nat()]);
        ben.config.fee_charge_code = "BEN".to_string();
        let out = generate(&ben);
        let txn: Vec<&str> = out.split("\r\n").nth(2).unwrap().split('|').collect();
        assert_eq!(txn[8], "BEN");
        assert_eq!(txn.len(), 28, "the record shape is unchanged");

        // …and it is a positional money file, so even a hostile value cannot shift a later field.
        let mut hostile = batch(vec![guard_nat()]);
        hostile.config.fee_charge_code = "O|UR".to_string();
        let out = generate(&hostile);
        let txn: Vec<&str> = out.split("\r\n").nth(2).unwrap().split('|').collect();
        assert_eq!(txn.len(), 28);
        assert_eq!(txn[8], "OUR", "the delimiter is stripped, not written");
    }

    #[test]
    fn the_fee_charge_code_table_is_the_tbfeeother_pair() {
        // `Master_data!TBFeeOther` — doc line 314 (BEN/OUR); the table PPY binds via the `Case Else`
        // arm at doc line 1997.
        assert_eq!(FEE_CHARGE_CODES, ["OUR", "BEN"]);
        assert!(is_valid_fee_charge_code("OUR"));
        assert!(is_valid_fee_charge_code(" BEN "), "trimmed");
        // `SHA` is BAHTNET's (doc line 312) — a product pguard does not ship, so it is NOT valid on
        // a PPY line even though it is a real SCB fee code.
        for bad in ["SHA", "", "our", "OU", "OURS", "0"] {
            assert!(
                !is_valid_fee_charge_code(bad),
                "{bad} is not a TBFeeOther code"
            );
        }
    }

    #[test]
    fn the_wht_pay_type_and_income_type_tables_are_lookups_not_ranges() {
        // `TBWHTPayType` (doc lines 157-166) — exactly four codes.
        assert_eq!(WHT_PAY_TYPE_CODES, ["1", "2", "3", "4"]);
        for ok in ["1", "2", "3", "4", " 3 "] {
            assert!(is_valid_wht_pay_type_code(ok), "{ok} is in TBWHTPayType");
        }
        for bad in ["0", "5", "", "01", "หัก"] {
            assert!(!is_valid_wht_pay_type_code(bad), "{bad} is not");
        }
        // `4` is REAL but unsupported here: it needs the pay-type remark (doc line 2582) we do not
        // model. The predicate still accepts it; refusing it is the config API's policy call.
        assert!(is_valid_wht_pay_type_code(WHT_PAY_TYPE_CODE_OTHER));

        // `TBIncomeType` (doc lines 167-190) — fifteen codes, and NOT integers: `4b1.4` is a code.
        assert_eq!(WHT_INCOME_TYPE_CODES.len(), 15);
        for ok in ["1", "5", "6", "4a", "4b1.4", "4b2.5", " 5 "] {
            assert!(is_valid_wht_income_type_code(ok), "{ok} is in TBIncomeType");
        }
        for bad in ["0", "7", "4", "4b", "4b1", "4B1.4", "", "05"] {
            assert!(!is_valid_wht_income_type_code(bad), "{bad} is not");
        }
        // The stored defaults (pay type 1, income type 5) are valid — a fresh install must be able
        // to export without touching the settings screen.
        assert!(is_valid_wht_pay_type_code("1") && is_valid_wht_income_type_code("5"));
    }

    #[test]
    fn txndet_wht_delivery_flag_is_e_not_y_when_an_email_is_set() {
        // `checkFlagHaveEmailWHT` emits "E", not "Y" (doc lines 1738, 2736, 2741).
        let out = generate(&batch(vec![guard_mob()]));
        let txn: Vec<&str> = out.split("\r\n").nth(2).unwrap().split('|').collect();
        assert_eq!(txn[11], "Y", "the e-mail NOTIFY flag is still Y/N");
        assert_eq!(txn[25], "E", "the WHT DELIVERY method is E");
        assert_eq!(txn[26], "guard2@example.com");
    }

    #[test]
    fn whtcer_is_19_fields_and_whtdet_is_its_own_seven_field_record() {
        let out = generate(&batch(vec![guard_nat()]));
        let lines: Vec<&str> = out.split("\r\n").collect();

        // The certificate HEADER: exactly 19 fields, no income figures appended.
        let wht: Vec<&str> = lines[3].split('|').collect();
        assert_eq!(
            wht.len(),
            19,
            "19 header fields, the detail is a separate line"
        );
        assert_eq!(wht[0], "WHTCER");
        assert_eq!(wht[2], "0105551234567", "payer tax id (org)");
        assert_eq!(wht[3], "PGuard Co., Ltd.");
        assert_eq!(wht[7], "1234567890121", "recipient tax id (guard)");
        assert_eq!(wht[8], "สมชาย รปภ");
        assert_eq!(wht[9], "99 Rama IX Rd, Bangkok");
        // Field 12 is BLANK on purpose — the doc disagrees with itself about whether it is a
        // sequence number (doc lines 2213/2308) or the "Alternative Recipient Name for WHT" the
        // sheet header gives column 14 (doc line 513). A digit in a NAME column would misname the
        // recipient on a government tax filing, so we omit it. See `wht_header_row`.
        assert_eq!(
            wht[12], "",
            "no per-recipient index in the alternative-name column"
        );
        assert_eq!(wht[13], "53", "ภ.ง.ด.53 form code");
        assert_eq!(wht[14], "20260905", "deduct date");
        assert_eq!(wht[17], "1", "one detail block");
        assert_eq!(wht[18], "30.00", "total WHT");

        // The income DETAIL: its own physical record, field 0 = the literal "WHTDET".
        let det: Vec<&str> = lines[4].split('|').collect();
        assert_eq!(det.len(), 7);
        assert_eq!(det[0], "WHTDET", "the record id, NOT a block index");
        assert_eq!(det[1], "5", "income type code");
        assert_eq!(det[2], "ค่าบริการรักษาความปลอดภัย");
        assert_eq!(det[3], "3.00", "rate %");
        assert_eq!(det[4], "", "dividend-to-net-profit % is blank");
        assert_eq!(det[5], "1000.00", "gross income");
        assert_eq!(det[6], "30.00", "wht amount");
    }

    #[test]
    fn without_wht_emits_no_certificate_and_flags_off() {
        // A recipient with zero WHT (e.g. the batch does not withhold) → no WHTCER/WHTDET at all.
        let mut g = guard_nat();
        g.wht = d("0");
        let out = generate(&batch(vec![g]));
        let lines: Vec<&str> = out.split("\r\n").collect();
        // HEADER | BCHDET | TXNDET | TRAILR
        assert_eq!(lines.len(), 4);
        assert!(!out.contains("WHTCER"));
        assert!(!out.contains("WHTDET"));
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
        let out = generate(&batch(vec![guard_nat(), guard_mob()]));
        let lines: Vec<&str> = out.split("\r\n").collect();
        // HEADER, BCHDET, (TXNDET, WHTCER, WHTDET)×2, TRAILR = 9
        assert_eq!(lines.len(), 9);
        let bch: Vec<&str> = lines[1].split('|').collect();
        assert_eq!(bch[6], "1455.00", "970 + 485");
        assert_eq!(bch[7], "2");
        // second recipient is MOB, with its own certificate pair right after its credit line.
        let txn2: Vec<&str> = lines[5].split('|').collect();
        assert_eq!(txn2[0], "TXNDET");
        assert_eq!(txn2[3], "MOB");
        assert_eq!(txn2[9], "N", "no phone → SMS flag off");
        assert!(lines[6].starts_with("WHTCER|"));
        assert!(lines[7].starts_with("WHTDET|"));
        assert_eq!(
            lines[6].split('|').nth(12),
            Some(""),
            "field 12 stays blank on EVERY certificate, not just the first"
        );
        let trailer: Vec<&str> = lines[8].split('|').collect();
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

    #[test]
    fn a_pipe_in_free_text_never_shifts_a_later_field() {
        // The whole point of sanitising: hostile/typo'd PII must not move the AMOUNT column.
        let mut g = guard_nat();
        g.name = "สมชาย|รปภ".to_string();
        g.address = "99|Rama|IX".to_string();
        let mut b = batch(vec![g]);
        b.payer.name = "PGuard|Co".to_string();
        b.payer.address = "1|Sathorn".to_string();
        let out = generate(&b);
        let lines: Vec<&str> = out.split("\r\n").collect();

        let txn: Vec<&str> = lines[2].split('|').collect();
        assert_eq!(txn.len(), 28, "still exactly 28 fields");
        assert_eq!(txn[6], "970.00", "the amount is still in field 6");
        assert_eq!(txn[13], "สมชายรปภ");
        assert_eq!(txn[14], "99RamaIX");
        let wht: Vec<&str> = lines[3].split('|').collect();
        assert_eq!(wht.len(), 19, "still exactly 19 fields");
        assert_eq!(wht[3], "PGuardCo");
        assert_eq!(wht[18], "30.00", "the WHT total is still in field 18");
    }

    /// GOLDEN FILE — the COMPLETE generated text for a two-recipient batch, line by line. Any
    /// change to field order, field count, record order or the CRLF joining fails here, which is
    /// exactly what a positional money file needs (a shifted field is silently wrong, not loud).
    #[test]
    fn golden_two_recipient_batch() {
        let out = generate(&batch(vec![guard_nat(), guard_mob()]));
        let expected = concat!(
            "HEADER|050926120000PPY|SYS-1\r\n",
            "BCHDET|050926120000|PPY|20260905|1234567896|1234567896|1455.00|2||\r\n",
            "TXNDET|PAY-0001|1234567890121|NAT|111|0000|970.00||OUR|Y|0812345678|N||",
            "สมชาย รปภ|99 Rama IX Rd, Bangkok|||Y|1|30.00|N|N||||N||\r\n",
            "WHTCER||0105551234567|PGuard Co., Ltd.|1 Sathorn Rd, Bangkok 10120|||",
            "1234567890121|สมชาย รปภ|99 Rama IX Rd, Bangkok||||53|20260905|1||1|30.00\r\n",
            "WHTDET|5|ค่าบริการรักษาความปลอดภัย|3.00||1000.00|30.00\r\n",
            "TXNDET|PAY-0002|0899999999|MOB|111|0000|485.00||OUR|N||Y|guard2@example.com|",
            "สมหญิง รปภ|12 Silom Rd, Bangkok|||Y|1|15.00|N|N||||E|guard2@example.com|\r\n",
            "WHTCER||0105551234567|PGuard Co., Ltd.|1 Sathorn Rd, Bangkok 10120|||",
            "9876543210989|สมหญิง รปภ|12 Silom Rd, Bangkok||||53|20260905|1||1|15.00\r\n",
            "WHTDET|5|ค่าบริการรักษาความปลอดภัย|3.00||500.00|15.00\r\n",
            "TRAILR|1|2|1455.00",
        );
        assert_eq!(out, expected);
        assert!(!out.ends_with("\r\n"), "no trailing newline (SCB shape)");
        // The debit accounts in the golden are real SCB numbers, not filler — the API layer refuses
        // to save or export anything else, so a golden built on an invalid one would drift.
        assert!(is_valid_scb_account("1234567896"));
    }

    /// GOLDEN FILE — the second product, end to end: an `OAT` sweep of the platform's cut into the
    /// company revenue account (stream ②). Same 28/10/4-field records, different wire values in
    /// exactly the four product-branched places — which is the point of the whole branch.
    #[test]
    fn golden_own_account_sweep_batch() {
        let out = generate(&oat_batch(vec![sweep_recipient()]));
        let expected = concat!(
            "HEADER|050926120000OAT|SYS-1\r\n",
            "BCHDET|050926120000|OAT|20260905|1234567896|1234567896|1200.00|1||\r\n",
            // f3 blank (no proxy) · f4 "014" (the bank code, zero-padded) · f5 "0111" · f7 blank.
            "TXNDET|SW-0001|4051234567||014|0111|1200.00||OUR|N||N||",
            "PGuard Revenue|1 Sathorn Rd, Bangkok 10120|||N|||N|N||||N||\r\n",
            // No WHT: the company does not withhold tax from itself, so no WHTCER/WHTDET pair.
            "TRAILR|1|1|1200.00",
        );
        assert_eq!(out, expected);
        assert!(!out.ends_with("\r\n"), "no trailing newline (SCB shape)");
        assert!(!out.contains("WHTCER"));
        // The credit account is a real SCB number and the destination is legal for this product —
        // a golden built on a rejectable line would encode a file the bank bounces.
        assert!(is_valid_scb_account("4051234567"));
        assert_eq!(
            destination_rejection(ScbProduct::OwnAccount, &sweep_recipient().destination),
            None
        );
    }

    #[test]
    fn a_special_character_in_a_name_is_dropped_while_the_address_keeps_its_own() {
        // End to end: the two rules must reach the FILE differently. A guard called `สมชาย & Co.`
        // used to bounce the whole upload (`&` is in `validateTextWithSpecialChar`), while an
        // address full of `( ) / .` is perfectly legal and must arrive intact.
        let mut g = guard_nat();
        g.name = "สมชาย & Co. #2".to_string();
        g.address = "99/1 ซ.รามคำแหง 24 (แยก 5), เขตบางกะปิ".to_string();
        let mut b = batch(vec![g]);
        b.payer.name = "PGuard & Sons Co., Ltd.".to_string();
        b.config.wht_income_desc = "ค่าบริการ รปภ. @ ไซต์งาน".to_string();
        let out = generate(&b);
        let lines: Vec<&str> = out.split("\r\n").collect();

        let txn: Vec<&str> = lines[2].split('|').collect();
        assert_eq!(txn.len(), 28, "still exactly 28 fields");
        assert_eq!(txn[13], "สมชาย Co. 2", "name: `&` and `#` dropped");
        assert_eq!(
            txn[14], "99/1 ซ.รามคำแหง 24 (แยก 5), เขตบางกะปิ",
            "address: untouched"
        );

        let wht: Vec<&str> = lines[3].split('|').collect();
        assert_eq!(wht[3], "PGuard Sons Co., Ltd.", "payer name: `&` dropped");
        assert_eq!(wht[8], "สมชาย Co. 2", "recipient name on the certificate");
        assert_eq!(wht[9], "99/1 ซ.รามคำแหง 24 (แยก 5), เขตบางกะปิ");

        let det: Vec<&str> = lines[4].split('|').collect();
        assert_eq!(det[2], "ค่าบริการ รปภ. ไซต์งาน", "income desc: `@` dropped");
    }

    /// STREAM ① — the customer-refund file emits NO withholding records AT ALL.
    ///
    /// A refund is the customer's own money coming back, not assessable income: every recipient
    /// carries `wht = 0`, so `has_wht()` is false and neither a `WHTCER` nor a `WHTDET` may appear.
    /// This is asserted on the RENDERED TEXT rather than on the recipient struct because it is the
    /// file that reaches the Revenue Department's paperwork — a future refactor that starts emitting
    /// a certificate "for completeness" would be issuing tax documents for money that is not income.
    /// The blank [`WhtPayer::none`] block proves the same thing from the other side: there is no
    /// company TIN in this file to put on a certificate, and none is needed to send one.
    #[test]
    fn a_refund_file_carries_no_wht_certificate_and_needs_no_payer() {
        let refund = |txn: &str, proxy: &str, name: &str, amount: &str| PayoutRecipient {
            transaction_ref: txn.to_string(),
            destination: CreditDestination::promptpay(proxy),
            tax_id: String::new(),
            name: name.to_string(),
            address: "99 Rama IX Rd, Bangkok".to_string(),
            income: d(amount),
            wht: Decimal::ZERO,
            phone: None,
            email: None,
        };
        let b = PayoutBatch {
            file_ref: "070926120000PPY".to_string(),
            system_ref: "PGUARD-REFUND".to_string(),
            batch_ref: "070926120000".to_string(),
            product: ScbProduct::PromptPay,
            service_type_code: String::new(),
            // No ภ.ง.ด. payer — the refund export never reads the company block.
            payer: WhtPayer::none(),
            config: config(),
            recipients: vec![
                refund("RF0709261200000001", "0812345678", "ลูกค้า หนึ่ง", "500.00"),
                refund("RF0709261200000002", "0899999999", "ลูกค้า สอง", "1070.00"),
            ],
        };
        let out = generate(&b);

        assert!(!out.contains(WHT_CODE), "no WHTCER in a refund file: {out}");
        assert!(
            !out.contains(WHT_DETAIL_CODE),
            "no WHTDET in a refund file: {out}"
        );
        // HEADER + BCHDET + one TXNDET per customer + TRAILR = 5. A withholding batch of two would
        // be 9 (three lines per recipient), so this count alone catches a certificate creeping back.
        let lines: Vec<&str> = out.split(NEWLINE).collect();
        assert_eq!(lines.len(), 5, "one credit line per customer: {out}");

        // The credit rows say "no withholding" in the three fields SCB reads it from.
        for line in lines.iter().filter(|l| l.starts_with(CREDIT_CODE)) {
            let f: Vec<&str> = line.split(DELIM).collect();
            assert_eq!(f.len(), 28, "still exactly 28 fields");
            assert_eq!(f[17], FLAG_N, "WHT required flag off");
            assert_eq!(f[18], "", "no certificate count");
            assert_eq!(f[19], "", "no withheld amount");
        }

        // The money is the FULL obligation — nothing is withheld on the way back.
        let credit: Vec<&str> = lines[2].split(DELIM).collect();
        assert_eq!(credit[6], "500.00");
        assert_eq!(credit[3], PROXY_MOBILE, "a customer is paid on their phone");
        let batch_line: Vec<&str> = lines[1].split(DELIM).collect();
        assert_eq!(
            batch_line[6], "1570.00",
            "500.00 + 1070.00, nothing withheld"
        );
        assert_eq!(batch_line[7], "2");
        let trailer: Vec<&str> = lines[4].split(DELIM).collect();
        assert_eq!(trailer[3], "1570.00");
    }
}
