//! Tiered-lockout DECISION — PURE. Models v1's `request_otp` B2 lockout
//! (`../guard-dispatch/services/auth/src/service.rs`) as a function over counts/TTLs so
//! the policy is unit-testable without Redis. The API layer reads the counters/TTL from
//! Redis and *applies* the returned decision; this module decides nothing about I/O.
//!
//! Two independent decisions:
//!   - [`existing_lock_decision`] — given the TTL of an already-set `otp_lock:{phone}`,
//!     which tier (burst vs admin-contact) is active, or none.
//!   - [`lockout_decision`] — given the short-window burst count AND the 24h daily count after
//!     INCR, whether to allow the request, or trip a new burst/admin lock.

/// Below this many requests IN THE BURST WINDOW no burst lock trips; at this count it trips.
pub const BURST_THRESHOLD: i64 = 3;
/// Burst lock duration (10 min). Also the TTL discriminator: a live lock with TTL
/// ≤ this is the burst tier; longer is the admin-contact tier.
pub const BURST_LOCK_SECS: u64 = 600;
/// The rolling window (10 min) over which burst requests are counted — SEPARATE from the 24h
/// daily counter. Keying the burst trip on the 24h count made a phone re-trip the 10-min lock on
/// EVERY request for the rest of the day after just [`BURST_THRESHOLD`] requests (a day-long
/// lockout hidden behind a "try again in 10 minutes" message). A short rolling window self-resets,
/// so a legit user recovers after one cool-off while the daily cap still bounds sustained abuse.
pub const BURST_WINDOW_SECS: u64 = 600;
/// Admin-contact lock duration (24h) — once tripped, no further SMS is sent.
pub const ADMIN_LOCK_SECS: u64 = 86_400;

/// What an already-present `otp_lock:{phone}` means, derived from its remaining TTL.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ActiveLock {
    /// No active lock (TTL ≤ 0 — key absent or expired).
    None,
    /// Burst tier — short cool-off; report the remaining minutes to the user.
    Burst { remaining_minutes: i64 },
    /// Admin-contact tier — user must contact staff.
    AdminContact,
}

/// Interpret an existing `otp_lock:{phone}` lock from its stored VALUE + TTL. The value now names
/// the tier explicitly (`"admin"` / `"burst"`), so the burst/admin distinction no longer depends on
/// TTL magnitude — which mis-reported a 24h admin lock as a burst lock during its final 10 minutes
/// once its TTL fell below the burst duration (deep-review). TTL is used only for the burst tier's
/// remaining-minutes display. A legacy `"1"` value (set by a pre-upgrade instance) falls back to the
/// old TTL-magnitude heuristic until it expires, so the change is backward-compatible.
pub fn existing_lock_decision(lock_value: Option<&str>, lock_ttl: i64) -> ActiveLock {
    if lock_ttl <= 0 {
        return ActiveLock::None;
    }
    // Round up to whole minutes (ceil) — matches v1's `(ttl + 59) / 60`.
    let remaining_minutes = (lock_ttl + 59) / 60;
    match lock_value {
        None => ActiveLock::None,
        Some("admin") => ActiveLock::AdminContact,
        Some("burst") => ActiveLock::Burst { remaining_minutes },
        // Legacy/unknown value → old TTL-magnitude heuristic (transient; the lock self-expires).
        _ if lock_ttl > BURST_LOCK_SECS as i64 => ActiveLock::AdminContact,
        _ => ActiveLock::Burst { remaining_minutes },
    }
}

/// The decision after counting today's request (the value returned by Redis INCR).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LockoutDecision {
    /// Within limits — proceed to generate + send the OTP.
    Allow,
    /// Crossed the daily limit — set an admin-contact lock and reject (no SMS sent).
    TripAdminLock { lock_secs: u64 },
    /// Crossed the burst threshold — set a burst lock and reject.
    TripBurstLock { lock_secs: u64 },
}

