//! PURE helpers for the booking-status WebSocket — no axum / nats / tokio here.
//!
//! Maps a `pguard.events.booking.*` event (as published by the booking outbox relay, i.e. a
//! serialized [`shared_events::EventEnvelope`]) to the client frame the mobile track coded
//! against:
//!
//! ```json
//! { "type": "booking_status", "booking_id": "…", "status": "…", "occurred_at": "…", "guard_id": "…"? }
//! ```
//!
//! `status` uses the booking lifecycle wire values (accepted / en_route / arrived /
//! pending_completion / completed / declined / cancelled). `pending_completion` arrives live via
//! `booking.completion_requested` (the guard's completion request) so the customer's screen
//! updates without a manual refresh; the initial REST snapshot still covers a mid-flight connect.

use serde_json::Value;
use shared_events::topics;

/// The sentinel "status" the hub forwards for a guard CHECK-IN (`booking.progress_reported`).
/// It is NOT a booking lifecycle status — the booking stays `arrived`. It rides the existing
/// `booking_status` frame as a lightweight live NUDGE so the customer's live screen re-pulls its
/// progress-reports (the new check-in photo + the advancing countdown) WITHOUT a manual refresh.
/// The mobile client recognises it as a refresh-only signal and never folds it into `status`.
pub const PROGRESS_REPORTED_NUDGE: &str = "progress_reported";

/// Map a booking event topic (`EventEnvelope.event_type`) to the client status wire value, or
/// `None` if the topic carries no client-visible status transition.
///
/// `booking.progress_reported` (a guard hourly check-in) is NOT a lifecycle transition, so it maps
/// to the [`PROGRESS_REPORTED_NUDGE`] sentinel rather than a real status — the customer's live
/// screen treats it as "re-pull the check-in timeline + countdown", not a status change.
pub fn status_from_topic(event_type: &str) -> Option<&'static str> {
    if event_type == topics::BOOKING_JOB_ACCEPTED {
        Some("accepted")
    } else if event_type == topics::BOOKING_GUARD_EN_ROUTE {
        Some("en_route")
    } else if event_type == topics::BOOKING_ARRIVED {
        Some("arrived")
    } else if event_type == topics::BOOKING_COMPLETION_REQUESTED {
        Some("pending_completion")
    } else if event_type == topics::BOOKING_COMPLETED {
        Some("completed")
    } else if event_type == topics::BOOKING_DECLINED {
        Some("declined")
    } else if event_type == topics::BOOKING_CANCELLED {
        Some("cancelled")
    } else if event_type == topics::BOOKING_PROGRESS_REPORTED {
        Some(PROGRESS_REPORTED_NUDGE)
    } else {
        None
    }
}

/// A client-ready status update: which booking, the status, when, and the guard (if assigned).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StatusUpdate {
    pub booking_id: String,
    pub status: String,
    pub occurred_at: String,
    pub guard_id: Option<String>,
}

/// Parse a NATS message body (a serialized `EventEnvelope` JSON) into a [`StatusUpdate`], or
/// `None` if it is not a client-visible booking status event (or is malformed). Pure: the
/// caller does the IO and the per-connection `booking_id` filtering.
pub fn parse_status_update(envelope_bytes: &[u8]) -> Option<StatusUpdate> {
    let v: Value = serde_json::from_slice(envelope_bytes).ok()?;
    let status = status_from_topic(v.get("event_type")?.as_str()?)?;
    let payload = v.get("payload")?;
    let booking_id = payload.get("booking_id")?.as_str()?.to_string();
    let occurred_at = v
        .get("occurred_at")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let guard_id = payload
        .get("guard_id")
        .and_then(Value::as_str)
        .map(str::to_string);
    Some(StatusUpdate {
        booking_id,
        status: status.to_string(),
        occurred_at,
        guard_id,
    })
}

