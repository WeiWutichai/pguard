//! Slip2Go client — the EXTERNAL slip-verification adapter for the REAL money path. THE MONEY PATH.
//!
//! Slip2Go (`connect.slip2go.com`, API v1.2) verifies that a Thai PromptPay/bank-transfer SLIP is
//! genuine and returns the amount / sender / receiver / refs. It is NOT a card gateway — the money
//! lands in OUR own account; Slip2Go only confirms the transfer happened (anti-fraud). The customer
//! transfers to our PromptPay/bank account, then uploads the slip image; we POST it here.
//!
//! A trait ([`SlipVerifier`]) decouples the handler from `reqwest` so the slip endpoint's verify +
//! re-validation + dedupe logic is unit-testable with a stub (NO real API calls in tests) — mirrors
//! the `BookingReader` pattern in `booking_client.rs`.
//!
//! Endpoints (v1.2, resolved from the official docs):
//!  - `POST /verify-slip/qr-image/info` — multipart: `file` (slip image) + `payload` (JSON
//!    conditions). The server decodes the QR from the image. ← USED here (the customer just picks
//!    the slip photo). CONSUMES quota.
//!  - `GET /verify-slip/{referenceId}` — FREE re-read (no quota) of a previously verified slip; for
//!    an idempotent re-confirm.
//!
//! Auth: `Authorization: Bearer {apiSecret}` (config `SLIP2GO_API_SECRET`). The service starts
//! WITHOUT the secret (so the simulated path is unaffected); the slip path requires it and fails
//! gracefully when absent (a typed config error) — see [`HttpSlipVerifier::verify`].
//!
//! Response envelope `{ code, message, data }`: per the Slip2Go docs' "Success Code" table,
//! TWO codes carry a verified slip — `200000` "Slip found" (no/before conditions) and `200200`
//! "Slip is Valid" (the slip ALSO matched every `checkCondition` we sent, e.g. `checkReceiver`;
//! same `data` shape as Slip found). Any other code is a FAIL whose `message` is surfaced
//! (`200401` receiver mismatch, `200404` not found, `200501` duplicate, …). We re-validate
//! amount/receiver on OUR side after either success code (never trust the external check
//! alone) — see the handler.

use serde::Deserialize;

use shared::error::AppError;

/// Slip2Go success: "Slip found" — the slip is real (returned when no condition gated it).
pub const SUCCESS_CODE: &str = "200000";
/// Slip2Go success: "Slip is Valid" — the slip is real AND matched every `checkCondition`
/// in the request. This is what a receiver-matched slip returns once `checkReceiver` is
/// sent; treating it as a failure rejected every legitimate QR payment (found 2026-07-03).
pub const SUCCESS_VALID_CODE: &str = "200200";

/// Both envelope codes that carry a [`VerifiedSlip`]. Anything else is a rejection.
fn is_success_code(code: &str) -> bool {
    code == SUCCESS_CODE || code == SUCCESS_VALID_CODE
}

/// The verified-slip facts we act on (a flattened subset of Slip2Go's `data`). All anti-fraud
/// re-validation (amount ≥ estimate, receiver == our account) + the our-side dedupe (trans_ref /
/// reference_id) run against THESE server-returned values, never the client's claims.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerifiedSlip {
    /// Slip2Go's verification id (UUID) — the key for the free re-read + a dedupe key.
    pub reference_id: String,
    /// The bank transfer reference printed on the slip — the PRIMARY our-side dedupe key.
    pub trans_ref: String,
    /// The verified transfer amount (exact decimal). Asserted `>= estimate` (overpay accepted).
    pub amount: rust_decimal::Decimal,
    /// EVERY receiver identifier Slip2Go read off the slip — the BANK account AND the PromptPay
    /// PROXY (phone / national-id). Both are kept because `RECEIVING_ACCOUNT` may be a PromptPay
    /// proxy (e.g. a phone) while the slip's bank account is a DIFFERENT number (and vice versa): a
    /// payment via our PromptPay QR lands with the PROXY matching but the underlying bank account
    /// not. The handler accepts the slip if ANY identifier matches `RECEIVING_ACCOUNT`. Empty when
    /// the slip carried neither (treated as a receiver mismatch by the handler).
    pub receiver_accounts: Vec<String>,
}