/// Decide what to do for a request, given the post-INCR `burst_count` over the last
/// [`BURST_WINDOW_SECS`] and the post-INCR `daily_count` over 24h, against the configured
/// `daily_limit`. Admin tier is checked FIRST (against the daily total) so we don't waste SMS
/// quota; the burst tier is driven by the SHORT-window count — NOT the daily total — so it
/// self-resets and never becomes a day-long lock. Passing the daily count as the burst count
/// (the old signature) is exactly the bug this fix removes.
pub fn lockout_decision(burst_count: i64, daily_count: i64, daily_limit: i64) -> LockoutDecision {
    if daily_count >= daily_limit {
        LockoutDecision::TripAdminLock {
            lock_secs: ADMIN_LOCK_SECS,
        }
    } else if burst_count >= BURST_THRESHOLD {
        LockoutDecision::TripBurstLock {
            lock_secs: BURST_LOCK_SECS,
        }
    } else {
        LockoutDecision::Allow
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ----- existing_lock_decision -----

    #[test]
    fn no_lock_when_ttl_non_positive_or_no_value() {
        assert_eq!(existing_lock_decision(Some("burst"), 0), ActiveLock::None);
        assert_eq!(existing_lock_decision(Some("admin"), -1), ActiveLock::None);
        assert_eq!(existing_lock_decision(None, 100), ActiveLock::None);
    }

    #[test]
    fn burst_value_reports_ceil_minutes() {
        assert_eq!(
            existing_lock_decision(Some("burst"), 600),
            ActiveLock::Burst {
                remaining_minutes: 10
            }
        );
        assert_eq!(
            existing_lock_decision(Some("burst"), 61),
            ActiveLock::Burst {
                remaining_minutes: 2
            }
        );
        assert_eq!(
            existing_lock_decision(Some("burst"), 1),
            ActiveLock::Burst {
                remaining_minutes: 1
            }
        );
    }

    #[test]
    fn admin_value_stays_admin_even_in_its_final_minutes() {
        // THE FIX: an admin lock whose TTL has fallen BELOW the burst window is STILL admin (the
        // value names the tier), not misreported as a burst lock (deep-review).
        assert_eq!(
            existing_lock_decision(Some("admin"), 5),
            ActiveLock::AdminContact
        );
        assert_eq!(
            existing_lock_decision(Some("admin"), ADMIN_LOCK_SECS as i64),
            ActiveLock::AdminContact
        );
    }

    #[test]
    fn legacy_value_falls_back_to_ttl_magnitude() {
        // A pre-upgrade `"1"` value uses the old TTL heuristic until it expires (backward-compat).
        assert_eq!(
            existing_lock_decision(Some("1"), 601),
            ActiveLock::AdminContact
        );
        assert_eq!(
            existing_lock_decision(Some("1"), 300),
            ActiveLock::Burst {
                remaining_minutes: 5
            }
        );
    }

    // ----- lockout_decision -----

    #[test]
    fn allows_below_burst_threshold() {
        // (burst_count, daily_count, daily_limit)
        assert_eq!(lockout_decision(1, 1, 10), LockoutDecision::Allow);
        assert_eq!(lockout_decision(2, 2, 10), LockoutDecision::Allow);
    }

    #[test]
    fn trips_burst_at_threshold() {
        // Burst trips on the SHORT-WINDOW count crossing the threshold (daily still below limit).
        assert_eq!(
            lockout_decision(BURST_THRESHOLD, BURST_THRESHOLD, 10),
            LockoutDecision::TripBurstLock {
                lock_secs: BURST_LOCK_SECS
            }
        );
    }

    #[test]
    fn burst_does_not_trip_from_the_daily_count_alone() {
        // THE regression: a high 24h daily count with a FRESH burst window (count 1, e.g. the first
        // request after a burst lock expired) must be ALLOWED — the old code keyed the burst trip
        // on the daily count, so daily=9 re-tripped the 10-min lock forever, locking the phone for
        // the whole day. Now only the short-window count trips burst.
        assert_eq!(lockout_decision(1, 9, 10), LockoutDecision::Allow);
        assert_eq!(lockout_decision(2, 8, 10), LockoutDecision::Allow);
    }

    #[test]
    fn trips_admin_at_daily_limit() {
        // Admin tier is the 24h total hitting the limit — regardless of the burst window (0 here).
        assert_eq!(
            lockout_decision(0, 10, 10),
            LockoutDecision::TripAdminLock {
                lock_secs: ADMIN_LOCK_SECS
            }
        );
    }

    #[test]
    fn admin_tier_takes_precedence_over_burst() {
        // Both thresholds crossed: admin tier wins (don't waste SMS quota).
        assert_eq!(
            lockout_decision(100, 100, 10),
            LockoutDecision::TripAdminLock {
                lock_secs: ADMIN_LOCK_SECS
            }
        );
    }
}
