//! PURE selection + obligation-identity logic for stream ① *ยอดที่ต้องโอนคืนกับคนจ้าง* — the
//! CUSTOMER-REFUND SCB file. No DB, no HTTP; 100% unit-testable.
//!
//! The refund backlog differs from the guard-payout one in exactly one structural way, and this
//! module is where that difference is modelled: **two different tables owe the money**, so a refund
//! obligation is identified by a PAIR — a [`RefundSourceKind`] plus the row id — not by a single
//! `booking_id`. Everything downstream (the paid-marker unique, the per-item void, the audit rows)
//! keys off that pair, so it gets a type rather than a pair of loose strings that a caller could
//! silently swap.
//!
//! The file itself is written by [`crate::domain::scb_export`], unchanged: a refund is a PromptPay
//! credit with `wht = 0`, so the existing writer already emits no `WHTCER`/`WHTDET` for it. There is
//! no second file writer here and there must never be one.

use chrono::NaiveDate;
use uuid::Uuid;

use shared::error::AppError;

use crate::domain::promptpay::{classify_proxy, PromptPayProxy};
use crate::domain::scb_export::digits_only;

/// What the customer's stored phone turns out to be, as a REFUND destination. Three outcomes, not
/// two, because "there is no phone" and "the phone we have is not a payable one" are different
/// problems for the admin: the first needs the customer contacted, the second needs the stored value
/// corrected.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RefundDestination {
    /// A genuine Thai mobile number, digits-only — the ONLY thing a refund may be credited to.
    Mobile(String),
    /// No phone on file at all (no `contact_phone`, and identity resolved no login phone either).
    NoPhone,
    /// A phone IS stored, but it is not a Thai mobile number — so it must never address money.
    NotAMobile,
}

/// Classify the customer's registration phone as a refund destination. PURE.
///
/// **THE REFUND STREAM IS MOB-ONLY.** This is the single most important rule in the module, and it is
/// deliberately NARROWER than the guard payout's, which legitimately accepts a 13-digit `NAT` proxy:
///
///  * a GUARD's proxy is their tax id — a number the guard themself supplied *as a payment address*,
///    validated at profile's write boundary and re-checked against the national-ID check digit
///    before it is allowed to address money;
///  * a CUSTOMER's phone is CONTACT data. Nobody ever offered it as a payment address, nothing
///    validates it as one, and registration accepts whatever was typed.
///
/// So the refund path must NOT classify by digit count the way SCB itself does (10→`MOB`, 13→`NAT`,
/// 15→`EWL` — [`crate::domain::scb_export::CreditDestination::proxy_type_code`], doc line 2055,
/// which is correct for what it models). A stored contact value that happens to normalise to 13
/// digits — a number saved with a country code, an extension appended, a typo, a pasted id — would
/// be stamped `NAT` and the refund would be PromptPay-credited to WHOEVER OWNS THAT NATIONAL ID.
/// PromptPay is irreversible, and by then the obligation is marked `processed`: the real customer is
/// neither refunded nor visible in the queue any more. That is money gone with no trace.
///
/// [`classify_proxy`] is reused rather than a length test because it already encodes the Thai mobile
/// RULE (leading `0`, ten digits) rather than trusting a bare digit count.
pub fn classify_refund_destination(phone: Option<&str>) -> RefundDestination {
    let Some(digits) = phone.map(digits_only).filter(|d| !d.is_empty()) else {
        return RefundDestination::NoPhone;
    };
    match classify_proxy(&digits) {
        Some(PromptPayProxy::Mobile) => RefundDestination::Mobile(digits),
        // Everything else — a 13-digit id, a 15-digit e-wallet, a 9-digit landline, a truncated
        // number — is a phone we cannot pay, NEVER a proxy of another type to guess at.
        _ => RefundDestination::NotAMobile,
    }
}

/// WHICH table owes one refund obligation. The two lanes have different shapes — a different id, a
/// different amount column, a different way of reaching the customer — so the export must carry the
/// lane with the id everywhere, or a `payments` row and a `payment_slips` row that happened to be
/// created with the same UUID would look like the same obligation.
///
/// Stored as [`Self::as_str`] in `payment.refund_batch_items.source_kind` (a DB CHECK pins the same
/// two values).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum RefundSourceKind {
    /// `payment.payments` — `refund_status = 'pending'` with `refund_amount > 0`. The completion
    /// reconcile's overpay, the cancellation refund (full, or net of a retained fee) and the
    /// race-lost pre-pay compensator all land here.
    Payment,
    /// `payment.payment_slips` — `applied = FALSE AND refund_status = 'pending'`: a SECOND, REAL
    /// transfer for an already-paid booking (migration 0006). The amount is the slip's own, and the
    /// customer is resolved through the slip's `payment_id`.
    Slip,
}

