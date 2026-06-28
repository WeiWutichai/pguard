//! PURE chat domain — no DB, no HTTP, no NATS, no S3. 100% unit-testable.
//!
//! Four concerns, each ported (and tightened) from v1 chat:
//!   * [`MessageType`] — the message kind enum (kept DB-free; the repo casts to/from text).
//!   * **Alignment + unread** ([`is_outbound`], [`counts_as_unread`]) — decided by ROLE, never
//!     by `sender_id` (the same user is the guard in one conversation, the customer in another).
//!     `counts_as_unread` encodes the SQL `sender_role IS DISTINCT FROM acting_role` semantics.
//!   * **Read-only state** ([`is_closed`]/[`is_writable`]) — the server-side gate that rejects
//!     writes to a `completed`/`cancelled` conversation (never trust the client).
//!   * **Attachment validation** ([`validate_upload`] + the magic-byte detector) — checks SIZE
//!     before reading magic bytes, then verifies the declared MIME against the actual bytes.

use std::fmt;
use std::str::FromStr;

use shared::error::AppError;

// =============================================================================
// MessageType
// =============================================================================

/// The message kind. Serialized lowercase to match the Postgres enum `chat.message_type` (NOT
/// `sqlx::Type` — the repo binds [`MessageType::as_db_str`] with a `::chat.message_type` cast
/// and reads the column back as text, keeping `domain` DB-free; mirrors calling.call_status).
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MessageType {
    Text,
    Image,
    Video,
    System,
}

impl MessageType {
    pub fn as_db_str(self) -> &'static str {
        match self {
            MessageType::Text => "text",
            MessageType::Image => "image",
            MessageType::Video => "video",
            MessageType::System => "system",
        }
    }
}

impl fmt::Display for MessageType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_db_str())
    }
}

impl FromStr for MessageType {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "text" => Ok(MessageType::Text),
            "image" => Ok(MessageType::Image),
            "video" => Ok(MessageType::Video),
            "system" => Ok(MessageType::System),
            other => Err(format!("unknown message_type: {other}")),
        }
    }
}

// =============================================================================
// Call summary (server-generated system message)
// =============================================================================

/// The PINNED shared-contract shape for a call-summary `system` message's `content` (a JSON
/// string). Field names are intentionally terse + STABLE (`k`/`ct`/`oc`/`ds`) — the mobile client
/// parses this exact shape. Built server-side from a terminated call's
/// `pguard.events.calling.ended` / `.rejected` event; clients can no longer forge a `system`
/// message (the security fix), so this is the ONLY producer of the shape.
///
///   `{"k":"call","ct":"audio"|"video","oc":"completed"|"missed"|"rejected","ds":<secs|null>}`
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct CallSummary {
    /// Kind discriminator — always `"call"` (lets the client tell a call line from future
    /// system kinds without sniffing other fields).
    pub k: &'static str,
    /// Call media: `"audio"` or `"video"`.
    pub ct: String,
    /// Outcome: `"completed"` | `"missed"` | `"rejected"`.
    pub oc: &'static str,
    /// Duration in whole seconds, or `null` if the call was never answered.
    pub ds: Option<i32>,
}

