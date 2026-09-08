//! PURE presence domain — no DB, no HTTP, no NATS, no Redis. 100% unit-testable.
//!
//! The GPS validation/sanitization, the per-connection rate-limit decision, the WS keep-alive
//! timing, and the online/freshness rules — all the logic the WS handler + read APIs orchestrate
//! but never re-encode. Ported (and tightened for v2) from v1
//! `../guard-dispatch/services/tracking/src/models.rs` (`GpsUpdate::validate`) and
//! `handlers.rs` (1/sec rate limit, 30s/10s ping-pong reaper).

use std::time::Duration;

use chrono::{DateTime, TimeDelta, Utc};
use serde::Deserialize;
use serde_json::Value;
use uuid::Uuid;

// ----- WS timing + rate-limit constants (mirrors v1 handlers.rs:53-63) -----

/// Server rate limit: at most one GPS fix per second per connection; excess is dropped.
pub const GPS_MIN_INTERVAL: Duration = Duration::from_secs(1);
/// Keep-alive heartbeat rate limit: at most one per 10s per connection.
pub const HEARTBEAT_MIN_INTERVAL: Duration = Duration::from_secs(10);
/// Server sends a liveness Ping after this much idle time.
pub const PING_INTERVAL: Duration = Duration::from_secs(30);
/// A Pong must arrive within this window of a Ping, else the socket is a zombie.
pub const PONG_TIMEOUT: Duration = Duration::from_secs(10);
/// Discovery freshness window: a guard is "live" only if its last fix is newer than this.
pub const FRESHNESS_MINUTES: i64 = 5;
/// SESSION-liveness window for the discovery offerable set — how long a row may claim a live
/// session without the server hearing ANYTHING from it (fix, heartbeat, or Pong).
///
/// This is NOT the GPS freshness rule above and must never be confused with it: `recorded_at`
/// only advances on a real fix, so gating discovery on it drops a STATIONARY online guard (the
/// movement-gated uplink — bug B, `2cd5554`). `last_seen_at` advances on any inbound frame, so a
/// guard standing still with the socket up stays offerable while a row whose service died stops
/// being offerable on its own.
///
/// 2 minutes is comfortably above the worst case a HEALTHY session can go silent —
/// [`PING_INTERVAL`] (30s) + [`PONG_TIMEOUT`] (10s) before the reaper kills the socket anyway,
/// plus the write throttle [`SEEN_TOUCH_INTERVAL`] (30s) — so it can only fire on a row nothing
/// is driving any more.
pub const SESSION_LIVENESS_MINUTES: i64 = 2;
/// Write throttle for the `last_seen_at` touch: at most one per connection per this interval,
/// regardless of inbound frame rate. Bounds the write amplification of session liveness to
/// ~1 single-row UPDATE per live guard per 30s (the column is deliberately unindexed so those
/// stay HOT updates).
pub const SEEN_TOUCH_INTERVAL: Duration = Duration::from_secs(30);
/// Hard ceiling on TOTAL inbound WS frames per second per connection (all frame types, counted
/// BEFORE parse). A backstop against an authenticated guard flooding frames to burn CPU/bandwidth
/// (v1 audit risk #13 — the 1/sec GPS gate + 1/10s heartbeat gate run AFTER parse, so they do not
/// bound junk/parse-fail frames). Set far above any legitimate client (≤1 GPS/s + ≤1 heartbeat/10s
/// + the odd control frame), so it only trips a clear flood; on breach the socket is closed.
pub const MAX_INBOUND_FRAMES_PER_SEC: u32 = 20;

// ----- GPS update (inbound frame) -----

/// A GPS fix sent by a guard's device over the WS. Deserialized from a bare coordinate object
/// (no `type` field — a frame carrying `type:"heartbeat"` is classified as a heartbeat instead;
/// see [`classify`]).
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct GpsUpdate {
    pub lat: f64,
    pub lng: f64,
    #[serde(default)]
    pub accuracy: Option<f32>,
    #[serde(default)]
    pub heading: Option<f32>,
    #[serde(default)]
    pub speed: Option<f32>,
    /// Optional booking the fix relates to. NON-AUTHORITATIVE and intentionally inert in this
    /// slice: it is never persisted and MUST NEVER feed an authz/attribution decision (doing so
    /// would be a GPS-spoofing vector — v1 audit risk #6). Attribution keys on the JWT `guard_id`.
    #[serde(default)]
    pub assignment_id: Option<Uuid>,
}

