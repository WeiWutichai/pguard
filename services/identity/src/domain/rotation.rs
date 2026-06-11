//! PURE refresh-token rotation decision (RFC 6749 §6 + reuse detection).
//!
//! The opaque refresh token the client holds is `"{rotation_id}.{secret}"`. On refresh,
//! `repo` looks the row up by `rotation_id` and Argon2-verifies the secret, then asks
//! this module — given the stored row's state and the clock — what to do. Keeping the
//! decision here (no DB, no time-of-day reads passed in explicitly) makes the security-
//! critical branch (reuse => kill the family) fully unit-testable.

use chrono::{DateTime, TimeDelta, Utc};

/// Absolute rotation ceiling (days). A family that has been continuously rotated for longer than
/// this must re-authenticate, so a single leaked-then-rotated lineage cannot live indefinitely
/// past the per-token 7-day expiry (RFC-6749-aligned hardening). Benign (force re-login), so it
/// does NOT kill the family. Lives here (not the api layer) so the ceiling is part of the pure,
/// unit-testable rotation decision.
pub const FAMILY_MAX_DAYS: i64 = 30;

/// The state of a stored refresh-token row relevant to the rotation decision.
/// Built by `repo` from a DB row; this module never touches the DB itself.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StoredRefresh {
    /// Has this exact token already been rotated away / explicitly revoked?
    pub revoked: bool,
    /// Absolute expiry of this token.
    pub expires_at: DateTime<Utc>,
    /// When the FAMILY was first issued (oldest row's `created_at`). Drives the absolute
    /// rotation ceiling so a continuously-rotated family can't live forever.
    pub family_started_at: DateTime<Utc>,
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
    /// The family has been rotating for longer than [`FAMILY_MAX_DAYS`] — reject and force
    /// re-authentication. Benign: NO family kill (it is not the reuse signal), generic 401.
    CeilingExceeded,
}

/// Decide the outcome for a presented refresh token whose secret already verified and
/// whose row was found. `now` is injected so the decision is deterministic in tests.
///
/// Order matters: reuse is checked BEFORE expiry (a revoked-but-not-yet-expired token being
/// replayed is the attack signal we must act on), and the ceiling is checked LAST — only a live,
/// unrevoked, unexpired token can hit it, exactly as the previous inline api-layer check did
/// (it only ran in the would-rotate branch). Reuse/expiry are never masked by the ceiling.
pub fn decide(stored: &StoredRefresh, now: DateTime<Utc>) -> RotationDecision {
    if stored.revoked {
        return RotationDecision::ReuseDetected;
    }
    if stored.expires_at <= now {
        return RotationDecision::Expired;
    }
    if now - stored.family_started_at > TimeDelta::days(FAMILY_MAX_DAYS) {
        return RotationDecision::CeilingExceeded;
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

    /// A live token in a young family (recent `family_started_at` so the ceiling never fires) —
    /// the baseline used by the reuse/expiry cases that don't care about the ceiling.
    fn young(revoked: bool, expires_at: DateTime<Utc>) -> StoredRefresh {
        StoredRefresh {
            revoked,
            expires_at,
            family_started_at: now(),
        }
    }

    #[test]
    fn live_unrevoked_token_rotates() {
        let stored = young(false, now() + TimeDelta::days(1));
        assert_eq!(decide(&stored, now()), RotationDecision::Rotate);
    }

    #[test]
    fn replaying_a_revoked_token_is_reuse() {
        // This is the core RFC 6749 §6 reuse-detection case.
        let stored = young(true, now() + TimeDelta::days(1));
        assert_eq!(decide(&stored, now()), RotationDecision::ReuseDetected);
    }

    #[test]
    fn reuse_wins_over_expiry_when_both_apply() {
        // A revoked AND expired token still reports reuse — the security signal must not
        // be masked by expiry.
        let stored = young(true, now() - TimeDelta::days(1));
        assert_eq!(decide(&stored, now()), RotationDecision::ReuseDetected);
    }

    #[test]
    fn expired_live_token_is_expired_not_reuse() {
        let stored = young(false, now() - TimeDelta::seconds(1));
        assert_eq!(decide(&stored, now()), RotationDecision::Expired);
    }

    #[test]
    fn exactly_at_expiry_is_expired() {
        let t = now();
        let stored = young(false, t);
        assert_eq!(decide(&stored, t), RotationDecision::Expired);
    }

    // ── absolute rotation ceiling (moved here from the api layer; behavior-identical) ──

    #[test]
    fn live_token_in_old_family_hits_the_ceiling() {
        // Unrevoked, unexpired, but the family is older than FAMILY_MAX_DAYS → force re-login.
        let stored = StoredRefresh {
            revoked: false,
            expires_at: now() + TimeDelta::days(1),
            family_started_at: now() - TimeDelta::days(FAMILY_MAX_DAYS + 1),
        };
        assert_eq!(decide(&stored, now()), RotationDecision::CeilingExceeded);
    }

    #[test]
    fn family_just_under_the_ceiling_still_rotates() {
        let stored = StoredRefresh {
            revoked: false,
            expires_at: now() + TimeDelta::days(1),
            family_started_at: now() - TimeDelta::days(FAMILY_MAX_DAYS - 1),
        };
        assert_eq!(decide(&stored, now()), RotationDecision::Rotate);
    }

    #[test]
    fn exactly_at_the_ceiling_boundary_still_rotates() {
        // The comparison is strict `>`, so a family aged EXACTLY FAMILY_MAX_DAYS is allowed —
        // matching the original inline check (which also used `>`).
        let t = now();
        let stored = StoredRefresh {
            revoked: false,
            expires_at: t + TimeDelta::days(1),
            family_started_at: t - TimeDelta::days(FAMILY_MAX_DAYS),
        };
        assert_eq!(decide(&stored, t), RotationDecision::Rotate);
    }

    #[test]
    fn reuse_wins_over_ceiling() {
        // A revoked token in an old family is REUSE, never CeilingExceeded — the attack signal
        // must not be downgraded to a benign re-login.
        let stored = StoredRefresh {
            revoked: true,
            expires_at: now() + TimeDelta::days(1),
            family_started_at: now() - TimeDelta::days(FAMILY_MAX_DAYS + 5),
        };
        assert_eq!(decide(&stored, now()), RotationDecision::ReuseDetected);
    }

    #[test]
    fn expiry_wins_over_ceiling() {
        // An expired token in an old family reports Expired (expiry is checked before the
        // ceiling, exactly as before — the ceiling only ran in the would-rotate branch).
        let stored = StoredRefresh {
            revoked: false,
            expires_at: now() - TimeDelta::seconds(1),
            family_started_at: now() - TimeDelta::days(FAMILY_MAX_DAYS + 5),
        };
        assert_eq!(decide(&stored, now()), RotationDecision::Expired);
    }
}