impl CallSummary {
    /// Derive the summary from a terminated call's event fields (PURE — no I/O, unit-tested):
    ///   * `oc = "completed"` when the call was ANSWERED — `answered_at` present OR
    ///     `duration_seconds > 0` (a connected/ended call).
    ///   * `oc = "rejected"` when the callee declined — terminal `status == "rejected"` OR
    ///     `end_reason` carries a reject marker — and it was NOT answered.
    ///   * `oc = "missed"` otherwise (never answered, not a reject — e.g. caller cancelled / timeout).
    ///
    /// `ds` is the duration when answered, else `null`. `ct` is normalized to a known media kind
    /// (`audio`/`video`); an unknown value falls back to `audio` (the mobile default).
    pub fn from_call(
        call_type: &str,
        status: &str,
        end_reason: Option<&str>,
        answered_at_present: bool,
        duration_seconds: Option<i32>,
    ) -> Self {
        let answered = answered_at_present || duration_seconds.is_some_and(|d| d > 0);
        let rejected = !answered
            && (status == "rejected"
                || end_reason.is_some_and(|r| r.contains("reject") || r.contains("declin")));
        let oc = if answered {
            "completed"
        } else if rejected {
            "rejected"
        } else {
            "missed"
        };
        let ct = if is_valid_call_type(call_type) {
            call_type.to_string()
        } else {
            "audio".to_string()
        };
        CallSummary {
            k: "call",
            ct,
            oc,
            // Duration only carries meaning for an answered call.
            ds: if answered { duration_seconds } else { None },
        }
    }

    /// Serialize to the pinned JSON STRING stored as the `system` message's `content`. Infallible
    /// in practice (a fixed, small struct of primitives); on the (unreachable) serde error we fall
    /// back to a minimal valid shape so the request path NEVER panics (no `.expect()` / `.unwrap()`).
    pub fn to_content(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| {
            format!(
                r#"{{"k":"call","ct":"audio","oc":"{}","ds":null}}"#,
                self.oc
            )
        })
    }
}

/// The PARSED form of a stored call-summary `system` message — the structured read of the pinned
/// `{"k":"call","ct":...,"oc":...,"ds":...}` JSON, so a reader (the admin audit view) renders a
/// real call event instead of raw JSON. PURE (no I/O); the inverse of [`CallSummary::to_content`].
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ParsedCallSummary {
    /// `"audio"` | `"video"` (from `ct`).
    pub call_type: String,
    /// `"completed"` | `"missed"` | `"rejected"` (from `oc`).
    pub outcome: String,
    /// Whole seconds for an answered call, else `None` (from `ds`).
    pub duration_seconds: Option<i32>,
}

/// Try to parse a `system` message's `content` as the pinned call-summary JSON. Returns `Some`
/// ONLY when the JSON is an object whose discriminator `k == "call"` (the summary kind) — any
/// other `system` content (a future system kind, or non-JSON) yields `None`, so the caller falls
/// back to a generic `system` render. Defensive: a missing/garbled `ct`/`oc` still yields a value
/// (the raw string is carried through) since the row is a known call line; only the `k` gate and
/// well-formed JSON object are required.
pub fn parse_call_summary(content: &str) -> Option<ParsedCallSummary> {
    let v: serde_json::Value = serde_json::from_str(content).ok()?;
    if v.get("k").and_then(|k| k.as_str()) != Some("call") {
        return None;
    }
    Some(ParsedCallSummary {
        call_type: v
            .get("ct")
            .and_then(|c| c.as_str())
            .unwrap_or("audio")
            .to_string(),
        outcome: v
            .get("oc")
            .and_then(|o| o.as_str())
            .unwrap_or("missed")
            .to_string(),
        // `ds` is null for an unanswered call; only an integer carries a duration.
        duration_seconds: v
            .get("ds")
            .and_then(|d| d.as_i64())
            .and_then(|d| i32::try_from(d).ok()),
    })
}

/// Accepted call media types (mirrors calling's `call_type` enum). The summary normalizes an
/// unknown value to `audio`.
const VALID_CALL_TYPES: [&str; 2] = ["audio", "video"];

/// `true` iff `t` is a known call type.
fn is_valid_call_type(t: &str) -> bool {
    VALID_CALL_TYPES.contains(&t)
}

// =============================================================================
// Roles, alignment, unread
// =============================================================================

/// The two conversation roles (drives alignment + per-role read receipts). `admin` is NOT a
/// conversation role — admins moderate, they don't participate.
pub const VALID_ROLES: [&str; 2] = ["guard", "customer"];

/// `true` iff `role` is a valid conversation role. The create path rejects anything else.
pub fn is_valid_role(role: &str) -> bool {
    VALID_ROLES.contains(&role)
}

