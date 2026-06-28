//! PURE rate-limit decision + tier→limit config.
//!
//! The Redis I/O (the fixed-window INCR + EXPIRE that produces `count`) lives in the
//! `ratelimit` middleware; here we only decide allow/deny given a count and a limit,
//! and hold the per-tier limits (env-overridable at startup).
//!
//! Ports the *intent* of v1's nginx zones (`../guard-dispatch/nginx/nginx.conf`):
//! `auth_limit 5r/s`, `otp_limit 10r/m`, `api_limit 30r/s`.

use crate::domain::routing::Tier;

/// Per-tier limits + window sizes, resolved from env at startup.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Limits {
    /// OTP send/challenge: max requests per 60s window (v1 `otp_limit 10r/m`).
    pub otp_per_min: u32,
    /// OTP verify: max requests per 60s window. Split from [`Self::otp_per_min`] so verify has
    /// its own per-IP budget and can't be starved by challenge/request churn (carrier-NAT). More
    /// generous than send because verify is cheap and the otp service caps attempts per code.
    pub otp_verify_per_min: u32,
    /// OTP CHALLENGE: max `GET /otp/challenge` per 60s window. Generous — minting a captcha is cheap
    /// (no SMS) and reloaded routinely, so it has its OWN per-IP budget and never burns the SMS-send
    /// window of [`Self::otp_per_min`]. See [`crate::domain::routing::Tier::OtpChallenge`].
    pub otp_challenge_per_min: u32,
    /// Auth: max requests per 1s window (v1 `auth_limit 5r/s`).
    pub auth_per_sec: u32,
    /// Api: max requests per 1s window (v1 `api_limit 30r/s`).
    pub api_per_sec: u32,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            otp_per_min: 10,
            otp_verify_per_min: 30,
            otp_challenge_per_min: 30,
            auth_per_sec: 5,
            api_per_sec: 30,
        }
    }
}

/// The window (in seconds) + max count for a given tier. The window length is the
/// Redis key TTL; `max` is the count above which requests are denied.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Window {
    pub seconds: u64,
    pub max: u32,
}

impl Limits {
    /// Resolve the fixed-window parameters for a routing tier.
    pub fn window_for(&self, tier: Tier) -> Window {
        match tier {
            Tier::Otp => Window {
                seconds: 60,
                max: self.otp_per_min,
            },
            Tier::OtpVerify => Window {
                seconds: 60,
                max: self.otp_verify_per_min,
            },
            Tier::OtpChallenge => Window {
                seconds: 60,
                max: self.otp_challenge_per_min,
            },
            Tier::Auth => Window {
                seconds: 1,
                max: self.auth_per_sec,
            },
            Tier::Api => Window {
                seconds: 1,
                max: self.api_per_sec,
            },
        }
    }
}

/// Outcome of a fixed-window check, given the post-increment count for the window.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RateDecision {
    Allow,
    /// Denied; suggest `Retry-After` seconds (the remaining window).
    Deny {
        retry_after_secs: u64,
    },
}

/// Decide allow/deny for a fixed window. `count` is the value AFTER incrementing this
/// request (so the first request in a window has `count == 1`). Requests are allowed
/// while `count <= window.max`.
pub fn decide(count: u32, window: Window) -> RateDecision {
    if count <= window.max {
        RateDecision::Allow
    } else {
        RateDecision::Deny {
            retry_after_secs: window.seconds,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_up_to_and_including_max() {
        let w = Window { seconds: 1, max: 5 };
        for c in 1..=5 {
            assert_eq!(decide(c, w), RateDecision::Allow, "count {c} should allow");
        }
    }

    #[test]
    fn denies_above_max_with_retry_after() {
        let w = Window {
            seconds: 60,
            max: 10,
        };
        assert_eq!(
            decide(11, w),
            RateDecision::Deny {
                retry_after_secs: 60
            }
        );
        assert_eq!(
            decide(1000, w),
            RateDecision::Deny {
                retry_after_secs: 60
            }
        );
    }

    #[test]
    fn first_request_is_allowed() {
        // count == 1 is the first request in a fresh window.
        assert_eq!(
            decide(1, Window { seconds: 1, max: 1 }),
            RateDecision::Allow
        );
        // The second request in a max=1 window is denied.
        assert_eq!(
            decide(2, Window { seconds: 1, max: 1 }),
            RateDecision::Deny {
                retry_after_secs: 1
            }
        );
    }

    #[test]
    fn default_limits_match_v1_intent() {
        let l = Limits::default();
        assert_eq!(l.otp_per_min, 10);
        assert_eq!(l.otp_verify_per_min, 30);
        assert_eq!(l.otp_challenge_per_min, 30);
        assert_eq!(l.auth_per_sec, 5);
        assert_eq!(l.api_per_sec, 30);
    }

    #[test]
    fn window_for_maps_tier_to_v1_zones() {
        let l = Limits::default();
        assert_eq!(
            l.window_for(Tier::Otp),
            Window {
                seconds: 60,
                max: 10
            }
        );
        assert_eq!(
            l.window_for(Tier::OtpVerify),
            Window {
                seconds: 60,
                max: 30
            }
        );
        assert_eq!(
            l.window_for(Tier::OtpChallenge),
            Window {
                seconds: 60,
                max: 30
            }
        );
        assert_eq!(l.window_for(Tier::Auth), Window { seconds: 1, max: 5 });
        assert_eq!(
            l.window_for(Tier::Api),
            Window {
                seconds: 1,
                max: 30
            }
        );
    }

    #[test]
    fn custom_limits_flow_through_window_for() {
        let l = Limits {
            otp_per_min: 3,
            otp_verify_per_min: 7,
            otp_challenge_per_min: 5,
            auth_per_sec: 2,
            api_per_sec: 100,
        };
        assert_eq!(l.window_for(Tier::Otp).max, 3);
        assert_eq!(l.window_for(Tier::OtpChallenge).max, 5);
        assert_eq!(l.window_for(Tier::OtpVerify).max, 7);
        assert_eq!(l.window_for(Tier::Auth).max, 2);
        assert_eq!(l.window_for(Tier::Api).max, 100);
    }
}
