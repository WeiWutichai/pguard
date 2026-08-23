//! PURE geofence rules for proximity gating. No DB/HTTP imports — 100% unit-testable (the
//! only shared import is the error TYPE, mirroring [`crate::domain::progress`]).
//!
//! The assigned guard may only mark a job ARRIVED while physically at the site: within
//! [`ARRIVED_GEOFENCE_M`] of the booking's pinned coordinates, plus a capped allowance for
//! the reported GPS accuracy (a fix with ±20m accuracy standing 130m out is plausibly
//! inside). Legacy address-only bookings (no site pin) skip the check entirely — there is
//! nothing to measure against.
//!
//! HISTORY: the proximity gate used to sit on "start work" (a tight 50m fence enforced in
//! `repo::start_job`). A guard could tap "arrived" from anywhere and then get stuck at the
//! start step far from the site. The gate now sits at the EnRoute→Arrived transition with a
//! roomier 120m radius (`repo::arrive_job`); once arrival is proven on-site, start / check-in
//! are free.

use shared::error::AppError;

/// Machine-readable `error.code` for the geofence 409: the guard's fix is farther from the
/// site than the fence allows. Clients branch on this sub-code (see `AppError::ConflictCode`)
/// to render a localized "move closer" screen instead of the English message.
pub const NOT_AT_SITE_CODE: &str = "NOT_AT_SITE";

/// Machine-readable `error.code` for the missing-fix 409: the booking HAS a site pin, so an
/// arrival without GPS cannot be verified. Clients branch on this to prompt for location
/// permission / a fresh fix and retry.
pub const GPS_REQUIRED_CODE: &str = "GPS_REQUIRED";

/// The arrive geofence radius: the guard must be within this many meters of the site pin to
/// mark the job arrived. Roomier than the old 50m start fence — a guard at the gate / parking
/// lot / building entrance of a large site is legitimately "arrived" without being on the exact
/// pin, and the tighter fence was stranding guards at the start step.
pub const ARRIVED_GEOFENCE_M: f64 = 120.0;

/// Cap on the accuracy allowance added to the fence. A fix's reported accuracy widens the
/// fence (the guard may truly be inside it), but only up to this cap — otherwise a junk
/// "±5km" fix would swallow the geofence whole.
pub const ACCURACY_ALLOWANCE_CAP_M: f64 = 30.0;

/// Mean Earth radius in meters (the SQL haversine in `repo` uses the same 6371km).
const EARTH_RADIUS_M: f64 = 6_371_000.0;

/// Great-circle distance in meters between two WGS84 points — the same haversine formula
/// as the open-job discovery SQL (`repo::list_open_bookings`), ported to Rust:
/// `2R·asin(min(1, √(sin²(Δlat/2) + cos(lat₁)·cos(lat₂)·sin²(Δlng/2))))`.
/// The `asin` input is clamped to 1.0 — float rounding can push the sum marginally past
/// 1.0 for near-antipodal points, and `asin(>1)` is NaN.
pub fn haversine_meters(a_lat: f64, a_lng: f64, b_lat: f64, b_lng: f64) -> f64 {
    let d_lat = (b_lat - a_lat).to_radians();
    let d_lng = (b_lng - a_lng).to_radians();
    let s = (d_lat / 2.0).sin().powi(2)
        + a_lat.to_radians().cos() * b_lat.to_radians().cos() * (d_lng / 2.0).sin().powi(2);
    2.0 * EARTH_RADIUS_M * s.sqrt().min(1.0).asin()
}

/// Validate that the guard may mark the job ARRIVED from where they stand — the
/// [`ARRIVED_GEOFENCE_M`] fence. See [`validate_geofence`] for the exact rule.
pub fn validate_arrived_geofence(
    site: Option<(f64, f64)>,
    guard: Option<(f64, f64)>,
    accuracy_m: Option<f32>,
) -> Result<(), AppError> {
    validate_geofence(ARRIVED_GEOFENCE_M, site, guard, accuracy_m)
}

