//! PURE refresh-token rotation decision (RFC 6749 §6 + reuse detection).
//!
//! The opaque refresh token the client holds is `"{rotation_id}.{secret}"`. On refresh,
//! `repo` looks the row up by `rotation_id` and Argon2-verifies the secret, then asks
//! this module — given the stored row's state and the clock — what to do. Keeping the
//! decision here (no DB, no time-of-day reads passed in explicitly) makes the security-
//! critical branch (reuse => kill the family) fully unit-testable.

use chrono::{DateTime, Utc};

/// The state of a stored refresh-token row relevant to the rotation decision.
/// Built by `repo` from a DB row; this module never touches the DB itself.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StoredRefresh {
    /// Has this exact token already been rotated away / explicitly revoked?
    pub revoked: bool,
    /// Absolute expiry of this token.
    pub expires_at: DateTime<Utc>,
}

/// What the caller should do after presenting a refresh token.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RotationDecision {
    /// Valid live token — issue a new access + refresh in the SAME family, mark this
    /// row revoked.
    Rotate,
    /// The presented token was already revoked (i.e. it was previously rotated, or its
    /// family was killed) yet someone is presenting it again => token REUSE. The caller
    /// MUST revoke the entire family and reject with 401.
    ReuseDetected,
    /// The token is past its absolute expiry — reject (no family kill; benign).
    Expired,
}

/// Decide the outcome for a presented refresh token whose secret already verified and
/// whose row was found. `now` is injected so the decision is deterministic in tests.
///
/// Order matters: reuse is checked BEFORE expiry, because a revoked-but-not-yet-expired
/// token being replayed is the attack signal we must act on.
pub fn decide(stored: &StoredRefresh, now: DateTime<Utc>) -> RotationDecision {
    if stored.revoked {
        return RotationDecision::ReuseDetected;
    }
    if stored.expires_at <= now {
        return RotationDecision::Expired;
    }
    RotationDecision::Rotate
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeDelta;

    fn now() -> DateTime<Utc> {
        Utc::now()
    }

    #[test]
    fn live_unrevoked_token_rotates() {
        let stored = StoredRefresh {
            revoked: false,
            expires_at: now() + TimeDelta::days(1),
        };
        assert_eq!(decide(&stored, now()), RotationDecision::Rotate);
    }

    #[test]
    fn replaying_a_revoked_token_is_reuse() {
        // This is the core RFC 6749 §6 reuse-detection case.
        let stored = StoredRefresh {
            revoked: true,
            expires_at: now() + TimeDelta::days(1),
        };
        assert_eq!(decide(&stored, now()), RotationDecision::ReuseDetected);
    }

    #[test]
    fn reuse_wins_over_expiry_when_both_apply() {
        // A revoked AND expired token still reports reuse — the security signal must not
        // be masked by expiry.
        let stored = StoredRefresh {
            revoked: true,
            expires_at: now() - TimeDelta::days(1),
        };
        assert_eq!(decide(&stored, now()), RotationDecision::ReuseDetected);
    }

    #[test]
    fn expired_live_token_is_expired_not_reuse() {
        let stored = StoredRefresh {
            revoked: false,
            expires_at: now() - TimeDelta::seconds(1),
        };
        assert_eq!(decide(&stored, now()), RotationDecision::Expired);
    }

    #[test]
    fn exactly_at_expiry_is_expired() {
        let t = now();
        let stored = StoredRefresh {
            revoked: false,
            expires_at: t,
        };
        assert_eq!(decide(&stored, t), RotationDecision::Expired);
    }
}