/// The verification conditions we send Slip2Go (the `payload`). The server runs these for us; we
/// STILL re-validate on our side (defence in depth). `amount` is a STRING (Slip2Go requires it —
/// no `0`/comma); `account_number` is OUR receiving account.
#[derive(Debug, Clone)]
pub struct SlipConditions {
    /// Our receiving account number — `checkReceiver:[{accountNumber}]` (verify money went to us).
    pub receiver_account: String,
    /// The Slip2Go account TYPE for our receiver, when known — sent with `accountNumber` so Slip2Go
    /// matches it as the RIGHT kind of identifier. Our `RECEIVING_ACCOUNT` is a PromptPay PROXY (a
    /// phone / national-id), NOT a bank account: WITHOUT a type Slip2Go treats the bare number as a
    /// bank account and returns 200401 "Recipient Account Not Match" against the slip's PromptPay
    /// receiver. A mobile proxy is `"02001"` (PromptPay MSISDN, per the Slip2Go docs). `None` → omit
    /// `accountType` (let Slip2Go infer — the pre-fix behaviour).
    pub receiver_account_type: Option<String>,
    /// The server-computed estimate as a plain string — `checkAmount:{type:"gte", amount}`
    /// (accept overpay, reject underpay).
    pub min_amount: String,
}

/// Port: verify a slip image against Slip2Go. Implemented by [`HttpSlipVerifier`] (real reqwest)
/// and a stub in tests. `async fn` in trait (internal, never `dyn`) — static dispatch, no
/// `async-trait`, mirroring `BookingReader`.
#[allow(async_fn_in_trait)]
pub trait SlipVerifier: Send + Sync {
    /// Verify `image` (the raw slip bytes) with the given `conditions`. On a Slip2Go success code
    /// (`200000` / `200200`) returns the [`VerifiedSlip`]; on any other code returns a typed slip-rejection error
    /// (the external `message` is surfaced); on a config/transport failure a generic error.
    async fn verify(
        &self,
        image: Vec<u8>,
        content_type: &str,
        conditions: &SlipConditions,
    ) -> Result<VerifiedSlip, AppError>;
}

// ----- Slip2Go wire shapes (deserialize side) -----

/// The `{ code, message, data }` envelope.
#[derive(Debug, Deserialize)]
struct SlipEnvelope {
    code: String,
    #[serde(default)]
    message: String,
    #[serde(default)]
    data: Option<SlipData>,
}

/// The subset of `data` we read. Slip2Go returns `amount` as a JSON NUMBER; the rest are strings /
/// nested objects (we reach into `receiver.account.proxy`/`receiver.account.bank` for the account).
#[derive(Debug, Deserialize)]
struct SlipData {
    #[serde(rename = "referenceId")]
    reference_id: String,
    #[serde(rename = "transRef")]
    trans_ref: String,
    // The workspace `rust_decimal` uses `serde-str` (Decimal ⇄ JSON STRING), but Slip2Go sends
    // `amount` as a JSON NUMBER — so override with a field deserializer that accepts a number OR a
    // string and yields an exact Decimal (NEVER an f64 round-trip; CLAUDE.md money rule).
    #[serde(deserialize_with = "deserialize_decimal_lenient")]
    amount: rust_decimal::Decimal,
    #[serde(default)]
    receiver: Option<SlipParty>,
}

/// Deserialize a Decimal from EITHER a JSON number or a JSON string, exactly (no binary-float
/// round-trip): a JSON number's textual form is parsed straight into `Decimal::from_str`, so e.g.
/// `2000.0` and `"2000.00"` both yield the exact value. Used for Slip2Go's numeric `amount` field.
fn deserialize_decimal_lenient<'de, D>(de: D) -> Result<rust_decimal::Decimal, D::Error>
where
    D: serde::Deserializer<'de>,
{
    use serde::de::Error as _;
    use std::str::FromStr;
    // serde_json::Number preserves the exact textual representation; a String passes through too.
    let raw = serde_json::Value::deserialize(de)?;
    let text = match &raw {
        serde_json::Value::Number(n) => n.to_string(),
        serde_json::Value::String(s) => s.clone(),
        other => {
            return Err(D::Error::custom(format!(
                "expected a number or string for amount, got {other}"
            )))
        }
    };
    rust_decimal::Decimal::from_str(&text)
        .map_err(|e| D::Error::custom(format!("invalid decimal amount {text:?}: {e}")))
}

