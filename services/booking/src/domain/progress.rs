//! PURE progress-report (hourly check-in) + open-job discovery rules. No DB/HTTP/S3 imports
//! — 100% unit-testable (the only shared import is the error TYPE, mirroring chat's domain).
//!
//! Check-in model: a job is IN PROGRESS in v2 when its status is `arrived` AND the assigned
//! guard has pressed start (`work_started_at` stamped — the proration clock). There is no
//! separate `in_progress` enum value (PHASE spec's "in_progress" maps onto this pair). Hour
//! `N` (1-based, ≤ the booked `hours`) opens once `N−1` hours have elapsed since
//! `work_started_at`, so a guard can never pre-file future hours; one report per hour is
//! enforced by the DB unique index (duplicate → 409, making client retries idempotent).

use chrono::{DateTime, Duration, Utc};

use shared::error::AppError;

use crate::domain::state::BookingStatus;

// ----- check-in photo validation (images only — ported subset of chat's attachment rules) -----

/// 10MB cap for check-in photos (mirrors chat's image cap).
pub const MAX_PHOTO_SIZE: usize = 10 * 1024 * 1024;

/// Allowed declared MIME types — IMAGES ONLY (a check-in is a photo; no videos).
pub const ALLOWED_PHOTO_MIME_TYPES: [&str; 3] = ["image/jpeg", "image/png", "image/webp"];

/// Map a (validated) photo MIME type to a file extension for the object key.
pub fn mime_to_extension(mime_type: &str) -> &'static str {
    match mime_type {
        "image/jpeg" => "jpg",
        "image/png" => "png",
        "image/webp" => "webp",
        _ => "bin",
    }
}

/// Detect the ACTUAL image type from magic bytes, ignoring the client-declared MIME. `None`
/// for anything not in the allowed set.
///   JPEG `FF D8 FF` · PNG `89 50 4E 47 0D 0A 1A 0A` · WEBP `RIFF....WEBP`
pub fn detect_image_mime(data: &[u8]) -> Option<&'static str> {
    if data.len() >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
        return Some("image/jpeg");
    }
    if data.len() >= 8 && data[..8] == [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A] {
        return Some("image/png");
    }
    if data.len() >= 12 && &data[..4] == b"RIFF" && &data[8..12] == b"WEBP" {
        return Some("image/webp");
    }
    None
}

/// Validate a check-in photo upload. Order matters (CLAUDE.md / chat spec): **size is checked
/// BEFORE the magic bytes** so an oversized blob is rejected without a large read. Then the
/// declared MIME must be allowed AND match the actual content. Returns the canonical
/// (detected) MIME on success.
pub fn validate_photo_upload(
    declared_mime: &str,
    file_size: usize,
    data: &[u8],
) -> Result<&'static str, AppError> {
    // 1. Declared MIME must be in the (image-only) allowlist.
    if !ALLOWED_PHOTO_MIME_TYPES.contains(&declared_mime) {
        return Err(AppError::BadRequest(format!(
            "Unsupported photo type: {declared_mime}. Allowed: JPEG, PNG, WEBP"
        )));
    }

    // 2. SIZE before magic bytes — reject oversized uploads cheaply.
    if file_size > MAX_PHOTO_SIZE {
        let max_mb = MAX_PHOTO_SIZE / (1024 * 1024);
        return Err(AppError::BadRequest(format!(
            "Photo too large: {file_size} bytes (max {max_mb}MB)"
        )));
    }

    // 3. Magic bytes must match a known image format.
    let detected = detect_image_mime(data).ok_or_else(|| {
        AppError::BadRequest("Photo content does not match any allowed image format".to_string())
    })?;

    // 4. Declared MIME must agree with the content.
    if detected != declared_mime {
        return Err(AppError::BadRequest(format!(
            "MIME mismatch: declared {declared_mime} but content is {detected}"
        )));
    }

    Ok(detected)
}

// ----- check-in legality (state gate + hour window) -----