impl GpsUpdate {
    /// HARD-validate the coordinate and SANITIZE the optional fields, returning a cleaned copy.
    ///
    /// lat/lng are rejected (whole update dropped) when non-finite, out of WGS84 range, or at
    /// the null-island `(0,0)`. The optional fields (`accuracy`/`heading`/`speed`) are *never*
    /// a reason to reject — a `NaN`/`Infinite`/out-of-range value (iOS reports `-1` for unknown
    /// accuracy) is simply treated as `None`, so a good fix with a junk accuracy still lands.
    pub fn validated(&self) -> Result<GpsUpdate, &'static str> {
        if !self.lat.is_finite() || !(-90.0..=90.0).contains(&self.lat) {
            return Err("lat must be a finite value between -90 and 90");
        }
        if !self.lng.is_finite() || !(-180.0..=180.0).contains(&self.lng) {
            return Err("lng must be a finite value between -180 and 180");
        }
        if self.lat == 0.0 && self.lng == 0.0 {
            return Err("lat/lng at (0,0) is rejected as invalid");
        }
        Ok(GpsUpdate {
            lat: self.lat,
            lng: self.lng,
            accuracy: sane(self.accuracy, 0.0, 10_000.0),
            heading: sane(self.heading, 0.0, 360.0),
            speed: sane(self.speed, 0.0, 500.0),
            assignment_id: self.assignment_id,
        })
    }
}

/// Keep an optional sensor reading only when it is finite and within `[lo, hi]`; otherwise drop
/// it to `None` (NaN/Infinite/out-of-range/iOS `-1` → unknown).
fn sane(v: Option<f32>, lo: f32, hi: f32) -> Option<f32> {
    v.filter(|x| x.is_finite() && (lo..=hi).contains(x))
}

// ----- Inbound frame classification -----

/// A parsed client frame. The classification rule is fixed: a JSON object with
/// `"type":"heartbeat"` is a [`ClientFrame::Heartbeat`], one with `"type":"availability"` is an
/// [`ClientFrame::Availability`]; anything else is parsed as a [`GpsUpdate`] (the GPS frame does
/// carry `"type":"location"`, which is simply ignored by the deserializer). This ordering is what
/// lets the handler run the heartbeat/availability paths BEFORE the GPS 1/sec gate (so neither
/// eats a GPS slot).
#[derive(Debug, Clone, PartialEq)]
pub enum ClientFrame {
    Heartbeat,
    /// The guard's "พร้อมรับงาน" toggle, declared on the session. This — NOT the mere existence
    /// of a GPS socket — is what makes the guard offerable to customers. Carried on the WS rather
    /// than a REST flag so intent CANNOT outlive the connection that declared it: a killed app
    /// leaves no durable "available" behind for the next session (opened by a job-tracking lease
    /// alone) to inherit.
    Availability(bool),
    Gps(GpsUpdate),
}

/// Classify a raw text frame. `Err` for unparseable JSON, an availability frame with no boolean
/// `available`, or a non-keep-alive object that is not a valid GPS update (the handler replies
/// with an error frame and keeps the socket open).
pub fn classify(text: &str) -> Result<ClientFrame, String> {
    let value: Value =
        serde_json::from_str(text).map_err(|e| format!("invalid json frame: {e}"))?;
    match value.get("type").and_then(Value::as_str) {
        Some("heartbeat") => return Ok(ClientFrame::Heartbeat),
        Some("availability") => {
            // Strictly a boolean — a missing/!bool `available` is an ERROR, never a silent
            // default. Defaulting either way would be a lie about the guard's intent: `true`
            // would offer a guard who never asked to be, `false` would hide one who did.
            let available = value
                .get("available")
                .and_then(Value::as_bool)
                .ok_or_else(|| "availability frame needs a boolean `available`".to_string())?;
            return Ok(ClientFrame::Availability(available));
        }
        _ => {}
    }
    let update: GpsUpdate =
        serde_json::from_value(value).map_err(|e| format!("invalid gps update: {e}"))?;
    Ok(ClientFrame::Gps(update))
}

// ----- Rate-limit decision (pure; the WS handler feeds it `Instant::elapsed()`) -----