/// `true` iff a message authored as `sender_role` aligns to the RIGHT (the reader's own side)
/// for a reader acting as `acting_role`. Alignment is by ROLE, never `sender_id`.
///
/// The CANONICAL pure rule for client-side bubble alignment, unit-tested here per the spec.
/// Production alignment runs client-side off the `sender_role` the server returns, so this is a
/// reference/spec encoding rather than a server call site — hence `allow(dead_code)`.
#[allow(dead_code)]
pub fn is_outbound(sender_role: &str, acting_role: &str) -> bool {
    sender_role == acting_role
}

/// Encodes the unread predicate `sender_role IS DISTINCT FROM acting_role`: a message counts as
/// unread (incoming) for a reader acting as `acting_role` iff its `sender_role` differs. NULL
/// `sender_role` is DISTINCT FROM any concrete role → counts as unread (defensive — v2 stores a
/// non-null role, so this only matters for legacy/garbage rows).
///
/// The CANONICAL pure rule, unit-tested here per the spec. The hot path runs the SAME predicate
/// IN SQL inside the single N+1-free `list_conversations` query (`sender_role IS DISTINCT FROM
/// $2`), so this Rust twin is a reference/spec encoding — hence `allow(dead_code)`.
#[allow(dead_code)]
pub fn counts_as_unread(sender_role: Option<&str>, acting_role: &str) -> bool {
    match sender_role {
        Some(s) => s != acting_role,
        None => true,
    }
}

// =============================================================================
// Read-only state
// =============================================================================

/// `true` iff the linked booking status closes the conversation to new writes. A `None` status
/// (unknown / not yet pushed) is treated as OPEN — the gate only fires on an explicit terminal
/// status, so an un-synced conversation is never silently frozen.
pub fn is_closed(request_status: Option<&str>) -> bool {
    matches!(request_status, Some("completed") | Some("cancelled"))
}

/// `true` iff a write (message send / attachment upload) is allowed. The inverse of
/// [`is_closed`]. The server enforces this even though the client also disables send.
pub fn is_writable(request_status: Option<&str>) -> bool {
    !is_closed(request_status)
}

// =============================================================================
// Attachment validation (magic bytes + size)
// =============================================================================

/// 10MB cap for images.
pub const MAX_IMAGE_SIZE: usize = 10 * 1024 * 1024;
/// 200MB cap for videos (phone 1080p hits 50MB in ~15s; matches the booking cap).
pub const MAX_VIDEO_SIZE: usize = 200 * 1024 * 1024;

/// Allowed declared MIME types: images (JPEG, PNG, WEBP) + videos (MP4, QuickTime/MOV).
pub const ALLOWED_MIME_TYPES: [&str; 5] = [
    "image/jpeg",
    "image/png",
    "image/webp",
    "video/mp4",
    "video/quicktime",
];

/// `true` iff `mime_type` is a video kind (selects the 200MB cap + `video` message type).
pub fn is_video_mime(mime_type: &str) -> bool {
    mime_type.starts_with("video/")
}

/// Map a (validated) MIME type to a file extension for the object key.
pub fn mime_to_extension(mime_type: &str) -> &'static str {
    match mime_type {
        "image/jpeg" => "jpg",
        "image/png" => "png",
        "image/webp" => "webp",
        "video/mp4" => "mp4",
        "video/quicktime" => "mov",
        _ => "bin",
    }
}

