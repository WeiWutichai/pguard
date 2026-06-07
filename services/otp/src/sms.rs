//! INET SMS adapter — Cheese Digital Network CSGAPI gateway.
//!
//! Ported faithfully from v1 (`../guard-dispatch/services/shared/src/sms.rs`),
//! re-implemented behind an [`SmsSender`] port (mirroring notification's `fcm::Pusher`)
//! so the API/domain layers stay transport-agnostic and the gateway can be swapped for a
//! [`NoopSender`] in dev via `SMS_DISABLED`. `domain` never imports this module.
//!
//! API: GET https://bulksms.cheesemobile.com/v2/
//! Params: username, passwd, from, to, text, datacoding=U, resultmode=xml

use async_trait::async_trait;

use shared::error::AppError;

/// Configuration for the INET SMS Gateway (Cheese Digital Network CSGAPI).
#[derive(Debug, Clone)]
pub struct InetConfig {
    pub username: String,
    pub password: String,
    pub sender: String,
    pub url: String,
}

impl InetConfig {
    /// Load SMS config from environment. **Fail-fast** on missing/empty
    /// `INET_SMS_USERNAME`/`INET_SMS_PASSWORD` (callers gate this behind `SMS_DISABLED`
    /// for dev, exactly like notification's `FCM_DISABLED`).
    pub fn from_env() -> Result<Self, AppError> {
        let username = std::env::var("INET_SMS_USERNAME").map_err(|_| {
            AppError::Internal(
                "Missing env var: INET_SMS_USERNAME (set SMS_DISABLED=1 for dev without SMS)"
                    .to_string(),
            )
        })?;
        let password = std::env::var("INET_SMS_PASSWORD").map_err(|_| {
            AppError::Internal(
                "Missing env var: INET_SMS_PASSWORD (set SMS_DISABLED=1 for dev without SMS)"
                    .to_string(),
            )
        })?;
        let sender = std::env::var("INET_SMS_SENDER").unwrap_or_else(|_| "GuardApp".to_string());
        let url = std::env::var("INET_SMS_URL")
            .unwrap_or_else(|_| "https://bulksms.cheesemobile.com/v2/".to_string());

        if username.is_empty() {
            return Err(AppError::Internal(
                "INET_SMS_USERNAME must not be empty".to_string(),
            ));
        }
        if password.is_empty() {
            return Err(AppError::Internal(
                "INET_SMS_PASSWORD must not be empty".to_string(),
            ));
        }

        Ok(Self {
            username,
            password,
            sender,
            url,
        })
    }
}

/// Port: deliver one SMS. Implemented by [`InetSender`] (real CSGAPI) and [`NoopSender`]
/// (dev/tests, selected when `SMS_DISABLED` is set).
#[async_trait]
pub trait SmsSender: Send + Sync {
    /// Send `text` to `to` (E.164-ish digits). Returns the gateway transaction id.
    async fn send(&self, to: &str, text: &str) -> Result<String, AppError>;
}

/// Dev/test sender — logs and succeeds without contacting the gateway. Selected when
/// `SMS_DISABLED` is truthy (see [`sms_disabled`]). Never logs the OTP body (PII / code leakage).
pub struct NoopSender;

#[async_trait]
impl SmsSender for NoopSender {
    async fn send(&self, to: &str, _text: &str) -> Result<String, AppError> {
        tracing::info!(to = %mask_phone(to), "noop SMS (SMS_DISABLED)");
        Ok("noop".to_string())
    }
}

/// otp's SMS-gating policy: real SMS is disabled ONLY when `SMS_DISABLED` carries a
/// truthy value (`true`/`1`/`yes`/`on`, case-insensitive). `false`/`0`/empty/unset keep
/// real SMS ENABLED. Pass `std::env::var("SMS_DISABLED").ok().as_deref()`.
///
/// Fixes the v1 footgun where presence-based `std::env::var("SMS_DISABLED").is_ok()`
/// treated *any* value — including `"false"` — as "disable", silently dropping real SMS.
pub fn sms_disabled(raw: Option<&str>) -> bool {
    shared::config::parse_env_bool(raw)
}

/// Real INET CSGAPI sender. Holds the gateway config + a shared `reqwest::Client`
/// (connection reuse). The `text` is encoded as TIS-620 / UCS-2 per the gateway quirk.
pub struct InetSender {
    config: InetConfig,
    http: reqwest::Client,
}

impl InetSender {
    pub fn new(config: InetConfig, http: reqwest::Client) -> Self {
        Self { config, http }
    }
}