/// Validate that the guard's fix is within `radius_m` (+ capped accuracy allowance) of the site.
///
/// - `site` `None` (legacy address-only booking — no pin) → `Ok` (nothing to measure; skip).
/// - `site` pinned but `guard` fix missing → 409 [`GPS_REQUIRED_CODE`] (an unverifiable
///   proximity claim on a pinned booking must not silently pass).
/// - Otherwise the fix must be within `radius_m` plus the accuracy allowance
///   (`min(max(accuracy_m, 0), `[`ACCURACY_ALLOWANCE_CAP_M`]`)`; negative/NaN accuracy
///   contributes 0) → 409 [`NOT_AT_SITE_CODE`] beyond that, with the measured distance
///   (whole meters) in the message.
pub fn validate_geofence(
    radius_m: f64,
    site: Option<(f64, f64)>,
    guard: Option<(f64, f64)>,
    accuracy_m: Option<f32>,
) -> Result<(), AppError> {
    let Some((site_lat, site_lng)) = site else {
        return Ok(());
    };
    let Some((guard_lat, guard_lng)) = guard else {
        return Err(AppError::ConflictCode {
            code: GPS_REQUIRED_CODE,
            message: "GPS fix required to mark this job arrived".to_string(),
        });
    };
    // Non-finite (NaN/±∞) accuracy is junk and — like a negative one — contributes 0
    // allowance (clamp alone would propagate NaN, silently failing the comparison below).
    let allowance = accuracy_m
        .map(f64::from)
        .filter(|a| a.is_finite())
        .unwrap_or(0.0)
        .clamp(0.0, ACCURACY_ALLOWANCE_CAP_M);
    let distance = haversine_meters(site_lat, site_lng, guard_lat, guard_lng);
    if distance <= radius_m + allowance {
        return Ok(());
    }
    Err(AppError::ConflictCode {
        code: NOT_AT_SITE_CODE,
        message: format!(
            "You are {} m from the meetup point (max {} m)",
            distance.round(),
            radius_m
        ),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Bangkok reference point (matches the coordinates the repo tests use).
    const SITE: (f64, f64) = (13.7563, 100.5018);

    /// A point `meters` NORTH of `from`: 1° latitude ≈ 111,194.9m at R = 6371km
    /// (π·R/180). Pure-latitude offsets make the haversine near-exact, so boundary
    /// tests can dial in distances precisely.
    fn north_of(from: (f64, f64), meters: f64) -> (f64, f64) {
        let deg_per_m = 180.0 / (std::f64::consts::PI * EARTH_RADIUS_M);
        (from.0 + meters * deg_per_m, from.1)
    }

    fn code_of(err: &AppError) -> &'static str {
        match err {
            AppError::ConflictCode { code, .. } => code,
            other => panic!("expected ConflictCode, got {other:?}"),
        }
    }

    // ----- haversine_meters -----

    #[test]
    fn haversine_zero_for_identical_points() {
        assert_eq!(haversine_meters(SITE.0, SITE.1, SITE.0, SITE.1), 0.0);
    }

    #[test]
    fn haversine_matches_known_offsets() {
        // 100m due north — within numerical noise of the constructed offset.
        let p = north_of(SITE, 100.0);
        let d = haversine_meters(SITE.0, SITE.1, p.0, p.1);
        assert!((d - 100.0).abs() < 0.01, "expected ~100m, got {d}");

        // A known long pair: Bangkok → Chiang Mai ≈ 580–590 km.
        let d = haversine_meters(13.7563, 100.5018, 18.7883, 98.9853);
        assert!(
            (560_000.0..610_000.0).contains(&d),
            "BKK→CNX expected ~585km, got {d}"
        );
    }

    #[test]
    fn haversine_antimeridian_sanity() {
        // Two points straddling ±180° are ~222m apart, not half the planet: the formula
        // works on Δlng through sin(), which is periodic — no wraparound special-case.
        let d = haversine_meters(0.0, 179.999, 0.0, -179.999);
        assert!((d - 222.4).abs() < 1.0, "expected ~222m, got {d}");
    }

    #[test]
    fn haversine_antipodal_does_not_nan() {
        // Exactly antipodal points push the asin input to (and past, with float rounding)
        // 1.0 — the clamp keeps the result a finite half-circumference (~20,015km).
        let d = haversine_meters(0.0, 0.0, 0.0, 180.0);
        assert!(d.is_finite(), "antipodal distance must be finite, got {d}");
        assert!(
            (d - std::f64::consts::PI * EARTH_RADIUS_M).abs() < 1.0,
            "expected half-circumference, got {d}"
        );
    }

    // ----- validate_arrived_geofence: skip / reject shape -----

    #[test]
    fn no_site_pin_skips_the_check() {
        // Legacy address-only booking: nothing to measure against — even a far-away (or
        // absent) fix passes.
        assert!(validate_arrived_geofence(None, Some((0.0, 0.0)), None).is_ok());
        assert!(validate_arrived_geofence(None, None, None).is_ok());
        assert!(validate_arrived_geofence(None, None, Some(f32::NAN)).is_ok());
    }

    #[test]
    fn pinned_site_without_fix_is_gps_required() {
        let err = validate_arrived_geofence(Some(SITE), None, None).unwrap_err();
        assert_eq!(code_of(&err), GPS_REQUIRED_CODE);
        // Accuracy alone is not a fix.
        let err = validate_arrived_geofence(Some(SITE), None, Some(5.0)).unwrap_err();
        assert_eq!(code_of(&err), GPS_REQUIRED_CODE);
    }

    #[test]
    fn far_fix_is_not_at_site_with_distance_in_message() {
        // 400m out — well beyond the 120m arrive fence.
        let guard = north_of(SITE, 400.0);
        let err = validate_arrived_geofence(Some(SITE), Some(guard), None).unwrap_err();
        assert_eq!(code_of(&err), NOT_AT_SITE_CODE);
        let msg = err.to_string();
        assert!(
            msg.contains("400 m") && msg.contains("max 120 m"),
            "message must carry the whole-meter distance and the fence, got: {msg}"
        );
    }

    // ----- validate_arrived_geofence: boundaries (120m) -----

    #[test]
    fn boundary_at_exactly_the_fence() {
        // ≤ is allowed: 120.0m in (fraction under, to sit inside float noise) passes;
        // a meter beyond does not.
        let at = north_of(SITE, ARRIVED_GEOFENCE_M - 0.001);
        assert!(validate_arrived_geofence(Some(SITE), Some(at), None).is_ok());
        let past = north_of(SITE, ARRIVED_GEOFENCE_M + 1.0);
        assert!(validate_arrived_geofence(Some(SITE), Some(past), None).is_err());
    }

    #[test]
    fn accuracy_widens_the_fence_up_to_the_cap() {
        // 140m out: rejected with no accuracy, accepted once the ±30m allowance applies.
        let guard = north_of(SITE, 140.0);
        assert!(validate_arrived_geofence(Some(SITE), Some(guard), None).is_err());
        assert!(validate_arrived_geofence(Some(SITE), Some(guard), Some(30.0)).is_ok());

        // The 120+30 boundary: just inside passes, past it fails even with a huge
        // reported accuracy (the cap holds).
        let cap_edge = north_of(SITE, ARRIVED_GEOFENCE_M + ACCURACY_ALLOWANCE_CAP_M - 0.001);
        assert!(validate_arrived_geofence(Some(SITE), Some(cap_edge), Some(30.0)).is_ok());
        assert!(validate_arrived_geofence(Some(SITE), Some(cap_edge), Some(9_999.0)).is_ok());
        let past_cap = north_of(SITE, ARRIVED_GEOFENCE_M + ACCURACY_ALLOWANCE_CAP_M + 1.0);
        assert!(
            validate_arrived_geofence(Some(SITE), Some(past_cap), Some(9_999.0)).is_err(),
            "accuracy allowance must cap at {ACCURACY_ALLOWANCE_CAP_M}m"
        );
    }

    #[test]
    fn junk_accuracy_contributes_zero_allowance() {
        // 130m out is only reachable through a real, positive accuracy allowance —
        // negative and NaN must be treated as 0 (reject), never as a widened fence.
        let guard = north_of(SITE, 130.0);
        for junk in [Some(-15.0), Some(f32::NAN)] {
            let err = validate_arrived_geofence(Some(SITE), Some(guard), junk).unwrap_err();
            assert_eq!(code_of(&err), NOT_AT_SITE_CODE, "accuracy {junk:?}");
        }
        // ...while None behaves identically (no allowance).
        assert!(validate_arrived_geofence(Some(SITE), Some(guard), None).is_err());
        // And a genuine 15m accuracy on the same fix passes (120 + 15 ≥ 130).
        assert!(validate_arrived_geofence(Some(SITE), Some(guard), Some(15.5)).is_ok());
    }

    #[test]
    fn at_site_passes_regardless_of_accuracy() {
        assert!(validate_arrived_geofence(Some(SITE), Some(SITE), None).is_ok());
        assert!(validate_arrived_geofence(Some(SITE), Some(SITE), Some(f32::NAN)).is_ok());
        assert!(validate_arrived_geofence(Some(SITE), Some(SITE), Some(-1.0)).is_ok());
    }

    // ----- validate_geofence: radius is parametric -----

    #[test]
    fn radius_parameter_controls_the_fence() {
        // A guard 80m out: inside a 120m fence, outside a 50m one — proving the radius arg
        // (not a hardcoded constant) decides.
        let guard = north_of(SITE, 80.0);
        assert!(validate_geofence(120.0, Some(SITE), Some(guard), None).is_ok());
        assert!(validate_geofence(50.0, Some(SITE), Some(guard), None).is_err());
    }
}
