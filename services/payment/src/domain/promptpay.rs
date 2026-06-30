//! PURE PromptPay / EMVCo QR payload generation — no DB/HTTP/NATS (100% unit-testable; the only
//! shared import is the error TYPE). THE MONEY PATH (the customer scans this to transfer to US).
//!
//! This is the ONE authoritative place the PromptPay QR string is built (CLAUDE.md "one place,
//! authoritative"). The mobile app renders the QR from `qr_payload` returned by
//! `GET /payments/{id}/promptpay`; it does NOT compose its own payload, so the amount + receiver
//! can never drift from the server-side estimate.
//!
//! It is a standard EMVCo "Merchant-Presented" QR (the Thai PromptPay "Tag 30 — Bill Payment" /
//! "Tag 29 — Credit Transfer" profile defined by the Thai Bankers' Association):
//!  - `00` Payload Format Indicator = `01`
//!  - `01` Point of Initiation Method = `11` static / `12` dynamic. We embed an amount, so `12`.
//!  - `29` Merchant Account Information (PromptPay) — sub-TLVs:
//!      - `00` AID = `A000000677010111` (the PromptPay application id)
//!      - `01` proxy = a MOBILE number (`0066` + the 9-digit national number, the leading 0 dropped)
//!      - `02` proxy = a CITIZEN ID / tax id (13 digits)
//!
//!    Exactly ONE of `01`/`02` is present, chosen from the configured `RECEIVING_ACCOUNT`.
//!  - `53` Transaction Currency = `764` (THB, ISO 4217 numeric)
//!  - `54` Transaction Amount = the estimate, e.g. `2000.00` (2 dp, plain string, no separators)
//!  - `58` Country Code = `TH`
//!  - `63` CRC-16/CCITT-FALSE over the whole string INCLUDING the `6304` tag+length prefix.
//!
//! Each field is `ID(2) || LEN(2, zero-padded) || VALUE`. The CRC is appended last.

use rust_decimal::Decimal;
use shared::error::AppError;

/// The PromptPay application id (the value of merchant-account sub-tag `00`). Fixed by the Thai
/// Bankers' Association — every PromptPay QR carries this.
pub const PROMPTPAY_AID: &str = "A000000677010111";

/// What kind of PromptPay proxy the configured `RECEIVING_ACCOUNT` is. PromptPay can be addressed
/// by a mobile number OR a national/tax id; the two go in DIFFERENT sub-tags and are formatted
/// differently, so we classify the configured account once and reject anything that is neither
/// (a bank account number is NOT PromptPay-addressable — the QR cannot be built for it).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PromptPayProxy {
    /// A Thai mobile number (10 digits, leading `0`). Goes in sub-tag `01` as `0066` + the last 9.
    Mobile,
    /// A 13-digit national id / tax id. Goes in sub-tag `02` verbatim.
    NationalId,
}

/// Classify the configured receiving account as a PromptPay proxy. Digits only are considered
/// (spaces/dashes are stripped defensively, though `RECEIVING_ACCOUNT` is documented as digits-
/// only). A 10-digit value starting `0` → mobile; a 13-digit value → national/tax id; anything
/// else is NOT PromptPay-addressable → `None` (the handler returns a typed config error). Pure.
pub fn classify_proxy(receiving_account: &str) -> Option<PromptPayProxy> {
    let digits: String = receiving_account
        .chars()
        .filter(|c| c.is_ascii_digit())
        .collect();
    match digits.len() {
        10 if digits.starts_with('0') => Some(PromptPayProxy::Mobile),
        13 => Some(PromptPayProxy::NationalId),
        _ => None,
    }
}

/// Format the configured account as the EMVCo proxy VALUE for its sub-tag:
///  - Mobile `0812345678` → `0066` + `812345678` = `0066812345678` (the domestic leading `0` is
///    dropped, the international `66` prefix is zero-padded to `0066`).
///  - National id `1234567890123` → itself (13 digits, unchanged).
///
/// Returns `None` for anything `classify_proxy` rejects.
fn proxy_value(receiving_account: &str) -> Option<(PromptPayProxy, String)> {
    let digits: String = receiving_account
        .chars()
        .filter(|c| c.is_ascii_digit())
        .collect();
    match classify_proxy(&digits)? {
        PromptPayProxy::Mobile => {
            // Drop the domestic leading 0, prepend the zero-padded country code 66 → `0066` + 9.
            let national = &digits[1..];
            Some((PromptPayProxy::Mobile, format!("0066{national}")))
        }
        PromptPayProxy::NationalId => Some((PromptPayProxy::NationalId, digits)),
    }
}

