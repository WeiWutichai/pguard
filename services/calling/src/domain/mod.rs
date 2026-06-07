//! PURE call domain — no DB, no HTTP, no NATS. 100% unit-testable.
//!
//! The call lifecycle state machine + the peer-resolution helper the WS relay uses. Ported
//! (and tightened) from v1 booking `calls/*`; v2 drops `ringing`/`failed` for the simpler set
//! in the spec.

use std::fmt;
use std::str::FromStr;

use base64::Engine as _;
use hmac::{Hmac, Mac};
use sha1::Sha1;
use uuid::Uuid;

type HmacSha1 = Hmac<Sha1>;

/// Mint a SHORT-LIVED TURN credential for the coturn REST API (`use-auth-secret`,
/// draft-uberti-behave-turn-rest). The `username` is `<expiry_unix>:<user_id>` — coturn reads the
/// numeric prefix as the credential's expiry and rejects it after that — and the `credential` is
/// `base64(HMAC-SHA1(secret, username))`, which coturn recomputes from the SAME `static-auth-secret`
/// to authenticate the allocation. SHA-1 is mandated by the scheme (not a security choice).
///
/// PURE + deterministic given its inputs → unit-tested here; the live coturn allocation
/// (turnutils_uclient against the running relay) is the integration known-answer check. The
/// secret never reaches the client — only this derived, time-boxed credential does.
///
/// Returns `None` only on HMAC key-construction failure, which is unreachable for HMAC (any byte
/// length is a valid key) — modelled as `Option` so the request path NEVER panics (no `.expect()`):
/// the caller degrades to STUN-only instead.
pub fn turn_credential(secret: &[u8], user_id: &str, expiry_unix: i64) -> Option<(String, String)> {
    let username = format!("{expiry_unix}:{user_id}");
    // new_from_slice only errors on impossible key sizes; any byte secret is valid for HMAC.
    let mut mac = HmacSha1::new_from_slice(secret).ok()?;
    mac.update(username.as_bytes());
    let credential = base64::engine::general_purpose::STANDARD.encode(mac.finalize().into_bytes());
    Some((username, credential))
}

/// The call lifecycle status. Serialized snake_case to match the Postgres enum
/// `calling.call_status` (NOT `sqlx::Type` — the repo binds [`CallStatus::as_db_str`] with a
/// `::calling.call_status` cast and reads the column back as text, keeping `domain` DB-free).
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CallStatus {
    Initiated,
    Accepted,
    Connected,
    Ended,
    Rejected,
    Missed,
}

impl CallStatus {
    pub fn as_db_str(self) -> &'static str {
        match self {
            CallStatus::Initiated => "initiated",
            CallStatus::Accepted => "accepted",
            CallStatus::Connected => "connected",
            CallStatus::Ended => "ended",
            CallStatus::Rejected => "rejected",
            CallStatus::Missed => "missed",
        }
    }

    /// A terminal status admits no further transitions.
    pub fn is_terminal(self) -> bool {
        matches!(
            self,
            CallStatus::Ended | CallStatus::Rejected | CallStatus::Missed
        )
    }
}

impl fmt::Display for CallStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_db_str())
    }
}

impl FromStr for CallStatus {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "initiated" => Ok(CallStatus::Initiated),
            "accepted" => Ok(CallStatus::Accepted),
            "connected" => Ok(CallStatus::Connected),
            "ended" => Ok(CallStatus::Ended),
            "rejected" => Ok(CallStatus::Rejected),
            "missed" => Ok(CallStatus::Missed),
            other => Err(format!("unknown call status: {other}")),
        }
    }
}

/// Accepted call media types (mirrors the `calling.call_type` enum).
pub const VALID_CALL_TYPES: [&str; 2] = ["audio", "video"];

/// `true` iff `t` is a known call type. Pure — the API rejects anything else with a 400.
pub fn is_valid_call_type(t: &str) -> bool {
    VALID_CALL_TYPES.contains(&t)
}

/// A call may only be placed while the booking is ACTIVE — a guard is assigned and the job is
/// in flight. Excludes `requested` (no guard), `declined`/`cancelled`/`completed` (done).
/// Pure rule over the booking status text (the authz read returns status as text).
pub fn is_callable_status(status: &str) -> bool {
    matches!(status, "accepted" | "en_route" | "arrived")
}

/// Pure transition guard. `true` iff `from → to` is a legal lifecycle move.
///
/// Happy path: `initiated → accepted → connected → ended`.
/// Branches: `initiated → rejected` (decline), `initiated → missed` (timeout / pre-answer
/// cancel), `accepted → ended` (hang up before media). A terminal status admits nothing.
pub fn can_transition(from: CallStatus, to: CallStatus) -> bool {
    use CallStatus::*;
    if from.is_terminal() {
        return false;
    }
    matches!(
        (from, to),
        (Initiated, Accepted)
            | (Initiated, Rejected)
            | (Initiated, Missed)
            | (Accepted, Connected)
            | (Accepted, Ended)
            | (Connected, Ended)
    )
}

/// The terminal status the "end" action produces from `from`, or `None` if the call is
/// already terminal (idempotent no-op). A never-answered call (`initiated`) becomes `missed`;
/// an answered one (`accepted`/`connected`) becomes `ended` — mirrors v1's `end_call` CASE.
pub fn end_target(from: CallStatus) -> Option<CallStatus> {
    match from {
        CallStatus::Initiated => Some(CallStatus::Missed),
        CallStatus::Accepted | CallStatus::Connected => Some(CallStatus::Ended),
        _ => None, // already terminal
    }
}