#[async_trait]
impl SmsSender for InetSender {
    #[tracing::instrument(skip(self, text), fields(to = %mask_phone(to)))]
    async fn send(&self, to: &str, text: &str) -> Result<String, AppError> {
        // Build the URL manually — text is encoded as TIS-620, other params are
        // ASCII-safe. reqwest's `.query()` would send UTF-8, which the gateway
        // misinterprets as TIS-620 (garbled output).
        let url = format!(
            "{}?username={}&passwd={}&from={}&to={}&text={}&datacoding=U&resultmode=xml",
            self.config.url,
            url_encode_bytes(self.config.username.as_bytes()),
            url_encode_bytes(self.config.password.as_bytes()),
            url_encode_bytes(self.config.sender.as_bytes()),
            url_encode_bytes(to.as_bytes()),
            text_to_sms_url(text),
        );

        let response = self
            .http
            .get(&url)
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("SMS gateway request failed: {e}")))?;

        let status_code = response.status();
        let body = response
            .text()
            .await
            .map_err(|e| AppError::Internal(format!("Failed to read SMS gateway response: {e}")))?;

        if !status_code.is_success() {
            tracing::error!("SMS gateway HTTP error: status={status_code}");
            return Err(AppError::Internal(
                "SMS gateway returned an error".to_string(),
            ));
        }

        let parsed = parse_inet_xml_response(&body);

        if parsed.status == "00" {
            let tran_id = parsed.tran_id.unwrap_or_default();
            tracing::info!("SMS sent successfully: tran_id={tran_id}");
            Ok(tran_id)
        } else {
            let error_desc = inet_error_description(&parsed.status);
            tracing::error!(
                "SMS gateway error: code={}, detail={}, desc={}",
                parsed.status,
                parsed.detail,
                error_desc
            );
            // Generic outward error — never leak gateway internals to the OTP caller.
            Err(AppError::Internal("Failed to send SMS".to_string()))
        }
    }
}

/// INET CSGAPI XML response fields.
#[derive(Debug)]
struct SmsResponse {
    status: String,
    detail: String,
    tran_id: Option<String>,
}

/// Mask a phone number for logs: keep the last 4 digits only (PDPA — no full phone in
/// logs). e.g. `66812345678` → `*******5678`.
fn mask_phone(phone: &str) -> String {
    let n = phone.len();
    if n <= 4 {
        return "*".repeat(n);
    }
    let mut out = "*".repeat(n - 4);
    out.push_str(&phone[n - 4..]);
    out
}

/// Percent-encode raw bytes for a URL query-parameter value.
fn url_encode_bytes(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 3);
    for &b in bytes {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~') {
            out.push(b as char);
        } else if b == b' ' {
            out.push_str("%20");
        } else {
            use std::fmt::Write;
            let _ = write!(out, "%{b:02X}");
        }
    }
    out
}

/// Encode text for the INET SMS gateway's UCS-2 output.
///
/// The gateway generates UCS-2 SMS (2 bytes per char) but has a quirk:
///   - **High bytes** (≥0x80): treated as TIS-620 → correctly expanded to 2-byte UCS-2
///   - **Low bytes** (<0x80): passed through as-is (1 byte) → causes UCS-2 misalignment
///
/// Fix: Thai chars → TIS-620 single byte (gateway expands to 2-byte UCS-2).
///      ASCII chars → prepend 0x00 so gateway passes both bytes through, forming a
///      correct UCS-2 pair (e.g., "O" → 00 4F → U+004F).
fn text_to_sms_url(text: &str) -> String {
    let mut bytes = Vec::with_capacity(text.len() * 2);
    for ch in text.chars() {
        let cp = ch as u32;
        if cp < 0x80 {
            // ASCII: prepend 0x00 to form correct UCS-2 pair in SMS PDU.
            bytes.push(0x00);
            bytes.push(cp as u8);
        } else if (0x0E01..=0x0E3A).contains(&cp) || cp == 0x0E3F || (0x0E40..=0x0E5B).contains(&cp)
        {
            // Thai: TIS-620 single byte (gateway correctly expands to 2-byte UCS-2).
            bytes.push((cp - 0x0D60) as u8);
        } else {
            bytes.push(0x00);
            bytes.push(b'?');
        }
    }
    url_encode_bytes(&bytes)
}

/// Parse INET CSGAPI XML response (simple tag extraction — no XML crate needed).
fn parse_inet_xml_response(xml: &str) -> SmsResponse {
    SmsResponse {
        status: extract_xml_tag(xml, "status").unwrap_or_default(),
        detail: extract_xml_tag(xml, "detail").unwrap_or_default(),
        tran_id: extract_xml_tag(xml, "tranid"),
    }
}

/// Extract text content from a simple XML tag: `<tag>content</tag>`.
fn extract_xml_tag(xml: &str, tag: &str) -> Option<String> {
    let open = format!("<{tag}>");
    let close = format!("</{tag}>");
    let start = xml.find(&open)? + open.len();
    let end = xml[start..].find(&close)? + start;
    Some(xml[start..end].to_string())
}

