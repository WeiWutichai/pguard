//! PURE force-revoke-all helper (CLAUDE.md "Token revocation": per-user
//! `token_revocation_version` + jti blocklist).
//!
//! Access tokens are stamped at issuance with the user's `token_revocation_version`.
//! Bumping the stored version (on logout-all / account compromise) instantly
//! invalidates every previously-issued access token without a per-token blocklist
//! entry: a validator simply compares the version carried in the token against the
//! current stored version. This module is the pure comparison + the next-version
//! computation; the actual DB bump lives in `repo`.

/// True if a token minted at `token_version` is still honoured given the user's current
/// `current_version`. A token is rejected once the user's version has moved past it.
pub fn token_version_is_current(token_version: i32, current_version: i32) -> bool {
    token_version >= current_version
}

/// The version to write when force-revoking all of a user's tokens (monotonic bump).
/// Saturating so a maxed-out counter cannot wrap to a value that would silently
/// re-honour old tokens.
pub fn next_revocation_version(current: i32) -> i32 {
    current.saturating_add(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_at_current_version_is_honoured() {
        assert!(token_version_is_current(3, 3));
    }

    #[test]
    fn token_minted_after_a_bump_is_honoured() {
        // Edge: a token at a HIGHER version than stored (shouldn't normally happen, but
        // must not be spuriously rejected).
        assert!(token_version_is_current(4, 3));
    }

    #[test]
    fn token_below_current_version_is_revoked() {
        // The whole point of force-revoke-all: every token at the old version dies.
        assert!(!token_version_is_current(2, 3));
    }

    #[test]
    fn bump_increments() {
        assert_eq!(next_revocation_version(0), 1);
        assert_eq!(next_revocation_version(41), 42);
    }

    #[test]
    fn bump_saturates_at_max() {
        assert_eq!(next_revocation_version(i32::MAX), i32::MAX);
    }

    #[test]
    fn bumped_version_revokes_a_token_at_the_old_version() {
        let old = 5;
        let bumped = next_revocation_version(old);
        // A token stamped with `old` is no longer current after the bump.
        assert!(!token_version_is_current(old, bumped));
    }
}