/// The two lane names, in the order the backlog UNION reads them — also the DB CHECK list, kept
/// next to the enum so an error message can name the whole set without re-typing it.
pub const REFUND_SOURCE_KINDS: [&str; 2] = ["payment", "slip"];

impl RefundSourceKind {
    /// The stored/wire form.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Payment => "payment",
            Self::Slip => "slip",
        }
    }

    /// Parse the stored/wire form. `None` for anything else — the caller decides whether that is a
    /// client 400 (a bad request body) or an internal error (a row the DB CHECK should have refused).
    pub fn parse(s: &str) -> Option<Self> {
        match s.trim() {
            "payment" => Some(Self::Payment),
            "slip" => Some(Self::Slip),
            _ => None,
        }
    }

    /// Thai label for the admin-facing messages (the API speaks Thai to admins).
    pub const fn label_th(self) -> &'static str {
        match self {
            Self::Payment => "เงินคืนจากรายการชำระเงิน",
            Self::Slip => "เงินคืนจากสลิปโอนซ้ำ",
        }
    }
}

/// ONE refund obligation, named the only way it can be named unambiguously. A plain `Uuid` would
/// not do: the two lanes are separate tables, so the same id could in principle exist in both.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct RefundSource {
    pub kind: RefundSourceKind,
    pub id: Uuid,
}

/// WHICH refund obligations one preview/export run covers — the admin's tick-list and/or the day
/// window. All-`None` is the default whole-backlog run, exactly like [`crate::domain::payout::PayoutSelection`].
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RefundSelection {
    /// The customers to refund; `None` = every customer with a pending, refundable obligation.
    pub customer_ids: Option<Vec<Uuid>>,
    /// Inclusive first day the refund became owed (Thai local date).
    pub from: Option<NaiveDate>,
    /// Inclusive last day the refund became owed (Thai local date).
    pub to: Option<NaiveDate>,
}

/// Upper bound on how many customers ONE export may name — a longer list is a client bug, not an
/// admin action (the file is uploaded to SCB by hand). The backlog-wide default is unbounded.
pub const MAX_SELECTED_CUSTOMERS: usize = 500;

impl RefundSelection {
    /// Reject a selection that cannot mean anything: an EXPLICIT but empty customer list (the admin
    /// ticked nobody — silently refunding everyone would be a money bug), an absurdly long list, or
    /// an inverted date window. PURE: no I/O, so the API layer validates before touching the DB.
    pub fn validate(&self) -> Result<(), AppError> {
        if let Some(ids) = &self.customer_ids {
            if ids.is_empty() {
                return Err(AppError::BadRequest(
                    "เลือกลูกค้าอย่างน้อย 1 รายก่อนสร้างไฟล์คืนเงิน".to_string(),
                ));
            }
            if ids.len() > MAX_SELECTED_CUSTOMERS {
                return Err(AppError::BadRequest(format!(
                    "เลือกลูกค้าได้ไม่เกิน {MAX_SELECTED_CUSTOMERS} รายต่อไฟล์"
                )));
            }
        }
        if let (Some(from), Some(to)) = (self.from, self.to) {
            if from > to {
                return Err(AppError::BadRequest(
                    "ช่วงวันที่ไม่ถูกต้อง (วันเริ่มต้องไม่เกินวันสิ้นสุด)".to_string(),
                ));
            }
        }
        Ok(())
    }
}

/// Upper bound on how many obligations ONE per-item void may name. Same reasoning as
/// [`MAX_SELECTED_CUSTOMERS`]: a longer list is a client bug, and this is an admin correcting the
/// handful of credit lines the bank could not deliver, never a bulk operation.
pub const MAX_VOIDED_REFUND_ITEMS: usize = 500;

