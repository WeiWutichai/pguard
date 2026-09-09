//! Pure field validation for profile writes. Bounds are defensive (reject absurd values
//! before they reach the DB / downstream payment+rating logic). No I/O.

/// Plausible bounds for a guard's self-reported years of experience. A negative value is
/// nonsense; the upper bound rejects obvious garbage without being so tight it rejects a
/// long career.
const MAX_YEARS_OF_EXPERIENCE: i32 = 80;

/// Free-text upper bound shared by short text fields (names, workplace, address). Keeps a
/// single oversized field from bloating a row or a log line.
pub const MAX_TEXT_LEN: usize = 500;

/// Bank account numbers are short; cap defensively (digits + a few separators).
pub const MAX_ACCOUNT_NUMBER_LEN: usize = 34; // IBAN max length, generous for TH accounts.

/// Validate optional years-of-experience. `None` is allowed (field is optional).
pub fn validate_years_of_experience(years: Option<i32>) -> Result<(), String> {
    match years {
        None => Ok(()),
        Some(y) if (0..=MAX_YEARS_OF_EXPERIENCE).contains(&y) => Ok(()),
        Some(_) => Err(format!(
            "years_of_experience must be between 0 and {MAX_YEARS_OF_EXPERIENCE}"
        )),
    }
}

/// Validate an optional bounded text field. `None`/empty is allowed (fields are optional).
pub fn validate_text(value: Option<&str>, field: &str, max: usize) -> Result<(), String> {
    match value {
        None => Ok(()),
        Some(v) if v.chars().count() <= max => Ok(()),
        Some(_) => Err(format!("{field} must be at most {max} characters")),
    }
}

/// Validate an optional email (loose, mirrors v1 — real verification is out of scope): must
/// contain `@` and `.`, length in `[5, MAX_TEXT_LEN]`. `None`/empty → Ok (optional field).
pub fn validate_email(value: Option<&str>) -> Result<(), String> {
    match value.map(str::trim) {
        None | Some("") => Ok(()),
        Some(v)
            if v.len() >= 5 && v.len() <= MAX_TEXT_LEN && v.contains('@') && v.contains('.') =>
        {
            Ok(())
        }
        Some(_) => Err("email must be a valid address".to_string()),
    }
}

/// Upper bound for a stored tax id (digits + a few separators). The Thai TIN is 13 digits;
/// kept generous so a future/foreign format or an entered separator is not rejected.
pub const MAX_TAX_ID_LEN: usize = 20;

/// Thai national ID (เลขประจำตัวประชาชน) mod-11 check digit.
///
/// `digits` must be the digits-only form (the caller strips separators first); anything that is
/// not exactly 13 ASCII digits returns `false` rather than panicking — this runs in a request
/// path, so no indexing/slicing that could trip on non-ASCII input.
///
/// ```text
/// sum   = Σ digit[i] × (13 − i)   over the first TWELVE digits (weights 13 → 2)
/// check = (11 − (sum mod 11)) mod 10
/// valid iff check == digit[12]
/// ```
///
/// Worked by hand against the implementation: `0123456789016` → sum 302, 302 mod 11 = 5,
/// (11−5) mod 10 = **6** = last digit ✓; `1234567890121` → sum 352, 352 mod 11 = 0,
/// (11−0) mod 10 = **1** = last digit ✓.
fn thai_national_id_check_digit_ok(digits: &str) -> bool {
    let d: Vec<u32> = digits.chars().filter_map(|c| c.to_digit(10)).collect();
    // `filter_map` silently drops a non-digit, so also require nothing was dropped.
    if d.len() != 13 || d.len() != digits.chars().count() {
        return false;
    }
    // Weights run 13,12,…,2 over the first twelve digits. Max sum is 9×90 = 810 — no overflow,
    // and `sum % 11` ∈ [0,10] so `11 - …` never underflows.
    let sum: u32 = d[..12]
        .iter()
        .zip((2u32..=13).rev())
        .map(|(digit, weight)| digit * weight)
        .sum();
    let check = (11 - (sum % 11)) % 10;
    check == d[12]
}