/// `true` iff at least `min_interval` has elapsed since the last accepted event of this kind.
/// Used for BOTH the GPS 1/sec gate and the heartbeat 1/10s gate (kept separate so a heartbeat
/// never consumes a GPS slot). Pure: the handler passes `last_accepted.elapsed()`.
pub fn rate_allows(elapsed_since_last: Duration, min_interval: Duration) -> bool {
    elapsed_since_last >= min_interval
}

/// `true` iff a connection's inbound-frame count for the current 1-second window has exceeded
/// [`MAX_INBOUND_FRAMES_PER_SEC`]. Pure: the handler owns the window (an `Instant` + counter,
/// reset each second) and asks this on every inbound frame; on `true` it closes the socket as
/// abusive (distinct from the silent per-second GPS drop — this is a flood backstop, not a gate).
pub fn frame_flood(frames_in_window: u32) -> bool {
    frames_in_window > MAX_INBOUND_FRAMES_PER_SEC
}

/// How long the session should wait before its next ping action: when awaiting a pong, the
/// remaining slice of [`PONG_TIMEOUT`]; otherwise the remaining slice of [`PING_INTERVAL`] since
/// the last inbound activity. Mirrors v1 `handlers.rs:69-75`.
pub fn ping_wait(awaiting_pong_for: Option<Duration>, idle_for: Duration) -> Duration {
    match awaiting_pong_for {
        Some(elapsed) => PONG_TIMEOUT.saturating_sub(elapsed),
        None => PING_INTERVAL.saturating_sub(idle_for),
    }
}

// ----- Online / freshness rules -----

/// `true` iff `recorded_at` is within the [`FRESHNESS_MINUTES`] window before `now` (the
/// recency half of the discovery "live" rule). A future-dated `recorded_at` is still fresh.
pub fn is_fresh(recorded_at: DateTime<Utc>, now: DateTime<Utc>) -> bool {
    now.signed_duration_since(recorded_at) < TimeDelta::minutes(FRESHNESS_MINUTES)
}

/// The discovery "live" rule: a guard counts as live only when a session is connected
/// (`is_online`) AND the last fix is fresh. Offline → never live (even if the last fix is
/// recent); online but stale → not live (lost-GPS guard does not stay green).
pub fn is_live(is_online: bool, recorded_at: DateTime<Utc>, now: DateTime<Utc>) -> bool {
    is_online && is_fresh(recorded_at, now)
}

/// The SESSION-liveness half of the discovery offerable rule: has the server heard anything at
/// all from this row's session inside [`SESSION_LIVENESS_MINUTES`]?
///
/// `None` (a row written before session liveness existed, i.e. before migration 0005) is NOT
/// live — fail-safe: an unknown session is treated as dead rather than offered. A future-dated
/// `last_seen_at` counts as live (clock skew must not evict a working guard).
///
/// WHY this exists at all: `set_offline` only runs inside the WS task, so a presence
/// crash/SIGKILL/redeploy strands every connected guard at `is_online = true` with no live
/// socket — the "my app says offline but customers still see me" report. This bound lets such a
/// row expire itself, without a boot-time table reset (which would be wrong under multiple
/// presence replicas: a restarting one would evict another's live sessions).
pub fn is_session_live(last_seen_at: Option<DateTime<Utc>>, now: DateTime<Utc>) -> bool {
    match last_seen_at {
        Some(seen) => {
            now.signed_duration_since(seen) < TimeDelta::minutes(SESSION_LIVENESS_MINUTES)
        }
        None => false,
    }
}

/// The cut-off a repo query compares `last_seen_at` against — `now - SESSION_LIVENESS_MINUTES`,
/// so the rule is defined here (pure, tested) and the SQL only carries the bound. Kept
/// consistent with [`is_session_live`] by construction.
pub fn session_liveness_cutoff(now: DateTime<Utc>) -> DateTime<Utc> {
    now - TimeDelta::minutes(SESSION_LIVENESS_MINUTES)
}

