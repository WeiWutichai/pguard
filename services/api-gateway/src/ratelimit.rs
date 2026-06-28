//! Per-IP rate limiting — the Redis I/O that backs `domain::ratelimit`.
//!
//! Fixed-window counter: `INCR ratelimit:{tier}:{window_id}:{ip}` with an EXPIRE on
//! first hit, then the pure [`decide`](crate::domain::ratelimit::decide) call. The
//! window id buckets time so a stale window's key TTLs away on its own.
//!
//! **Fail-OPEN on Redis error** (logged): a Redis hiccup must not take down all edge
//! traffic — availability is preferred over enforcement here (the backends still
//! validate auth + have their own app-layer limits). The client IP is the first hop of
//! `X-Forwarded-For`, falling back to the socket peer.

use std::net::SocketAddr;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::http::HeaderMap;
use redis::AsyncCommands;

use crate::domain::ratelimit::{decide, Limits, RateDecision};
use crate::domain::routing::Tier;

/// Resolve the client IP: first hop of `X-Forwarded-For`, else the socket peer addr.
///
/// The gateway is expected to sit behind a trusted L4/L7 LB that sets XFF; we take the
/// left-most (original client) entry. Falls back to the TCP peer when XFF is absent.
pub fn client_ip(headers: &HeaderMap, peer: SocketAddr) -> String {
    headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|xff| xff.split(',').next())
        .map(|first| first.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| peer.ip().to_string())
}

/// Check + record a request against the per-IP fixed-window limit for `tier`.
///
/// Returns the pure [`RateDecision`]. On any Redis error this **fails open**
/// (returns [`RateDecision::Allow`]) after logging — see module docs.
///
/// Generic over the connection type so the gateway passes its reconnecting
/// [`redis::aio::ConnectionManager`] (chaos case 3): after a Redis blip the limiter resumes
/// ENFORCING on the next request (no wedge), while still failing OPEN for the duration of the
/// outage (availability > enforcement at the edge).
#[tracing::instrument(skip(redis, limits), fields(tier = ?tier))]
pub async fn check<C>(redis: &mut C, limits: &Limits, tier: Tier, ip: &str) -> RateDecision
where
    C: redis::aio::ConnectionLike + Send,
{
    let window = limits.window_for(tier);

    // Bucket the current time into window-sized slots so each window has its own key.
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let window_id = now / window.seconds.max(1);

    let key = format!("ratelimit:{}:{}:{}", tier_tag(tier), window_id, ip);

    // INCR returns the post-increment count; set EXPIRE on the first hit so the key
    // self-cleans. Both steps fail open.
    let count: i64 = match redis.incr(&key, 1).await {
        Ok(c) => c,
        Err(e) => {
            tracing::warn!(error = %e, "rate-limit INCR failed; failing open");
            return RateDecision::Allow;
        }
    };
    if count == 1 {
        // Best-effort TTL; an EXPIRE failure only risks a stale counter, not a stuck one
        // long-term (next window uses a new key). Don't block traffic on it.
        if let Err(e) = redis.expire::<_, ()>(&key, window.seconds as i64).await {
            tracing::warn!(error = %e, "rate-limit EXPIRE failed");
        }
    }

    decide(count.max(0) as u32, window)
}