/// **The LENIENT (shape-only) tax-id rule — for the ORG / company tax id.**
///
/// After stripping spaces/hyphens the value must be ALL DIGITS, length in `[8, MAX_TAX_ID_LEN]`.
/// That catches an obvious typo (letters / empty-after-strip / absurd length) and nothing more.
/// `None`/empty → Ok (the admin may save the company name before they have the tax id).
///
/// # Why this one is deliberately NOT the strict one — do not "clean up" by merging
///
/// Its caller is `PUT /admin/org-settings`, which stores the COMPANY's tax id. A company TIN is a
/// เลขประจำตัวผู้เสียภาษี for a **juristic person**, not a citizen id, so the Thai national-id
/// mod-11 checksum has no authority over it even though both are 13 digits. Worse, applying the
/// citizen checksum here is self-defeating: the web-admin settings form always re-sends the value
/// it loaded, so an install whose stored company TIN happens to fail that checksum could no longer
/// save the company profile AT ALL — and the payout export 400s without a company tax id, so a
/// "hardening" would brick the very screen an operator needs in order to pay anybody.
///
/// The company tax id is also a tax REFERENCE (it is stamped into the ภ.ง.ด. payer block and onto
/// receipts), never a payment DESTINATION — nothing is ever transferred to it. Wrong digits there
/// produce a paperwork correction, not lost money. See [`validate_guard_tax_id`] for the path
/// where the same field IS the destination, and therefore does carry the checksum.
pub fn validate_tax_id(value: Option<&str>) -> Result<(), String> {
    match value.map(str::trim) {
        None | Some("") => Ok(()),
        Some(v) => {
            // The RAW value must still fit (a pathologically long separator-laden string is junk).
            if v.chars().count() > MAX_TAX_ID_LEN {
                return Err(format!(
                    "tax_id must be at most {MAX_TAX_ID_LEN} characters"
                ));
            }
            // Only digits, spaces and hyphens are allowed as input characters.
            if !v
                .chars()
                .all(|c| c.is_ascii_digit() || c == ' ' || c == '-')
            {
                return Err("tax_id must contain only digits (spaces/hyphens allowed)".to_string());
            }
            let digits: String = v.chars().filter(char::is_ascii_digit).collect();
            if !(8..=MAX_TAX_ID_LEN).contains(&digits.len()) {
                return Err("tax_id must be 8–20 digits".to_string());
            }
            Ok(())
        }
    }
}

