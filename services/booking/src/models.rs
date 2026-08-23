//! DTOs for the booking service (transport shapes). Pure data — no I/O.
//!
//! Money fields (`base_fee`, `tip`) are [`rust_decimal::Decimal`] — never `f64` (CLAUDE.md
//! money rules); they serialize as JSON strings via the workspace `serde-str` feature.

use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ----- Requests -----

/// Customer creates a booking request. `guard_count` and `tip` are part of the request but
/// become authoritative once persisted (the money path reads them from the booking, never
/// from the payment request body). `base_fee` is NOT client-settable — it is a server-owned
/// rate (DB default), so the customer can never undercut the price.
#[derive(Debug, Deserialize)]
pub struct CreateBookingRequest {
    pub address: String,
    pub scheduled_at: DateTime<Utc>,
    pub hours: i32,
    /// Optional catalog service the customer picked. When present, the booking's `base_fee`
    /// is resolved SERVER-SIDE from that active catalog service (the client never sends a
    /// fee) and the service's `min_hours` floor is enforced. When absent, behaviour is
    /// unchanged: `base_fee` falls to the server-owned column DEFAULT (back-compat).
    #[serde(default)]
    pub service_id: Option<Uuid>,
    /// Number of guards requested (default 1; validated 1..=20).
    #[serde(default)]
    pub guard_count: Option<i32>,
    /// Optional tip the customer adds up front (default 0; folded into the expected total).
    #[serde(default)]
    pub tip: Option<Decimal>,
    /// Optional site coordinates (both-or-neither; validated ranges) — feed open-job radius
    /// discovery. Coordinates are NOT money: f64 per the presence house style.
    #[serde(default)]
    pub lat: Option<f64>,
    #[serde(default)]
    pub lng: Option<f64>,
    /// DIRECTED OFFER (C3): the ONE guard the customer chose in discovery. When present, the
    /// booking is offered ONLY to that guard — no other guard sees it in `GET /bookings/open` or
    /// can `accept` it (a non-target accept 403s `NOT_OFFERED_TO_YOU`). When absent (the default),
    /// the booking is OPEN first-come (any online guard may claim it — the legacy behaviour). Not
    /// validated to be a real approved guard here (mirrors admin `/assign`): the customer picks
    /// from `GET /available-guards`, so the id is real; a bogus id just makes the booking
    /// unclaimable, never a security issue. There is no auto-fallback to the open pool.
    #[serde(default)]
    pub target_guard_id: Option<Uuid>,
}

/// Customer's verdict on a guard's completion request (`pending_completion`).
#[derive(Debug, Deserialize)]
pub struct ReviewCompletionRequest {
    /// `"approve"` → completed; `"reject"` → back to arrived.
    pub action: String,
}

/// The customer cancels a PRE-ARRIVAL booking (`PUT /bookings/{id}/cancel`). The reason is
/// MANDATORY (contract: `required: true`) but is typed `Option<String>` here on purpose: a body
/// that omits it must fail with the typed 400 `CANCEL_REASON_REQUIRED` the app localizes, not
/// with the Json extractor's untyped deserialization rejection. Validation (which set of codes,
/// the note rules) is [`crate::domain::cancellation::validate_cancellation`] — pure, not here.
#[derive(Debug, Deserialize)]
pub struct CancelBookingRequest {
    /// A stable CUSTOMER reason code: `changed_plan` | `mistake` | `not_needed` | `other`.
    #[serde(default)]
    pub reason: Option<String>,
    /// Optional free text (≤ 500 chars); REQUIRED when `reason == "other"`.
    #[serde(default)]
    pub note: Option<String>,
}

/// The ASSIGNED guard withdraws pre-arrival (`PUT /bookings/{id}/decline`). Same shape as
/// [`CancelBookingRequest`] but a DIFFERENT code set — a customer code sent here is a 400
/// (and vice versa), so the two vocabularies never mix in reporting.
#[derive(Debug, Deserialize)]
pub struct DeclineBookingRequest {
    /// A stable GUARD reason code: `emergency` | `sick` | `cannot_reach` | `other`.
    #[serde(default)]
    pub reason: Option<String>,
    /// Optional free text (≤ 500 chars); REQUIRED when `reason == "other"`.
    #[serde(default)]
    pub note: Option<String>,
}