#[derive(Debug, Deserialize)]
struct SlipParty {
    #[serde(default)]
    account: Option<SlipAccount>,
}

/// The account block. The receiving account number can surface as `bank.account` (bank account) or
/// `proxy.account` (a PromptPay proxy id, e.g. phone/citizen-id). We accept either as the receiver.
#[derive(Debug, Deserialize)]
struct SlipAccount {
    #[serde(default)]
    bank: Option<SlipAccountRef>,
    #[serde(default)]
    proxy: Option<SlipAccountRef>,
}

#[derive(Debug, Deserialize)]
struct SlipAccountRef {
    #[serde(default)]
    account: Option<String>,
}

impl SlipData {
    /// EVERY receiver identifier on the slip — the bank account AND the PromptPay proxy id — with
    /// blank/duplicate values dropped. A PromptPay QR payment lands with the proxy == our account
    /// but the bank account a DIFFERENT number, so both are needed for the receiver match (the old
    /// bank-preferred flatten silently rejected legitimate PromptPay payments). Empty when neither.
    fn receiver_accounts(&self) -> Vec<String> {
        let Some(acct) = self.receiver.as_ref().and_then(|r| r.account.as_ref()) else {
            return Vec::new();
        };
        let mut out = Vec::new();
        for candidate in [
            acct.bank.as_ref().and_then(|b| b.account.clone()),
            acct.proxy.as_ref().and_then(|p| p.account.clone()),
        ]
        .into_iter()
        .flatten()
        {
            let trimmed = candidate.trim().to_string();
            if !trimmed.is_empty() && !out.contains(&trimmed) {
                out.push(trimmed);
            }
        }
        out
    }
}

/// Map a verified envelope into either a [`VerifiedSlip`] (200000 "Slip found" / 200200 "Slip is
/// Valid") or a typed slip-rejection error carrying the external `message`. Pure (no I/O) so the
/// success/fail branching is unit-testable.
fn interpret(envelope: SlipEnvelope) -> Result<VerifiedSlip, AppError> {
    if !is_success_code(&envelope.code) {
        // A non-success code = the slip is not valid / a condition did not match / a duplicate /
        // quota. Surface Slip2Go's message under a typed code so the client can branch + retry.
        let msg = if envelope.message.trim().is_empty() {
            "Slip verification failed".to_string()
        } else {
            envelope.message
        };
        // Diagnostic (no image/secret/PII): a "ตรวจไม่พบการโอน" on the device is otherwise opaque —
        // log Slip2Go's verdict so duplicate vs wrong-receiver vs unreadable-QR vs not-found is
        // debuggable from the payment logs. The code/message are Slip2Go's, not customer data.
        tracing::warn!(slip2go_code = %envelope.code, "slip rejected by Slip2Go: {msg}");
        return Err(AppError::ConflictCode {
            code: SLIP_VERIFY_FAILED_CODE,
            message: msg,
        });
    }
    let data = envelope
        .data
        .ok_or_else(|| AppError::Internal("Slip verification returned no data".to_string()))?;
    let receiver_accounts = data.receiver_accounts();
    Ok(VerifiedSlip {
        reference_id: data.reference_id,
        trans_ref: data.trans_ref,
        amount: data.amount,
        receiver_accounts,
    })
}

// ----- Typed slip-rejection codes (the client branches on `error.code`) -----

/// Slip2Go itself rejected the slip (non-success code): invalid / altered / condition not met / quota.
pub const SLIP_VERIFY_FAILED_CODE: &str = "SLIP_VERIFY_FAILED";
/// The slip's amount was less than the server estimate (underpay) — our-side re-validation.
pub const SLIP_AMOUNT_TOO_LOW_CODE: &str = "SLIP_AMOUNT_TOO_LOW";
/// The slip's receiver was NOT our receiving account — our-side re-validation.
pub const SLIP_WRONG_RECEIVER_CODE: &str = "SLIP_WRONG_RECEIVER";
/// The slip (transRef / referenceId) was already used to pay a booking — our-side UNIQUE dedupe.
pub const SLIP_DUPLICATE_CODE: &str = "SLIP_DUPLICATE";

