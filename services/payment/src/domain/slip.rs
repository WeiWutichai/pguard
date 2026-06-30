//! PURE slip-image upload rules — no DB/HTTP/S3 imports (100% unit-testable; the only shared
//! import is the error TYPE). Ported from profile's guard-document validator
//! (`domain/documents`): a payment slip is just an image (the customer's transfer receipt photo),
//! so it reuses the SAME magic-byte/size discipline — declare the MIME from the bytes, never the
//! client extension/header.

use shared::error::AppError;

/// 10 MB cap for a slip image (mirrors the guard-document cap; the gateway carve-out is 12 MiB to
/// cover multipart framing).
pub const MAX_SLIP_SIZE: usize = 10 * 1024 * 1024;

/// Allowed declared MIME types — IMAGES ONLY (a bank-app slip screenshot; no PDF/video).
pub const ALLOWED_SLIP_MIME_TYPES: [&str; 3] = ["image/jpeg", "image/png", "image/webp"];

/// Map a (validated) image MIME type to a file extension for the object key.
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

/// Validate a slip image upload. Order matters: **size is checked BEFORE the magic bytes** so an
/// oversized blob is rejected without a large read. Then the declared MIME must be allowed AND
/// match the actual content. Returns the canonical (detected) MIME on success.
pub fn validate_slip_upload(
    declared_mime: &str,
    file_size: usize,
    data: &[u8],
) -> Result<&'static str, AppError> {
    // 1. Declared MIME must be in the (image-only) allowlist.
    if !ALLOWED_SLIP_MIME_TYPES.contains(&declared_mime) {
        return Err(AppError::BadRequest(format!(
            "Unsupported slip type: {declared_mime}. Allowed: JPEG, PNG, WEBP"
        )));
    }
    // 2. SIZE before magic bytes — reject oversized uploads cheaply.
    if file_size > MAX_SLIP_SIZE {
        let max_mb = MAX_SLIP_SIZE / (1024 * 1024);
        return Err(AppError::BadRequest(format!(
            "Slip image too large: {file_size} bytes (max {max_mb}MB)"
        )));
    }
    // 3. Magic bytes must match a known image format.
    let detected = detect_image_mime(data).ok_or_else(|| {
        AppError::BadRequest("Slip content does not match any allowed image format".to_string())
    })?;
    // 4. Declared MIME must agree with the content.
    if detected != declared_mime {
        return Err(AppError::BadRequest(format!(
            "MIME mismatch: declared {declared_mime} but content is {detected}"
        )));
    }
    Ok(detected)
}

#[cfg(test)]
mod tests {
    use super::*;

    const JPEG: &[u8] = &[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
    const PNG: &[u8] = &[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    const WEBP: &[u8] = b"RIFF\x00\x00\x00\x00WEBP";
    const MP4: &[u8] = b"\x00\x00\x00\x1cftypisom\x00\x00\x02\x00";

    #[test]
    fn detect_each_allowed_image_magic() {
        assert_eq!(detect_image_mime(JPEG), Some("image/jpeg"));
        assert_eq!(detect_image_mime(PNG), Some("image/png"));
        assert_eq!(detect_image_mime(WEBP), Some("image/webp"));
        assert_eq!(detect_image_mime(MP4), None);
        assert_eq!(detect_image_mime(b""), None);
    }

    #[test]
    fn accepts_each_allowed_image() {
        assert_eq!(
            validate_slip_upload("image/jpeg", JPEG.len(), JPEG).unwrap(),
            "image/jpeg"
        );
        assert_eq!(
            validate_slip_upload("image/png", PNG.len(), PNG).unwrap(),
            "image/png"
        );
        assert_eq!(
            validate_slip_upload("image/webp", WEBP.len(), WEBP).unwrap(),
            "image/webp"
        );
    }

    #[test]
    fn rejects_non_images_and_spoofed_mime() {
        assert!(validate_slip_upload("video/mp4", MP4.len(), MP4).is_err());
        assert!(validate_slip_upload("application/pdf", 8, b"%PDF-1.4").is_err());
        // Declares JPEG but the bytes are PNG → mismatch.
        assert!(validate_slip_upload("image/jpeg", PNG.len(), PNG).is_err());
        // Declares PNG but the bytes are garbage → no detected format.
        assert!(validate_slip_upload("image/png", 10, b"notanimage").is_err());
    }

    #[test]
    fn checks_size_before_magic_bytes() {
        let err = validate_slip_upload("image/jpeg", MAX_SLIP_SIZE + 1, JPEG).unwrap_err();
        match err {
            AppError::BadRequest(m) => assert!(m.contains("too large"), "size error, got: {m}"),
            other => panic!("expected size BadRequest, got {other:?}"),
        }
        assert!(validate_slip_upload("image/jpeg", MAX_SLIP_SIZE, JPEG).is_ok());
    }
}