/// Build one EMVCo TLV field: `ID(2) || LEN(2) || VALUE`, with the length zero-padded to 2 digits.
/// Internal helper — IDs/values here are all ASCII and short (< 100 chars), matching the spec.
fn tlv(id: &str, value: &str) -> String {
    format!("{id}{:02}{value}", value.len())
}

/// Compute the EMVCo CRC: CRC-16/CCITT-FALSE (poly `0x1021`, init `0xFFFF`, no reflection, no final
/// xor) over the ASCII bytes, rendered as 4 uppercase hex digits. The CRC is computed over the
/// payload INCLUDING the trailing `6304` (tag `63`, length `04`) per the EMVCo spec. Pure.
fn crc16_ccitt(data: &[u8]) -> u16 {
    let mut crc: u16 = 0xFFFF;
    for &byte in data {
        crc ^= (byte as u16) << 8;
        for _ in 0..8 {
            if crc & 0x8000 != 0 {
                crc = (crc << 1) ^ 0x1021;
            } else {
                crc <<= 1;
            }
        }
    }
    crc
}

/// Build the authoritative EMVCo PromptPay QR payload string for a transfer to OUR
/// `receiving_account` for exactly `amount` THB.
///
/// `amount` is the SERVER-side estimate (`rust_decimal::Decimal`) — formatted to a plain 2-dp
/// string (`2000.00`, no thousands separators) for tag `54`. Returns a typed `BadRequest` if
/// `receiving_account` is not a PromptPay-addressable proxy (a phone or a national/tax id) — a bank
/// account number cannot be encoded as a PromptPay QR (the caller surfaces this as a config error).
///
/// The result is a complete, scannable payload; the mobile renders it as a QR with any QR library.
pub fn build_promptpay_payload(
    receiving_account: &str,
    amount: Decimal,
) -> Result<String, AppError> {
    let (proxy_kind, proxy) = proxy_value(receiving_account).ok_or_else(|| {
        AppError::Internal(
            "RECEIVING_ACCOUNT is not a PromptPay proxy (need a phone or national/tax id)"
                .to_string(),
        )
    })?;

    // 29 — Merchant Account Information (PromptPay): AID + exactly one proxy sub-tag.
    let proxy_sub_id = match proxy_kind {
        PromptPayProxy::Mobile => "01",
        PromptPayProxy::NationalId => "02",
    };
    let merchant_info = format!("{}{}", tlv("00", PROMPTPAY_AID), tlv(proxy_sub_id, &proxy));

    // Amount → a plain 2-dp string (matches the NUMERIC(12,2) money scale; no separators).
    let amount_str = format!("{:.2}", amount.round_dp(2));

    // Assemble all fields up to (and including) the `6304` CRC prefix, then append the CRC.
    let mut payload = String::new();
    payload.push_str(&tlv("00", "01")); // Payload Format Indicator
    payload.push_str(&tlv("01", "12")); // Point of Initiation — dynamic (amount embedded)
    payload.push_str(&tlv("29", &merchant_info)); // Merchant Account Information (PromptPay)
    payload.push_str(&tlv("53", "764")); // Currency THB
    payload.push_str(&tlv("54", &amount_str)); // Amount
    payload.push_str(&tlv("58", "TH")); // Country
    payload.push_str("6304"); // CRC tag + length, INCLUDED in the CRC input.

    let crc = crc16_ccitt(payload.as_bytes());
    payload.push_str(&format!("{crc:04X}"));
    Ok(payload)
}