/// Validate that the assigned guard may check in for `hour_number` NOW.
///
/// Rules (PHASE spec §B2, mapped onto the v2 state machine):
/// - the job must be IN PROGRESS: status `arrived` AND `work_started_at` stamped → 409
///   otherwise. The 409 messages do NOT embed the booking's real current status (the caller
///   is always a verified participant by this point, but keep the no-state-leak discipline).
/// - `hour_number` must be `1..=hours` → 400 otherwise.
/// - hour `N` opens once `N−1` hours have elapsed since `work_started_at` → 409 (too early)
///   otherwise, so future hours can never be pre-filed.
///
/// Duplicate-hour (the idempotent-retry 409) is NOT decided here — it is enforced by the DB
/// unique index inside the insert transaction (a pure function cannot see concurrent writes).
pub fn validate_check_in(
    status: BookingStatus,
    work_started_at: Option<DateTime<Utc>>,
    hours: i32,
    hour_number: i32,
    now: DateTime<Utc>,
) -> Result<(), AppError> {
    if status != BookingStatus::Arrived {
        return Err(AppError::Conflict(
            "Check-in requires a job in progress".to_string(),
        ));
    }
    let started = work_started_at.ok_or_else(|| {
        AppError::Conflict("Job has not been started; cannot check in".to_string())
    })?;
    if hour_number < 1 || hour_number > hours {
        return Err(AppError::BadRequest(format!(
            "hour_number must be between 1 and {hours}"
        )));
    }
    // Hour N opens at started + (N−1)h. Built from i64 math — no float drift.
    let opens_at = started + Duration::hours(i64::from(hour_number) - 1);
    if now < opens_at {
        return Err(AppError::Conflict(format!(
            "Too early to check in for hour {hour_number}"
        )));
    }
    Ok(())
}

// ----- note + accuracy sanitation -----

/// Max characters for the optional free-text note (it is echoed to the customer on every
/// list read — without a cap an assigned guard could persist megabytes of TEXT per hour).
pub const MAX_NOTE_CHARS: usize = 2000;

/// Validate the (already-trimmed, non-empty) note length.
pub fn validate_note(note: &str) -> Result<(), AppError> {
    if note.chars().count() > MAX_NOTE_CHARS {
        return Err(AppError::BadRequest(format!(
            "note must be at most {MAX_NOTE_CHARS} characters"
        )));
    }
    Ok(())
}

/// Sanitize GPS accuracy (meters): non-finite, negative, or absurd values become `None`
/// rather than persisted junk — mirrors presence's `sane(0.0..10_000.0)` precedent
/// (`NaN::real` would otherwise round-trip inconsistently: stored as NaN, served as null).
pub fn sanitize_accuracy(accuracy_m: Option<f32>) -> Option<f32> {
    accuracy_m.filter(|a| a.is_finite() && (0.0..=10_000.0).contains(a))
}

// ----- GPS + open-job discovery query validation -----

/// A validated geo filter for open-job discovery.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GeoFilter {
    pub lat: f64,
    pub lng: f64,
    pub radius_km: f64,
}

/// Default discovery radius when the guard sends coordinates without `radius_km`.
pub const DEFAULT_RADIUS_KM: f64 = 10.0;
/// Upper bound on the discovery radius (defensive — beyond this the filter is meaningless).
pub const MAX_RADIUS_KM: f64 = 500.0;

/// Validate an optional coordinate pair: both-or-neither, and each within range. Returns the
/// pair when present. Used by create-booking, check-in GPS, and open-job discovery.
pub fn validate_coords(lat: Option<f64>, lng: Option<f64>) -> Result<Option<(f64, f64)>, AppError> {
    match (lat, lng) {
        (None, None) => Ok(None),
        (Some(lat), Some(lng)) => {
            if !(-90.0..=90.0).contains(&lat) || !lat.is_finite() {
                return Err(AppError::BadRequest(
                    "lat must be between -90 and 90".to_string(),
                ));
            }
            if !(-180.0..=180.0).contains(&lng) || !lng.is_finite() {
                return Err(AppError::BadRequest(
                    "lng must be between -180 and 180".to_string(),
                ));
            }
            Ok(Some((lat, lng)))
        }
        _ => Err(AppError::BadRequest(
            "lat and lng must be provided together".to_string(),
        )),
    }
}

