//! PURE decision for per-account failed-login lockout — no I/O. The API layer owns the Redis
//! counter (`login_fail:{id}` within a rolling window) and the lock key (`login_lock:{id}`); this
//! function just maps a post-increment consecutive-failure count to a lock duration.
//!
//! Why this exists: the mobile app enforces a PIN lockout/wipe entirely client-side, so an attacker
//! who scripts `POST /auth/login` directly (bypassing the app) faced ONLY the gateway's per-IP rate
//! limit — with rotating IPs the 10^6 six-digit-PIN space is exhaustible because nothing locked the
//! ACCOUNT. This adds a server-side, per-account throttle independent of the edge per-IP limit.

/// Consecutive failed-login attempts (within the window) that are allowed before the first lock.
pub const LOGIN_FAIL_THRESHOLD: i64 = 5;
/// Rolling window (seconds) over which consecutive failures accumulate. A gap longer than this
/// lets the counter expire, so an occasional fat-finger never compounds toward a lock.
pub const LOGIN_FAIL_WINDOW_SECS: u64 = 900; // 15 min
/// Hard cap on a single lock so a locked-out legitimate user always recovers (and a targeted
/// lock-out DoS is bounded). The gateway per-IP limit bounds how fast anyone drives the counter.
pub const LOGIN_LOCK_MAX_SECS: u64 = 1800; // 30 min

/// Given the post-increment failure count, return `Some(lock_secs)` when this attempt should arm
/// (or refresh) an account lock, or `None` while still under the threshold. Escalates 1min → 2 → 4
/// → … doubling per failure past the threshold, capped at [`LOGIN_LOCK_MAX_SECS`]. Because the API
/// layer returns early (without incrementing) while a lock is live, `fail_count` advances by one per
/// UNLOCKED attempt, so each post-lock retry lands on the next-higher tier.
pub fn login_lock_secs(fail_count: i64) -> Option<u64> {
    if fail_count < LOGIN_FAIL_THRESHOLD {
        return None;
    }
    let over = (fail_count - LOGIN_FAIL_THRESHOLD) as u32; // 0 at the threshold
                                                           // 60 * 2^over, saturating, then capped.
    let secs = 60u64.saturating_mul(1u64.checked_shl(over).unwrap_or(u64::MAX));
    Some(secs.min(LOGIN_LOCK_MAX_SECS))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn under_threshold_never_locks() {
        for n in 0..LOGIN_FAIL_THRESHOLD {
            assert_eq!(login_lock_secs(n), None, "n={n} must not lock");
        }
    }

    #[test]
    fn first_lock_is_one_minute_then_doubles() {
        assert_eq!(login_lock_secs(5), Some(60));
        assert_eq!(login_lock_secs(6), Some(120));
        assert_eq!(login_lock_secs(7), Some(240));
        assert_eq!(login_lock_secs(8), Some(480));
        assert_eq!(login_lock_secs(9), Some(960));
    }

    #[test]
    fn escalation_is_capped_and_never_overflows() {
        assert_eq!(login_lock_secs(10), Some(LOGIN_LOCK_MAX_SECS));
        // Far past the doubling range must saturate to the cap, not panic/overflow.
        assert_eq!(login_lock_secs(1000), Some(LOGIN_LOCK_MAX_SECS));
        assert_eq!(login_lock_secs(i64::MAX), Some(LOGIN_LOCK_MAX_SECS));
    }
}