/// Real verifier: POSTs the slip image multipart to Slip2Go with the Bearer secret.
#[derive(Clone)]
pub struct HttpSlipVerifier {
    http: reqwest::Client,
    /// Base URL, e.g. `https://connect.slip2go.com/api` (config `SLIP2GO_BASE_URL`; a sandbox URL
    /// can override). No trailing slash.
    base_url: String,
    /// The Bearer secret (`SLIP2GO_API_SECRET`). `None` when unset — the service still starts (the
    /// simulated path needs no secret), but a verify call fails gracefully with a config error.
    api_secret: Option<String>,
}

impl HttpSlipVerifier {
    pub fn new(http: reqwest::Client, base_url: String, api_secret: Option<String>) -> Self {
        Self {
            http,
            base_url: base_url.trim_end_matches('/').to_string(),
            // An empty/whitespace secret is treated as absent (a common env-template footgun).
            api_secret: api_secret.filter(|s| !s.trim().is_empty()),
        }
    }

    /// Build the `payload` JSON Slip2Go's multipart expects: our receiver + a `gte` amount +
    /// `checkDuplicate`. `amount` is a STRING (no `0`/comma), per the API.
    fn payload_json(conditions: &SlipConditions) -> String {
        // The receiver condition: the account number, plus its account TYPE when we know it. The
        // type is REQUIRED for a PromptPay proxy (our RECEIVING_ACCOUNT) — without it Slip2Go treats
        // the number as a bank account and 200401s against the slip's PromptPay receiver.
        let mut receiver = serde_json::Map::new();
        if let Some(account_type) = &conditions.receiver_account_type {
            receiver.insert("accountType".into(), serde_json::json!(account_type));
        }
        receiver.insert(
            "accountNumber".into(),
            serde_json::json!(conditions.receiver_account),
        );
        serde_json::json!({
            "checkReceiver": [ receiver ],
            "checkAmount": { "type": "gte", "amount": conditions.min_amount },
            "checkDuplicate": true,
        })
        .to_string()
    }
}

impl SlipVerifier for HttpSlipVerifier {
    async fn verify(
        &self,
        image: Vec<u8>,
        content_type: &str,
        conditions: &SlipConditions,
    ) -> Result<VerifiedSlip, AppError> {
        // Fail gracefully when the secret is absent: the slip path is unusable without it, but the
        // service (and the simulated path) started fine. A typed config error, never a panic.
        let Some(secret) = self.api_secret.as_deref() else {
            tracing::warn!("slip verification attempted but SLIP2GO_API_SECRET is not configured");
            return Err(AppError::Internal(
                "Slip verification is not configured".to_string(),
            ));
        };

        let url = format!("{}/verify-slip/qr-image/info", self.base_url);
        let part = reqwest::multipart::Part::bytes(image)
            .file_name("slip")
            .mime_str(content_type)
            .map_err(|e| {
                tracing::warn!("slip multipart mime error: {e}");
                AppError::Internal("Slip verification failed".to_string())
            })?;
        let form = reqwest::multipart::Form::new()
            .part("file", part)
            .text("payload", Self::payload_json(conditions));

        let resp = self
            .http
            .post(&url)
            .header("Authorization", format!("Bearer {secret}"))
            .multipart(form)
            .send()
            .await
            .map_err(|e| {
                // Never leak the URL/secret — `without_url()` strips reqwest's embedded request URL.
                tracing::warn!("slip verify transport error: {}", e.without_url());
                AppError::Internal("Slip verification failed".to_string())
            })?;

        // Slip2Go returns 200 with the `code` in the BODY even for verification failures, but be
        // defensive about transport-level non-2xx (e.g. 401 bad secret, 429 quota).
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            tracing::warn!("slip verify returned HTTP {status}: {body}");
            // Try to parse the typed envelope out of an error body so the client still gets the
            // Slip2Go message; otherwise a generic failure.
            if let Ok(envelope) = serde_json::from_str::<SlipEnvelope>(&body) {
                return interpret(envelope);
            }
            return Err(AppError::Internal("Slip verification failed".to_string()));
        }