/// Normalise the `(source_kind, source_id)` pairs of a per-item void into the list the repo may act
/// on: every kind PARSED (an unknown lane is a 400, never a silent skip), DE-DUPLICATED (order
/// preserved), non-empty, and within [`MAX_VOIDED_REFUND_ITEMS`].
///
/// De-duplicating is not tidiness — it is what keeps the repo's "every named obligation must have
/// been returned" count honest. The same pair twice updates ONE row, so a repo comparing
/// `rows_affected` against the requested length would see 1 ≠ 2 and refuse a request that is really
/// just clumsy; and not comparing at all would let a genuinely wrong id pass silently.
///
/// An EMPTY list is refused rather than treated as "all of them": the whole-batch void is a
/// different, more dangerous action with its own endpoint, and a client bug must never escalate into
/// it. PURE: no I/O, so the API layer validates before touching the DB.
pub fn normalize_voided_refund_sources(
    raw: &[(String, Uuid)],
) -> Result<Vec<RefundSource>, AppError> {
    if raw.is_empty() {
        return Err(AppError::BadRequest(
            "เลือกรายการคืนเงินอย่างน้อย 1 รายการที่ต้องการดึงกลับเข้าคิว".to_string(),
        ));
    }
    if raw.len() > MAX_VOIDED_REFUND_ITEMS {
        return Err(AppError::BadRequest(format!(
            "ดึงรายการคืนเงินกลับได้ไม่เกิน {MAX_VOIDED_REFUND_ITEMS} รายการต่อครั้ง"
        )));
    }
    let mut out: Vec<RefundSource> = Vec::with_capacity(raw.len());
    for (kind, id) in raw {
        let Some(kind) = RefundSourceKind::parse(kind) else {
            // Naming the allowed set beats "invalid": the caller is a screen that just read these
            // very strings back off the batch drill-down, so a mismatch is a bug worth spelling out.
            return Err(AppError::BadRequest(format!(
                "ประเภทรายการคืนเงินไม่ถูกต้อง — ต้องเป็นหนึ่งใน {}",
                REFUND_SOURCE_KINDS.join(", ")
            )));
        };
        let source = RefundSource { kind, id: *id };
        if !out.contains(&source) {
            out.push(source);
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn day(y: i32, m: u32, d: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, d).expect("valid date")
    }

    /// THE MONEY-GOES-TO-A-STRANGER TEST. A customer's phone is contact data, so a stored value that
    /// normalises to 13 digits is a TYPO, not a national id — but SCB stamps a proxy type from the
    /// digit count alone, so accepting it would credit the refund to whoever really owns that id,
    /// irreversibly, while the obligation is marked `processed`. Only a genuine Thai mobile is a
    /// refund destination; everything else excludes that ONE customer with a reason.
    #[test]
    fn only_a_real_thai_mobile_may_receive_a_refund() {
        // The one payable shape: leading 0, ten digits — separators are stripped first.
        assert_eq!(
            classify_refund_destination(Some("081-234-5678")),
            RefundDestination::Mobile("0812345678".to_string()),
            "a Thai mobile is the refund destination, digits-only"
        );

        // 13 digits: SCB would stamp this `NAT` and pay the citizen who owns it. NOT a destination.
        assert_eq!(
            classify_refund_destination(Some("1234567890123")),
            RefundDestination::NotAMobile,
            "a 13-digit value must never be treated as a national-id proxy on the refund path"
        );
        // A real mobile saved with the country code lands on 13 digits too (`66812345678` is 11, but
        // `0066812345678` is exactly 13) — the everyday way this bug would have been triggered.
        assert_eq!(
            classify_refund_destination(Some("0066-81-234-5678")),
            RefundDestination::NotAMobile,
            "a country-coded phone normalises to 13 digits — excluded, not paid to a stranger"
        );
        // 15 digits: SCB's `EWL` e-wallet proxy. A customer's phone is never one of those.
        assert_eq!(
            classify_refund_destination(Some("081234567890123")),
            RefundDestination::NotAMobile
        );
        // A landline (9 digits), a truncated number, and a 10-digit value that is not a mobile.
        for unusable in ["021234567", "12345", "1234567890"] {
            assert_eq!(
                classify_refund_destination(Some(unusable)),
                RefundDestination::NotAMobile,
                "{unusable} cannot receive a PromptPay transfer"
            );
        }

        // Nothing on file at all — a different message for the admin, and still not payable.
        assert_eq!(
            classify_refund_destination(None),
            RefundDestination::NoPhone
        );
        assert_eq!(
            classify_refund_destination(Some("")),
            RefundDestination::NoPhone
        );
        assert_eq!(
            classify_refund_destination(Some("  -- ")),
            RefundDestination::NoPhone,
            "a value with no digits at all is no phone, not a bad one"
        );
    }

    #[test]
    fn the_two_lanes_round_trip_and_nothing_else_parses() {
        for kind in [RefundSourceKind::Payment, RefundSourceKind::Slip] {
            assert_eq!(RefundSourceKind::parse(kind.as_str()), Some(kind));
            assert!(REFUND_SOURCE_KINDS.contains(&kind.as_str()));
            assert!(!kind.label_th().is_empty());
        }
        // Whitespace is tolerated (the value may come back off a form), anything else is refused —
        // a lane we cannot name is an obligation we must not mark settled.
        assert_eq!(
            RefundSourceKind::parse(" slip "),
            Some(RefundSourceKind::Slip)
        );
        for bogus in ["", "payments", "SLIP", "booking", "payment "] {
            if bogus == "payment " {
                continue; // trimmed above — covered by the whitespace case
            }
            assert_eq!(
                RefundSourceKind::parse(bogus),
                None,
                "{bogus} is not a lane"
            );
        }
    }

    #[test]
    fn the_default_selection_is_the_whole_backlog() {
        let sel = RefundSelection::default();
        assert_eq!(sel.customer_ids, None);
        assert_eq!((sel.from, sel.to), (None, None));
        assert!(sel.validate().is_ok());
    }

    #[test]
    fn many_customers_and_a_valid_window_are_accepted() {
        let sel = RefundSelection {
            customer_ids: Some(vec![Uuid::new_v4(), Uuid::new_v4()]),
            from: Some(day(2026, 9, 1)),
            to: Some(day(2026, 9, 30)),
        };
        assert!(sel.validate().is_ok(), "a multi-customer file is the point");
        // A single-day window (from == to) is a legitimate "refund today's obligations" run.
        let same_day = RefundSelection {
            customer_ids: None,
            from: Some(day(2026, 9, 7)),
            to: Some(day(2026, 9, 7)),
        };
        assert!(same_day.validate().is_ok());
    }

    #[test]
    fn an_explicit_empty_customer_list_is_rejected() {
        // Ticking nobody must NOT silently fall back to refunding the whole backlog.
        let sel = RefundSelection {
            customer_ids: Some(vec![]),
            ..Default::default()
        };
        assert!(matches!(sel.validate(), Err(AppError::BadRequest(_))));
    }

    #[test]
    fn an_oversized_customer_list_and_an_inverted_window_are_rejected() {
        let sel = RefundSelection {
            customer_ids: Some(vec![Uuid::new_v4(); MAX_SELECTED_CUSTOMERS + 1]),
            ..Default::default()
        };
        assert!(matches!(sel.validate(), Err(AppError::BadRequest(_))));
        let inverted = RefundSelection {
            customer_ids: None,
            from: Some(day(2026, 9, 30)),
            to: Some(day(2026, 9, 1)),
        };
        assert!(matches!(inverted.validate(), Err(AppError::BadRequest(_))));
    }

    #[test]
    fn voided_sources_are_parsed_deduplicated_and_bounded() {
        let a = Uuid::new_v4();
        let b = Uuid::new_v4();
        let got = normalize_voided_refund_sources(&[
            ("payment".to_string(), a),
            ("slip".to_string(), a), // the SAME uuid in the other lane is a DIFFERENT obligation
            ("payment".to_string(), a), // a true duplicate — collapsed
            ("slip".to_string(), b),
        ])
        .expect("valid");
        assert_eq!(
            got,
            vec![
                RefundSource {
                    kind: RefundSourceKind::Payment,
                    id: a
                },
                RefundSource {
                    kind: RefundSourceKind::Slip,
                    id: a
                },
                RefundSource {
                    kind: RefundSourceKind::Slip,
                    id: b
                },
            ],
            "order preserved, only the exact repeat dropped"
        );

        // Empty is NOT "all of them" — that is the whole-batch void's job.
        assert!(matches!(
            normalize_voided_refund_sources(&[]),
            Err(AppError::BadRequest(_))
        ));
        // An unknown lane is a 400 naming the set, never a silent skip.
        let err = normalize_voided_refund_sources(&[("booking".to_string(), a)])
            .expect_err("unknown lane");
        let AppError::BadRequest(msg) = err else {
            unreachable!()
        };
        assert!(msg.contains("payment, slip"), "names the set: {msg}");
        // Oversized.
        let many: Vec<(String, Uuid)> = (0..MAX_VOIDED_REFUND_ITEMS + 1)
            .map(|_| ("payment".to_string(), Uuid::new_v4()))
            .collect();
        assert!(matches!(
            normalize_voided_refund_sources(&many),
            Err(AppError::BadRequest(_))
        ));
    }
}