/// Map INET error codes to human-readable descriptions (server-side logging only).
fn inet_error_description(code: &str) -> &'static str {
    match code {
        "00" => "Accepted",
        "01" => "No Such User",
        "02" => "Password is wrong",
        "03" => "No parameters list found",
        "04" => "Method is wrong",
        "05" => "Internal Server Error",
        "06" => "Phone Number is wrong",
        "07" => "SMS parameter missing",
        "08" => "Insufficient SMS Credits",
        "09" => "User is expire",
        "10" => "Transaction ID invalid",
        "11" => "Text length overflow",
        "12" => "DateTime is wrong",
        "13" => "User is disable",
        "14" => "Invalid SenderName",
        "15" => "Text not match Datacoding",
        "16" => "Invalid Datacoding",
        "17" => "Text is empty",
        "18" => "Parameter is empty",
        "19" => "URL invalid format",
        "20" => "Wappush name invalid format",
        "99" => "Permission denied",
        _ => "Unknown error",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_xml_success_response() {
        let xml = r#"<?xml version="1.0" encoding="UTF8"?><xml><response><status>00</status><detail>Accepted</detail><tranid>CM.108.1350356789.51730500</tranid></response><data/></xml>"#;
        let result = parse_inet_xml_response(xml);
        assert_eq!(result.status, "00");
        assert_eq!(result.detail, "Accepted");
        assert_eq!(
            result.tran_id,
            Some("CM.108.1350356789.51730500".to_string())
        );
    }

    #[test]
    fn parse_xml_error_response() {
        let xml = r#"<?xml version="1.0"?><xml><response><status>06</status><detail>Phone Number is wrong</detail></response></xml>"#;
        let result = parse_inet_xml_response(xml);
        assert_eq!(result.status, "06");
        assert_eq!(result.detail, "Phone Number is wrong");
        assert!(result.tran_id.is_none());
    }

    #[test]
    fn extract_xml_tag_finds_content() {
        let xml = "<root><name>hello</name></root>";
        assert_eq!(extract_xml_tag(xml, "name"), Some("hello".to_string()));
    }

    #[test]
    fn extract_xml_tag_returns_none_for_missing() {
        let xml = "<root><name>hello</name></root>";
        assert_eq!(extract_xml_tag(xml, "missing"), None);
    }

    #[test]
    fn text_to_sms_url_thai_chars() {
        // Thai-only: ร=0xC3, ห=0xCB, ั=0xD1, ส=0xCA (TIS-620, no 0x00 prefix).
        assert_eq!(text_to_sms_url("รหัส"), "%C3%CB%D1%CA");
    }

    #[test]
    fn text_to_sms_url_ascii() {
        // ASCII: each char gets a 0x00 prefix → %00 + char.
        assert_eq!(text_to_sms_url("O"), "%00O");
        assert_eq!(text_to_sms_url("OTP"), "%00O%00T%00P");
        assert_eq!(text_to_sms_url("123"), "%001%002%003");
    }

    #[test]
    fn text_to_sms_url_mixed() {
        let encoded = text_to_sms_url("OTP: 123");
        assert!(encoded.starts_with("%00O%00T%00P"));
        assert!(encoded.contains("%001%002%003"));
    }

    #[test]
    fn text_to_sms_url_full_otp_message() {
        let msg = "รหัส OTP: 123456 หมดอายุใน 5 นาที";
        let encoded = text_to_sms_url(msg);
        assert!(encoded.starts_with("%C3%CB%D1%CA"));
        assert!(encoded.contains("%00O%00T%00P"));
        assert!(encoded.contains("%001%002%003%004%005%006"));
    }

    #[test]
    fn inet_error_codes_mapped() {
        assert_eq!(inet_error_description("00"), "Accepted");
        assert_eq!(inet_error_description("06"), "Phone Number is wrong");
        assert_eq!(inet_error_description("08"), "Insufficient SMS Credits");
        assert_eq!(inet_error_description("99"), "Permission denied");
        assert_eq!(inet_error_description("ZZ"), "Unknown error");
    }

    #[test]
    fn mask_phone_keeps_last_four() {
        assert_eq!(mask_phone("66812345678"), "*******5678");
        assert_eq!(mask_phone("1234"), "****");
        assert_eq!(mask_phone("12"), "**");
    }

    // ----- SMS_DISABLED is value-aware (the v1 footgun fix) -----

    #[test]
    fn sms_disabled_only_for_truthy_values() {
        // Disabled (NoopSender) only when explicitly truthy.
        assert!(sms_disabled(Some("true")));
        assert!(sms_disabled(Some("True")));
        assert!(sms_disabled(Some("1")));
        assert!(sms_disabled(Some("yes")));
    }

    #[test]
    fn sms_disabled_false_keeps_real_sms() {
        // The crux: "false"/"0"/empty must NOT disable real SMS (v1's `.is_ok()` got this wrong).
        assert!(!sms_disabled(Some("false")));
        assert!(!sms_disabled(Some("0")));
        assert!(!sms_disabled(Some("")));
    }

    #[test]
    fn sms_disabled_unset_keeps_real_sms() {
        assert!(!sms_disabled(None));
    }
}