/// Detect the ACTUAL file type from magic bytes, ignoring the client-declared MIME. `None` for
/// anything not in the allowed set.
///   JPEG `FF D8 FF` · PNG `89 50 4E 47 0D 0A 1A 0A` · WEBP `RIFF....WEBP` ·
///   MP4/MOV bytes 4-7 `ftyp` (brand `qt  ` ⇒ QuickTime, else MP4).
pub fn detect_mime_from_bytes(data: &[u8]) -> Option<&'static str> {
    if data.len() >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
        return Some("image/jpeg");
    }
    if data.len() >= 8 && data[..8] == [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A] {
        return Some("image/png");
    }
    if data.len() >= 12 && &data[..4] == b"RIFF" && &data[8..12] == b"WEBP" {
        return Some("image/webp");
    }
    // ISO base media (MP4/MOV): bytes 4-7 are "ftyp"; the brand at 8-11 distinguishes MOV.
    if data.len() >= 8 && &data[4..8] == b"ftyp" {
        if data.len() >= 12 && &data[8..12] == b"qt  " {
            return Some("video/quicktime");
        }
        return Some("video/mp4");
    }
    None
}

/// Validate an attachment upload. Order matters (CLAUDE.md / spec): **size is checked BEFORE
/// the magic bytes** so an oversized blob is rejected without a large read/allocation. Then the
/// declared MIME must be allowed AND match the actual content (mp4/mov are interchangeable since
/// they share the ISO container). Returns the canonical (detected) MIME on success.
pub fn validate_upload(
    declared_mime: &str,
    file_size: usize,
    data: &[u8],
) -> Result<&'static str, AppError> {
    // 1. Declared MIME must be in the allowlist.
    if !ALLOWED_MIME_TYPES.contains(&declared_mime) {
        return Err(AppError::BadRequest(format!(
            "Unsupported file type: {declared_mime}. Allowed: JPEG, PNG, WEBP, MP4, MOV"
        )));
    }

    // 2. SIZE before magic bytes — reject oversized uploads cheaply.
    let max_size = if is_video_mime(declared_mime) {
        MAX_VIDEO_SIZE
    } else {
        MAX_IMAGE_SIZE
    };
    if file_size > max_size {
        let max_mb = max_size / (1024 * 1024);
        return Err(AppError::BadRequest(format!(
            "File too large: {file_size} bytes (max {max_mb}MB)"
        )));
    }

    // 3. Magic bytes must match a known format.
    let detected = detect_mime_from_bytes(data).ok_or_else(|| {
        AppError::BadRequest(
            "File content does not match any allowed format (image or video)".to_string(),
        )
    })?;

    // 4. Declared MIME must agree with the content (videos are interchangeable mp4/mov).
    let agrees =
        detected == declared_mime || (is_video_mime(detected) && is_video_mime(declared_mime));
    if !agrees {
        return Err(AppError::BadRequest(format!(
            "MIME mismatch: declared {declared_mime} but content is {detected}"
        )));
    }

    Ok(detected)
}

#[cfg(test)]
mod tests {
    use super::*;

    // ----- MessageType -----

    #[test]
    fn message_type_db_str_roundtrips() {
        for t in [
            MessageType::Text,
            MessageType::Image,
            MessageType::Video,
            MessageType::System,
        ] {
            assert_eq!(t.as_db_str().parse::<MessageType>().unwrap(), t);
            assert_eq!(t.to_string(), t.as_db_str());
        }
        assert!("bogus".parse::<MessageType>().is_err());
    }

    #[test]
    fn message_type_serializes_lowercase() {
        assert_eq!(
            serde_json::to_string(&MessageType::Image).unwrap(),
            "\"image\""
        );
        let t: MessageType = serde_json::from_str("\"video\"").unwrap();
        assert_eq!(t, MessageType::Video);
    }

    // ----- call summary -----

    #[test]
    fn summary_completed_when_answered() {
        // answered_at present → completed, ds carried.
        let s = CallSummary::from_call("video", "ended", Some("hangup"), true, Some(125));
        assert_eq!(s.oc, "completed");
        assert_eq!(s.ct, "video");
        assert_eq!(s.ds, Some(125));
        // duration > 0 also counts as answered even if answered_at flag is false (defensive).
        let s2 = CallSummary::from_call("audio", "ended", None, false, Some(3));
        assert_eq!(s2.oc, "completed");
        assert_eq!(s2.ds, Some(3));
    }

