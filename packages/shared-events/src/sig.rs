//! HMAC-SHA256 signing for the NATS event bus — the event-bus counterpart of the
//! request-path Service-JWT (CLAUDE.md "Service auth (internal)").
//!
//! The NATS bus has no producer authentication: anything that can publish to a subject can
//! forge a state-changing event (a fake `user.approved` that approves an account, or a
//! `user.compromised` that force-revokes one). To close that gap, every producer attaches a
//! detached HMAC-SHA256 signature over the exact published bytes (in the
//! [`SIGNATURE_HEADER`] NATS header), and every durable consumer verifies it BEFORE any
//! dedupe/business logic — an unsigned/forged/tampered event is dropped, never applied.
//!
//! Signing the raw published bytes (not a re-serialized struct) makes "canonical" trivially
//! exact: the consumer verifies the very bytes it received, then parses them — no field-order
//! or re-encoding mismatch is possible. The key is a dedicated `EVENT_SIGNING_SECRET`
//! (≥64 chars), loaded once at startup via [`init_signing_key_from_env`] (fail-fast, mirrors
//! `JwtConfig`), and never an overload of an unrelated secret.

use std::sync::OnceLock;

use hmac::{Hmac, Mac};
use sha2::Sha256;
use subtle::ConstantTimeEq;

type HmacSha256 = Hmac<Sha256>;

/// NATS header carrying the lowercase-hex HMAC-SHA256 of the message payload.
pub const SIGNATURE_HEADER: &str = "X-Pguard-Signature";

/// Minimum length of `EVENT_SIGNING_SECRET` (mirrors the JWT secret floor).
const MIN_SECRET_LEN: usize = 64;

/// Process-wide signing key, loaded once at startup. A `OnceLock` (not threaded through every
/// relay/consumer) so a new producer/consumer physically cannot forget to use the same key —
/// it is read by [`publish_signed`]/[`verify_message`] from here.
static SIGNING_KEY: OnceLock<Vec<u8>> = OnceLock::new();

/// Load the signing key from `EVENT_SIGNING_SECRET` (≥64 chars) and cache it. Call ONCE at
/// service startup, before spawning any relay/consumer — fail-fast so a misconfigured service
/// never silently runs unsigned. Returns `Err` (caller aborts startup) if unset/too short.
/// Idempotent: a redundant call with the value already set is a no-op.
pub fn init_signing_key_from_env() -> Result<(), String> {
    let secret = std::env::var("EVENT_SIGNING_SECRET")
        .map_err(|_| "EVENT_SIGNING_SECRET is required (>= 64 chars)".to_string())?;
    if secret.len() < MIN_SECRET_LEN {
        return Err(format!(
            "EVENT_SIGNING_SECRET must be at least {MIN_SECRET_LEN} characters"
        ));
    }
    let _ = SIGNING_KEY.set(secret.into_bytes());
    Ok(())
}

/// Set the signing key explicitly — for TESTS / non-env bootstrap only. First write wins (a
/// later call with a different key silently no-ops). Production loads via
/// [`init_signing_key_from_env`] at startup. (`pub` because downstream crates' integration
/// tests need it; `#[doc(hidden)]` keeps it out of the public surface.)
#[doc(hidden)]
pub fn init_signing_key(secret: &[u8]) {
    let _ = SIGNING_KEY.set(secret.to_vec());
}

/// The cached key. Panics only if a service reaches the publish/verify path without having
/// called [`init_signing_key_from_env`] at startup — a startup-invariant bug, surfaced loudly.
fn signing_key() -> &'static [u8] {
    SIGNING_KEY
        .get()
        .map(Vec::as_slice)
        .expect("event signing key not initialized — call init_signing_key_from_env() at startup")
}

/// Lowercase-hex HMAC-SHA256 of `payload` under `key`. Pure (explicit key) so it is
/// unit-testable without the process-global.
pub fn sign_bytes(payload: &[u8], key: &[u8]) -> String {
    // HMAC accepts a key of any length, so this never errors.
    let mut mac = HmacSha256::new_from_slice(key).expect("HMAC accepts any key length");
    mac.update(payload);
    let tag = mac.finalize().into_bytes();
    let mut hex = String::with_capacity(tag.len() * 2);
    for b in tag {
        use std::fmt::Write;
        let _ = write!(hex, "{b:02x}");
    }
    hex
}

/// Verify a hex signature against `payload` under `key`, constant-time (mirrors the OTP
/// code-compare: `subtle::ConstantTimeEq` over equal-length hex). A wrong-length signature is
/// rejected up front — its length carries no information about the secret.
pub fn verify_bytes(payload: &[u8], sig_hex: &str, key: &[u8]) -> bool {
    let expected = sign_bytes(payload, key);
    if expected.len() != sig_hex.len() {
        return false;
    }
    expected.as_bytes().ct_eq(sig_hex.as_bytes()).into()
}