/// The peer a participant is signaling to: given the `sender` and the call's two
/// participants, return the OTHER one, or `None` if `sender` is not a participant (the WS
/// relay rejects the message → IDOR protection on the wire).
pub fn peer_of(sender: Uuid, caller: Uuid, callee: Uuid) -> Option<Uuid> {
    if sender == caller {
        Some(callee)
    } else if sender == callee {
        Some(caller)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::CallStatus::*;
    use super::*;

    #[test]
    fn happy_path_is_legal() {
        assert!(can_transition(Initiated, Accepted));
        assert!(can_transition(Accepted, Connected));
        assert!(can_transition(Connected, Ended));
    }

    #[test]
    fn initiated_branches() {
        assert!(can_transition(Initiated, Rejected));
        assert!(can_transition(Initiated, Missed));
        assert!(can_transition(Accepted, Ended)); // hang up before media
    }

    #[test]
    fn illegal_moves_are_rejected() {
        // can't skip to connected/ended from initiated
        assert!(!can_transition(Initiated, Connected));
        assert!(!can_transition(Initiated, Ended));
        // can't go back, can't re-accept
        assert!(!can_transition(Connected, Accepted));
        assert!(!can_transition(Accepted, Accepted));
        assert!(!can_transition(Connected, Rejected));
        // can't reject/miss after answer
        assert!(!can_transition(Accepted, Rejected));
        assert!(!can_transition(Accepted, Missed));
    }

    #[test]
    fn terminal_states_admit_nothing() {
        for terminal in [Ended, Rejected, Missed] {
            assert!(terminal.is_terminal());
            for to in [Initiated, Accepted, Connected, Ended, Rejected, Missed] {
                assert!(
                    !can_transition(terminal, to),
                    "{terminal} → {to} must be rejected (terminal)"
                );
            }
        }
    }

    #[test]
    fn end_target_maps_by_answered_state() {
        assert_eq!(end_target(Initiated), Some(Missed)); // never answered → missed
        assert_eq!(end_target(Accepted), Some(Ended));
        assert_eq!(end_target(Connected), Some(Ended));
        // already terminal → no-op
        assert_eq!(end_target(Ended), None);
        assert_eq!(end_target(Rejected), None);
        assert_eq!(end_target(Missed), None);
    }

    #[test]
    fn end_target_results_are_legal_transitions_or_noop() {
        for from in [Initiated, Accepted, Connected] {
            let to = end_target(from).expect("non-terminal ends");
            assert!(can_transition(from, to), "{from} → {to} must be legal");
        }
    }

    #[test]
    fn peer_resolution() {
        let a = Uuid::new_v4();
        let b = Uuid::new_v4();
        let stranger = Uuid::new_v4();
        assert_eq!(peer_of(a, a, b), Some(b));
        assert_eq!(peer_of(b, a, b), Some(a));
        assert_eq!(peer_of(stranger, a, b), None, "non-participant has no peer");
    }

    #[test]
    fn callable_status() {
        for ok in ["accepted", "en_route", "arrived"] {
            assert!(is_callable_status(ok), "{ok} must be callable");
        }
        for no in [
            "requested",
            "declined",
            "cancelled",
            "completed",
            "",
            "ACCEPTED",
        ] {
            assert!(!is_callable_status(no), "{no} must not be callable");
        }
    }

    #[test]
    fn call_type_validation() {
        assert!(is_valid_call_type("audio"));
        assert!(is_valid_call_type("video"));
        for bad in ["", "AUDIO", "screen", "voice"] {
            assert!(!is_valid_call_type(bad), "{bad} must be invalid");
        }
    }

    #[test]
    fn turn_credential_is_deterministic_and_well_formed() {
        let (u1, c1) = turn_credential(b"super-secret", "user-abc", 1_000_000_000).unwrap();
        let (u2, c2) = turn_credential(b"super-secret", "user-abc", 1_000_000_000).unwrap();
        // Deterministic: same inputs → identical credential (so a client can present it as-is).
        assert_eq!((u1.as_str(), c1.as_str()), (u2.as_str(), c2.as_str()));
        // username = <expiry>:<user> (coturn parses the timestamp prefix as the expiry).
        assert_eq!(u1, "1000000000:user-abc");
        // credential = base64 of a 20-byte SHA-1 HMAC → 28 chars (24 + '=' padding), valid base64.
        assert_eq!(c1.len(), 28);
        assert!(base64::engine::general_purpose::STANDARD
            .decode(&c1)
            .is_ok());
        // Golden vector tying us to the CANONICAL coturn REST scheme — verified ACCEPTED by a live
        // coturn 4.6.2 relay (turnutils_uclient ALLOCATE success). Equivalent to:
        //   printf '%s' '1000000000:user-abc' | openssl dgst -sha1 -hmac 'super-secret' -binary | base64
        assert_eq!(c1, "hLZrI4Uz6/iVAWCFqNO6CjmPdYs=");
    }

    #[test]
    fn turn_credential_changes_with_every_input() {
        let base = turn_credential(b"secret", "u", 1000).unwrap().1;
        // Different secret, expiry, or user → different credential (HMAC actually keyed on all).
        assert_ne!(
            base,
            turn_credential(b"secret2", "u", 1000).unwrap().1,
            "secret-sensitive"
        );
        assert_ne!(
            base,
            turn_credential(b"secret", "u", 1001).unwrap().1,
            "expiry-sensitive"
        );
        assert_ne!(
            base,
            turn_credential(b"secret", "u2", 1000).unwrap().1,
            "user-sensitive"
        );
    }

    #[test]
    fn db_str_roundtrips() {
        for s in [Initiated, Accepted, Connected, Ended, Rejected, Missed] {
            assert_eq!(s.as_db_str().parse::<CallStatus>().unwrap(), s);
        }
        assert!("bogus".parse::<CallStatus>().is_err());
    }
}