/// Cross-Site-WebSocket-Hijacking gate for the upgrade. CORS does NOT protect WS handshakes, so
/// the upgrade must check `Origin` itself. A browser always sends `Origin`; a native client
/// (mobile, Bearer) sends none. Rule: **absent Origin → allowed** (non-browser); **present
/// Origin → must be in the allowlist**. This blocks a cross-origin page from opening the socket
/// on a victim's cookie while leaving mobile/Bearer clients unaffected. Pure + testable.
pub fn origin_allowed(origin: Option<&str>, allowed: &[String]) -> bool {
    match origin {
        None => true,
        Some(o) => allowed.iter().any(|a| a == o),
    }
}

/// Build the outbound client frame. `guard_id` is included only when present (matches the
/// mobile contract's optional field).
pub fn status_frame(
    booking_id: &str,
    status: &str,
    occurred_at: &str,
    guard_id: Option<&str>,
) -> Value {
    let mut frame = serde_json::json!({
        "type": "booking_status",
        "booking_id": booking_id,
        "status": status,
        "occurred_at": occurred_at,
    });
    if let Some(g) = guard_id {
        frame["guard_id"] = Value::String(g.to_string());
    }
    frame
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_every_booking_topic_to_a_status() {
        assert_eq!(
            status_from_topic(topics::BOOKING_JOB_ACCEPTED),
            Some("accepted")
        );
        assert_eq!(
            status_from_topic(topics::BOOKING_GUARD_EN_ROUTE),
            Some("en_route")
        );
        assert_eq!(status_from_topic(topics::BOOKING_ARRIVED), Some("arrived"));
        assert_eq!(
            status_from_topic(topics::BOOKING_COMPLETION_REQUESTED),
            Some("pending_completion")
        );
        assert_eq!(
            status_from_topic(topics::BOOKING_COMPLETED),
            Some("completed")
        );
        assert_eq!(
            status_from_topic(topics::BOOKING_DECLINED),
            Some("declined")
        );
        assert_eq!(
            status_from_topic(topics::BOOKING_CANCELLED),
            Some("cancelled")
        );
    }

    #[test]
    fn maps_progress_reported_to_the_refresh_nudge() {
        // A guard check-in is NOT a lifecycle transition — it maps to the refresh-only sentinel so
        // the customer's live screen re-pulls its progress timeline without a manual refresh.
        assert_eq!(
            status_from_topic(topics::BOOKING_PROGRESS_REPORTED),
            Some(PROGRESS_REPORTED_NUDGE)
        );
        assert_eq!(PROGRESS_REPORTED_NUDGE, "progress_reported");
    }

    #[test]
    fn ignores_non_status_topics() {
        assert_eq!(status_from_topic("pguard.events.payment.completed"), None);
        assert_eq!(
            status_from_topic("pguard.events.booking.something_new"),
            None
        );
        // `requested` carries no client-visible status frame (the customer created it).
        assert_eq!(status_from_topic(topics::BOOKING_REQUESTED), None);
    }

    #[test]
    fn parses_progress_reported_to_the_nudge_frame() {
        // The check-in envelope the booking outbox publishes — carries booking_id + customer_id +
        // guard_id (see booking::domain::events::event_for_progress_report).
        let bytes = serde_json::to_vec(&serde_json::json!({
            "event_id": "11111111-1111-1111-1111-111111111111",
            "event_type": topics::BOOKING_PROGRESS_REPORTED,
            "occurred_at": "2026-06-25T10:00:00Z",
            "correlation_id": "22222222-2222-2222-2222-222222222222",
            "payload": { "booking_id": "b1", "customer_id": "c1", "guard_id": "g1" }
        }))
        .unwrap();
        let u = parse_status_update(&bytes).expect("check-in must fan out as a nudge");
        assert_eq!(u.booking_id, "b1");
        assert_eq!(u.status, PROGRESS_REPORTED_NUDGE);
        assert_eq!(u.guard_id.as_deref(), Some("g1"));
    }

    #[test]
    fn parses_a_well_formed_envelope() {
        let bytes = serde_json::to_vec(&serde_json::json!({
            "event_id": "11111111-1111-1111-1111-111111111111",
            "event_type": topics::BOOKING_GUARD_EN_ROUTE,
            "occurred_at": "2026-06-05T10:00:00Z",
            "correlation_id": "22222222-2222-2222-2222-222222222222",
            "payload": { "booking_id": "b1", "customer_id": "c1", "guard_id": "g1" }
        }))
        .unwrap();
        let u = parse_status_update(&bytes).expect("should parse");
        assert_eq!(u.booking_id, "b1");
        assert_eq!(u.status, "en_route");
        assert_eq!(u.occurred_at, "2026-06-05T10:00:00Z");
        assert_eq!(u.guard_id.as_deref(), Some("g1"));
    }

    #[test]
    fn parses_completion_requested_to_pending_completion() {
        // The guard's completion request must surface to the customer's live WS as
        // pending_completion (the bug was this topic being dropped → no live frame).
        let bytes = serde_json::to_vec(&serde_json::json!({
            "event_id": "11111111-1111-1111-1111-111111111111",
            "event_type": topics::BOOKING_COMPLETION_REQUESTED,
            "occurred_at": "2026-06-24T10:00:00Z",
            "correlation_id": "22222222-2222-2222-2222-222222222222",
            "payload": { "booking_id": "b1", "customer_id": "c1", "guard_id": "g1" }
        }))
        .unwrap();
        let u = parse_status_update(&bytes).expect("should parse");
        assert_eq!(u.booking_id, "b1");
        assert_eq!(u.status, "pending_completion");
        assert_eq!(u.guard_id.as_deref(), Some("g1"));
    }

    #[test]
    fn parse_returns_none_for_unmappable_or_malformed() {
        // non-booking topic
        let payment = serde_json::to_vec(&serde_json::json!({
            "event_type": "pguard.events.payment.completed",
            "payload": { "booking_id": "b1" }
        }))
        .unwrap();
        assert!(parse_status_update(&payment).is_none());
        // missing booking_id
        let no_id = serde_json::to_vec(&serde_json::json!({
            "event_type": topics::BOOKING_ARRIVED,
            "payload": { "customer_id": "c1" }
        }))
        .unwrap();
        assert!(parse_status_update(&no_id).is_none());
        // not JSON
        assert!(parse_status_update(b"not json").is_none());
    }

    #[test]
    fn parse_omits_guard_when_absent() {
        let bytes = serde_json::to_vec(&serde_json::json!({
            "event_type": topics::BOOKING_DECLINED,
            "occurred_at": "2026-06-05T10:00:00Z",
            "payload": { "booking_id": "b9", "customer_id": "c1" }
        }))
        .unwrap();
        let u = parse_status_update(&bytes).unwrap();
        assert_eq!(u.status, "declined");
        assert!(u.guard_id.is_none());
    }

    #[test]
    fn frame_matches_the_mobile_contract() {
        let f = status_frame("b1", "arrived", "2026-06-05T10:00:00Z", Some("g1"));
        assert_eq!(f["type"], "booking_status");
        assert_eq!(f["booking_id"], "b1");
        assert_eq!(f["status"], "arrived");
        assert_eq!(f["occurred_at"], "2026-06-05T10:00:00Z");
        assert_eq!(f["guard_id"], "g1");
    }

    #[test]
    fn frame_omits_guard_id_when_none() {
        let f = status_frame("b1", "cancelled", "t", None);
        assert!(f.get("guard_id").is_none(), "guard_id omitted when absent");
        assert_eq!(f["type"], "booking_status");
    }

    #[test]
    fn origin_gate_allows_absent_and_listed_rejects_others() {
        let allowed = vec![
            "http://localhost:3000".to_string(),
            "https://admin.pguard.app".to_string(),
        ];
        // Native client (mobile/Bearer) sends no Origin → allowed.
        assert!(origin_allowed(None, &allowed));
        // Listed browser origins → allowed.
        assert!(origin_allowed(Some("http://localhost:3000"), &allowed));
        assert!(origin_allowed(Some("https://admin.pguard.app"), &allowed));
        // Cross-origin page → rejected (CSWSH gate).
        assert!(!origin_allowed(Some("https://evil.example.com"), &allowed));
        assert!(!origin_allowed(Some("http://localhost:9999"), &allowed));
    }
}
