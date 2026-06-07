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