/// **The STRICT tax-id rule — for a GUARD's tax id only** (`PUT /profile/guard` and
/// `PUT /admin/guard-profiles/{user_id}/payout`).
///
/// Shape first (delegated to [`validate_tax_id`], so the two paths can never disagree about what
/// "a tax id" looks like), then a LENGTH-CONDITIONAL Thai national-id mod-11 checksum: exactly 13
/// digits must pass; 8–12 / 14–20 keep the lenient behaviour.
///
/// # Why the guard path is stricter — do not "clean up" by merging these two
///
/// A guard's `tax_id` is not a reference, it is the account money is SENT to. The SCB export
/// stamps a 13-length PromptPay proxy as `NAT` (`CPX_Toolkit_Reverse_Engineering.md`:1872
/// "PPY→…len 15→EWL, 13→NAT, 10→MOB"; the proxy-code table is at :138) and writes it into TXNDET
/// field 2, the credit account (:1714 `rowArr(2) = … 'C credit acc / proxy value`). payment's
/// `resolve_proxy` PREFERS `tax_id` over the phone, so a shape-only check is not enough: a 13-digit
/// id mistyped off a photocopied ID card is still 13 digits, so it would pass, classify as a valid
/// `NAT` proxy, and credit a STRANGER. PromptPay is irreversible, and the booking is stamped paid
/// in `payment.payout_batch_items` the moment the file is generated, so the real guard is never
/// paid for that work either.
///
/// The checksum stays LENGTH-CONDITIONAL because only 13 digits is a citizen id. A guard row whose
/// `tax_id` is 8–12 or 14–20 digits is not a `NAT` proxy at all (the toolkit stamps it `TAX`), so
/// the citizen checksum would be rejecting a value it has no authority over — the same overreach
/// that [`validate_tax_id`] exists to avoid on the company screen.
pub fn validate_guard_tax_id(value: Option<&str>) -> Result<(), String> {
    // Shape is the SHARED half of the rule; the verdict below is the half that is not.
    validate_tax_id(value)?;
    let Some(v) = value.map(str::trim).filter(|v| !v.is_empty()) else {
        // Optional on this path too — a guard fills the profile across a multi-step onboarding,
        // and an admin may correct the bank block before they hold a copy of the ID card.
        return Ok(());
    };
    let digits: String = v.chars().filter(char::is_ascii_digit).collect();
    if digits.len() == 13 && !thai_national_id_check_digit_ok(&digits) {
        // Thai copy: this reaches an operator typing off an ID card, and it has to say what the
        // number is FOR (money destination) or a mismatch reads as bureaucratic pedantry. The
        // PromptPay wording is confined to this message — it is meaningless on the company screen.
        return Err(
            "tax_id: เลขประจำตัวประชาชน 13 หลักไม่ถูกต้อง (หลักตรวจสอบไม่ตรง) — \
             กรุณาตรวจสอบตัวเลขอีกครั้ง เลขนี้ถูกใช้เป็นพร้อมเพย์ปลายทางในการโอนเงินให้ รปภ. \
             หากกรอกผิดเงินจะเข้าบัญชีคนอื่นและเรียกคืนไม่ได้"
                .to_string(),
        );
    }
    Ok(())
}

/// Validate a support-ticket `kind` against the allowed set (`problem` | `feedback`). REQUIRED —
/// unlike the optional profile fields, a ticket must carry a valid kind. Returns the kind's error
/// message on a mismatch (empty / unknown value).
pub fn validate_ticket_kind(kind: &str, allowed: &[&str]) -> Result<(), String> {
    if allowed.contains(&kind) {
        Ok(())
    } else {
        Err(format!("kind must be one of: {}", allowed.join(", ")))
    }
}

/// Validate a REQUIRED support-ticket message: non-empty after trimming, at most `max` chars
/// (counted, not bytes — mirrors [`validate_text`]). An empty/whitespace-only or over-long body
/// is rejected so the reporter never files a blank ticket and the DB CHECK is never the first
/// line of defence.
pub fn validate_ticket_message(message: &str, max: usize) -> Result<(), String> {
    let trimmed = message.trim();
    if trimmed.is_empty() {
        return Err("message must not be empty".to_string());
    }
    if trimmed.chars().count() > max {
        return Err(format!("message must be at most {max} characters"));
    }
    Ok(())
}