        let envelope: SlipEnvelope = resp.json().await.map_err(|e| {
            tracing::warn!("slip verify decode error: {e}");
            AppError::Internal("Slip verification failed".to_string())
        })?;
        interpret(envelope)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dec(s: &str) -> rust_decimal::Decimal {
        s.parse().unwrap()
    }

    #[test]
    fn interpret_success_flattens_bank_receiver() {
        let envelope: SlipEnvelope = serde_json::from_value(serde_json::json!({
            "code": "200000",
            "message": "Slip found",
            "data": {
                "referenceId": "11111111-1111-1111-1111-111111111111",
                "transRef": "0140315796",
                "amount": 2000.0,
                "receiver": { "account": { "bank": { "account": "1234567890" } } }
            }
        }))
        .unwrap();
        let v = interpret(envelope).unwrap();
        assert_eq!(v.reference_id, "11111111-1111-1111-1111-111111111111");
        assert_eq!(v.trans_ref, "0140315796");
        assert_eq!(v.amount, dec("2000.0"));
        assert_eq!(v.receiver_accounts, vec!["1234567890".to_string()]);
    }

    #[test]
    fn interpret_success_keeps_both_bank_and_proxy() {
        // A PromptPay QR payment: the slip carries BOTH the underlying bank account AND the proxy
        // (phone). Both must survive so the handler can match RECEIVING_ACCOUNT against EITHER —
        // the proxy is what equals our configured account; the bank account is a different number.
        let envelope: SlipEnvelope = serde_json::from_value(serde_json::json!({
            "code": "200000",
            "data": {
                "referenceId": "r", "transRef": "t", "amount": 100,
                "receiver": { "account": {
                    "bank": { "account": "1234567890" },
                    "proxy": { "type": "MSISDN", "account": "0863208235" }
                } }
            }
        }))
        .unwrap();
        let v = interpret(envelope).unwrap();
        assert_eq!(
            v.receiver_accounts,
            vec!["1234567890".to_string(), "0863208235".to_string()]
        );
    }

    #[test]
    fn interpret_success_falls_back_to_proxy_account() {
        // No bank account, but a PromptPay proxy id (e.g. a phone number) → the proxy is the only
        // receiver identifier.
        let envelope: SlipEnvelope = serde_json::from_value(serde_json::json!({
            "code": "200000",
            "data": {
                "referenceId": "ref", "transRef": "tr", "amount": 500,
                "receiver": { "account": { "proxy": { "type": "MSISDN", "account": "0812345678" } } }
            }
        }))
        .unwrap();
        let v = interpret(envelope).unwrap();
        assert_eq!(v.receiver_accounts, vec!["0812345678".to_string()]);
    }

    #[test]
    fn interpret_accepts_200200_slip_is_valid() {
        // REGRESSION (staging 2026-07-03): once `checkReceiver` matches, Slip2Go answers
        // `200200 "Slip is Valid"` (its condition-matched SUCCESS code, same data shape) —
        // treating only 200000 as success rejected every legitimate in-app QR payment
        // right after the receiver fix (#209) started matching.
        let envelope: SlipEnvelope = serde_json::from_value(serde_json::json!({
            "code": "200200",
            "message": "Slip is Valid",
            "data": {
                "referenceId": "22222222-2222-2222-2222-222222222222",
                "transRef": "184440173749COT08999",
                "amount": 750.5,
                "receiver": { "account": {
                    "bank": { "account": "1234567890" },
                    "proxy": { "type": "MSISDN", "account": "0863208235" }
                } }
            }
        }))
        .unwrap();
        let v = interpret(envelope).unwrap();
        assert_eq!(v.trans_ref, "184440173749COT08999");
        assert_eq!(v.amount, dec("750.5"));
        assert_eq!(
            v.receiver_accounts,
            vec!["1234567890".to_string(), "0863208235".to_string()]
        );
    }

    #[test]
    fn interpret_condition_mismatch_codes_stay_rejections() {
        // The neighbouring 2004xx family (receiver/amount/date mismatch, not found) and the
        // duplicate code must STAY rejections — only the two documented success codes pass.
        for code in ["200401", "200402", "200403", "200404", "200501"] {
            let envelope: SlipEnvelope = serde_json::from_value(serde_json::json!({
                "code": code,
                "message": "mismatch",
                "data": null
            }))
            .unwrap();
            assert!(
                interpret(envelope).is_err(),
                "code {code} must remain a rejection"
            );
        }
    }