/// The assigned guard starts the job (`PUT /bookings/{id}/start`) — their GPS fix at the
/// moment of pressing start, feeding the 50m geofence (`domain::geo`). The WHOLE body is
/// optional (older app builds send none): absent body/fields → no fix, which 409s
/// `GPS_REQUIRED` on a pinned booking and passes on a legacy address-only one.
/// `lat`/`lng` are both-or-neither (validated like create-booking's site coordinates).
#[derive(Debug, Deserialize)]
pub struct StartJobRequest {
    #[serde(default)]
    pub lat: Option<f64>,
    #[serde(default)]
    pub lng: Option<f64>,
    /// Reported fix accuracy in meters — widens the fence up to the domain cap; junk
    /// (negative/NaN) is treated as 0 for the fence and stored as NULL.
    #[serde(default)]
    pub accuracy_m: Option<f32>,
}

// ----- Responses -----

/// A booking row as returned to clients. `status` is read as text (the DB enum cast to
/// text) so the read path needs no enum decoding — mirrors the notification slice.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct BookingResponse {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub status: String,
    pub address: String,
    pub scheduled_at: DateTime<Utc>,
    pub hours: i32,
    /// ฿ per hour per guard (server-owned rate).
    pub base_fee: Decimal,
    pub guard_count: i32,
    pub tip: Decimal,
    /// Site coordinates — `None` when the customer did not provide them at create.
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    /// DIRECTED OFFER (C3): the ONE guard this booking was OFFERED to at create — distinct from
    /// [`Self::guard_id`] (the guard who ACCEPTED). `None` = OPEN first-come (legacy rows, and
    /// bookings the customer left un-directed): any online guard may claim it. When set, discovery
    /// hides the booking from every other guard and `accept` 403s a non-target `NOT_OFFERED_TO_YOU`.
    /// On a directed booking the target accepts, both this and `guard_id` end up the same guard.
    pub target_guard_id: Option<Uuid>,
    /// When the assigned guard STARTED work (stamped by `PUT /bookings/{id}/start`; the
    /// proration basis). `None` until started — the client restores the job clock from this
    /// after an app restart.
    pub work_started_at: Option<DateTime<Utc>>,
    /// When the booking was PAID (PRE-PAY: stamped by the `payment.completed` consumer). `None`
    /// = unpaid — the client uses this to know the `accepted → en_route` transition is gated
    /// (show the pay-step) vs. already paid.
    pub paid_at: Option<DateTime<Utc>>,
    /// WHY the booking ended without work: the stable code recorded by `cancel` (customer) or
    /// `decline` (assigned guard) — never localized text, so the client renders the TH/EN label
    /// from the code. `None` for every booking that was not cancelled/declined, and for rows
    /// terminated before migration 0009.
    pub cancellation_reason: Option<String>,
    /// The optional free-text elaboration on that reason (≤ 500 chars; required when the reason
    /// is `other`). `None` when the customer/guard wrote nothing.
    pub cancellation_note: Option<String>,
    /// SNAPSHOT of the chosen catalog service's platform commission (%) at creation — deducted
    /// from the GUARD's pay, never added to the customer's bill. Frozen here so an admin editing
    /// the catalog next week cannot restate what a guard earned on this job. `None` only for a
    /// booking created before migration 0010 (read as 0); a booking made without a catalog
    /// service carries a real `0`.
    #[serde(serialize_with = "money_2dp")]
    pub commission_percent: Option<Decimal>,
    /// SNAPSHOT of the chosen catalog service's flat cancellation fee (฿) at creation — what the
    /// customer forfeits by cancelling pre-arrival (capped at what they actually paid). Same
    /// `None` semantics as [`Self::commission_percent`].
    #[serde(serialize_with = "money_2dp")]
    pub cancellation_fee: Option<Decimal>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Serialize an optional money Decimal at EXACTLY 2dp.