/// Validate an optional Thai phone in national format: at least 10 digits starting with `0`
/// (mirrors the otp/identity phone shape — separators are ignored, not a carrier lookup).
/// `None`/empty → Ok (optional field).
pub fn validate_thai_phone(value: Option<&str>, field: &str) -> Result<(), String> {
    match value.map(str::trim) {
        None | Some("") => Ok(()),
        Some(v) => {
            let digits: String = v.chars().filter(char::is_ascii_digit).collect();
            if digits.len() >= 10 && digits.len() <= 15 && digits.starts_with('0') {
                Ok(())
            } else {
                Err(format!(
                    "{field} must be a valid Thai phone (≥10 digits starting with 0)"
                ))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn years_none_is_ok() {
        assert!(validate_years_of_experience(None).is_ok());
    }

    #[test]
    fn years_in_range_is_ok() {
        assert!(validate_years_of_experience(Some(0)).is_ok());
        assert!(validate_years_of_experience(Some(10)).is_ok());
        assert!(validate_years_of_experience(Some(MAX_YEARS_OF_EXPERIENCE)).is_ok());
    }

    #[test]
    fn years_negative_is_rejected() {
        assert!(validate_years_of_experience(Some(-1)).is_err());
    }

    #[test]
    fn years_above_max_is_rejected() {
        assert!(validate_years_of_experience(Some(MAX_YEARS_OF_EXPERIENCE + 1)).is_err());
    }

    #[test]
    fn text_none_and_short_are_ok() {
        assert!(validate_text(None, "f", MAX_TEXT_LEN).is_ok());
        assert!(validate_text(Some("hello"), "f", MAX_TEXT_LEN).is_ok());
    }

    #[test]
    fn text_at_limit_is_ok() {
        let s = "a".repeat(MAX_TEXT_LEN);
        assert!(validate_text(Some(&s), "f", MAX_TEXT_LEN).is_ok());
    }

    #[test]
    fn text_over_limit_is_rejected() {
        let s = "a".repeat(MAX_TEXT_LEN + 1);
        assert!(validate_text(Some(&s), "f", MAX_TEXT_LEN).is_err());
    }

    #[test]
    fn text_counts_chars_not_bytes() {
        // 5 multi-byte chars must NOT be rejected by a max of 5 (would fail if counting bytes).
        assert!(validate_text(Some("กขคงจ"), "f", 5).is_ok());
    }

    #[test]
    fn email_none_empty_and_valid_are_ok() {
        assert!(validate_email(None).is_ok());
        assert!(validate_email(Some("  ")).is_ok());
        assert!(validate_email(Some("a@b.co")).is_ok());
    }

    #[test]
    fn email_missing_at_or_dot_or_too_short_is_rejected() {
        assert!(validate_email(Some("nope")).is_err());
        assert!(validate_email(Some("a@bcd")).is_err()); // no dot
        assert!(validate_email(Some("a.bcd")).is_err()); // no @
        assert!(validate_email(Some("a@b.")).is_err()); // len 4 < 5
    }

    #[test]
    fn phone_none_empty_and_valid_are_ok() {
        assert!(validate_thai_phone(None, "phone").is_ok());
        assert!(validate_thai_phone(Some(""), "phone").is_ok());
        assert!(validate_thai_phone(Some("0812345678"), "phone").is_ok());
        assert!(validate_thai_phone(Some("08-1234-5678"), "phone").is_ok()); // separators ignored
    }

    #[test]
    fn phone_wrong_shape_is_rejected() {
        assert!(validate_thai_phone(Some("12345"), "phone").is_err()); // too short
        assert!(validate_thai_phone(Some("8123456789"), "phone").is_err()); // no leading 0
    }

    /// Two 13-digit ids whose check digit was computed BY HAND (see the fn doc comment) and only
    /// then confirmed against the implementation — so the tests are not just echoing the code.
    ///
    /// Both are deliberately a VISIBLE `0123456789…` / `1234567890…` keyboard run, and any future
    /// fixture here must be too. A 13-digit number that satisfies mod-11 *and* opens with a real
    /// province/district registration prefix is indistinguishable from a living person's
    /// เลขประจำตัวประชาชน — committing one would put a stranger's PII in git history permanently, in
    /// the very repo whose job is to handle these numbers correctly (PDPA), and on the code path
    /// where a 13-digit id is the PromptPay destination money is sent to. Never make a fixture
    /// "look realistic"; it must be wrong at a glance.
    ///
    /// `VALID_NATIONAL_ID_2` digit × weight, so the next reader can check it without running
    /// anything:
    ///   1×13 + 2×12 + 3×11 + 4×10 + 5×9 + 6×8 + 7×7 + 8×6 + 9×5 + 0×4 + 1×3 + 2×2
    /// = 13 + 24 + 33 + 40 + 45 + 48 + 49 + 48 + 45 + 0 + 3 + 4 = **352**
    /// 352 mod 11 = 0 → check = (11 − 0) mod 10 = **1** = the 13th digit ✓
    const VALID_NATIONAL_ID: &str = "0123456789016"; // sum 302 → (11−5)%10 = 6 ✓
    const VALID_NATIONAL_ID_2: &str = "1234567890121"; // sum 352 → (11−0)%10 = 1 ✓

    /// A SHAPE-perfect 13-digit id whose mod-11 check digit is WRONG — the exact value that must
    /// split the two rules apart. `0123456789016` is valid, so `…015` cannot be.
    const CHECKSUM_INVALID_13: &str = "0123456789015";

    #[test]
    fn tax_id_none_empty_and_valid_are_ok() {
        assert!(validate_tax_id(None).is_ok());
        assert!(validate_tax_id(Some("  ")).is_ok());
        assert!(validate_tax_id(Some(VALID_NATIONAL_ID)).is_ok()); // 13-digit Thai national id
        assert!(validate_tax_id(Some(VALID_NATIONAL_ID_2)).is_ok());
        assert!(validate_tax_id(Some("0-1234-56789-01-6")).is_ok()); // separators allowed
        assert!(validate_tax_id(Some("0 1234 56789 01 6")).is_ok()); // spaces too
        assert!(validate_tax_id(Some("12345678")).is_ok()); // 8 digits (lower bound)
    }

    #[test]
    fn tax_id_wrong_shape_is_rejected() {
        assert!(validate_tax_id(Some("1234567")).is_err()); // 7 digits — too short
        assert!(validate_tax_id(Some("12AB5678")).is_err()); // letters
        assert!(validate_tax_id(Some(&"1".repeat(MAX_TAX_ID_LEN + 1))).is_err()); // too long
        assert!(validate_tax_id(Some("123456789012345678901")).is_err()); // 21 digits
    }

    #[test]
    fn guard_tax_id_13_digits_must_pass_the_national_id_checksum() {
        // A 13-digit GUARD tax_id is the PromptPay NAT proxy money is SENT to, so a single
        // mistyped digit must not survive: it would otherwise pay a stranger AND mark the booking
        // paid. Transposition of two ADJACENT digits (the classic keying error): 0,1 → 1,0.
        assert!(validate_guard_tax_id(Some("1023456789016")).is_err());
        // One digit changed (…89016 → …88016).
        assert!(validate_guard_tax_id(Some("0123456788016")).is_err());
        // A wrong check digit on an otherwise-correct prefix.
        assert!(validate_guard_tax_id(Some(CHECKSUM_INVALID_13)).is_err());
        // …including via the separator form, since the check runs on the digits-only value.
        assert!(validate_guard_tax_id(Some("1-0234-56789-01-6")).is_err());
        // The error must be the Thai "mistyped" copy, not the generic shape message, and it must
        // carry the PromptPay wording — that wording is what makes it actionable HERE, and is the
        // reason it must never be shown on the company screen.
        let msg = validate_guard_tax_id(Some("1023456789016")).unwrap_err();
        assert!(
            msg.contains("เลขประจำตัวประชาชน") && msg.contains("พร้อมเพย์"),
            "Thai PromptPay copy expected: {msg}"
        );
    }

    #[test]
    fn org_tax_id_does_not_apply_the_citizen_checksum() {
        // THE SPLIT (F9). A company TIN is a juristic-person number: the citizen mod-11 rule has no
        // authority over it, and enforcing it would brick `PUT /admin/org-settings` for any install
        // whose stored value fails — which is itself a payout blocker (the export 400s with no
        // company tax id). The SAME value must be accepted here and rejected on the guard paths.
        assert!(validate_tax_id(Some(CHECKSUM_INVALID_13)).is_ok());
        assert!(validate_tax_id(Some("1023456789016")).is_ok());
        assert!(validate_guard_tax_id(Some(CHECKSUM_INVALID_13)).is_err());
        assert!(validate_guard_tax_id(Some("1023456789016")).is_err());
    }

    #[test]
    fn valid_national_id_passes_on_every_path() {
        // The split must not make a genuinely valid id path-dependent.
        for id in [VALID_NATIONAL_ID, VALID_NATIONAL_ID_2, "0-1234-56789-01-6"] {
            assert!(validate_tax_id(Some(id)).is_ok(), "org path: {id}");
            assert!(validate_guard_tax_id(Some(id)).is_ok(), "guard path: {id}");
        }
    }

    #[test]
    fn non_13_digit_tax_ids_are_identical_on_both_paths() {
        // 8–12 and 14–20 digits are never a `NAT` PromptPay proxy (the toolkit stamps them `TAX`),
        // so the checksum must not apply on EITHER path — these all fail the mod-11 rule yet must
        // still be accepted, and the shape rejects must stay identical too.
        for ok in [
            "12345678",             // 8 (lower bound)
            "012345678901",         // 12
            "01234567890123",       // 14
            "12345678901234567890", // 20 (upper bound)
        ] {
            assert!(validate_tax_id(Some(ok)).is_ok(), "org path: {ok}");
            assert!(validate_guard_tax_id(Some(ok)).is_ok(), "guard path: {ok}");
        }
        for bad in ["1234567", "12AB5678", "123456789012345678901"] {
            assert!(validate_tax_id(Some(bad)).is_err(), "org path: {bad}");
            assert!(
                validate_guard_tax_id(Some(bad)).is_err(),
                "guard path: {bad}"
            );
        }
    }

    #[test]
    fn guard_tax_id_none_and_empty_are_ok() {
        // Optional on the guard path too (multi-step onboarding / an admin correcting only bank
        // fields) — the strict wrapper must not turn "not filled in yet" into a 400.
        assert!(validate_guard_tax_id(None).is_ok());
        assert!(validate_guard_tax_id(Some("")).is_ok());
        assert!(validate_guard_tax_id(Some("  ")).is_ok());
    }

    #[test]
    fn national_id_check_digit_matches_hand_computation() {
        assert!(thai_national_id_check_digit_ok(VALID_NATIONAL_ID));
        assert!(thai_national_id_check_digit_ok(VALID_NATIONAL_ID_2));
        // Every wrong check digit for the same 12-digit prefix must fail (only 6 is right).
        for d in 0..10u32 {
            let candidate = format!("012345678901{d}");
            assert_eq!(
                thai_national_id_check_digit_ok(&candidate),
                d == 6,
                "candidate {candidate}"
            );
        }
        // Wrong length / non-digit input is `false`, never a panic (request path).
        assert!(!thai_national_id_check_digit_ok(""));
        assert!(!thai_national_id_check_digit_ok("012345678901")); // 12
        assert!(!thai_national_id_check_digit_ok("01234567890166")); // 14
        assert!(!thai_national_id_check_digit_ok("012345678901X"));
        assert!(!thai_national_id_check_digit_ok("กขคงจฉชซฌญฎฏฐ")); // multi-byte, 13 chars
    }

    const KINDS: &[&str] = &["problem", "feedback"];

    #[test]
    fn ticket_kind_allowed_values_pass() {
        assert!(validate_ticket_kind("problem", KINDS).is_ok());
        assert!(validate_ticket_kind("feedback", KINDS).is_ok());
    }

    #[test]
    fn ticket_kind_unknown_or_empty_is_rejected() {
        assert!(validate_ticket_kind("", KINDS).is_err());
        assert!(validate_ticket_kind("bug", KINDS).is_err());
        assert!(validate_ticket_kind("Problem", KINDS).is_err()); // case-sensitive
    }

    #[test]
    fn ticket_message_valid_lengths_pass() {
        assert!(validate_ticket_message("แอปค้าง", 2000).is_ok());
        let at_limit = "a".repeat(2000);
        assert!(validate_ticket_message(&at_limit, 2000).is_ok());
    }

    #[test]
    fn ticket_message_empty_or_over_limit_is_rejected() {
        assert!(validate_ticket_message("", 2000).is_err());
        assert!(validate_ticket_message("   ", 2000).is_err()); // whitespace-only
        let over = "a".repeat(2001);
        assert!(validate_ticket_message(&over, 2000).is_err());
    }

    #[test]
    fn ticket_message_counts_chars_not_bytes() {
        // 3 multi-byte Thai chars must NOT trip a max of 3 (would fail if counting bytes).
        assert!(validate_ticket_message("กขค", 3).is_ok());
    }
}