    #[test]
    fn summary_rejected_when_declined_and_unanswered() {
        // terminal status rejected → rejected, ds null.
        let s =
            CallSummary::from_call("audio", "rejected", Some("rejected_by_callee"), false, None);
        assert_eq!(s.oc, "rejected");
        assert_eq!(s.ds, None);
        // end_reason marker also classifies as rejected even if status text differs.
        let s2 = CallSummary::from_call("audio", "ended", Some("declined"), false, None);
        assert_eq!(s2.oc, "rejected");
    }

    #[test]
    fn summary_missed_when_never_answered_not_rejected() {
        // initiated → ended without answer, caller cancelled → missed, ds null.
        let s = CallSummary::from_call("audio", "missed", Some("cancelled"), false, None);
        assert_eq!(s.oc, "missed");
        assert_eq!(s.ds, None);
    }

    #[test]
    fn summary_answered_wins_over_reject_markers() {
        // An ANSWERED call is completed even if end_reason mentions reject (answered dominates).
        let s = CallSummary::from_call("video", "rejected", Some("rejected"), true, Some(10));
        assert_eq!(
            s.oc, "completed",
            "answered call is never classified rejected"
        );
    }

    #[test]
    fn summary_unknown_call_type_falls_back_to_audio() {
        let s = CallSummary::from_call("screen", "ended", None, true, Some(5));
        assert_eq!(
            s.ct, "audio",
            "unknown media normalizes to audio (mobile default)"
        );
    }