    #[test]
    fn interpret_non_success_is_typed_rejection_with_message() {
        let envelope: SlipEnvelope = serde_json::from_value(serde_json::json!({
            "code": "400xxx",
            "message": "Slip already used",
            "data": null
        }))
        .unwrap();
        let err = interpret(envelope).unwrap_err();
        match err {
            AppError::ConflictCode { code, message } => {
                assert_eq!(code, SLIP_VERIFY_FAILED_CODE);
                assert_eq!(message, "Slip already used", "surfaces Slip2Go's message");
            }
            other => panic!("expected typed slip rejection, got {other:?}"),
        }
    }

    #[test]
    fn interpret_non_success_empty_message_uses_default() {
        let envelope: SlipEnvelope = serde_json::from_value(serde_json::json!({
            "code": "499999", "message": "", "data": null
        }))
        .unwrap();
        match interpret(envelope).unwrap_err() {
            AppError::ConflictCode { message, .. } => {
                assert_eq!(message, "Slip verification failed")
            }
            other => panic!("expected typed rejection, got {other:?}"),
        }
    }

    #[test]
    fn interpret_success_missing_receiver_is_none_not_error() {
        // A 200000 with no receiver block → receiver_account None (the handler treats that as a
        // receiver mismatch and rejects); interpret itself does NOT error here.
        let envelope: SlipEnvelope = serde_json::from_value(serde_json::json!({
            "code": "200000",
            "data": { "referenceId": "r", "transRef": "t", "amount": 100 }
        }))
        .unwrap();
        let v = interpret(envelope).unwrap();
        assert!(v.receiver_accounts.is_empty());
    }

    #[test]
    fn payload_json_has_gte_amount_receiver_and_dedupe() {
        let conds = SlipConditions {
            receiver_account: "0863208235".to_string(),
            receiver_account_type: Some("02001".to_string()),
            min_amount: "2000.00".to_string(),
        };
        let v: serde_json::Value =
            serde_json::from_str(&HttpSlipVerifier::payload_json(&conds)).unwrap();
        assert_eq!(v["checkReceiver"][0]["accountNumber"], "0863208235");
        // The PromptPay MSISDN type is sent so Slip2Go matches the proxy, not a bank account.
        assert_eq!(v["checkReceiver"][0]["accountType"], "02001");
        assert_eq!(v["checkAmount"]["type"], "gte");
        assert_eq!(v["checkAmount"]["amount"], "2000.00"); // STRING, not a number
        assert_eq!(v["checkDuplicate"], true);
    }

    #[test]
    fn payload_json_omits_account_type_when_unknown() {
        // No type → the accountType key is absent (Slip2Go infers); accountNumber still present.
        let conds = SlipConditions {
            receiver_account: "1234567890".to_string(),
            receiver_account_type: None,
            min_amount: "500.00".to_string(),
        };
        let v: serde_json::Value =
            serde_json::from_str(&HttpSlipVerifier::payload_json(&conds)).unwrap();
        assert_eq!(v["checkReceiver"][0]["accountNumber"], "1234567890");
        assert!(v["checkReceiver"][0].get("accountType").is_none());
    }

    #[tokio::test]
    async fn verify_without_secret_fails_gracefully() {
        // The service started without SLIP2GO_API_SECRET (simulated path) → a verify call returns
        // a typed config error, never a panic / never an outbound HTTP call.
        let verifier = HttpSlipVerifier::new(
            reqwest::Client::new(),
            "https://connect.slip2go.com/api".to_string(),
            None,
        );
        let conds = SlipConditions {
            receiver_account: "1234567890".to_string(),
            receiver_account_type: None,
            min_amount: "2000.00".to_string(),
        };
        let err = verifier
            .verify(vec![0xFF, 0xD8, 0xFF], "image/jpeg", &conds)
            .await
            .unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
    }

    #[test]
    fn empty_secret_is_treated_as_absent() {
        let v = HttpSlipVerifier::new(
            reqwest::Client::new(),
            "https://x".to_string(),
            Some("  ".to_string()),
        );
        assert!(v.api_secret.is_none(), "whitespace secret → absent");
    }
}