fn tier_tag(tier: Tier) -> &'static str {
    match tier {
        Tier::Auth => "auth",
        Tier::Otp => "otp",
        // Distinct tag → distinct Redis key, so verify counts in its own window (never shares
        // the `otp` send bucket).
        Tier::OtpVerify => "otpv",
        // Distinct tag → its own window, so reloading a captcha question never burns the `otp`
        // SMS-send bucket (the bug that locked users out of fetching a question).
        Tier::OtpChallenge => "otpc",
        Tier::Api => "api",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{IpAddr, Ipv4Addr};

    fn peer() -> SocketAddr {
        SocketAddr::new(IpAddr::V4(Ipv4Addr::new(10, 0, 0, 9)), 5555)
    }

    #[test]
    fn client_ip_uses_xff_first_hop() {
        let mut h = HeaderMap::new();
        h.insert(
            "x-forwarded-for",
            "203.0.113.7, 70.41.3.18, 150.172.238.178".parse().unwrap(),
        );
        assert_eq!(client_ip(&h, peer()), "203.0.113.7");
    }

    #[test]
    fn client_ip_trims_whitespace() {
        let mut h = HeaderMap::new();
        h.insert("x-forwarded-for", "  198.51.100.5  ".parse().unwrap());
        assert_eq!(client_ip(&h, peer()), "198.51.100.5");
    }

    #[test]
    fn client_ip_falls_back_to_peer() {
        assert_eq!(client_ip(&HeaderMap::new(), peer()), "10.0.0.9");
    }

    #[test]
    fn client_ip_falls_back_when_xff_empty() {
        let mut h = HeaderMap::new();
        h.insert("x-forwarded-for", "".parse().unwrap());
        assert_eq!(client_ip(&h, peer()), "10.0.0.9");
    }

    #[test]
    fn tier_tag_is_stable() {
        assert_eq!(tier_tag(Tier::Auth), "auth");
        assert_eq!(tier_tag(Tier::Otp), "otp");
        assert_eq!(tier_tag(Tier::OtpVerify), "otpv");
        assert_eq!(tier_tag(Tier::Api), "api");
    }

    // ----- reconnect / fail-open behaviour (hermetic, via the FlakyRedis double) -----

    /// Fail-OPEN during a Redis outage: a Redis error must not take down edge traffic — the
    /// limiter allows (logged) rather than 500-ing every request.
    #[tokio::test]
    async fn check_fails_open_when_redis_errors() {
        let mut redis = crate::test_support::FlakyRedis::always_broken();
        let d = check(&mut redis, &Limits::default(), Tier::Api, "203.0.113.7").await;
        assert!(
            matches!(d, RateDecision::Allow),
            "rate-limit MUST fail OPEN on a Redis error (availability > enforcement)"
        );
    }

    /// The whole point of the split: exhausting the OTP-SEND bucket must NOT deny OTP-VERIFY —
    /// the two tiers map to distinct Redis keys, so a challenge/request burst on a shared per-IP
    /// (carrier-NAT) window can't starve a legitimate code verification.
    #[tokio::test]
    async fn otp_send_and_verify_buckets_are_independent() {
        let mut redis = crate::test_support::CountingRedis::new();
        let limits = Limits {
            otp_per_min: 2,
            otp_verify_per_min: 2,
            otp_challenge_per_min: 2,
            auth_per_sec: 5,
            api_per_sec: 30,
        };
        let ip = "203.0.113.7";

        // Burn the send bucket past its max (2): the 3rd send is denied.
        for _ in 0..2 {
            assert!(matches!(
                check(&mut redis, &limits, Tier::Otp, ip).await,
                RateDecision::Allow
            ));
        }
        assert!(
            matches!(
                check(&mut redis, &limits, Tier::Otp, ip).await,
                RateDecision::Deny { .. }
            ),
            "send tier should be exhausted"
        );

        // Verify is on its OWN counter → still allowed despite the send-bucket exhaustion.
        assert!(
            matches!(
                check(&mut redis, &limits, Tier::OtpVerify, ip).await,
                RateDecision::Allow
            ),
            "verify MUST NOT be starved by send-tier exhaustion"
        );
    }

    /// Self-heal: while down it fails open (Allow); once Redis is back the INCR returns a count
    /// well over the limit, so the limiter ENFORCES again (Deny) — proving it re-queries Redis
    /// after recovery instead of staying stuck in fail-open.
    #[tokio::test]
    async fn check_enforces_again_after_recovery() {
        // 1 command errors (outage), then INCR replies 1_000_000 (Redis back, far over any limit).
        let mut redis = crate::test_support::FlakyRedis::new(1, 1_000_000);
        assert!(
            matches!(
                check(&mut redis, &Limits::default(), Tier::Api, "203.0.113.7").await,
                RateDecision::Allow
            ),
            "fail-open during the outage"
        );
        assert!(
            matches!(
                check(&mut redis, &Limits::default(), Tier::Api, "203.0.113.7").await,
                RateDecision::Deny { .. }
            ),
            "after recovery the limiter enforces again (not stuck fail-open)"
        );
    }
}