/// Publish `payload` to `subject` on JetStream with its HMAC signature in [`SIGNATURE_HEADER`],
/// awaiting the broker persistence ack. THE single signed-publish path every relay routes
/// through, so no producer can forget to sign.
pub async fn publish_signed(
    jetstream: &async_nats::jetstream::Context,
    subject: &str,
    payload: &[u8],
) -> Result<(), anyhow::Error> {
    let sig = sign_bytes(payload, signing_key());
    let mut headers = async_nats::HeaderMap::new();
    headers.insert(SIGNATURE_HEADER, sig.as_str());
    let ack = jetstream
        .publish_with_headers(subject.to_string(), headers, payload.to_vec().into())
        .await?;
    ack.await?;
    Ok(())
}

/// Verify a received message: `true` iff it carries a [`SIGNATURE_HEADER`] that is a valid
/// HMAC of its payload under the process key. Fail-CLOSED — a missing header, an unparseable
/// value, or a bad signature all return `false`. Consumers call this BEFORE dedupe/business
/// logic and drop (ack without applying) on `false`.
pub fn verify_message(headers: Option<&async_nats::HeaderMap>, payload: &[u8]) -> bool {
    let Some(headers) = headers else {
        return false;
    };
    let Some(sig) = headers.get(SIGNATURE_HEADER) else {
        return false;
    };
    verify_bytes(payload, sig.as_str(), signing_key())
}

#[cfg(test)]
mod tests {
    use super::*;

    const KEY: &[u8] = b"event-signing-secret-at-least-64-characters-long-for-hmac-sha256!!";
    const KEY2: &[u8] = b"another-event-signing-secret-also-64-characters-long-for-hmac256!!";

    #[test]
    fn sign_verify_round_trip() {
        let payload = br#"{"event_type":"pguard.events.user.approved","payload":{"user_id":"x"}}"#;
        let sig = sign_bytes(payload, KEY);
        assert!(
            verify_bytes(payload, &sig, KEY),
            "a fresh signature verifies"
        );
        assert_eq!(sig.len(), 64, "HMAC-SHA256 hex is 32 bytes = 64 hex chars");
    }

    #[test]
    fn tampered_payload_fails() {
        let payload = br#"{"user_id":"alice","role":"customer"}"#;
        let sig = sign_bytes(payload, KEY);
        let tampered = br#"{"user_id":"alice","role":"admin!!!"}"#; // SAME length, different bytes
        assert_eq!(
            payload.len(),
            tampered.len(),
            "equal-length tamper proves verify rejects on content, not length"
        );
        assert!(
            !verify_bytes(tampered, &sig, KEY),
            "a tampered payload must not verify"
        );
    }

    #[test]
    fn wrong_key_fails() {
        let payload = b"pguard.events.user.approved|deadbeef";
        let sig = sign_bytes(payload, KEY);
        assert!(
            !verify_bytes(payload, &sig, KEY2),
            "a signature made with a different key must not verify"
        );
    }

    #[test]
    fn missing_or_malformed_signature_fails() {
        let payload = b"anything";
        assert!(!verify_bytes(payload, "", KEY), "empty signature fails");
        assert!(
            !verify_bytes(payload, "not-hex-and-wrong-length", KEY),
            "garbage signature fails"
        );
        // A 64-char-but-wrong hex string (right length, wrong value) is rejected.
        let wrong = "0".repeat(64);
        assert!(
            !verify_bytes(payload, &wrong, KEY),
            "wrong same-length hex fails"
        );
    }

    #[test]
    fn signature_is_deterministic_for_same_input() {
        let payload = b"deterministic";
        assert_eq!(
            sign_bytes(payload, KEY),
            sign_bytes(payload, KEY),
            "HMAC is deterministic for the same (payload, key)"
        );
    }

    /// The actual consumer entry point (`verify_message`) is fail-closed on every header shape:
    /// no headers → false, missing signature header → false, present-but-wrong → false, valid →
    /// true. Offline (no NATS/DB) — keeps the fail-closed guarantee covered without the gated e2e.
    #[test]
    fn verify_message_is_fail_closed_on_headers() {
        init_signing_key(KEY);
        let payload = br#"{"event_type":"pguard.events.booking.arrived"}"#;

        // (1) No headers at all → rejected.
        assert!(!verify_message(None, payload), "None headers must fail");

        // (2) Headers present but NO signature header → rejected.
        let empty = async_nats::HeaderMap::new();
        assert!(
            !verify_message(Some(&empty), payload),
            "missing signature header must fail"
        );

        // (3) Signature header present but WRONG → rejected.
        let mut bad = async_nats::HeaderMap::new();
        bad.insert(SIGNATURE_HEADER, "0".repeat(64).as_str());
        assert!(
            !verify_message(Some(&bad), payload),
            "wrong signature must fail"
        );

        // (4) Valid signature (over the exact bytes, same key) → accepted.
        let mut good = async_nats::HeaderMap::new();
        good.insert(SIGNATURE_HEADER, sign_bytes(payload, KEY).as_str());
        assert!(
            verify_message(Some(&good), payload),
            "a valid signature must pass"
        );

        // (5) Valid signature but TAMPERED payload → rejected (sig is over content).
        assert!(
            !verify_message(
                Some(&good),
                br#"{"event_type":"pguard.events.booking.ARRIVED"}"#
            ),
            "a valid sig over different bytes must fail"
        );
    }
}