/// `true` iff the session's `last_seen_at` touch is due — at most one write per
/// [`SEEN_TOUCH_INTERVAL`] per connection. Pure: the session loop passes
/// `last_touch.elapsed()`, exactly like the GPS/heartbeat rate gates.
pub fn seen_touch_due(elapsed_since_last_touch: Duration) -> bool {
    elapsed_since_last_touch >= SEEN_TOUCH_INTERVAL
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base() -> GpsUpdate {
        GpsUpdate {
            lat: 13.7563,
            lng: 100.5018,
            accuracy: Some(10.0),
            heading: Some(90.0),
            speed: Some(1.0),
            assignment_id: None,
        }
    }

    // --- GpsUpdate::validated: coordinate boundaries ---

    #[test]
    fn accepts_valid_fix_and_preserves_good_optionals() {
        let clean = base().validated().expect("valid");
        assert_eq!(clean.lat, 13.7563);
        assert_eq!(clean.accuracy, Some(10.0));
        assert_eq!(clean.heading, Some(90.0));
        assert_eq!(clean.speed, Some(1.0));
    }

    #[test]
    fn lat_lng_boundaries_inclusive() {
        for (lat, lng) in [(90.0, 180.0), (-90.0, -180.0), (90.0, -180.0)] {
            let u = GpsUpdate { lat, lng, ..base() };
            assert!(u.validated().is_ok(), "{lat},{lng} on-boundary is valid");
        }
    }

    #[test]
    fn rejects_out_of_range_coordinates() {
        assert!(GpsUpdate {
            lat: 90.1,
            ..base()
        }
        .validated()
        .is_err());
        assert!(GpsUpdate {
            lat: -90.1,
            ..base()
        }
        .validated()
        .is_err());
        assert!(GpsUpdate {
            lng: 180.1,
            ..base()
        }
        .validated()
        .is_err());
        assert!(GpsUpdate {
            lng: -180.1,
            ..base()
        }
        .validated()
        .is_err());
    }

    #[test]
    fn rejects_null_island() {
        let u = GpsUpdate {
            lat: 0.0,
            lng: 0.0,
            ..base()
        };
        assert!(u.validated().is_err(), "(0,0) must be rejected");
    }

    #[test]
    fn rejects_non_finite_coordinates() {
        assert!(GpsUpdate {
            lat: f64::NAN,
            ..base()
        }
        .validated()
        .is_err());
        assert!(GpsUpdate {
            lat: f64::INFINITY,
            ..base()
        }
        .validated()
        .is_err());
        assert!(GpsUpdate {
            lng: f64::NEG_INFINITY,
            ..base()
        }
        .validated()
        .is_err());
    }

    // --- GpsUpdate::validated: optional sanitization (NaN / out-of-range → None, NOT reject) ---

    #[test]
    fn ios_negative_accuracy_becomes_none_not_rejected() {
        let u = GpsUpdate {
            accuracy: Some(-1.0),
            ..base()
        };
        let clean = u
            .validated()
            .expect("a -1 accuracy must NOT reject the fix");
        assert_eq!(clean.accuracy, None);
        assert_eq!(clean.lat, base().lat, "the coordinate still lands");
    }

    #[test]
    fn nan_and_out_of_range_optionals_sanitize_to_none() {
        let u = GpsUpdate {
            accuracy: Some(f32::NAN),
            heading: Some(400.0),
            speed: Some(99_999.0),
            ..base()
        };
        let clean = u.validated().expect("sanitized, not rejected");
        assert_eq!(clean.accuracy, None);
        assert_eq!(clean.heading, None, "heading 400 out of 0..360 → None");
        assert_eq!(clean.speed, None, "speed 99999 out of 0..500 → None");
    }

    #[test]
    fn optional_boundaries_are_kept() {
        let u = GpsUpdate {
            accuracy: Some(10_000.0),
            heading: Some(360.0),
            speed: Some(500.0),
            ..base()
        };
        let clean = u.validated().expect("valid");
        assert_eq!(clean.accuracy, Some(10_000.0));
        assert_eq!(clean.heading, Some(360.0));
        assert_eq!(clean.speed, Some(500.0));
    }

    #[test]
    fn infinite_optional_becomes_none() {
        let u = GpsUpdate {
            speed: Some(f32::INFINITY),
            ..base()
        };
        assert_eq!(u.validated().unwrap().speed, None);
    }

    // --- classify ---

    #[test]
    fn classify_heartbeat() {
        assert_eq!(
            classify(r#"{"type":"heartbeat"}"#).unwrap(),
            ClientFrame::Heartbeat
        );
    }

    #[test]
    fn classify_gps_without_type() {
        match classify(r#"{"lat":13.7,"lng":100.5}"#).unwrap() {
            ClientFrame::Gps(u) => {
                assert_eq!(u.lat, 13.7);
                assert_eq!(u.lng, 100.5);
                assert_eq!(u.accuracy, None);
            }
            other => panic!("expected Gps, got {other:?}"),
        }
    }

    #[test]
    fn classify_rejects_garbage_and_non_gps() {
        assert!(classify("not json").is_err());
        assert!(
            classify(r#"{"foo":"bar"}"#).is_err(),
            "no lat/lng → invalid gps"
        );
    }

    // --- rate_allows ---

    #[test]
    fn rate_allows_at_and_after_interval() {
        assert!(
            rate_allows(GPS_MIN_INTERVAL, GPS_MIN_INTERVAL),
            "exactly 1s elapsed → allowed"
        );
        assert!(rate_allows(Duration::from_millis(1500), GPS_MIN_INTERVAL));
    }

    #[test]
    fn rate_denies_before_interval() {
        assert!(!rate_allows(Duration::from_millis(999), GPS_MIN_INTERVAL));
        assert!(!rate_allows(Duration::from_millis(0), GPS_MIN_INTERVAL));
        // heartbeat gate
        assert!(!rate_allows(Duration::from_secs(9), HEARTBEAT_MIN_INTERVAL));
        assert!(rate_allows(Duration::from_secs(10), HEARTBEAT_MIN_INTERVAL));
    }

    // --- frame_flood (inbound abuse backstop) ---

    #[test]
    fn frame_flood_trips_only_past_the_ceiling() {
        assert!(!frame_flood(1));
        assert!(
            !frame_flood(MAX_INBOUND_FRAMES_PER_SEC),
            "exactly at the ceiling is allowed (legitimate burst headroom)"
        );
        assert!(
            frame_flood(MAX_INBOUND_FRAMES_PER_SEC + 1),
            "one past the ceiling is a flood → close"
        );
    }

    // --- ping_wait ---

    #[test]
    fn ping_wait_counts_down_to_ping_then_pong() {
        // Not awaiting a pong: wait the remainder of the 30s idle window.
        assert_eq!(
            ping_wait(None, Duration::from_secs(10)),
            Duration::from_secs(20)
        );
        // Idle longer than the interval saturates to zero (fire now).
        assert_eq!(ping_wait(None, Duration::from_secs(40)), Duration::ZERO);
        // Awaiting a pong: wait the remainder of the 10s pong timeout.
        assert_eq!(
            ping_wait(Some(Duration::from_secs(3)), Duration::from_secs(0)),
            Duration::from_secs(7)
        );
        assert_eq!(
            ping_wait(Some(Duration::from_secs(10)), Duration::ZERO),
            Duration::ZERO,
            "pong overdue → timeout fires now"
        );
    }

    // --- freshness / online transitions ---

    #[test]
    fn freshness_5_min_boundary() {
        let now = Utc::now();
        assert!(is_fresh(
            now - TimeDelta::minutes(4) - TimeDelta::seconds(59),
            now
        ));
        assert!(
            !is_fresh(now - TimeDelta::minutes(5), now),
            "5:00 is not fresh"
        );
        assert!(!is_fresh(now - TimeDelta::minutes(6), now));
    }

    #[test]
    fn live_requires_online_and_fresh() {
        let now = Utc::now();
        let fresh = now - TimeDelta::minutes(1);
        let stale = now - TimeDelta::minutes(10);
        // online + fresh → live
        assert!(is_live(true, fresh, now));
        // online but stale → NOT live (lost-GPS guard)
        assert!(!is_live(true, stale, now));
        // offline → never live even if fresh
        assert!(!is_live(false, fresh, now));
        assert!(!is_live(false, stale, now));
    }

    // --- session liveness (0005) — the ghost-row expiry, NOT the GPS freshness rule ---

    #[test]
    fn session_liveness_2_min_boundary_and_unknown_is_dead() {
        let now = Utc::now();
        assert!(is_session_live(
            Some(now - TimeDelta::minutes(1) - TimeDelta::seconds(59)),
            now
        ));
        assert!(
            !is_session_live(Some(now - TimeDelta::minutes(2)), now),
            "2:00 of total silence is not a live session"
        );
        assert!(!is_session_live(Some(now - TimeDelta::hours(3)), now));
        assert!(
            !is_session_live(None, now),
            "a row with no recorded session activity (pre-0005) is treated as DEAD, not live — \
             the fail-safe direction for a rule that decides who customers are offered"
        );
        assert!(
            is_session_live(Some(now + TimeDelta::seconds(30)), now),
            "clock skew must not evict a working guard"
        );
    }

    /// Session liveness must stay INDEPENDENT of GPS freshness — conflating them is bug B. A
    /// guard standing still for 10 minutes has a stale `recorded_at` (movement-gated uplink) but
    /// a perfectly live session, and must remain offerable.
    #[test]
    fn session_liveness_is_not_gps_freshness() {
        let now = Utc::now();
        let stale_fix = now - TimeDelta::minutes(10);
        let recent_frame = now - TimeDelta::seconds(35);
        assert!(!is_fresh(stale_fix, now), "the FIX is stale");
        assert!(
            is_session_live(Some(recent_frame), now),
            "…but the SESSION is alive (a Pong got through), so the guard stays offerable"
        );
        // And the converse: a fresh fix cannot rescue a session nothing has been heard from
        // (the crashed-service ghost, whose last fix is exactly as recent as the crash).
        assert!(
            !is_session_live(Some(now - TimeDelta::minutes(5)), now),
            "no frames for 5 minutes → dead session regardless of the stored fix"
        );
    }

    #[test]
    fn session_liveness_cutoff_matches_the_predicate() {
        let now = Utc::now();
        let cutoff = session_liveness_cutoff(now);
        // The SQL bound (`last_seen_at > cutoff`) and the pure predicate must agree exactly,
        // since one is used by the offerable-set query and the other by the read DTO.
        for offset_secs in [0i64, 30, 119, 120, 600] {
            let seen = now - TimeDelta::seconds(offset_secs);
            assert_eq!(
                seen > cutoff,
                is_session_live(Some(seen), now),
                "cutoff and predicate disagree at {offset_secs}s"
            );
        }
    }

    #[test]
    fn seen_touch_is_throttled_to_the_interval() {
        assert!(!seen_touch_due(Duration::from_secs(0)));
        assert!(!seen_touch_due(
            SEEN_TOUCH_INTERVAL - Duration::from_millis(1)
        ));
        assert!(seen_touch_due(SEEN_TOUCH_INTERVAL));
        assert!(seen_touch_due(Duration::from_secs(600)));
    }

    /// The throttle must stay comfortably inside the liveness window, or a healthy session would
    /// expire itself between touches. Guards the two constants against drifting apart.
    #[test]
    fn touch_interval_leaves_headroom_inside_the_liveness_window() {
        let window = Duration::from_secs((SESSION_LIVENESS_MINUTES as u64) * 60);
        // Worst case a healthy session goes quiet: the reaper's ping wait + pong grace, plus a
        // full throttle interval before the next touch lands.
        let worst_case = PING_INTERVAL + PONG_TIMEOUT + SEEN_TOUCH_INTERVAL;
        assert!(
            worst_case < window,
            "a healthy session ({worst_case:?}) must not out-wait the liveness window ({window:?})"
        );
    }

    // --- availability frame classification (the "พร้อมรับงาน" declaration) ---

    #[test]
    fn classify_reads_the_availability_declaration() {
        assert_eq!(
            classify(r#"{"type":"availability","available":true}"#).expect("on"),
            ClientFrame::Availability(true)
        );
        assert_eq!(
            classify(r#"{"type":"availability","available":false}"#).expect("off"),
            ClientFrame::Availability(false)
        );
    }

    /// A malformed declaration is an ERROR, never a default: guessing `true` would offer a guard
    /// who never opted in (the exact defect), guessing `false` would hide one who did.
    #[test]
    fn classify_rejects_an_availability_frame_without_a_boolean() {
        for bad in [
            r#"{"type":"availability"}"#,
            r#"{"type":"availability","available":"yes"}"#,
            r#"{"type":"availability","available":1}"#,
            r#"{"type":"availability","available":null}"#,
        ] {
            assert!(classify(bad).is_err(), "{bad} must not be accepted");
        }
    }

    /// The GPS frame the mobile client actually sends carries `type:"location"`, which must keep
    /// classifying as a fix (the `type` key is simply not part of `GpsUpdate`).
    #[test]
    fn classify_still_reads_a_typed_location_frame_as_gps() {
        let frame = r#"{"type":"location","lat":13.75,"lng":100.5,"accuracy":8.0}"#;
        match classify(frame).expect("location frame") {
            ClientFrame::Gps(u) => assert_eq!((u.lat, u.lng), (13.75, 100.5)),
            other => panic!("expected a GPS fix, got {other:?}"),
        }
    }
}