///
/// Scale survives neither the value nor the round-trip: Postgres sends a `numeric` zero with no
/// digits, so sqlx decodes `0.00` back as scale-0 `0`, while `12.50` keeps its two places. With
/// `serde-str` rendering whatever scale it finds, one booking answered `"0"` and another `"12.50"`
/// for the same column — a client comparing the strings sees a difference that is not there.
/// Normalizing at the boundary fixes every read path at once, including rows written before
/// migration 0010.
fn money_2dp<S>(v: &Option<Decimal>, s: S) -> Result<S::Ok, S::Error>
where
    S: serde::Serializer,
{
    match v {
        Some(d) => {
            let mut d = *d;
            d.rescale(2);
            serde::Serialize::serialize(&d, s)
        }
        None => s.serialize_none(),
    }
}

#[cfg(test)]
mod money_wire_tests {
    use super::*;

    fn ser(v: Option<Decimal>) -> String {
        // A minimal stand-in for the field's position in BookingResponse.
        #[derive(serde::Serialize)]
        struct W {
            #[serde(serialize_with = "money_2dp")]
            v: Option<Decimal>,
        }
        serde_json::to_string(&W { v }).expect("serialize")
    }

    #[test]
    fn money_is_two_decimals_whatever_scale_it_arrives_with() {
        // A scale-0 zero is exactly what sqlx hands back for a `numeric` 0 from Postgres — the
        // shape that made a no-service booking answer "0" while a catalog one answered "12.50".
        assert_eq!(ser(Some(Decimal::ZERO)), r#"{"v":"0.00"}"#);
        assert_eq!(ser(Some("5".parse().unwrap())), r#"{"v":"5.00"}"#);
        assert_eq!(ser(Some("12.50".parse().unwrap())), r#"{"v":"12.50"}"#);
        // A pre-migration row is absent, not zero — the client must be able to tell them apart.
        assert_eq!(ser(None), r#"{"v":null}"#);
    }
}

// ----- Progress reports (hourly check-in) -----

/// A `booking.progress_reports` row as stored. Only the S3 `photo_key` is persisted —
/// signed URLs are minted fresh per read (the chat-attachment pattern), never stored as
/// the source of truth.
#[derive(Debug, sqlx::FromRow)]
pub struct ProgressReportRow {
    pub id: Uuid,
    pub booking_id: Uuid,
    pub guard_id: Uuid,
    pub hour_number: i32,
    pub photo_key: String,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub accuracy_m: Option<f32>,
    pub note: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// The client view of a progress report: the row plus a FRESH presigned GET URL (TTL 1h)
/// signed from `photo_key` at response time.
#[derive(Debug, Serialize)]
pub struct ProgressReportResponse {
    pub id: Uuid,
    pub booking_id: Uuid,
    pub guard_id: Uuid,
    pub hour_number: i32,
    pub photo_key: String,
    pub photo_url: String,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub accuracy_m: Option<f32>,
    pub note: Option<String>,
    pub created_at: DateTime<Utc>,
}

impl ProgressReportResponse {
    /// Attach a freshly-signed download URL to a stored row.
    pub fn from_row(row: ProgressReportRow, photo_url: String) -> Self {
        Self {
            id: row.id,
            booking_id: row.booking_id,
            guard_id: row.guard_id,
            hour_number: row.hour_number,
            photo_key: row.photo_key,
            photo_url,
            lat: row.lat,
            lng: row.lng,
            accuracy_m: row.accuracy_m,
            note: row.note,
            created_at: row.created_at,
        }
    }
}

/// The validated, ready-to-persist check-in (built by the handler AFTER multipart parsing,
/// photo validation, and the S3 upload; the repo re-validates legality inside the row lock).
#[derive(Debug)]
pub struct NewProgressReport {
    pub hour_number: i32,
    pub photo_key: String,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub accuracy_m: Option<f32>,
    pub note: Option<String>,
}

/// Query params for `GET /bookings/{id}/progress-reports` (house limit/offset pagination).
#[derive(Debug, Deserialize)]
pub struct ListProgressReportsQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// Query params for `GET /bookings/open` (open-job discovery).
#[derive(Debug, Deserialize)]
pub struct OpenJobsQuery {
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub radius_km: Option<f64>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// Query params for `GET /available-guards`. When BOTH `scheduled_at` + `hours` are present, the
/// busy-guard exclusion is scoped to that time window (a guard free at the requested time is still
/// offered). Omitting them falls back to the coarse "any active job" exclusion (back-compat).
///
/// `lat`/`lng` are the optional MEETUP point (the booking's site pin, both-or-neither): when
/// present the discovery list is sorted NEAREST-to-meetup (C2) by the guards' live positions and
/// each entry carries `distance_m`; absent → today's order (catalog order) with `distance_m`
/// omitted (backward compatible).
#[derive(Debug, Deserialize)]
pub struct AvailableGuardsQuery {
    pub scheduled_at: Option<DateTime<Utc>>,
    pub hours: Option<i32>,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
}

/// Query params for `GET /admin/bookings` (admin cross-user list). `status` is validated
/// against `BookingStatus` (unknown → 400); `search` is a case-insensitive substring match on
/// the address. `guard_id`/`customer_id` narrow the list to one guard's job history or one
/// customer's booking history (admin drill-down). House limit/offset pagination.
#[derive(Debug, Deserialize)]
pub struct AdminListBookingsQuery {
    pub status: Option<String>,
    pub search: Option<String>,
    pub guard_id: Option<Uuid>,
    pub customer_id: Option<Uuid>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// Query params for `GET /admin/checkins/overdue` — house limit/offset pagination only (the
/// predicate is fixed: active jobs with an overdue hourly check-in).
#[derive(Debug, Deserialize)]
pub struct OverdueCheckinsQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// Body for `POST /admin/bookings/{id}/assign` — the admin's chosen guard for the booking.
#[derive(Debug, Deserialize)]
pub struct AssignGuardRequest {
    pub guard_id: Uuid,
}

// ----- Reports (admin analytics) -----

/// Inclusive-from / exclusive-to date window (RFC3339); both optional — the handler defaults
/// to the last 30 days. Shared shape with the payment revenue report.
#[derive(Debug, Deserialize)]
pub struct ReportRangeQuery {
    pub from: Option<DateTime<Utc>>,
    pub to: Option<DateTime<Utc>>,
}

/// One day's booking count (the bookings-volume line on the revenue chart).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct DailyCount {
    pub date: NaiveDate,
    pub count: i64,
}

/// One heatmap cell: guard-hours scheduled in a `dow` (0=Sun..6=Sat) × 2-hour `bucket`
/// (0=00:00–02:00 .. 11=22:00–24:00). `hours` = Σ(hours × guard_count) for that slot.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct UtilizationCell {
    pub dow: i32,
    pub bucket: i32,
    pub hours: i64,
}

/// One point on the aggregate retention curve: % of customers still active `week` weeks after
/// their first booking (week 0 = 100%).
#[derive(Debug, Serialize)]
pub struct RetentionPoint {
    pub week: i32,
    pub pct: f64,
}

/// Composite booking analytics for the reports screen — three booking-derived panels in one
/// round-trip (volume trend, utilization heatmap, retention cohort).
#[derive(Debug, Serialize)]
pub struct BookingsReport {
    pub daily: Vec<DailyCount>,
    pub utilization: Vec<UtilizationCell>,
    pub retention: Vec<RetentionPoint>,
    pub total: i64,
}

/// Per-customer booking aggregate for the web-admin customers page: lifetime booking counts
/// keyed by customer. `cancelled` folds the terminal "did not happen" states (cancelled +
/// declined). All counts are `i64` (Postgres `COUNT(*)` is `bigint`).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct CustomerBookingStat {
    pub customer_id: Uuid,
    pub total: i64,
    pub completed: i64,
    pub cancelled: i64,
}

/// One active job whose next scheduled hourly check-in is OVERDUE — the dashboard
/// "เช็คอินที่ขาด" (missed check-ins) signal. A job is in progress when `status = 'arrived'`
/// AND `work_started_at` is stamped (the proration clock); hour `N` (1-based, ≤ `hours`) opens
/// at `work_started_at + (N−1)h`. `due_at` is the open time of the EARLIEST owed-but-unfiled
/// hour (the oldest gap), and `missed_count` is how many owed hours (open time already passed)
/// have no `progress_reports` row yet — late/out-of-order filing is tolerated, so this counts
/// every gap, not just the latest.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct OverdueCheckin {
    pub booking_id: Uuid,
    /// The assigned guard who owes the check-in (always set — only assigned jobs reach `arrived`).
    pub guard_id: Uuid,
    pub customer_id: Uuid,
    /// Open time of the oldest owed-but-unfiled hour (RFC3339). The check-in is "overdue since".
    pub due_at: DateTime<Utc>,
    /// Count of owed hours (open time has passed) with no check-in filed yet.
    pub missed_count: i64,
}

/// The overdue-check-ins payload: the list plus a `total` count (number of distinct active jobs
/// with at least one overdue check-in) for the dashboard alert card. `total` equals `items.len()`
/// when unpaginated, but is returned explicitly so the card can show the badge without the client
/// re-counting (mirrors `BookingsReport.total`).
#[derive(Debug, Serialize)]
pub struct OverdueCheckinsResponse {
    pub items: Vec<OverdueCheckin>,
    pub total: i64,
}

// ----- Service catalog (admin-managed pricing; standalone, not wired to the charge path) -----

/// A service-catalog row as returned to the admin. `base_fee` is a Decimal serialized as a
/// string on the wire (money rule), like the booking response.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct ServiceCatalogItem {
    pub id: Uuid,
    pub name_th: String,
    pub name_en: String,
    /// ฿ per hour per guard.
    pub base_fee: Decimal,
    pub min_hours: i32,
    /// The platform's cut of the GUARD's pay for this service, in percent (0..=100). The
    /// customer's bill is unaffected — the commission comes out of what the guard receives.
    pub commission_percent: Decimal,
    /// Flat ฿ kept when the CUSTOMER cancels this service pre-arrival (0 = free cancellation).
    /// Charged as `min(fee, amount_paid)`, so it can never leave the customer in debt.
    pub cancellation_fee: Decimal,
    pub notes: Option<String>,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// The customer-facing view of an ACTIVE catalog service (the `GET /services` picker). A
/// deliberately narrow subset of [`ServiceCatalogItem`] — no `is_active`/timestamps. `notes` is
/// surfaced as the customer-facing package description (card + detail screen); everything else the
/// customer needs to choose + price (`base_fee × hours × guard_count`).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct PublicServiceItem {
    pub id: Uuid,
    pub name_th: String,
    pub name_en: String,
    /// ฿ per hour per guard (server-owned rate; Decimal serialized as a string on the wire).
    pub base_fee: Decimal,
    pub min_hours: i32,
    /// Short customer-facing description (the admin `notes`), shown on the package card + detail.
    pub notes: Option<String>,
}

/// Create a catalog service (admin). Validated in the handler (non-empty names, fee ≥ 0,
/// min_hours 1..=24) plus the pure `domain::pricing` validators for the two money knobs.
#[derive(Debug, Deserialize)]
pub struct CreateServiceRequest {
    pub name_th: String,
    pub name_en: String,
    pub base_fee: Decimal,
    pub min_hours: i32,
    /// Platform commission on the GUARD's pay, in percent (0..=100).
    ///
    /// `#[serde(default)]` → 0 when absent, on purpose: during a mixed deploy an older
    /// web-admin build still sends the pre-0010 body, and the safe reading of "the admin did
    /// not say" is "the platform takes nothing" — not a 422 that bricks the pricing screen.
    #[serde(default)]
    pub commission_percent: Decimal,
    /// Flat ฿ cancellation fee (≥ 0). Same absent-means-zero rationale as
    /// [`Self::commission_percent`].
    #[serde(default)]
    pub cancellation_fee: Decimal,
    pub notes: Option<String>,
}

/// Update a catalog service (admin) — full replace of the editable fields.
#[derive(Debug, Deserialize)]
pub struct UpdateServiceRequest {
    pub name_th: String,
    pub name_en: String,
    pub base_fee: Decimal,
    pub min_hours: i32,
    /// Platform commission on the GUARD's pay, in percent (0..=100); absent → 0 (see
    /// [`CreateServiceRequest::commission_percent`]). This is a FULL replace, so an omitted
    /// value clears a previously-set commission — bookings already made keep their snapshot.
    #[serde(default)]
    pub commission_percent: Decimal,
    /// Flat ฿ cancellation fee (≥ 0); absent → 0, same full-replace semantics.
    #[serde(default)]
    pub cancellation_fee: Decimal,
    pub notes: Option<String>,
}

/// One entry in the `/available-guards` discovery list: an approved guard (from profile's
/// catalog) enriched with their live rating summary (from rating). `average_rating` is `None`
/// when the guard has no visible reviews (or rating was unreachable — best-effort).
/// `display_name` + `avatar_url` come straight from profile's catalog (the same approved-guard
/// exposure as `GET /guards/{id}/public`) so the customer's selection card shows a real name +
/// photo instead of an id + initials; both are omitted from the JSON when absent.
/// `has_documents` is profile's derived boolean (all five credential documents on file) — the
/// customer sees WHETHER the guard has documents, never the documents themselves. OMITTED (not
/// `false`) when profile didn't say (older profile during a mixed-version deploy), so the app
/// can render "unknown" as nothing rather than a false "no documents".
#[derive(Debug, Serialize)]
pub struct AvailableGuard {
    pub guard_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avatar_url: Option<String>,
    pub years_of_experience: Option<i32>,
    pub average_rating: Option<Decimal>,
    pub review_count: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub has_documents: Option<bool>,
    /// Per-credential PRESENCE (has/doesn't-have), passed straight through from profile so the
    /// customer sees WHICH credential types are on file — never the files themselves. OMITTED (not
    /// an all-false object) when profile didn't say (older profile during a mixed-version deploy),
    /// so the app renders "unknown" as nothing rather than a false "has none".
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documents: Option<GuardDocuments>,

    /// Straight-line distance (meters) from the guard's LIVE position (per presence) to the
    /// booking's meetup point — set ONLY when the discovery query carried a meetup `lat`/`lng`
    /// AND this guard's live position is known; the list is then sorted by it ascending
    /// (nearest first). OMITTED otherwise, so the UI shows "~1.2 กม." only when it is meaningful.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub distance_m: Option<f64>,
}

/// Per-credential presence flags for the five customer-relevant credential documents. Booleans
/// ONLY (each = the file is on record), never the file bytes. Serialized to the customer AND
/// deserialized from profile's catalog, so it carries both derives. Passbook is excluded (banking).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GuardDocuments {
    pub id_card: bool,
    pub security_license: bool,
    pub training_cert: bool,
    pub criminal_check: bool,
    pub driver_license: bool,
}

/// The authoritative subset of a booking exposed to internal callers (service-JWT'd),
/// e.g. the payment service deciding whether a charge is legitimate and computing the
/// expected total. Deliberately narrow: ownership/payability + the pricing inputs the money
/// path needs (`base_fee × hours × guard_count + tip`). NOT the address/timestamps a
/// participant sees — internal callers get the minimum they need (least-privilege).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct InternalBooking {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub status: String,
    pub hours: i32,
    /// ฿ per hour per guard (server-owned; the client never sets this).
    pub base_fee: Decimal,
    pub guard_count: i32,
    pub tip: Decimal,
    /// The booking's SNAPSHOT of the platform commission (%). Payment needs it to split a
    /// completed job's money (`guard_net = guard_gross − guard_gross × pct / 100`) — from the
    /// booking, never from today's catalog, so a settled job's numbers never move. `None` for a
    /// pre-migration-0010 booking; payment reads that as 0 (no cut).
    pub commission_percent: Option<Decimal>,
    /// The booking's SNAPSHOT of the flat cancellation fee (฿). Payment charges
    /// `min(cancellation_fee, amount_paid)` on a CUSTOMER pre-arrival cancel (a guard
    /// withdrawing still refunds in full). Same `None`-is-zero semantics.
    pub cancellation_fee: Option<Decimal>,
}