/// Format the receiving account for human DISPLAY on the payment screen (NOT the QR — that is the
/// `qr_payload`). A mobile is grouped `0XX-XXX-XXXX`; a national id is grouped `X-XXXX-XXXXX-XX-X`;
/// anything else is returned digits-only as a fallback. Pure (display only; never parsed back).
pub fn format_account_for_display(receiving_account: &str) -> String {
    let digits: String = receiving_account
        .chars()
        .filter(|c| c.is_ascii_digit())
        .collect();
    match classify_proxy(&digits) {
        Some(PromptPayProxy::Mobile) => {
            format!("{}-{}-{}", &digits[0..3], &digits[3..6], &digits[6..10])
        }
        Some(PromptPayProxy::NationalId) => format!(
            "{}-{}-{}-{}-{}",
            &digits[0..1],
            &digits[1..5],
            &digits[5..10],
            &digits[10..12],
            &digits[12..13],
        ),
        None => digits,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dec(s: &str) -> Decimal {
        s.parse().unwrap()
    }

    #[test]
    fn classify_distinguishes_mobile_national_and_rejects_bank() {
        assert_eq!(classify_proxy("0812345678"), Some(PromptPayProxy::Mobile));
        assert_eq!(
            classify_proxy("1234567890123"),
            Some(PromptPayProxy::NationalId)
        );
        // A typical 10-digit bank account NOT starting with 0 → not a mobile, not 13 → rejected.
        assert_eq!(classify_proxy("1234567890"), None);
        // Too short / too long / empty → rejected.
        assert_eq!(classify_proxy("08123"), None);
        assert_eq!(classify_proxy(""), None);
    }

    #[test]
    fn mobile_proxy_value_drops_leading_zero_and_prepends_0066() {
        let (kind, v) = proxy_value("0812345678").unwrap();
        assert_eq!(kind, PromptPayProxy::Mobile);
        assert_eq!(v, "0066812345678");
    }

    #[test]
    fn national_id_proxy_value_is_verbatim() {
        let (kind, v) = proxy_value("1234567890123").unwrap();
        assert_eq!(kind, PromptPayProxy::NationalId);
        assert_eq!(v, "1234567890123");
    }

    #[test]
    fn tlv_zero_pads_length() {
        assert_eq!(tlv("00", "01"), "000201");
        assert_eq!(tlv("54", "2000.00"), "54072000.00");
    }

    #[test]
    fn crc16_matches_ccitt_false_check_value() {
        // The universal CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) check value: the ASCII
        // string "123456789" MUST hash to 0x29B1. Pins the exact CRC variant EMVCo/PromptPay
        // require (a wrong poly/init/reflection would fail here).
        assert_eq!(crc16_ccitt(b"123456789"), 0x29B1);
    }

    #[test]
    fn payload_round_trip_has_all_required_fields_and_valid_crc() {
        let payload = build_promptpay_payload("0812345678", dec("2000.00")).unwrap();
        // Format indicator + dynamic POI.
        assert!(payload.starts_with("000201010212"), "format + POI");
        // PromptPay AID present.
        assert!(payload.contains(PROMPTPAY_AID), "AID");
        // Mobile proxy sub-tag 01 with the 0066-prefixed value.
        assert!(payload.contains("0066812345678"), "mobile proxy value");
        // Currency THB + country TH.
        assert!(payload.contains("5303764"), "currency 764");
        assert!(payload.contains("5802TH"), "country TH");
        // Amount tag 54, length 07, value 2000.00.
        assert!(payload.contains("54072000.00"), "amount field");
        // CRC tag + 4 hex digits at the very end; the CRC must verify.
        assert!(payload.len() > 8);
        let (body, crc_hex) = payload.split_at(payload.len() - 4);
        assert!(body.ends_with("6304"), "CRC tag prefix");
        let expected = crc16_ccitt(body.as_bytes());
        assert_eq!(
            format!("{expected:04X}"),
            crc_hex,
            "the appended CRC must validate over the body incl. 6304"
        );
    }

    #[test]
    fn national_id_payload_uses_sub_tag_02() {
        let payload = build_promptpay_payload("1234567890123", dec("500.00")).unwrap();
        assert!(payload.contains(PROMPTPAY_AID));
        // Merchant info sub-tag 02 (national id), length 13, verbatim value.
        assert!(
            payload.contains("02131234567890123"),
            "national-id sub-tag 02"
        );
        // Amount tag 54, length 06, value 500.00.
        assert!(payload.contains("5406500.00"), "amount 500.00");
    }

    #[test]
    fn amount_is_two_dp_no_separators() {
        // A whole-thousand amount must render `12000.00`, never `12,000` or `12000`.
        let payload = build_promptpay_payload("0812345678", dec("12000")).unwrap();
        assert!(
            payload.contains("540812000.00"),
            "2dp, no thousands separator"
        );
        // A 3-dp estimate is rounded to 2dp for the wire (matches NUMERIC(12,2)).
        let p2 = build_promptpay_payload("0812345678", dec("99.999")).unwrap();
        assert!(p2.contains("5406100.00"), "rounded to 2dp");
    }

    #[test]
    fn rejects_non_promptpay_account() {
        // A 10-digit bank account (not starting 0) is not PromptPay-addressable → typed error.
        let err = build_promptpay_payload("1234567890", dec("100.00")).unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
    }

    #[test]
    fn display_groups_mobile_and_national_id() {
        assert_eq!(format_account_for_display("0812345678"), "081-234-5678");
        assert_eq!(
            format_account_for_display("1234567890123"),
            "1-2345-67890-12-3"
        );
        // A non-proxy falls back to digits-only (no panic on odd lengths).
        assert_eq!(format_account_for_display("12-34"), "1234");
    }
}
