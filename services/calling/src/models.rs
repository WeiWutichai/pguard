//! DTOs for the calling service (transport shapes). Pure data — no I/O.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ----- Requests -----

/// Initiate a call. The `callee` is DERIVED from the booking (the other participant), never
/// supplied by the client — so a caller can't dial a stranger (CLAUDE.md authz / IDOR).
#[derive(Debug, Deserialize)]
pub struct InitiateCallRequest {
    pub booking_id: Uuid,
    /// `audio` (default) or `video`; validated by the domain.
    #[serde(default)]
    pub call_type: Option<String>,
}

/// Optional reason carried on `end` (e.g. "hangup", "cancelled"). Free text, audit-only.
#[derive(Debug, Default, Deserialize)]
pub struct EndCallRequest {
    #[serde(default)]
    pub reason: Option<String>,
}

/// Query params for `GET /admin/calls` (admin cross-user call log). `status`/`call_type` are
/// validated against the enums (unknown → 400). House limit/offset pagination.
#[derive(Debug, Deserialize)]
pub struct AdminListCallsQuery {
    pub status: Option<String>,
    pub call_type: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

// ----- Responses -----

/// A call row as returned to clients. `status`/`call_type` are read as text (the DB enums
/// cast to text) so the read path needs no enum decoding — mirrors the booking slice.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct CallResponse {
    pub id: Uuid,
    pub caller_id: Uuid,
    pub callee_id: Uuid,
    pub booking_id: Uuid,
    pub call_type: String,
    pub status: String,
    pub started_at: DateTime<Utc>,
    pub answered_at: Option<DateTime<Utc>>,
    pub ended_at: Option<DateTime<Utc>>,
    pub duration_seconds: Option<i32>,
    pub end_reason: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// One ICE server for the client's RTCPeerConnection — a STUN entry (urls only) or a TURN entry
/// (urls + a short-lived username/credential). Field names match the WebRTC `RTCIceServer` shape
/// the mobile client feeds straight into `createPeerConnection`.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct IceServer {
    pub urls: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub username: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub credential: Option<String>,
}

/// The served ICE config: public STUN + (when TURN is configured) a relay with short-lived,
/// per-caller HMAC credentials. `ttl_secs` tells the client how long the TURN credential is good
/// for so it can refetch before expiry. The coturn `static-auth-secret` is NEVER in here.
#[derive(Debug, Clone, Serialize)]
pub struct IceConfig {
    pub ice_servers: Vec<IceServer>,
    pub ttl_secs: i64,
}

impl IceConfig {
    /// Assemble the ICE list: every `stun_urls` entry (no creds) + one TURN entry carrying all
    /// `turn_urls` (udp/tcp) with a freshly-minted short-lived credential — only when a `secret`
    /// AND at least one TURN URL are configured (else STUN-only, e.g. local dev). `now_unix` +
    /// `ttl_secs` set the credential's expiry. Pure (delegates to [`crate::domain::turn_credential`])
    /// → hermetically unit-testable.
    pub fn build(
        stun_urls: &[String],
        turn_urls: &[String],
        secret: Option<&str>,
        user_id: &str,
        now_unix: i64,
        ttl_secs: i64,
    ) -> Self {
        let mut ice_servers: Vec<IceServer> = stun_urls
            .iter()
            .map(|u| IceServer {
                urls: vec![u.clone()],
                username: None,
                credential: None,
            })
            .collect();
        if let Some(secret) = secret {
            if !turn_urls.is_empty() {
                // `turn_credential` is `None` only on the unreachable HMAC-key error → degrade to
                // STUN-only rather than panic (no `.expect()` in the request path).
                if let Some((username, credential)) =
                    crate::domain::turn_credential(secret.as_bytes(), user_id, now_unix + ttl_secs)
                {
                    ice_servers.push(IceServer {
                        urls: turn_urls.to_vec(),
                        username: Some(username),
                        credential: Some(credential),
                    });
                }
            }
        }
        IceConfig {
            ice_servers,
            ttl_secs,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const STUN: &[&str] = &["stun:stun.l.google.com:19302"];

    fn strs(xs: &[&str]) -> Vec<String> {
        xs.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn build_stun_only_when_no_turn_configured() {
        let cfg = IceConfig::build(&strs(STUN), &[], None, "u1", 1_000, 3600);
        assert_eq!(cfg.ice_servers.len(), 1);
        assert_eq!(cfg.ice_servers[0].urls, strs(STUN));
        assert!(
            cfg.ice_servers[0].credential.is_none(),
            "STUN carries no creds"
        );
        assert_eq!(cfg.ttl_secs, 3600);
    }

    #[test]
    fn build_adds_turn_with_short_lived_creds() {
        let turn = strs(&[
            "turn:turn.pguard.app:3478?transport=udp",
            "turn:turn.pguard.app:3478?transport=tcp",
        ]);
        let cfg = IceConfig::build(&strs(STUN), &turn, Some("the-secret"), "user-9", 1_000, 600);
        // STUN entry + one TURN entry carrying BOTH transports.
        assert_eq!(cfg.ice_servers.len(), 2);
        let t = &cfg.ice_servers[1];
        assert_eq!(t.urls, turn);
        // username = expiry:user (expiry = now+ttl), credential = the HMAC (non-empty), secret absent.
        assert_eq!(t.username.as_deref(), Some("1600:user-9"));
        assert_eq!(t.credential.as_ref().map(|c| c.len()), Some(28));
        let json = serde_json::to_string(&cfg).unwrap();
        assert!(
            !json.contains("the-secret"),
            "the static secret must never be serialized"
        );
    }

    #[test]
    fn build_turn_url_without_secret_yields_stun_only() {
        // Defensive: a TURN URL but no secret → we can't mint creds, so don't advertise TURN.
        let cfg = IceConfig::build(&strs(STUN), &strs(&["turn:x:3478"]), None, "u", 1_000, 3600);
        assert_eq!(cfg.ice_servers.len(), 1, "no secret ⇒ STUN-only");
    }
}

// ----- booking internal read (deserialized from booking's /internal/bookings/{id}) -----

/// The authoritative booking fields the calling service verifies participation against.
/// Mirrors the subset of booking's `InternalBooking` we need; serde ignores extra fields.
#[derive(Debug, Clone, Deserialize)]
pub struct InternalBooking {
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub status: String,
}
