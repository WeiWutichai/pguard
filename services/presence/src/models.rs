//! DTOs (REST responses + query params), the sqlx row types, and the Redis live-position event.
//! Transport/serialization only — the validation/online rules live in [`crate::domain`].

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ----- REST query params -----

/// `GET /locations?online_only=true` — restrict the bulk list to connected guards.
#[derive(Debug, Default, Deserialize)]
pub struct LocationsQuery {
    #[serde(default)]
    pub online_only: bool,
}

/// `GET /guards/{id}/history?limit=&offset=` — paginated, newest-first.
#[derive(Debug, Deserialize)]
pub struct HistoryQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// `GET /admin/track/replay` — admin route playback (#141 ดูเส้นทางย้อนหลัง). EITHER mode:
///   * by JOB:  `?booking_id=<uuid>` — the GPS track during that booking's window (the window is
///     derived server-side from the event-projected assignment; `guard_id`/`from`/`to` ignored).
///   * by GUARD: `?guard_id=<uuid>&from=<rfc3339>&to=<rfc3339>` — that guard's track in the
///     `[from, to)` window. `from`/`to` are optional and default to the last 24h ending now.
///
/// `limit` caps the returned points (default 500, hard cap 1000); see [`crate::api::replay`].
#[derive(Debug, Default, Deserialize)]
pub struct ReplayQuery {
    pub booking_id: Option<Uuid>,
    pub guard_id: Option<Uuid>,
    pub from: Option<DateTime<Utc>>,
    pub to: Option<DateTime<Utc>>,
    pub limit: Option<i64>,
}

// ----- REST response DTOs -----

/// A guard's current position + liveness, returned by `/locations` (bulk) and
/// `/guards/{id}/location`. `is_live` is computed (not stored): the 5-minute discovery
/// freshness rule applied to `is_online` + `recorded_at` at read time.
#[derive(Debug, Serialize)]
pub struct GuardLocation {
    pub guard_id: Uuid,
    pub lat: f64,
    pub lng: f64,
    pub accuracy: Option<f32>,
    pub heading: Option<f32>,
    pub speed: Option<f32>,
    pub recorded_at: DateTime<Utc>,
    pub is_online: bool,
    pub is_live: bool,
}

/// One point of a guard's GPS history (from the append-only `location_history`).
#[derive(Debug, Serialize)]
pub struct HistoryPoint {
    pub lat: f64,
    pub lng: f64,
    pub accuracy: Option<f32>,
    pub recorded_at: DateTime<Utc>,
}

/// `GET /admin/track/replay` response — the resolved guard, the resolved `[from, to)` window, the
/// ordered (oldest-first) GPS track, and the cap metadata. `truncated` is true when the cap was
/// hit (more points exist in the window than were returned) so the caller can page or narrow.
///
/// `speed`/`heading` are DELIBERATELY ABSENT from each point: the append-only `location_history`
/// store keeps only lat/lng/accuracy + time (0001) — heading/speed are live-only signals on
/// `guard_locations`, never historized. `per_point_speed_heading_available = false` flags this so
/// a client never assumes they were dropped (they were never stored — not fabricated here).
#[derive(Debug, Serialize)]
pub struct TrackReplay {
    pub guard_id: Uuid,
    /// Set only for the by-booking mode (echoes which booking the window was derived from).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub booking_id: Option<Uuid>,
    pub from: DateTime<Utc>,
    pub to: DateTime<Utc>,
    /// For the by-booking mode: true when the job is still active (no terminal event yet), so
    /// `to` was clamped to the request time rather than a real `ended_at`. Always false for the
    /// by-guard mode (the window is the requested `[from, to)`).
    pub window_open: bool,
    pub points: Vec<HistoryPoint>,
    /// The applied cap (default 500, hard max 1000) — number of points the response can hold.
    pub limit: i64,
    /// True when `points.len() == limit` (the window holds at least this many points; there may
    /// be more — narrow the window or raise `limit` up to the cap to see the rest).
    pub truncated: bool,
    /// Always false — `location_history` does not store per-point speed/heading (see above). FLAG,
    /// not a fabrication.
    pub per_point_speed_heading_available: bool,
}

/// `GET /internal/online-guards` — the guards currently LIVE, each with their latest fix
/// position (service-JWT'd; consumed by booking's discovery). booking uses membership for the
/// "พร้อมรับงาน" online filter AND the coordinates to sort the customer's guard list
/// nearest-to-meetup (C2). Deliberately narrow — just id + position, none of the
/// heading/speed/accuracy the admin `/locations` bulk read carries (least-privilege).
#[derive(Debug, Serialize)]
pub struct OnlineGuards {
    pub guards: Vec<OnlineGuard>,
}

/// One live guard in [`OnlineGuards`]: the id plus the latest fix coordinates (the guard's
/// current position, which booking measures against the meetup point for the nearest-first sort).
#[derive(Debug, Serialize)]
pub struct OnlineGuard {
    pub guard_id: Uuid,
    pub lat: f64,
    pub lng: f64,
}

// ----- sqlx row types (DB I/O shapes) -----

/// A `presence.guard_locations` row. `is_live` is NOT a column — the handler computes it via
/// [`crate::domain::is_live`] and assembles [`GuardLocation`].
#[derive(Debug, sqlx::FromRow)]
pub struct GuardLocationRow {
    pub guard_id: Uuid,
    pub lat: f64,
    pub lng: f64,
    pub accuracy: Option<f32>,
    pub heading: Option<f32>,
    pub speed: Option<f32>,
    pub recorded_at: DateTime<Utc>,
    pub is_online: bool,
}

/// A `presence.location_history` row projection (history reads select these columns).
#[derive(Debug, sqlx::FromRow)]
pub struct HistoryRow {
    pub latitude: f64,
    pub longitude: f64,
    pub accuracy_m: Option<f32>,
    pub recorded_at: DateTime<Utc>,
}

impl From<HistoryRow> for HistoryPoint {
    fn from(r: HistoryRow) -> Self {
        Self {
            lat: r.latitude,
            lng: r.longitude,
            accuracy: r.accuracy_m,
            recorded_at: r.recorded_at,
        }
    }
}

/// The job-window projection of a `presence.guard_assignments` row (0004): which guard ran the
/// booking and the accept→terminal window. `guard_id`/`started_at` are NULL for a row projected
/// before the guard/accept was known (e.g. a terminal-before-accept reorder, or a pre-0004 row);
/// the by-booking replay handler treats a missing `guard_id`/`started_at` as un-replayable.
#[derive(Debug, sqlx::FromRow)]
pub struct AssignmentWindowRow {
    pub guard_id: Option<Uuid>,
    pub started_at: Option<DateTime<Utc>>,
    pub ended_at: Option<DateTime<Utc>>,
}

// ----- Redis pub/sub live-position event -----

/// The raw fix republished to Redis pub/sub (channel `presence:gps`) for the admin live map.
/// Raw high-frequency GPS stays on Redis — NOT NATS (CLAUDE.md / the presence boundary).
#[derive(Debug, Serialize)]
pub struct GpsEvent {
    pub guard_id: Uuid,
    pub lat: f64,
    pub lng: f64,
    pub accuracy: Option<f32>,
    pub heading: Option<f32>,
    pub speed: Option<f32>,
    pub recorded_at: DateTime<Utc>,
}