/// Validate the open-job discovery query: `lat`/`lng` both-or-neither (in range),
/// `radius_km` only WITH coordinates (default [`DEFAULT_RADIUS_KM`], bounded by
/// [`MAX_RADIUS_KM`]). `None` → no geo filter (newest-first listing).
pub fn validate_open_jobs_query(
    lat: Option<f64>,
    lng: Option<f64>,
    radius_km: Option<f64>,
) -> Result<Option<GeoFilter>, AppError> {
    let coords = validate_coords(lat, lng)?;
    match (coords, radius_km) {
        (None, None) => Ok(None),
        (None, Some(_)) => Err(AppError::BadRequest(
            "radius_km requires lat and lng".to_string(),
        )),
        (Some((lat, lng)), radius) => {
            let radius_km = radius.unwrap_or(DEFAULT_RADIUS_KM);
            if !radius_km.is_finite() || radius_km <= 0.0 || radius_km > MAX_RADIUS_KM {
                return Err(AppError::BadRequest(format!(
                    "radius_km must be between 0 (exclusive) and {MAX_RADIUS_KM}"
                )));
            }
            Ok(Some(GeoFilter {
                lat,
                lng,
                radius_km,
            }))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn t0() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 6, 10, 8, 0, 0).unwrap()
    }

    // ----- validate_check_in: state gate -----

    #[test]
    fn check_in_requires_arrived_status() {
        for status in [
            BookingStatus::Requested,
            BookingStatus::Accepted,
            BookingStatus::EnRoute,
            BookingStatus::PendingCompletion,
            BookingStatus::Completed,
            BookingStatus::Declined,
            BookingStatus::Cancelled,
        ] {
            let err = validate_check_in(status, Some(t0()), 4, 1, t0()).unwrap_err();
            assert!(
                matches!(err, AppError::Conflict(_)),
                "{status}: expected Conflict, got {err:?}"
            );
            // No-state-leak discipline: the message never embeds the real current status.
            assert!(
                !err.to_string().to_lowercase().contains(status.as_db_str()),
                "{status}: message must not disclose the current status, got: {err}"
            );
        }
    }

    #[test]
    fn check_in_requires_started_job() {
        let err = validate_check_in(BookingStatus::Arrived, None, 4, 1, t0()).unwrap_err();
        assert!(matches!(err, AppError::Conflict(_)), "got {err:?}");
    }

    #[test]
    fn check_in_hour_one_opens_immediately_at_start() {
        // Hour 1 opens at work_started_at exactly (N−1 = 0 elapsed required).
        assert!(validate_check_in(BookingStatus::Arrived, Some(t0()), 4, 1, t0()).is_ok());
    }

    // ----- validate_check_in: hour range -----

    #[test]
    fn check_in_hour_out_of_range_is_bad_request() {
        for bad in [0, -1, 5] {
            let err =
                validate_check_in(BookingStatus::Arrived, Some(t0()), 4, bad, t0()).unwrap_err();
            assert!(
                matches!(err, AppError::BadRequest(_)),
                "hour {bad}: expected BadRequest, got {err:?}"
            );
        }
        // The last booked hour itself is valid (given enough elapsed time).
        let late = t0() + Duration::hours(3);
        assert!(validate_check_in(BookingStatus::Arrived, Some(t0()), 4, 4, late).is_ok());
    }

    // ----- validate_check_in: too-early window -----

    #[test]
    fn check_in_future_hours_are_too_early() {
        // At start (0 elapsed) only hour 1 is open; hour 2 opens at +1h.
        let err = validate_check_in(BookingStatus::Arrived, Some(t0()), 4, 2, t0()).unwrap_err();
        assert!(matches!(err, AppError::Conflict(_)), "got {err:?}");

        // One second before the boundary → still too early.
        let almost = t0() + Duration::hours(1) - Duration::seconds(1);
        let err = validate_check_in(BookingStatus::Arrived, Some(t0()), 4, 2, almost).unwrap_err();
        assert!(matches!(err, AppError::Conflict(_)), "got {err:?}");

        // Exactly at the boundary → open.
        let boundary = t0() + Duration::hours(1);
        assert!(validate_check_in(BookingStatus::Arrived, Some(t0()), 4, 2, boundary).is_ok());

        // 2.5h elapsed → hours 1..=3 open, hour 4 still closed.
        let mid = t0() + Duration::minutes(150);
        for ok_hour in [1, 2, 3] {
            assert!(
                validate_check_in(BookingStatus::Arrived, Some(t0()), 4, ok_hour, mid).is_ok(),
                "hour {ok_hour} must be open at +2.5h"
            );
        }
        let err = validate_check_in(BookingStatus::Arrived, Some(t0()), 4, 4, mid).unwrap_err();
        assert!(matches!(err, AppError::Conflict(_)), "got {err:?}");
    }

    #[test]
    fn check_in_late_filing_of_past_hours_is_allowed() {
        // A guard who missed hour 1 can still file it later (back-filling a PAST hour is the
        // retry/poor-connectivity path; only FUTURE hours are blocked).
        let late = t0() + Duration::hours(3);
        assert!(validate_check_in(BookingStatus::Arrived, Some(t0()), 4, 1, late).is_ok());
    }

    // ----- photo validation -----

    const JPEG: &[u8] = &[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
    const PNG: &[u8] = &[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    const WEBP: &[u8] = b"RIFF\x00\x00\x00\x00WEBP";
    const MP4: &[u8] = b"\x00\x00\x00\x1cftypisom\x00\x00\x02\x00";
    const GIF: &[u8] = b"GIF89a";

    #[test]
    fn detect_each_allowed_image_magic() {
        assert_eq!(detect_image_mime(JPEG), Some("image/jpeg"));
        assert_eq!(detect_image_mime(PNG), Some("image/png"));
        assert_eq!(detect_image_mime(WEBP), Some("image/webp"));
        // Videos and others are NOT images here (unlike chat's detector).
        assert_eq!(detect_image_mime(MP4), None);
        assert_eq!(detect_image_mime(GIF), None);
        assert_eq!(detect_image_mime(b""), None);
    }

    #[test]
    fn photo_accepts_each_allowed_image() {
        assert_eq!(
            validate_photo_upload("image/jpeg", JPEG.len(), JPEG).unwrap(),
            "image/jpeg"
        );
        assert_eq!(
            validate_photo_upload("image/png", PNG.len(), PNG).unwrap(),
            "image/png"
        );
        assert_eq!(
            validate_photo_upload("image/webp", WEBP.len(), WEBP).unwrap(),
            "image/webp"
        );
    }

    #[test]
    fn photo_rejects_videos_and_other_types() {
        // A check-in is a PHOTO — the video types chat allows must reject here.
        assert!(validate_photo_upload("video/mp4", MP4.len(), MP4).is_err());
        assert!(validate_photo_upload("image/gif", GIF.len(), GIF).is_err());
        assert!(validate_photo_upload("application/pdf", 8, b"%PDF-1.4").is_err());
        assert!(validate_photo_upload("", 3, b"\x00\x00\x00").is_err());
    }

    #[test]
    fn photo_rejects_spoofed_mime() {
        // Declares JPEG but the bytes are PNG → mismatch.
        assert!(validate_photo_upload("image/jpeg", PNG.len(), PNG).is_err());
        // Declares PNG but the bytes are garbage → no detected format.
        assert!(validate_photo_upload("image/png", 10, b"notanimage").is_err());
    }

    #[test]
    fn photo_checks_size_before_magic_bytes() {
        // Valid jpeg header but over the cap — the size check must fire FIRST.
        let err = validate_photo_upload("image/jpeg", MAX_PHOTO_SIZE + 1, JPEG).unwrap_err();
        match err {
            AppError::BadRequest(m) => assert!(m.contains("too large"), "size error, got: {m}"),
            other => panic!("expected size BadRequest, got {other:?}"),
        }
        // Exactly at the cap passes.
        assert!(validate_photo_upload("image/jpeg", MAX_PHOTO_SIZE, JPEG).is_ok());
    }

    // ----- note + accuracy sanitation -----

    #[test]
    fn note_capped_at_max_chars() {
        assert!(validate_note(&"ก".repeat(MAX_NOTE_CHARS)).is_ok());
        assert!(validate_note(&"ก".repeat(MAX_NOTE_CHARS + 1)).is_err());
        assert!(validate_note("perimeter clear").is_ok());
    }

    #[test]
    fn accuracy_junk_becomes_none() {
        assert_eq!(sanitize_accuracy(Some(8.5)), Some(8.5));
        assert_eq!(sanitize_accuracy(Some(0.0)), Some(0.0));
        assert_eq!(sanitize_accuracy(Some(10_000.0)), Some(10_000.0));
        assert_eq!(sanitize_accuracy(Some(-1.0)), None);
        assert_eq!(sanitize_accuracy(Some(10_000.1)), None);
        assert_eq!(sanitize_accuracy(Some(f32::NAN)), None);
        assert_eq!(sanitize_accuracy(Some(f32::INFINITY)), None);
        assert_eq!(sanitize_accuracy(None), None);
    }

    // ----- coords + open-job query validation -----

    #[test]
    fn coords_both_or_neither() {
        assert_eq!(validate_coords(None, None).unwrap(), None);
        assert_eq!(
            validate_coords(Some(13.75), Some(100.5)).unwrap(),
            Some((13.75, 100.5))
        );
        assert!(validate_coords(Some(13.75), None).is_err());
        assert!(validate_coords(None, Some(100.5)).is_err());
    }

    #[test]
    fn coords_bounds() {
        assert!(validate_coords(Some(90.0), Some(180.0)).is_ok());
        assert!(validate_coords(Some(-90.0), Some(-180.0)).is_ok());
        assert!(validate_coords(Some(90.1), Some(0.0)).is_err());
        assert!(validate_coords(Some(0.0), Some(180.1)).is_err());
        assert!(validate_coords(Some(f64::NAN), Some(0.0)).is_err());
        assert!(validate_coords(Some(0.0), Some(f64::INFINITY)).is_err());
    }

    #[test]
    fn open_jobs_query_no_filter() {
        assert_eq!(validate_open_jobs_query(None, None, None).unwrap(), None);
    }

    #[test]
    fn open_jobs_query_defaults_radius() {
        let f = validate_open_jobs_query(Some(13.75), Some(100.5), None)
            .unwrap()
            .expect("filter");
        assert_eq!(f.radius_km, DEFAULT_RADIUS_KM);
        assert_eq!((f.lat, f.lng), (13.75, 100.5));
    }

    #[test]
    fn open_jobs_query_radius_requires_coords() {
        assert!(validate_open_jobs_query(None, None, Some(5.0)).is_err());
    }

    #[test]
    fn open_jobs_query_radius_bounds() {
        assert!(validate_open_jobs_query(Some(0.0), Some(0.0), Some(0.0)).is_err());
        assert!(validate_open_jobs_query(Some(0.0), Some(0.0), Some(-1.0)).is_err());
        assert!(validate_open_jobs_query(Some(0.0), Some(0.0), Some(MAX_RADIUS_KM + 0.1)).is_err());
        assert!(validate_open_jobs_query(Some(0.0), Some(0.0), Some(f64::NAN)).is_err());
        assert!(validate_open_jobs_query(Some(0.0), Some(0.0), Some(MAX_RADIUS_KM)).is_ok());
    }
}