    #[test]
    fn summary_to_content_matches_pinned_shape() {
        let s = CallSummary::from_call("video", "ended", None, true, Some(90));
        let json = s.to_content();
        // Round-trips to the exact contract keys + values.
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["k"], "call");
        assert_eq!(v["ct"], "video");
        assert_eq!(v["oc"], "completed");
        assert_eq!(v["ds"], 90);
        // A never-answered call serializes ds as null (not omitted).
        let missed = CallSummary::from_call("audio", "missed", None, false, None).to_content();
        let mv: serde_json::Value = serde_json::from_str(&missed).unwrap();
        assert!(mv["ds"].is_null(), "ds is null for an unanswered call");
        assert_eq!(mv["oc"], "missed");
    }

    // ----- parse_call_summary (inverse of to_content) -----

    #[test]
    fn parse_call_summary_roundtrips_to_content() {
        // A completed video call round-trips: to_content → parse_call_summary.
        let summary = CallSummary::from_call("video", "ended", None, true, Some(90));
        let parsed = parse_call_summary(&summary.to_content()).expect("parses the pinned shape");
        assert_eq!(parsed.call_type, "video");
        assert_eq!(parsed.outcome, "completed");
        assert_eq!(parsed.duration_seconds, Some(90));

        // A never-answered (missed) audio call: ds is null → None.
        let missed = CallSummary::from_call("audio", "missed", None, false, None);
        let pm = parse_call_summary(&missed.to_content()).expect("parses missed");
        assert_eq!(pm.call_type, "audio");
        assert_eq!(pm.outcome, "missed");
        assert_eq!(pm.duration_seconds, None);

        // A rejected call.
        let rej = CallSummary::from_call("audio", "rejected", Some("declined"), false, None);
        let pr = parse_call_summary(&rej.to_content()).expect("parses rejected");
        assert_eq!(pr.outcome, "rejected");
    }

    #[test]
    fn parse_call_summary_rejects_non_call_and_garbage() {
        // Not the call kind → None (a future system kind falls back to a generic system render).
        assert!(parse_call_summary(r#"{"k":"other","x":1}"#).is_none());
        // Non-JSON → None.
        assert!(parse_call_summary("just some text").is_none());
        // Missing `k` → None.
        assert!(parse_call_summary(r#"{"ct":"audio","oc":"missed"}"#).is_none());
        // A JSON array (not an object) → None (no `k`).
        assert!(parse_call_summary(r#"["call"]"#).is_none());
    }

    #[test]
    fn parse_call_summary_is_defensive_on_partial_fields() {
        // `k` present but `ct`/`oc` missing → defaults (audio/missed), still Some (it IS a call line).
        let p = parse_call_summary(r#"{"k":"call"}"#).expect("call kind → Some");
        assert_eq!(p.call_type, "audio");
        assert_eq!(p.outcome, "missed");
        assert_eq!(p.duration_seconds, None);
    }

    // ----- roles + alignment -----

    #[test]
    fn valid_roles() {
        assert!(is_valid_role("guard"));
        assert!(is_valid_role("customer"));
        for bad in ["admin", "Guard", "", "manager"] {
            assert!(!is_valid_role(bad), "{bad} must be invalid");
        }
    }

    #[test]
    fn outbound_is_by_role_not_sender_id() {
        // A guard reading their own (guard-authored) message → right side.
        assert!(is_outbound("guard", "guard"));
        assert!(is_outbound("customer", "customer"));
        // The counterpart's message → left side.
        assert!(!is_outbound("guard", "customer"));
        assert!(!is_outbound("customer", "guard"));
    }

    // ----- unread: IS DISTINCT FROM semantics -----

    #[test]
    fn unread_counts_only_the_other_role() {
        // Acting as customer: a guard's message is unread; my own (customer) message is not.
        assert!(counts_as_unread(Some("guard"), "customer"));
        assert!(!counts_as_unread(Some("customer"), "customer"));
        // Acting as guard: symmetric.
        assert!(counts_as_unread(Some("customer"), "guard"));
        assert!(!counts_as_unread(Some("guard"), "guard"));
    }

    #[test]
    fn unread_null_sender_role_is_distinct() {
        // NULL IS DISTINCT FROM 'x' is TRUE — a null-role message counts as unread (defensive).
        assert!(counts_as_unread(None, "customer"));
        assert!(counts_as_unread(None, "guard"));
    }

    // ----- read-only state -----

    #[test]
    fn closed_only_for_terminal_statuses() {
        assert!(is_closed(Some("completed")));
        assert!(is_closed(Some("cancelled")));
        for open in [
            Some("accepted"),
            Some("en_route"),
            Some("arrived"),
            Some("requested"),
        ] {
            assert!(!is_closed(open), "{open:?} must be writable");
        }
    }

    #[test]
    fn unknown_or_missing_status_is_writable() {
        // None (not yet synced) and unrecognized values default to OPEN (don't freeze silently).
        assert!(is_writable(None));
        assert!(is_writable(Some("some_future_status")));
        // The two terminal ones are not writable.
        assert!(!is_writable(Some("completed")));
        assert!(!is_writable(Some("cancelled")));
    }

    // ----- magic bytes -----

    const JPEG: &[u8] = &[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
    const PNG: &[u8] = &[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    const WEBP: &[u8] = b"RIFF\x00\x00\x00\x00WEBP";
    const MP4: &[u8] = b"\x00\x00\x00\x1cftypisom\x00\x00\x02\x00";
    const MOV: &[u8] = b"\x00\x00\x00\x14ftypqt  \x00\x00\x00\x00";
    const GIF: &[u8] = b"GIF89a";

    #[test]
    fn detect_each_allowed_magic() {
        assert_eq!(detect_mime_from_bytes(JPEG), Some("image/jpeg"));
        assert_eq!(detect_mime_from_bytes(PNG), Some("image/png"));
        assert_eq!(detect_mime_from_bytes(WEBP), Some("image/webp"));
        assert_eq!(detect_mime_from_bytes(MP4), Some("video/mp4"));
        assert_eq!(detect_mime_from_bytes(MOV), Some("video/quicktime"));
    }

    #[test]
    fn detect_rejects_unknown_and_short() {
        assert_eq!(detect_mime_from_bytes(GIF), None);
        assert_eq!(detect_mime_from_bytes(b""), None);
        assert_eq!(detect_mime_from_bytes(b"\x00\x00"), None);
        assert_eq!(detect_mime_from_bytes(b"%PDF-1.4"), None);
    }

    #[test]
    fn validate_accepts_each_allowed() {
        assert_eq!(
            validate_upload("image/jpeg", JPEG.len(), JPEG).unwrap(),
            "image/jpeg"
        );
        assert_eq!(
            validate_upload("image/png", PNG.len(), PNG).unwrap(),
            "image/png"
        );
        assert_eq!(
            validate_upload("image/webp", WEBP.len(), WEBP).unwrap(),
            "image/webp"
        );
        assert_eq!(
            validate_upload("video/mp4", MP4.len(), MP4).unwrap(),
            "video/mp4"
        );
        assert_eq!(
            validate_upload("video/quicktime", MOV.len(), MOV).unwrap(),
            "video/quicktime"
        );
    }

    #[test]
    fn validate_video_mime_interchangeable() {
        // Declared mp4 but content is a MOV (qt brand) — both are video/*, accepted.
        assert!(validate_upload("video/mp4", MOV.len(), MOV).is_ok());
        assert!(validate_upload("video/quicktime", MP4.len(), MP4).is_ok());
    }

    #[test]
    fn validate_rejects_disallowed_declared_mime() {
        for (mime, data) in [
            ("image/gif", GIF),
            ("application/pdf", b"%PDF-1.4" as &[u8]),
            ("image/svg+xml", b"<svg>"),
            ("text/plain", b"hello"),
            ("", b"\x00\x00\x00"),
        ] {
            assert!(
                validate_upload(mime, data.len(), data).is_err(),
                "{mime} must reject"
            );
        }
    }

    #[test]
    fn validate_rejects_spoofed_mime() {
        // Declares JPEG but the bytes are PNG → mismatch.
        assert!(validate_upload("image/jpeg", PNG.len(), PNG).is_err());
        // Declares PNG but the bytes are garbage → no detected format.
        assert!(validate_upload("image/png", 10, b"notanimage").is_err());
    }

    #[test]
    fn validate_checks_size_before_magic_bytes() {
        // The bytes are a VALID jpeg header, but the declared size is over the image cap. The
        // size check must fire FIRST (so a hostile caller can't force a big read before reject).
        let over = MAX_IMAGE_SIZE + 1;
        let err = validate_upload("image/jpeg", over, JPEG).unwrap_err();
        match err {
            AppError::BadRequest(m) => assert!(m.contains("too large"), "size error, got: {m}"),
            other => panic!("expected size BadRequest, got {other:?}"),
        }
        // And a video just over its (larger) cap is rejected too.
        assert!(validate_upload("video/mp4", MAX_VIDEO_SIZE + 1, MP4).is_err());
        // 100MB video (under the 200MB cap) passes.
        assert!(validate_upload("video/mp4", 100 * 1024 * 1024, MP4).is_ok());
        // An image at exactly the cap passes.
        assert!(validate_upload("image/jpeg", MAX_IMAGE_SIZE, JPEG).is_ok());
    }

    #[test]
    fn mime_extension_mapping() {
        assert_eq!(mime_to_extension("image/jpeg"), "jpg");
        assert_eq!(mime_to_extension("image/png"), "png");
        assert_eq!(mime_to_extension("image/webp"), "webp");
        assert_eq!(mime_to_extension("video/mp4"), "mp4");
        assert_eq!(mime_to_extension("video/quicktime"), "mov");
        assert_eq!(mime_to_extension("application/pdf"), "bin");
    }

    #[test]
    fn video_mime_detection() {
        assert!(is_video_mime("video/mp4"));
        assert!(is_video_mime("video/quicktime"));
        assert!(!is_video_mime("image/png"));
    }
}
