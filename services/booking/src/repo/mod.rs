//! Repository layer — the ONLY place that touches the `booking` schema.
//!
//! Uses runtime `sqlx::query`/`query_as` (not the compile-time `query!` macro): the
//! scaffold has no DATABASE_URL / offline `.sqlx` cache at build time (mirrors the
//! notification slice).
//!
//! The heart of this slice is [`transition`]: it writes the status change AND the outbox
//! event row in ONE transaction (CLAUDE.md "Cross-tx consistency: transactional outbox"),
//! so a committed status change always has its event durably queued, and a rolled-back
//! change emits nothing.

use chrono::{DateTime, Utc};
use serde_json::Value;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::EventEnvelope;

use crate::domain::cancellation::{set_for_target, CANCEL_REASON_REQUIRED_CODE};
use crate::domain::progress::GeoFilter;
use crate::domain::state::{required_actor, BookingStatus, RequiredActor};
use crate::domain::{
    event_for_booking_requested, event_for_progress_report, event_for_status, Cancellation,
    CompletionInfo, EventMapping, PricingSnapshot,
};
use crate::models::{
    BookingResponse, CreateBookingRequest, CreateServiceRequest, CustomerBookingStat, DailyCount,
    InternalBooking, NewProgressReport, OverdueCheckin, ProgressReportRow, PublicServiceItem,
    ServiceCatalogItem, UpdateServiceRequest, UtilizationCell,
};

const BOOKING_COLUMNS: &str = "id, customer_id, guard_id, status::text AS status, address, \
     scheduled_at, hours, base_fee, guard_count, tip, lat, lng, target_guard_id, work_started_at, \
     paid_at, actual_seconds, cancellation_reason, cancellation_note, commission_percent, \
     cancellation_fee, created_at, updated_at";

const PROGRESS_REPORT_COLUMNS: &str =
    "id, booking_id, guard_id, hour_number, photo_key, lat, lng, accuracy_m, note, created_at";

// ----- Outbox row (for the relay) -----

/// One unpublished outbox row, as the relay reads it.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct OutboxRow {
    pub id: Uuid,
    pub topic: String,
    /// The serialized `EventEnvelope` (JSONB).
    pub payload: Value,
}

// ----- Reads -----

pub async fn get_booking(db: &sqlx::PgPool, id: Uuid) -> Result<BookingResponse, AppError> {
    let sql = format!("SELECT {BOOKING_COLUMNS} FROM booking.bookings WHERE id = $1");
    sqlx::query_as::<_, BookingResponse>(&sql)
        .bind(id)
        .fetch_optional(db)
        .await?
        .ok_or_else(|| AppError::NotFound("Booking not found".to_string()))
}

/// Read the authoritative subset another service needs to make a decision about a booking
/// (service-JWT'd internal read). Returns only `id, customer_id, guard_id, status, hours`
/// — the fields the payment service verifies a charge against, plus the booking's own money
/// SNAPSHOT (`commission_percent`, `cancellation_fee`) so payment splits the guard's pay and
/// prices a cancellation from what this booking agreed to, not from today's catalog. No
/// `SELECT *` (CLAUDE.md "Data"): the projection is explicit and narrow.
pub async fn get_internal(db: &sqlx::PgPool, id: Uuid) -> Result<InternalBooking, AppError> {
    sqlx::query_as::<_, InternalBooking>(
        "SELECT id, customer_id, guard_id, status::text AS status, hours, \
                base_fee, guard_count, tip, commission_percent, cancellation_fee \
         FROM booking.bookings WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".to_string()))
}

/// List bookings the caller participates in (as customer OR assigned guard), newest first.
pub async fn list_bookings(
    db: &sqlx::PgPool,
    user_id: Uuid,
) -> Result<Vec<BookingResponse>, AppError> {
    let sql = format!(
        r#"
        SELECT {BOOKING_COLUMNS}
        FROM booking.bookings
        WHERE customer_id = $1 OR guard_id = $1
        ORDER BY created_at DESC
        LIMIT 100
        "#
    );
    let rows = sqlx::query_as::<_, BookingResponse>(&sql)
        .bind(user_id)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

/// Admin cross-user list — every booking (NO owner filter; the admin-role gate is the API
/// layer's job), newest first, with optional `status` (validated enum), `search` (address
/// substring), and `guard_id`/`customer_id` (drill into one guard's or customer's bookings)
/// filters plus house limit/offset pagination. Diverges from [`list_bookings`] precisely by
/// dropping the implicit `customer_id = $1 OR guard_id = $1` scope — here either column is an
/// explicit, optional filter. `$n` placeholders are built from a controlled counter; every
/// value (incl. the ILIKE pattern) is a BOUND param — no user input is interpolated into the SQL.
pub async fn admin_list_bookings(
    db: &sqlx::PgPool,
    status: Option<BookingStatus>,
    search: Option<&str>,
    guard_id: Option<Uuid>,
    customer_id: Option<Uuid>,
    limit: i64,
    offset: i64,
) -> Result<Vec<BookingResponse>, AppError> {
    let mut sql = format!("SELECT {BOOKING_COLUMNS} FROM booking.bookings");
    let mut conds: Vec<String> = Vec::new();
    let mut idx = 1;
    if status.is_some() {
        conds.push(format!("status = ${idx}::booking.booking_status"));
        idx += 1;
    }
    if search.is_some() {
        // Case-insensitive substring on the address; the value is bound ($idx), only the
        // wildcards are literal.
        conds.push(format!("address ILIKE '%' || ${idx} || '%'"));
        idx += 1;
    }
    if guard_id.is_some() {
        conds.push(format!("guard_id = ${idx}"));
        idx += 1;
    }
    if customer_id.is_some() {
        conds.push(format!("customer_id = ${idx}"));
        idx += 1;
    }
    if !conds.is_empty() {
        sql.push_str(" WHERE ");
        sql.push_str(&conds.join(" AND "));
    }
    sql.push_str(&format!(
        " ORDER BY created_at DESC LIMIT ${} OFFSET ${}",
        idx,
        idx + 1
    ));

    let mut query = sqlx::query_as::<_, BookingResponse>(&sql);
    if let Some(s) = status {
        query = query.bind(s.as_db_str());
    }
    if let Some(s) = search {
        query = query.bind(s.to_string());
    }
    if let Some(g) = guard_id {
        query = query.bind(g);
    }
    if let Some(c) = customer_id {
        query = query.bind(c);
    }
    let rows = query.bind(limit).bind(offset).fetch_all(db).await?;
    Ok(rows)
}

// ----- Reports (admin analytics) -----

/// Daily booking count over `[from, to)` by `created_at` (the bookings-volume line). Ascending.
pub async fn bookings_daily(
    db: &sqlx::PgPool,
    from: DateTime<Utc>,
    to: DateTime<Utc>,
) -> Result<Vec<DailyCount>, AppError> {
    let rows = sqlx::query_as::<_, DailyCount>(
        r#"
        SELECT date_trunc('day', created_at)::date AS date, COUNT(*) AS count
        FROM booking.bookings
        WHERE created_at >= $1 AND created_at < $2
        GROUP BY 1
        ORDER BY 1
        "#,
    )
    .bind(from)
    .bind(to)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Guard-hours scheduled per (day-of-week × 2-hour bucket) over `[from, to)`, keyed on
/// `scheduled_at`. Excludes cancelled/declined (they represent no work). `hours` = Σ(hours ×
/// guard_count). Only non-empty cells are returned — the client fills the rest with zero.
pub async fn utilization(
    db: &sqlx::PgPool,
    from: DateTime<Utc>,
    to: DateTime<Utc>,
) -> Result<Vec<UtilizationCell>, AppError> {
    let rows = sqlx::query_as::<_, UtilizationCell>(
        // `EXTRACT(hour ...)` returns numeric, so it MUST be cast to int BEFORE the `/ 2` —
        // otherwise the division is numeric (e.g. 23/2 = 11.5) and the trailing `::int` ROUNDS
        // half-to-even (11.5 → 12), spilling hours 22-23 into a phantom bucket 12 that the
        // contract (buckets 0..11) and web-admin (`cell.bucket < 12`) silently drop. Casting
        // first makes it integer (truncating) division: 23 / 2 = 11. Bucket = floor(hour / 2).
        r#"
        SELECT EXTRACT(dow FROM scheduled_at)::int AS dow,
               (EXTRACT(hour FROM scheduled_at)::int / 2) AS bucket,
               COALESCE(SUM(hours * guard_count), 0)::bigint AS hours
        FROM booking.bookings
        WHERE scheduled_at >= $1 AND scheduled_at < $2
          AND status NOT IN ('cancelled', 'declined')
        GROUP BY 1, 2
        "#,
    )
    .bind(from)
    .bind(to)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Aggregate retention counts over `[from, to)`. Per customer, the span (weeks between their
/// first and last booking in the window); then how many customers have a span ≥ N weeks for
/// N ∈ {1,2,4,8,12}, plus the base (total customers). Retention is monotonic in N, so this is
/// the % "still active at week N" curve. Returns `(base, w1, w2, w4, w8, w12)`.
pub async fn retention_counts(
    db: &sqlx::PgPool,
    from: DateTime<Utc>,
    to: DateTime<Utc>,
) -> Result<(i64, i64, i64, i64, i64, i64), AppError> {
    let row: (i64, i64, i64, i64, i64, i64) = sqlx::query_as(
        r#"
        WITH spans AS (
            SELECT customer_id,
                   floor(extract(epoch FROM (max(created_at) - min(created_at))) / 604800)::int
                       AS span_weeks
            FROM booking.bookings
            WHERE created_at >= $1 AND created_at < $2
            GROUP BY customer_id
        )
        SELECT count(*)::bigint AS base,
               count(*) FILTER (WHERE span_weeks >= 1)::bigint  AS w1,
               count(*) FILTER (WHERE span_weeks >= 2)::bigint  AS w2,
               count(*) FILTER (WHERE span_weeks >= 4)::bigint  AS w4,
               count(*) FILTER (WHERE span_weeks >= 8)::bigint  AS w8,
               count(*) FILTER (WHERE span_weeks >= 12)::bigint AS w12
        FROM spans
        "#,
    )
    .bind(from)
    .bind(to)
    .fetch_one(db)
    .await?;
    Ok(row)
}

/// Per-customer lifetime booking aggregate for the web-admin customers page: `total`,
/// `completed`, and `cancelled` (folding the terminal cancelled + declined states), grouped by
/// customer. No window filter — this is the lifetime view. `COUNT(*)` returns `bigint` (i64).
pub async fn customer_booking_stats(
    db: &sqlx::PgPool,
) -> Result<Vec<CustomerBookingStat>, AppError> {
    let rows = sqlx::query_as::<_, CustomerBookingStat>(
        r#"
        SELECT customer_id,
               COUNT(*) AS total,
               COUNT(*) FILTER (WHERE status = 'completed'::booking.booking_status) AS completed,
               COUNT(*) FILTER (WHERE status IN ('cancelled'::booking.booking_status, 'declined'::booking.booking_status)) AS cancelled
        FROM booking.bookings
        GROUP BY customer_id
        "#,
    )
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Active jobs with an OVERDUE hourly check-in — the admin dashboard "missed check-ins" signal.
///
/// A job is in progress when `status = 'arrived'` AND `work_started_at` is stamped (the
/// proration clock; mirrors [`crate::domain::progress::validate_check_in`]). Hour `N` (1-based,
/// ≤ `hours`) opens at `work_started_at + (N−1)h`. For each active job we expand its owed hours
/// `1..=hours` via `generate_series`, anti-join the filed `progress_reports`, and keep the hours
/// whose open time has already passed (`now()`) but were never filed. `due_at` is the open time
/// of the OLDEST such gap; `missed_count` counts every gap (late/out-of-order filing is
/// tolerated). Only jobs with ≥ 1 overdue hour are returned, oldest-overdue first (the most
/// urgent at the top). `limit`/`offset` paginate (house convention). Replica read.
///
/// `generate_series(1, b.hours)` is bounded by the DB CHECK `hours BETWEEN 1 AND 168`, so the
/// per-job expansion can never blow up. The anti-join uses the `uq_progress_reports_booking_hour`
/// unique index on `(booking_id, hour_number)`.
pub async fn overdue_checkins(
    db: &sqlx::PgPool,
    limit: i64,
    offset: i64,
) -> Result<Vec<OverdueCheckin>, AppError> {
    let rows = sqlx::query_as::<_, OverdueCheckin>(
        r#"
        SELECT b.id          AS booking_id,
               b.guard_id    AS guard_id,
               b.customer_id AS customer_id,
               b.work_started_at + make_interval(hours => (MIN(h.n)::int - 1)) AS due_at,
               COUNT(*)      AS missed_count
        FROM booking.bookings b
        CROSS JOIN LATERAL generate_series(1, b.hours) AS h(n)
        LEFT JOIN booking.progress_reports pr
               ON pr.booking_id = b.id AND pr.hour_number = h.n
        WHERE b.status = 'arrived'::booking.booking_status
          AND b.work_started_at IS NOT NULL
          AND b.guard_id IS NOT NULL
          AND pr.id IS NULL
          AND b.work_started_at + make_interval(hours => (h.n::int - 1)) <= now()
        GROUP BY b.id, b.guard_id, b.customer_id, b.work_started_at
        ORDER BY due_at ASC
        LIMIT $1 OFFSET $2
        "#,
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Count of distinct active jobs that have ≥ 1 overdue check-in (the dashboard alert badge).
/// Same predicate as [`overdue_checkins`] but counts jobs, not gaps — `EXISTS` short-circuits
/// on the first owed-but-unfiled past-due hour per job (no per-job expansion of every hour).
pub async fn overdue_checkins_count(db: &sqlx::PgPool) -> Result<i64, AppError> {
    let count: i64 = sqlx::query_scalar(
        r#"
        SELECT COUNT(*)
        FROM booking.bookings b
        WHERE b.status = 'arrived'::booking.booking_status
          AND b.work_started_at IS NOT NULL
          AND b.guard_id IS NOT NULL
          AND EXISTS (
              SELECT 1
              FROM generate_series(1, b.hours) AS h(n)
              LEFT JOIN booking.progress_reports pr
                     ON pr.booking_id = b.id AND pr.hour_number = h.n
              WHERE pr.id IS NULL
                AND b.work_started_at + make_interval(hours => (h.n::int - 1)) <= now()
          )
        "#,
    )
    .fetch_one(db)
    .await?;
    Ok(count)
}

// ----- Service catalog (admin pricing; standalone — not read by the charge path) -----

const SERVICE_COLUMNS: &str = "id, name_th, name_en, base_fee, min_hours, commission_percent, \
     cancellation_fee, notes, is_active, created_at, updated_at";

/// List catalog services for the admin (active-first, then newest).
pub async fn list_services(db: &sqlx::PgPool) -> Result<Vec<ServiceCatalogItem>, AppError> {
    let sql = format!(
        "SELECT {SERVICE_COLUMNS} FROM booking.service_catalog \
         ORDER BY is_active DESC, created_at DESC LIMIT 200"
    );
    let rows = sqlx::query_as::<_, ServiceCatalogItem>(&sql)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

/// Customer-facing list — ONLY active catalog services, newest first, projected to the narrow
/// [`PublicServiceItem`] (`notes` is the customer description; no `is_active`/timestamps). Mirrors
/// [`list_services`] but filters `is_active = true`; covered by `idx_service_catalog_active`.
pub async fn list_active_services(db: &sqlx::PgPool) -> Result<Vec<PublicServiceItem>, AppError> {
    let rows = sqlx::query_as::<_, PublicServiceItem>(
        "SELECT id, name_th, name_en, base_fee, min_hours, notes FROM booking.service_catalog \
         WHERE is_active = true ORDER BY created_at DESC LIMIT 200",
    )
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Look up one ACTIVE catalog service by id (the charge-path resolution). Returns the full
/// [`ServiceCatalogItem`] so the handler can read its authoritative `base_fee` + `min_hours`
/// and SNAPSHOT its `commission_percent` + `cancellation_fee` onto the booking.
/// `None` if the id does not exist OR the service has been deactivated — the handler maps that
/// to 404 (a customer must not be able to book against an inactive/unknown rate).
pub async fn get_active_service(
    db: &sqlx::PgPool,
    id: Uuid,
) -> Result<Option<ServiceCatalogItem>, AppError> {
    let row = sqlx::query_as::<_, ServiceCatalogItem>(&format!(
        "SELECT {SERVICE_COLUMNS} FROM booking.service_catalog \
         WHERE id = $1 AND is_active = true"
    ))
    .bind(id)
    .fetch_optional(db)
    .await?;
    Ok(row)
}

/// Insert a new catalog service. Fields are validated by the handler before this call
/// (`commission_percent`/`cancellation_fee` by the pure `domain::pricing` validators, which
/// also round them to the columns' 2-dp scale).
pub async fn create_service(
    db: &sqlx::PgPool,
    req: &CreateServiceRequest,
) -> Result<ServiceCatalogItem, AppError> {
    let sql = format!(
        "INSERT INTO booking.service_catalog \
             (name_th, name_en, base_fee, min_hours, commission_percent, cancellation_fee, notes) \
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING {SERVICE_COLUMNS}"
    );
    let row = sqlx::query_as::<_, ServiceCatalogItem>(&sql)
        .bind(&req.name_th)
        .bind(&req.name_en)
        .bind(req.base_fee)
        .bind(req.min_hours)
        .bind(req.commission_percent)
        .bind(req.cancellation_fee)
        .bind(req.notes.as_deref())
        .fetch_one(db)
        .await?;
    Ok(row)
}

/// Replace the editable fields of a catalog service. 404 if it does not exist.
///
/// Editing the money knobs is safe by construction: every booking already created copied them
/// at creation (see [`create_booking`]), so a new commission applies ONLY to bookings made from
/// here on — it never restates what a guard earned on a job already worked.
pub async fn update_service(
    db: &sqlx::PgPool,
    id: Uuid,
    req: &UpdateServiceRequest,
) -> Result<ServiceCatalogItem, AppError> {
    let sql = format!(
        "UPDATE booking.service_catalog \
         SET name_th = $2, name_en = $3, base_fee = $4, min_hours = $5, \
             commission_percent = $6, cancellation_fee = $7, notes = $8, updated_at = now() \
         WHERE id = $1 RETURNING {SERVICE_COLUMNS}"
    );
    sqlx::query_as::<_, ServiceCatalogItem>(&sql)
        .bind(id)
        .bind(&req.name_th)
        .bind(&req.name_en)
        .bind(req.base_fee)
        .bind(req.min_hours)
        .bind(req.commission_percent)
        .bind(req.cancellation_fee)
        .bind(req.notes.as_deref())
        .fetch_optional(db)
        .await?
        .ok_or_else(|| AppError::NotFound("Service not found".to_string()))
}

/// Soft-delete a catalog service (set `is_active = false`) — preserves history and any future
/// references. 404 if it does not exist. Returns the updated row.
pub async fn deactivate_service(
    db: &sqlx::PgPool,
    id: Uuid,
) -> Result<ServiceCatalogItem, AppError> {
    let sql = format!(
        "UPDATE booking.service_catalog SET is_active = false, updated_at = now() \
         WHERE id = $1 RETURNING {SERVICE_COLUMNS}"
    );
    sqlx::query_as::<_, ServiceCatalogItem>(&sql)
        .bind(id)
        .fetch_optional(db)
        .await?
        .ok_or_else(|| AppError::NotFound("Service not found".to_string()))
}

// ----- Writes -----

/// Insert a new booking in `requested` status AND enqueue its
/// `pguard.events.booking.requested` event — both in ONE transaction (transactional outbox,
/// CLAUDE.md "Cross-tx consistency"). So a committed request always has its event durably
/// queued for the relay (notification fans it out as a data-push to every online guard), and a
/// rolled-back insert emits nothing. `correlation_id` threads the envelope for distributed tracing.
///
/// `guard_count`/`tip` come from the request (defaulted by the handler). `pricing` is the
/// SNAPSHOT of the catalog service the handler resolved — `Some` when the customer picked one,
/// `None` for the back-compat path (no service chosen). It is ALWAYS server-resolved (the
/// client never sends money — CLAUDE.md money rules), so the customer can never undercut the
/// price. It decides three columns:
///
/// * `base_fee` — the catalog's authoritative rate, or (when `None`) the column's server-owned
///   DEFAULT, left to apply by omitting the column from the INSERT.
/// * `commission_percent` + `cancellation_fee` — COPIED onto the booking, always written
///   (0/0 when no service was chosen). This snapshot is the point: the catalog is editable, so
///   an admin raising the commission next week would otherwise silently restate what a guard
///   earned on a job booked — and worked, and paid — today. The money path reads the booking's
///   copy, never the catalog. NULL in these columns means only "booking predates migration
///   0010", never "look it up".
#[tracing::instrument(skip(db, req), fields(customer_id = %customer_id))]
pub async fn create_booking(
    db: &sqlx::PgPool,
    customer_id: Uuid,
    req: &CreateBookingRequest,
    guard_count: i32,
    tip: rust_decimal::Decimal,
    pricing: Option<PricingSnapshot>,
    correlation_id: Uuid,
) -> Result<BookingResponse, AppError> {
    let mut tx = db.begin().await?;

    // 1) the business row. `base_fee` is bound when a catalog service was picked; otherwise the
    // column is omitted so its server-owned DEFAULT applies (COALESCE($n, DEFAULT) is not valid,
    // so branch the SQL). The two snapshot columns are bound on BOTH branches — a booking made
    // today always states its terms, even when those terms are "no cut, no fee".
    let (commission_percent, cancellation_fee) = PricingSnapshot::terms_or_zero(pricing.as_ref());
    // DIRECTED OFFER (C3): the customer's chosen guard, or NULL for an OPEN first-come booking.
    // Bound on BOTH branches (a directed booking states its target whether or not a catalog
    // service was picked). NULL = open; readers (discovery + accept) treat it as "anyone may claim".
    let sql = if pricing.is_some() {
        format!(
            r#"
            INSERT INTO booking.bookings (customer_id, status, address, scheduled_at, hours, guard_count, tip, lat, lng, target_guard_id, commission_percent, cancellation_fee, base_fee)
            VALUES ($1, 'requested'::booking.booking_status, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
            RETURNING {BOOKING_COLUMNS}
            "#
        )
    } else {
        format!(
            r#"
            INSERT INTO booking.bookings (customer_id, status, address, scheduled_at, hours, guard_count, tip, lat, lng, target_guard_id, commission_percent, cancellation_fee)
            VALUES ($1, 'requested'::booking.booking_status, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
            RETURNING {BOOKING_COLUMNS}
            "#
        )
    };
    let mut query = sqlx::query_as::<_, BookingResponse>(&sql)
        .bind(customer_id)
        .bind(&req.address)
        .bind(req.scheduled_at)
        .bind(req.hours)
        .bind(guard_count)
        .bind(tip)
        .bind(req.lat)
        .bind(req.lng)
        .bind(req.target_guard_id)
        .bind(commission_percent)
        .bind(cancellation_fee);
    if let Some(snapshot) = pricing {
        query = query.bind(snapshot.base_fee);
    }
    let created = query.fetch_one(&mut *tx).await.map_err(AppError::from)?;

    // 2) the event — same transaction (transactional outbox). Carries the booking's site
    // coordinates EVEN WHEN NULL so a radius-ranking consumer never reads back into booking.
    let EventMapping { topic, payload } = event_for_booking_requested(
        created.id,
        created.customer_id,
        &created.address,
        created.lat,
        created.lng,
        created.scheduled_at,
        created.hours,
        created.guard_count,
        // DIRECTED OFFER (C3): rides the event so notification can push the "new job" ONLY to the
        // targeted guard (a broadcast to all online guards would defeat the point). NULL = open →
        // notification fans out to everyone, as today.
        created.target_guard_id,
    );
    let envelope = EventEnvelope::new(topic, correlation_id, payload);
    let envelope_json = serde_json::to_value(&envelope)
        .map_err(|e| AppError::Internal(format!("serialize event envelope: {e}")))?;
    enqueue_outbox(&mut tx, topic, &envelope_json).await?;

    tx.commit().await?;
    Ok(created)
}

/// A booking's authoritative decision inputs: status + participant ids + proration clock +
/// site pin. Read row-locked inside transactions ([`locked_current`]) and plain for
/// handler pre-flight checks ([`get_booking_core`]).
pub struct BookingCore {
    pub status: BookingStatus,
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub hours: i32,
    /// When the customer scheduled the job to start. NOT NULL on `booking.bookings` — the
    /// start-time gate (G3) rejects a start pressed before `scheduled_at - 15min`.
    pub scheduled_at: DateTime<Utc>,
    /// When the guard STARTED work (set by `start_job`); the proration basis. `None` until then.
    pub work_started_at: Option<DateTime<Utc>>,
    /// When the booking was PAID (stamped by the `payment.completed` consumer). `None` = unpaid;
    /// the `accepted → en_route` transition is gated on this being set (PRE-PAY).
    pub paid_at: Option<DateTime<Utc>>,
    /// Site pin (customer-provided at create). `None` = legacy address-only booking — the
    /// start-work geofence has nothing to measure against and skips.
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    /// DIRECTED OFFER (C3): the guard this booking was offered to, or `None` for an OPEN
    /// first-come booking. Read inside the row lock so the accept gate rejects a non-target guard
    /// (`NOT_OFFERED_TO_YOU`) with no TOCTOU.
    pub target_guard_id: Option<Uuid>,
    /// When the guard REQUESTED completion (`arrived → pending_completion`) — the END of the
    /// worked-duration measurement. `None` until requested (and cleared on the completion-reject
    /// bounce). Read inside the row lock so the completion proration is measured at the request,
    /// not at the customer's later approval (deep-review HIGH #1).
    pub completion_requested_at: Option<DateTime<Utc>>,
}

impl BookingCore {
    /// The site pin as a coordinate pair — `Some` only when BOTH columns are set (the
    /// create API enforces both-or-neither, so a half-pin can't occur; this is defensive).
    pub fn site(&self) -> Option<(f64, f64)> {
        self.lat.zip(self.lng)
    }
}

/// Raw row shape returned by the core queries: status text, customer, guard, booked hours,
/// scheduled time, work-start clock, paid-at clock, site pin. Aliased to keep the query type
/// readable (clippy `type_complexity`).
type CoreRow = (
    String,
    Uuid,
    Option<Uuid>,
    i32,
    DateTime<Utc>,
    Option<DateTime<Utc>>,
    Option<DateTime<Utc>>,
    Option<f64>,
    Option<f64>,
    Option<Uuid>,
    Option<DateTime<Utc>>,
);

const CORE_QUERY: &str =
    "SELECT status::text, customer_id, guard_id, hours, scheduled_at, work_started_at, paid_at, \
     lat, lng, target_guard_id, completion_requested_at FROM booking.bookings WHERE id = $1";

fn core_from_row(row: Option<CoreRow>) -> Result<BookingCore, AppError> {
    let (
        status_str,
        customer_id,
        guard_id,
        hours,
        scheduled_at,
        work_started_at,
        paid_at,
        lat,
        lng,
        target_guard_id,
        completion_requested_at,
    ) = row.ok_or_else(|| AppError::NotFound("Booking not found".to_string()))?;
    let status = status_str
        .parse::<BookingStatus>()
        .map_err(AppError::Internal)?;
    Ok(BookingCore {
        status,
        customer_id,
        guard_id,
        hours,
        scheduled_at,
        work_started_at,
        paid_at,
        lat,
        lng,
        target_guard_id,
        completion_requested_at,
    })
}

/// Read a booking's current status + ids + proration inputs inside a transaction
/// (row-locked) so a decision validates against state that cannot change underneath it.
async fn locked_current(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    id: Uuid,
) -> Result<BookingCore, AppError> {
    let row: Option<CoreRow> = sqlx::query_as(&format!("{CORE_QUERY} FOR UPDATE"))
        .bind(id)
        .fetch_optional(&mut **tx)
        .await?;
    core_from_row(row)
}

/// Plain (un-locked) read of the same decision inputs — handler pre-flight only. Never
/// authoritative: any write path MUST re-validate via [`locked_current`] inside its own
/// transaction (the pre-flight just fails fast before expensive work like an S3 upload).
pub async fn get_booking_core(db: &sqlx::PgPool, id: Uuid) -> Result<BookingCore, AppError> {
    let row: Option<CoreRow> = sqlx::query_as(CORE_QUERY)
        .bind(id)
        .fetch_optional(db)
        .await?;
    core_from_row(row)
}

/// Atomically transition a booking to `new_status` and, when the change maps to an event,
/// enqueue that event into the outbox — both in ONE transaction.
///
/// Authz is enforced INSIDE the row lock via the pure [`required_actor`] mapping (no TOCTOU):
/// an `AssignedGuard` move needs `actor == guard_id`; a `RequestOwner` move needs
/// `actor == customer_id`; `ClaimUnassigned` needs the booking to have no guard yet. `is_admin`
/// overrides the owner checks. Illegal transitions → `Conflict`. `assign_guard` (the accept
/// path) sets the guard. Completing requires the job to have been started.
///
/// `cancellation` is the same kind of per-transition extra as `assign_guard`: the validated
/// reason (+ optional note) for the two terminal "did not happen" targets (`cancelled` /
/// `declined`). It is persisted on the row AND rides the emitted event; `None` on every other
/// transition (and on legacy/admin paths), where it is simply not written.
#[allow(clippy::too_many_arguments)] // per-transition extras (assign_guard, cancellation) + correlation
#[tracing::instrument(skip(db, cancellation), fields(booking_id = %id, new_status = %new_status))]
pub async fn transition(
    db: &sqlx::PgPool,
    id: Uuid,
    actor: Uuid,
    is_admin: bool,
    new_status: BookingStatus,
    assign_guard: Option<Uuid>,
    cancellation: Option<Cancellation>,
    correlation_id: Uuid,
) -> Result<BookingResponse, AppError> {
    let mut tx = db.begin().await?;

    let BookingCore {
        status: current,
        customer_id,
        guard_id: existing_guard,
        hours,
        work_started_at,
        paid_at,
        target_guard_id,
        completion_requested_at,
        ..
    } = locked_current(&mut tx, id).await?;

    let actor_class = required_actor(current, new_status);

    // PARTICIPATION GATE (inside the lock → no TOCTOU). A caller who is neither the customer
    // nor the assigned guard (nor admin) must get a generic 403 BEFORE the legality check —
    // otherwise an illegal-transition 409 (whose message embeds the booking's real `current`
    // status) would disclose another guard's job state to a non-participant who only knows the
    // UUID (IDOR / status leak). The CLAIM path (accept) is exempt: an unassigned booking has
    // no incumbent guard, so any guard may claim it (first-come).
    let is_participant = customer_id == actor || existing_guard == Some(actor);
    let is_claim = matches!(actor_class, Some(RequiredActor::ClaimUnassigned));
    if !is_admin && !is_participant && !is_claim {
        tx.rollback().await?;
        return Err(AppError::Forbidden(
            "Not a participant in this booking".to_string(),
        ));
    }

    // Legality (state machine). The class is the same `required_actor` value used below — one
    // source of truth. A non-participant never reaches here (gated above), so the 409 message
    // is only ever seen by a participant/admin; even so it does NOT embed the server-side
    // `current` status (only the caller's own requested target) to avoid any state disclosure.
    let actor_class = match actor_class {
        Some(a) => a,
        None => {
            tx.rollback().await?;
            return Err(AppError::Conflict(format!(
                "Booking cannot be transitioned to {new_status} from its current state"
            )));
        }
    };

    // Ownership authz (inside the lock → no TOCTOU). admin overrides the owner checks; a
    // non-owner gets 403 (not 409) so IDOR is indistinguishable from a real permission denial.
    match actor_class {
        RequiredActor::ClaimUnassigned => {
            // DIRECTED OFFER (C3), checked FIRST (inside the row lock → no TOCTOU). A booking
            // targeted at ONE guard may be claimed ONLY by that guard: a non-target caller — who
            // cannot even see it in discovery but might POST the id directly — gets a typed 403 the
            // app localizes. Admin `/assign` overrides (support may place any guard on any booking).
            // `assign_guard` is the guard being placed (the accepting guard on self-accept), so the
            // target must equal it. Ordered before JOB_TAKEN/overlap so a non-target never learns
            // whether the job is still open.
            if !is_admin {
                if let Some(target) = target_guard_id {
                    if assign_guard != Some(target) {
                        tx.rollback().await?;
                        return Err(AppError::ForbiddenCode {
                            code: "NOT_OFFERED_TO_YOU",
                            message: "This booking was offered to a specific guard".to_string(),
                        });
                    }
                }
            }
            if existing_guard.is_some() {
                tx.rollback().await?;
                // Typed: first-come-accept means losing the race is the NORMAL contention case, so
                // the app must localize it ("งานนี้มีเจ้าหน้าที่รับไปแล้ว") rather than show the raw
                // English sentence to a Thai guard (deep-review).
                return Err(AppError::ConflictCode {
                    code: "JOB_TAKEN",
                    message: "Booking already has an assigned guard".to_string(),
                });
            }
            // TIME-OVERLAP guard, race-proof. The handler pre-check (accept_booking) is a fast-fail
            // but is check-then-act OUTSIDE any lock, so two CONCURRENT accepts by the SAME guard for
            // different overlapping jobs (double-tap / retry / two devices) both pass it — neither
            // job is committed at check time. Serialize same-guard accepts on a guard-scoped advisory
            // xact lock, THEN re-test overlap against the now-committed state inside this tx: the
            // loser blocks until the winner commits, sees its active job, and is rejected 409.
            if let Some(guard) = assign_guard {
                sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1::text, 0))")
                    .bind(guard)
                    .execute(&mut *tx)
                    .await?;
                let (overlaps,): (bool,) = sqlx::query_as(
                    "SELECT EXISTS ( \
                       SELECT 1 FROM booking.bookings a \
                       JOIN booking.bookings t ON t.id = $2 \
                       WHERE a.guard_id = $1 AND a.id <> t.id \
                         AND a.status IN ('accepted'::booking.booking_status, \
                                          'en_route'::booking.booking_status, \
                                          'arrived'::booking.booking_status, \
                                          'pending_completion'::booking.booking_status) \
                         AND a.scheduled_at < t.scheduled_at + make_interval(hours => t.hours) \
                         AND t.scheduled_at < a.scheduled_at + make_interval(hours => a.hours) )",
                )
                .bind(guard)
                .bind(id)
                .fetch_one(&mut *tx)
                .await?;
                if overlaps {
                    tx.rollback().await?;
                    return Err(AppError::ConflictCode {
                        code: "GUARD_BUSY",
                        message:
                            "You already have a job during this time window — pick a non-overlapping one."
                                .to_string(),
                    });
                }
            }
        }
        RequiredActor::AssignedGuard => {
            if !is_admin && existing_guard != Some(actor) {
                tx.rollback().await?;
                return Err(AppError::Forbidden(
                    "Only the assigned guard can update this booking".to_string(),
                ));
            }
        }
        RequiredActor::RequestOwner => {
            if !is_admin && customer_id != actor {
                tx.rollback().await?;
                return Err(AppError::Forbidden(
                    "Only the booking's customer can do this".to_string(),
                ));
            }
        }
    }

    // REASON DISCIPLINE for the two terminal "did not happen" targets (cancelled / declined),
    // resolved AFTER legality/ownership so a terminal or illegal move is already rejected above:
    //
    //   * `current == Declined` — the ONLY edge out of `declined` is the customer's
    //     cancel-after-decline ACK (`declined → cancelled`). It must PRESERVE the guard's recorded
    //     decline reason, so FORCE `cancellation = None` here regardless of what the caller sent.
    //     This closes BOTH (a) the regular `PUT /cancel` overwriting the guard's reason with a
    //     customer code on a declined booking (deep-review LOW #29) and (b) the ACK path being
    //     used with a stray reason.
    //
    //   * `current != Declined` but the target is reason-bearing — a validated reason is
    //     MANDATORY. `PUT /cancel-after-decline` passes `None`, so pointing it at a still-active
    //     booking (requested/accepted/en_route) would otherwise commit a reasonless money-bearing
    //     terminal cancel that `validate_cancellation` was meant to make impossible
    //     (deep-review MED #5). Reject it with the same typed 400 the app already localizes.
    let cancellation = if set_for_target(new_status).is_some() {
        if current == BookingStatus::Declined {
            None // the ACK — never overwrite the guard's decline reason
        } else if cancellation.is_none() {
            tx.rollback().await?;
            return Err(AppError::BadRequestCode {
                code: CANCEL_REASON_REQUIRED_CODE,
                message: "A valid cancellation reason is required".to_string(),
            });
        } else {
            cancellation
        }
    } else {
        cancellation
    };

    // PRE-PAY gate (inside the lock → no TOCTOU). The `accepted → en_route` transition REQUIRES
    // the booking to have been PAID — `paid_at` is stamped by the `payment.completed` consumer
    // (the customer pays the server-computed estimate after a guard accepts). Until then en_route
    // is a 409 with the machine-readable `PAYMENT_REQUIRED` sub-code so the mobile pay-step can
    // branch on it (vs. the English message). Everything AFTER en_route is naturally gated — the
    // state machine forbids skipping en_route, so arrived/complete can never be reached unpaid.
    if current == BookingStatus::Accepted
        && new_status == BookingStatus::EnRoute
        && paid_at.is_none()
    {
        tx.rollback().await?;
        return Err(AppError::ConflictCode {
            code: crate::domain::state::PAYMENT_REQUIRED_CODE,
            message: "Payment required before the guard can go en route".to_string(),
        });
    }

    // Completing (the guard's request) requires the job to have been STARTED — otherwise there
    // is no factual basis for the worked-hours proration the completion event carries.
    if new_status == BookingStatus::PendingCompletion && work_started_at.is_none() {
        tx.rollback().await?;
        return Err(AppError::Conflict(
            "Job has not been started; cannot request completion".to_string(),
        ));
    }

    // Completing ALSO requires at least one filed check-in — the start-of-work check-in is the
    // guard's first-person on-site attestation, so a job with ZERO progress reports has no
    // evidence the guard was ever present and must not be billable/completable. Authoritative
    // (inside the row lock), not just the client-side button gate — a modified app can't bypass
    // it. Progress reports are append-only (no delete path) and each requires `arrived` +
    // `work_started_at`, so an EXISTS check can never wrongly ALLOW a zero-report completion.
    // Gate on ANY report (not hour 1 specifically): a guard who filed only a later hour has still
    // attested presence, and there is no UI path to backfill hour 1 once a later slot is due.
    if new_status == BookingStatus::PendingCompletion {
        let (has_check_in,): (bool,) = sqlx::query_as(
            "SELECT EXISTS(SELECT 1 FROM booking.progress_reports WHERE booking_id = $1)",
        )
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
        if !has_check_in {
            tx.rollback().await?;
            return Err(AppError::ConflictCode {
                code: crate::domain::state::CHECK_IN_REQUIRED_CODE,
                message: "The start-of-work check-in is required before requesting completion"
                    .to_string(),
            });
        }
    }

    let guard_id = assign_guard.or(existing_guard);

    // On completion, compute the worked duration ending at the guard's completion REQUEST, not at
    // the customer's approval: `completion_requested_at − work_started_at` (deep-review HIGH #1).
    // `completion_requested_at` is stamped on `arrived → pending_completion` below; falling back to
    // `now()` ONLY when unstamped (a legacy row that reached `pending_completion` before the
    // column existed). `None` work_started_at → `None` actual_seconds (payment keeps the full
    // charge; mirrors v1's "missing timestamps → skip proration"). Computed BEFORE the UPDATE so
    // the SAME value is (a) STAMPED onto the row in the completion UPDATE below — the guard's
    // earnings screen then reads the reconciled figure off any booking read immediately (feature
    // G) — and (b) carried on the `booking.completed` event (payment's `actual_hours` is truth).
    let completion_actual_seconds = if new_status == BookingStatus::Completed {
        work_started_at.map(|started| {
            let ended = completion_requested_at.unwrap_or_else(Utc::now);
            (ended - started).num_seconds()
        })
    } else {
        None
    };

    // completion_requested_at ledger, keyed on the transition:
    //   * `arrived → pending_completion` (the guard presses จบงาน) — STAMP `now()`: this is the
    //     moment the worked clock stops, regardless of when the customer later reviews.
    //   * `pending_completion → arrived` (the customer REJECTS completion) — CLEAR to NULL so work
    //     resumed after the reject is re-measured from the NEXT completion request, not the stale
    //     first one (per the shared contract).
    //   * every other transition leaves the column untouched.
    // Static fragments (no user input) — safe to interpolate into the UPDATE.
    let completion_ts_clause = match (current, new_status) {
        (BookingStatus::Arrived, BookingStatus::PendingCompletion) => {
            "completion_requested_at = now(),"
        }
        (BookingStatus::PendingCompletion, BookingStatus::Arrived) => {
            "completion_requested_at = NULL,"
        }
        _ => "",
    };

    // 1) the business change. `work_started_at` is owned by `start_job`, never touched here.
    // The cancellation columns follow `guard_id`'s COALESCE precedent: only a transition that
    // CARRIES a reason writes one, so no other transition can blank a recorded reason.
    // `actual_seconds` follows the SAME precedent: only a completion carrying a computed duration
    // writes it (COALESCE keeps the existing value on every other transition).
    let sql = format!(
        r#"
        UPDATE booking.bookings
        SET status = $2::booking.booking_status,
            guard_id = COALESCE($3, guard_id),
            cancellation_reason = COALESCE($4, cancellation_reason),
            cancellation_note = COALESCE($5, cancellation_note),
            actual_seconds = COALESCE($6, actual_seconds),
            {completion_ts_clause}
            updated_at = now()
        WHERE id = $1
        RETURNING {BOOKING_COLUMNS}
        "#
    );
    let updated = sqlx::query_as::<_, BookingResponse>(&sql)
        .bind(id)
        .bind(new_status.as_db_str())
        .bind(assign_guard)
        .bind(cancellation.as_ref().map(|c| c.reason))
        .bind(cancellation.as_ref().and_then(|c| c.note.as_deref()))
        .bind(completion_actual_seconds)
        .fetch_one(&mut *tx)
        .await?;

    // The completion event carries the proration + pricing inputs the post-pay money path
    // consumes (payment reconciles the charge from `actual_seconds`; its `actual_hours` is truth).
    let completion = if new_status == BookingStatus::Completed {
        Some(CompletionInfo {
            booked_hours: hours,
            actual_seconds: completion_actual_seconds,
            // Carry booking's server-owned pricing so the post-pay consumer bills self-contained.
            base_fee: updated.base_fee,
            guard_count: updated.guard_count,
            tip: updated.tip,
        })
    } else {
        None
    };

    // 2) the event — same transaction (transactional outbox). The topic is keyed on the TARGET
    // status (`event_for_status`), so BOTH a fresh arrival (`en_route → arrived`) and the
    // completion-reject bounce (`pending_completion → arrived`) emit `booking.arrived` — the
    // latter is what lets the guard's live screen leave "pending_completion" without a manual
    // refresh (see `event_for_status` + the `review_reject_returns_to_arrived_owner_only` test).
    if let Some(EventMapping { topic, payload }) = event_for_status(
        current,
        new_status,
        id,
        customer_id,
        guard_id,
        completion,
        cancellation.as_ref(),
        is_admin,
    ) {
        let envelope = EventEnvelope::new(topic, correlation_id, payload);
        let envelope_json = serde_json::to_value(&envelope)
            .map_err(|e| AppError::Internal(format!("serialize event envelope: {e}")))?;
        enqueue_outbox(&mut tx, topic, &envelope_json).await?;
    }

    tx.commit().await?;
    Ok(updated)
}

/// Mark the job STARTED — stamp `work_started_at` (the proration basis) while the booking
/// stays `arrived`. A guarded side-effect, NOT a status transition (mirrors v1's `start_job`
/// quirk): only the assigned guard (or admin) may start, the booking must be `arrived`, and a
/// second start is an idempotent no-op (returns the current row). No event.
///
/// NO proximity geofence anymore (G4): on-site presence is proven at ARRIVAL ([`arrive_job`],
/// the 120m fence), so once a guard is `arrived`, starting is free. The only gate here is the
/// START-TIME gate (G3) — a start pressed before `scheduled_at - 15min` is refused; `is_admin`
/// bypasses it. The guard's GPS fix, when sent, is still persisted
/// (`work_started_lat/lng/accuracy_m`) as audit evidence of where the job was started.
#[tracing::instrument(skip(db), fields(booking_id = %id))]
pub async fn start_job(
    db: &sqlx::PgPool,
    id: Uuid,
    actor: Uuid,
    is_admin: bool,
    guard_gps: Option<(f64, f64)>,
    accuracy_m: Option<f32>,
) -> Result<BookingResponse, AppError> {
    let mut tx = db.begin().await?;
    let core = locked_current(&mut tx, id).await?;

    if !is_admin && core.guard_id != Some(actor) {
        tx.rollback().await?;
        return Err(AppError::Forbidden(
            "Only the assigned guard can start this job".to_string(),
        ));
    }
    if core.status != BookingStatus::Arrived {
        tx.rollback().await?;
        return Err(AppError::Conflict(
            "Can only start a job after arriving at the location".to_string(),
        ));
    }
    // Idempotent: already started → return the current row unchanged (BEFORE the time gate and
    // geofence — a retry of an already-accepted start must not re-run either).
    if core.work_started_at.is_some() {
        tx.rollback().await?;
        return get_booking(db, id).await;
    }
    // START-TIME GATE (G3) — a pure domain rule against the row-locked booking; admin bypasses
    // (support acts on behalf, possibly early). NO proximity geofence here anymore (G4): on-site
    // presence is proven at ARRIVAL (`arrive_job`, the 120m fence), so once a guard is arrived,
    // starting the work clock is free. The guard GPS is still persisted below as audit evidence.
    if !is_admin {
        if let Err(e) =
            crate::domain::scheduling::validate_start_time(core.scheduled_at, Utc::now())
        {
            tx.rollback().await?;
            return Err(e);
        }
    }

    let sql = format!(
        "UPDATE booking.bookings SET work_started_at = now(), work_started_lat = $2, \
         work_started_lng = $3, work_started_accuracy_m = $4, updated_at = now() \
         WHERE id = $1 RETURNING {BOOKING_COLUMNS}"
    );
    let updated = sqlx::query_as::<_, BookingResponse>(&sql)
        .bind(id)
        .bind(guard_gps.map(|(lat, _)| lat))
        .bind(guard_gps.map(|(_, lng)| lng))
        // Junk accuracy (negative/NaN/absurd) is stored as NULL, not persisted noise.
        .bind(crate::domain::progress::sanitize_accuracy(accuracy_m))
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(updated)
}

/// Mark the job ARRIVED — the `en_route → arrived` transition WITH the proximity geofence (G4).
///
/// Mirrors [`start_job`]'s guarded-mutation shape but, unlike start, it IS a status transition:
/// it emits `booking.arrived` via the outbox (the SAME envelope as [`transition`]). It is kept
/// SEPARATE from the generic `transition` because only the guard's fresh arrival is proximity-
/// gated — the completion-REJECT bounce (`pending_completion → arrived`) also targets `arrived`
/// but is NOT a proximity event and keeps flowing through `transition` (no fence).
///
/// GEOFENCE (inside the row lock, against the booking's own site pin): a pinned booking may only
/// be marked arrived from within [`crate::domain::geo::ARRIVED_GEOFENCE_M`] of the site
/// (+ capped accuracy allowance) — 409 `NOT_AT_SITE`; a pinned booking with no `guard_gps` is
/// 409 `GPS_REQUIRED`. Unpinned (legacy address-only) bookings skip the check. `is_admin`
/// bypasses it (support acting on behalf is not on site). Authz: only the ASSIGNED guard (or
/// admin); status must be `en_route`. The accepted fix is persisted (`arrived_lat/lng/
/// accuracy_m`) as audit evidence of on-site presence.
#[tracing::instrument(skip(db), fields(booking_id = %id))]
pub async fn arrive_job(
    db: &sqlx::PgPool,
    id: Uuid,
    actor: Uuid,
    is_admin: bool,
    guard_gps: Option<(f64, f64)>,
    accuracy_m: Option<f32>,
    correlation_id: Uuid,
) -> Result<BookingResponse, AppError> {
    let mut tx = db.begin().await?;
    let core = locked_current(&mut tx, id).await?;

    // PARTICIPATION GATE first (generic 403 — a stranger must not learn job state), then the
    // assignment gate (only the assigned guard may mark arrived). Mirrors `transition`'s order.
    let is_participant = core.customer_id == actor || core.guard_id == Some(actor);
    if !is_admin && !is_participant {
        tx.rollback().await?;
        return Err(AppError::Forbidden(
            "Not a participant in this booking".to_string(),
        ));
    }
    if !is_admin && core.guard_id != Some(actor) {
        tx.rollback().await?;
        return Err(AppError::Forbidden(
            "Only the assigned guard can update this booking".to_string(),
        ));
    }
    // LEGALITY: only `en_route → arrived` runs through here (the reject bounce
    // `pending_completion → arrived` goes through `transition`). Message mirrors `transition`'s
    // and does NOT embed the server-side status (no state disclosure).
    if core.status != BookingStatus::EnRoute {
        tx.rollback().await?;
        return Err(AppError::Conflict(
            "Booking cannot be transitioned to arrived from its current state".to_string(),
        ));
    }
    // GEOFENCE (pure domain rule, inside the row lock). Admin bypasses (off-site support action).
    if !is_admin {
        if let Err(e) =
            crate::domain::geo::validate_arrived_geofence(core.site(), guard_gps, accuracy_m)
        {
            tx.rollback().await?;
            return Err(e);
        }
    }

    // 1) the business change — flip to `arrived` and persist the accepted fix (audit evidence).
    let sql = format!(
        "UPDATE booking.bookings SET status = 'arrived'::booking.booking_status, \
         arrived_lat = $2, arrived_lng = $3, arrived_accuracy_m = $4, updated_at = now() \
         WHERE id = $1 RETURNING {BOOKING_COLUMNS}"
    );
    let updated = sqlx::query_as::<_, BookingResponse>(&sql)
        .bind(id)
        .bind(guard_gps.map(|(lat, _)| lat))
        .bind(guard_gps.map(|(_, lng)| lng))
        // Junk accuracy (negative/NaN/absurd) is stored as NULL, not persisted noise.
        .bind(crate::domain::progress::sanitize_accuracy(accuracy_m))
        .fetch_one(&mut *tx)
        .await?;

    // 2) the `booking.arrived` event — same transaction (transactional outbox), same mapping as
    // `transition` so both arrival paths emit an identical envelope.
    if let Some(EventMapping { topic, payload }) = event_for_status(
        BookingStatus::EnRoute,
        BookingStatus::Arrived,
        id,
        core.customer_id,
        core.guard_id,
        None,
        None,
        is_admin,
    ) {
        let envelope = EventEnvelope::new(topic, correlation_id, payload);
        let envelope_json = serde_json::to_value(&envelope)
            .map_err(|e| AppError::Internal(format!("serialize event envelope: {e}")))?;
        enqueue_outbox(&mut tx, topic, &envelope_json).await?;
    }

    tx.commit().await?;
    Ok(updated)
}

// ----- Progress reports (hourly check-in) -----

/// Atomically persist an hourly check-in AND enqueue its
/// `pguard.events.booking.progress_reported` event — both in ONE transaction
/// (transactional outbox), with every gate re-validated inside the row lock (no TOCTOU;
/// the handler's pre-flight is advisory only).
///
/// Authz: STRICTLY the assigned guard — `actor == guard_id`, NO admin bypass (a check-in
/// is the guard's first-person attestation of presence; nobody files it on their behalf).
/// A non-participant gets the same generic 403 as everywhere else (no status leak).
/// Legality: the pure [`crate::domain::progress::validate_check_in`] (status `arrived` +
/// started + hour window). Duplicate hour: the `uq_progress_reports_booking_hour` unique
/// index fires inside this tx → mapped to 409 `Conflict`, which also makes a guard's
/// network-retry idempotent-safe under concurrency (the booking row lock serializes
/// same-booking check-ins; the survivor of a race gets the 409).
#[tracing::instrument(skip(db, report), fields(booking_id = %booking_id, hour = report.hour_number))]
pub async fn create_progress_report(
    db: &sqlx::PgPool,
    booking_id: Uuid,
    actor: Uuid,
    report: &NewProgressReport,
    correlation_id: Uuid,
) -> Result<ProgressReportRow, AppError> {
    let mut tx = db.begin().await?;
    let core = locked_current(&mut tx, booking_id).await?;

    // PARTICIPATION GATE first (generic 403 — a stranger must not learn job state), then the
    // assignment gate (a participant customer may know only the assigned guard checks in).
    let is_participant = core.customer_id == actor || core.guard_id == Some(actor);
    if !is_participant {
        tx.rollback().await?;
        return Err(AppError::Forbidden(
            "Not a participant in this booking".to_string(),
        ));
    }
    if core.guard_id != Some(actor) {
        tx.rollback().await?;
        return Err(AppError::Forbidden(
            "Only the assigned guard can check in".to_string(),
        ));
    }

    if let Err(e) = crate::domain::progress::validate_check_in(
        core.status,
        core.work_started_at,
        core.hours,
        report.hour_number,
        Utc::now(),
    ) {
        tx.rollback().await?;
        return Err(e);
    }

    // 1) the business row. The unique (booking_id, hour_number) index turns a duplicate
    //    hour into 409 here, inside the same tx — so a failed insert enqueues NO event.
    let sql = format!(
        r#"
        INSERT INTO booking.progress_reports
            (booking_id, guard_id, hour_number, photo_key, lat, lng, accuracy_m, note)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING {PROGRESS_REPORT_COLUMNS}
        "#
    );
    let row = sqlx::query_as::<_, ProgressReportRow>(&sql)
        .bind(booking_id)
        .bind(actor)
        .bind(report.hour_number)
        .bind(&report.photo_key)
        .bind(report.lat)
        .bind(report.lng)
        .bind(report.accuracy_m)
        .bind(&report.note)
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| match &e {
            sqlx::Error::Database(d) if d.code().as_deref() == Some("23505") => {
                AppError::ConflictCode {
                    code: crate::domain::progress::DUPLICATE_CHECK_IN_CODE,
                    message: format!("A check-in for hour {} already exists", report.hour_number),
                }
            }
            _ => AppError::from(e),
        })?;

    // 2) the event — same transaction (transactional outbox).
    let mapping =
        event_for_progress_report(booking_id, core.customer_id, actor, row.id, row.hour_number);
    let envelope = EventEnvelope::new(mapping.topic, correlation_id, mapping.payload);
    let envelope_json = serde_json::to_value(&envelope)
        .map_err(|e| AppError::Internal(format!("serialize event envelope: {e}")))?;
    enqueue_outbox(&mut tx, mapping.topic, &envelope_json).await?;

    tx.commit().await?;
    Ok(row)
}

/// Advisory duplicate-hour pre-flight: `true` iff a report for `(booking_id, hour_number)`
/// already exists. The handler calls this BEFORE the S3 upload so the spec's idempotent
/// guard-retry 409s without uploading (no orphaned object); the unique index inside
/// [`create_progress_report`]'s transaction remains the authoritative gate.
pub async fn progress_report_exists(
    db: &sqlx::PgPool,
    booking_id: Uuid,
    hour_number: i32,
) -> Result<bool, AppError> {
    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM booking.progress_reports \
         WHERE booking_id = $1 AND hour_number = $2)",
    )
    .bind(booking_id)
    .bind(hour_number)
    .fetch_one(db)
    .await?;
    Ok(exists)
}

/// A booking's check-in reports in hour order (paginated). The IDOR gate (customer-owner /
/// assigned guard / admin) lives in the handler against the booking row — by the time this
/// runs the caller is a verified participant.
pub async fn list_progress_reports(
    db: &sqlx::PgPool,
    booking_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<ProgressReportRow>, AppError> {
    let sql = format!(
        r#"
        SELECT {PROGRESS_REPORT_COLUMNS}
        FROM booking.progress_reports
        WHERE booking_id = $1
        ORDER BY hour_number
        LIMIT $2 OFFSET $3
        "#
    );
    let rows = sqlx::query_as::<_, ProgressReportRow>(&sql)
        .bind(booking_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

// ----- Open-job discovery -----

/// Open jobs a guard can claim: `status = 'requested' AND guard_id IS NULL`. A SEPARATE
/// query from [`list_bookings`] — the participant list's semantics (`customer_id = $1 OR
/// guard_id = $1`) are untouched (PHASE spec §B3).
///
/// With a [`GeoFilter`]: only bookings that HAVE coordinates, within `radius_km`
/// great-circle distance (pure-SQL haversine — plain `postgres:17`, no PostGIS/extension
/// precedent), nearest first. Without: newest first (bookings without coordinates included).
/// The haversine's `asin` input is clamped with `least(1, …)` — float rounding can push the
/// formula marginally past 1.0, and Postgres `asin(>1)` errors.
pub async fn list_open_bookings(
    db: &sqlx::PgPool,
    guard_id: Uuid,
    geo: Option<GeoFilter>,
    limit: i64,
    offset: i64,
) -> Result<Vec<BookingResponse>, AppError> {
    // Never re-offer a job THIS guard has skipped (server-tracked; the booking stays open for others).
    let rows = match geo {
        None => {
            let sql = format!(
                r#"
                SELECT {BOOKING_COLUMNS}
                FROM booking.bookings b
                WHERE status = 'requested'::booking.booking_status AND guard_id IS NULL
                  -- DIRECTED OFFER (C3): a guard sees an open booking (target NULL) OR one
                  -- targeted at THEM; a booking directed at another guard is invisible here.
                  AND (target_guard_id IS NULL OR target_guard_id = $1)
                  AND NOT EXISTS (
                      SELECT 1 FROM booking.guard_job_skips s
                      WHERE s.booking_id = b.id AND s.guard_id = $1
                  )
                ORDER BY created_at DESC
                LIMIT $2 OFFSET $3
                "#
            );
            sqlx::query_as::<_, BookingResponse>(&sql)
                .bind(guard_id)
                .bind(limit)
                .bind(offset)
                .fetch_all(db)
                .await?
        }
        Some(GeoFilter {
            lat,
            lng,
            radius_km,
        }) => {
            let sql = format!(
                r#"
                -- The outer projection exists ONLY to drop `distance_km` (the sort key) from the
                -- row, so it must mirror BOOKING_COLUMNS field-for-field — `status` is already
                -- text-cast + aliased by the inner select. Add new booking columns to BOTH.
                SELECT id, customer_id, guard_id, status, address, scheduled_at, hours,
                       base_fee, guard_count, tip, lat, lng, target_guard_id, work_started_at,
                       paid_at, actual_seconds, cancellation_reason, cancellation_note,
                       commission_percent, cancellation_fee, created_at, updated_at
                FROM (
                    SELECT {BOOKING_COLUMNS},
                           2 * 6371 * asin(least(1, sqrt(
                               power(sin(radians(lat - $1) / 2), 2)
                               + cos(radians($1)) * cos(radians(lat))
                                 * power(sin(radians(lng - $2) / 2), 2)
                           ))) AS distance_km
                    FROM booking.bookings b
                    WHERE status = 'requested'::booking.booking_status
                      AND guard_id IS NULL
                      AND lat IS NOT NULL AND lng IS NOT NULL
                      -- DIRECTED OFFER (C3): open (target NULL) OR targeted at THIS guard ($6).
                      AND (target_guard_id IS NULL OR target_guard_id = $6)
                      AND NOT EXISTS (
                          SELECT 1 FROM booking.guard_job_skips s
                          WHERE s.booking_id = b.id AND s.guard_id = $6
                      )
                ) AS open_jobs
                WHERE distance_km <= $3
                ORDER BY distance_km, created_at DESC
                LIMIT $4 OFFSET $5
                "#
            );
            sqlx::query_as::<_, BookingResponse>(&sql)
                .bind(lat)
                .bind(lng)
                .bind(radius_km)
                .bind(limit)
                .bind(offset)
                .bind(guard_id)
                .fetch_all(db)
                .await?
        }
    };
    Ok(rows)
}

/// Record that `guard_id` SKIPPED (passed on) open booking `booking_id`, so discovery stops
/// re-offering it to THEM. Idempotent (PK conflict → no-op); the booking stays open for other guards.
pub async fn skip_job(db: &sqlx::PgPool, guard_id: Uuid, booking_id: Uuid) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO booking.guard_job_skips (guard_id, booking_id) \
         VALUES ($1, $2) ON CONFLICT (guard_id, booking_id) DO NOTHING",
    )
    .bind(guard_id)
    .bind(booking_id)
    .execute(db)
    .await?;
    Ok(())
}

/// The set of guards who currently hold an ACTIVE assignment — a booking assigned to them in
/// `accepted | en_route | arrived | pending_completion`. These guards are BUSY and must be
/// EXCLUDED from `/available-guards` discovery (the fix: a guard already working a job must not
/// be offered for another). booking owns its own schema, so this is a local read (no cross-
/// service round-trip); backed by the partial `idx_bookings_active_assignment` index. `declined`,
/// `cancelled`, `completed`, and unassigned `requested` rows are NOT active and never count.
pub async fn busy_guard_ids(
    db: &sqlx::PgPool,
) -> Result<std::collections::HashSet<Uuid>, AppError> {
    let rows: Vec<(Uuid,)> = sqlx::query_as(
        "SELECT DISTINCT guard_id FROM booking.bookings \
         WHERE guard_id IS NOT NULL \
           AND status IN ('accepted'::booking.booking_status, \
                          'en_route'::booking.booking_status, \
                          'arrived'::booking.booking_status, \
                          'pending_completion'::booking.booking_status)",
    )
    .fetch_all(db)
    .await?;
    Ok(rows.into_iter().map(|(g,)| g).collect())
}

/// Guards whose active assignment OVERLAPS the requested window `[window_start, window_start +
/// window_hours h)`. A guard is only "busy" FOR THAT WINDOW — they can still take non-overlapping
/// jobs (a physical guard works one place at a time, but 9–18 then 19–22 is fine). Overlap test:
/// `existing.start < requested.end AND requested.start < existing.end`.
pub async fn busy_guard_ids_overlapping(
    db: &sqlx::PgPool,
    window_start: DateTime<Utc>,
    window_hours: i32,
) -> Result<std::collections::HashSet<Uuid>, AppError> {
    let rows: Vec<(Uuid,)> = sqlx::query_as(
        "SELECT DISTINCT guard_id FROM booking.bookings \
         WHERE guard_id IS NOT NULL \
           AND status IN ('accepted'::booking.booking_status, \
                          'en_route'::booking.booking_status, \
                          'arrived'::booking.booking_status, \
                          'pending_completion'::booking.booking_status) \
           AND scheduled_at < $1 + make_interval(hours => $2) \
           AND $1 < scheduled_at + make_interval(hours => hours)",
    )
    .bind(window_start)
    .bind(window_hours)
    .fetch_all(db)
    .await?;
    Ok(rows.into_iter().map(|(g,)| g).collect())
}

/// Whether `guard_id` already holds an active assignment whose window OVERLAPS the target booking's
/// own window (the booking being accepted is excluded). Drives the accept gate: a guard can accept a
/// job only if it doesn't overlap one they're already committed to.
pub async fn guard_has_overlapping_active_job(
    db: &sqlx::PgPool,
    guard_id: Uuid,
    target_booking_id: Uuid,
) -> Result<bool, AppError> {
    let (exists,): (bool,) = sqlx::query_as(
        "SELECT EXISTS ( \
           SELECT 1 FROM booking.bookings a \
           JOIN booking.bookings t ON t.id = $2 \
           WHERE a.guard_id = $1 AND a.id <> t.id \
             AND a.status IN ('accepted'::booking.booking_status, \
                              'en_route'::booking.booking_status, \
                              'arrived'::booking.booking_status, \
                              'pending_completion'::booking.booking_status) \
             AND a.scheduled_at < t.scheduled_at + make_interval(hours => t.hours) \
             AND t.scheduled_at < a.scheduled_at + make_interval(hours => a.hours) )",
    )
    .bind(guard_id)
    .bind(target_booking_id)
    .fetch_one(db)
    .await?;
    Ok(exists)
}

/// PRE-PAY: react to a `pguard.events.payment.completed` event by stamping the booking's
/// `paid_at` (which un-gates the `accepted → en_route` transition) — IDEMPOTENTLY, in ONE
/// transaction:
///   1. claim the envelope's `event_id` in `processed_events` (`ON CONFLICT DO NOTHING`); a
///      JetStream redelivery loses the claim and the whole call is a no-op.
///   2. on a won claim, `UPDATE ... SET paid_at = now() WHERE id = $1 AND paid_at IS NULL` — the
///      `paid_at IS NULL` guard makes a (theoretical) duplicate event_id-free re-pay a no-op too,
///      so the first payment's timestamp is never overwritten.
/// Returns `true` if this delivery newly claimed the event (regardless of whether the booking row
/// existed / was already paid — the claim is the dedupe boundary), `false` on a redelivery.
#[tracing::instrument(skip(db), fields(event_id = %event_id, booking_id = %booking_id))]
pub async fn mark_paid_idempotent(
    db: &sqlx::PgPool,
    event_id: Uuid,
    event_type: &str,
    booking_id: Uuid,
) -> Result<bool, AppError> {
    let mut tx = db.begin().await?;

    // 1) dedupe claim — a redelivered event_id inserts nothing.
    let claimed = sqlx::query(
        "INSERT INTO booking.processed_events (event_id, event_type) VALUES ($1, $2) \
         ON CONFLICT (event_id) DO NOTHING",
    )
    .bind(event_id)
    .bind(event_type)
    .execute(&mut *tx)
    .await?
    .rows_affected()
        == 1;

    if !claimed {
        tx.rollback().await?;
        return Ok(false);
    }

    // 2) stamp paid_at once (first-write-wins). A missing booking row updates nothing — the claim
    // still holds, so a redelivery won't reprocess; an operator reconciles via the booking id.
    sqlx::query(
        "UPDATE booking.bookings SET paid_at = now(), updated_at = now() \
         WHERE id = $1 AND paid_at IS NULL",
    )
    .bind(booking_id)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(true)
}

/// Insert one outbox row inside the caller's transaction.
async fn enqueue_outbox(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    topic: &str,
    envelope_json: &Value,
) -> Result<(), AppError> {
    sqlx::query("INSERT INTO booking.outbox (topic, payload) VALUES ($1, $2)")
        .bind(topic)
        .bind(envelope_json)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

// ----- Outbox relay support -----

/// Claim up to `limit` unpublished outbox rows, oldest first, INSIDE the caller's
/// transaction. `FOR UPDATE SKIP LOCKED` locks each returned row for the life of `tx` and
/// skips rows another relay instance is already holding, so two concurrent relays (scaled
/// replicas, or a rolling-deploy overlap) never claim — and therefore never double-publish —
/// the same row. The lock only holds while the transaction is open, so the relay MUST keep
/// `tx` open across publish + [`mark_published`] (see `drain_once`); a plain pool fetch would
/// release the lock immediately and defeat the guard.
pub async fn fetch_unpublished(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    limit: i64,
) -> Result<Vec<OutboxRow>, AppError> {
    let rows = sqlx::query_as::<_, OutboxRow>(
        r#"
        SELECT id, topic, payload
        FROM booking.outbox
        WHERE published_at IS NULL
        ORDER BY created_at
        FOR UPDATE SKIP LOCKED
        LIMIT $1
        "#,
    )
    .bind(limit)
    .fetch_all(&mut **tx)
    .await?;
    Ok(rows)
}

/// Stamp one outbox row published (called only after a successful NATS publish), INSIDE the
/// same transaction that claimed it via [`fetch_unpublished`] — so the `FOR UPDATE SKIP
/// LOCKED` claim still holds the row and the mark commits atomically with the release.
pub async fn mark_published(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    id: Uuid,
) -> Result<(), AppError> {
    sqlx::query("UPDATE booking.outbox SET published_at = now() WHERE id = $1")
        .bind(id)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

/// PDPA §19/§32 data export: a user's OWN bookings — as the customer OR the assigned guard.
/// Money fields are cast to text so they cross the wire as exact-decimal strings (CLAUDE.md
/// money rule) without pulling a Decimal type through the export path. Scoped to `user_id`.
/// Includes the (customer-supplied) site lat/lng. NOTE: the guard's check-in rows (their
/// GPS/notes/photo keys) are a tracked follow-up — exporting them changes the shape the
/// identity aggregator consumes, a cross-service contract bump this slice doesn't own.
pub async fn export_user_bookings(db: &sqlx::PgPool, user_id: Uuid) -> Result<Value, AppError> {
    #[allow(clippy::type_complexity)]
    let rows: Vec<(
        Uuid,
        Uuid,
        Option<Uuid>,
        String,
        DateTime<Utc>,
        i32,
        String,
        String,
        i32,
        String,
        Option<DateTime<Utc>>,
        DateTime<Utc>,
        DateTime<Utc>,
        Option<f64>,
        Option<f64>,
    )> = sqlx::query_as(
        "SELECT id, customer_id, guard_id, address, scheduled_at, hours, status::text, \
                base_fee::text, guard_count, tip::text, work_started_at, created_at, updated_at, \
                lat, lng \
         FROM booking.bookings WHERE customer_id = $1 OR guard_id = $1 \
         ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(db)
    .await?;

    let bookings: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            let (
                id,
                customer_id,
                guard_id,
                address,
                scheduled_at,
                hours,
                status,
                base_fee,
                guard_count,
                tip,
                work_started_at,
                created_at,
                updated_at,
                lat,
                lng,
            ) = r;
            // `role` tells the user how they relate to each booking.
            let role = if Some(user_id) == guard_id {
                "guard"
            } else {
                "customer"
            };
            serde_json::json!({
                "id": id,
                "role": role,
                "customer_id": customer_id,
                "guard_id": guard_id,
                "address": address,
                "scheduled_at": scheduled_at,
                "hours": hours,
                "status": status,
                "base_fee": base_fee,
                "guard_count": guard_count,
                "tip": tip,
                "lat": lat,
                "lng": lng,
                "work_started_at": work_started_at,
                "created_at": created_at,
                "updated_at": updated_at,
            })
        })
        .collect();
    Ok(Value::Array(bookings))
}

#[cfg(test)]
mod db_tests {
    use super::*;
    use chrono::Utc;
    use shared_events::topics;
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;

    /// C5.3 create→read consistency: a write committed on the PRIMARY is visible both to a
    /// read-after-write on the primary (`get_booking`) AND to a list read on the REPLICA pool
    /// (`list_bookings` runs on `db_read`). The read pool is built the way services build it —
    /// `read_url` unset → falls back to the same DB — so committed writes are immediately
    /// visible (single-node). Gated on `DATABASE_URL`; hermetic SKIP otherwise.
    #[tokio::test]
    async fn create_read_consistency_primary_and_read_pool() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let primary = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("primary pool");
        // Build the read pool exactly as the service does (fallback → same DB here).
        let cfg = shared::config::DatabaseConfig {
            url: url.clone(),
            read_url: None,
            max_connections: 5,
            read_max_connections: 5,
        };
        let read = shared::db::create_read_pool(&cfg).await.expect("read pool");

        let customer_id = Uuid::new_v4();
        let id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO booking.bookings (id, customer_id, address, scheduled_at, hours) \
             VALUES ($1, $2, '1 Consistency Rd', now(), 4)",
        )
        .bind(id)
        .bind(customer_id)
        .execute(&primary) // WRITE → primary
        .await
        .expect("insert booking");

        // read-after-write on the PRIMARY sees it
        let got = get_booking(&primary, id).await.expect("get on primary");
        assert_eq!(got.id, id, "read-after-write on primary is consistent");

        // list on the READ pool sees the committed write
        let listed = list_bookings(&read, customer_id)
            .await
            .expect("list on read pool");
        assert!(
            listed.iter().any(|b| b.id == id),
            "read pool sees the committed booking"
        );

        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(id)
            .execute(&primary)
            .await;
    }

    /// Real-Postgres integration test: proves the transactional outbox end-to-end —
    /// accepting a booking writes BOTH the status change AND exactly one outbox row in one
    /// transaction, and the enqueued payload is a well-formed EventEnvelope for the right
    /// topic. No-op unless `DATABASE_URL` is set, so `cargo test` stays hermetic. Run
    /// against a migrated DB:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-booking -- accept_enqueues_outbox_event_atomically --nocapture
    #[tokio::test]
    async fn accept_enqueues_outbox_event_atomically() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        let created = create_booking(
            &pool,
            customer_id,
            &CreateBookingRequest {
                address: "123 Test Rd".to_string(),
                scheduled_at: Utc::now(),
                hours: 4,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");
        assert_eq!(created.status, "requested");

        let accepted = transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Accepted,
            Some(guard_id),
            None,
            correlation,
        )
        .await
        .expect("accept");
        assert_eq!(accepted.status, "accepted");
        assert_eq!(accepted.guard_id, Some(guard_id));

        // exactly one job_accepted outbox row for this booking, carrying a valid envelope.
        // (create_booking also enqueues a booking.requested row, so filter by topic.)
        let rows: Vec<OutboxRow> = sqlx::query_as(
            "SELECT id, topic, payload FROM booking.outbox \
             WHERE payload->'payload'->>'booking_id' = $1 AND topic = $2",
        )
        .bind(created.id.to_string())
        .bind(topics::BOOKING_JOB_ACCEPTED)
        .fetch_all(&pool)
        .await
        .expect("query outbox");
        assert_eq!(
            rows.len(),
            1,
            "exactly one job_accepted event enqueued for accept"
        );
        assert_eq!(rows[0].topic, topics::BOOKING_JOB_ACCEPTED);
        let envelope: EventEnvelope<Value> =
            serde_json::from_value(rows[0].payload.clone()).expect("valid envelope");
        assert_eq!(envelope.event_type, topics::BOOKING_JOB_ACCEPTED);
        assert_eq!(envelope.correlation_id, correlation);
        assert_eq!(envelope.payload["guard_id"], serde_json::json!(guard_id));

        // an illegal transition writes nothing (no second outbox row). The actor is the
        // assigned guard, so it passes the ownership check and fails at the state machine.
        let err = transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Arrived,
            None,
            None,
            correlation,
        )
        .await
        .expect_err("accepted → arrived is illegal");
        assert!(matches!(err, AppError::Conflict(_)));

        // cleanup
        let _ =
            sqlx::query("DELETE FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(created.id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
    }

    /// `create_booking` enqueues EXACTLY ONE `pguard.events.booking.requested` outbox row in the
    /// SAME transaction as the bookings insert (transactional outbox) — the new-job signal the
    /// notification consumer fans out to online guards. Asserts the subject + the full payload
    /// (ids, address, scheduled_at, hours, guard_count) AND that the booking's site coordinates
    /// are CARRIED EVEN WHEN PRESENT. DATABASE_URL-gated (hermetic SKIP otherwise). Run:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-booking -- create_enqueues_booking_requested --nocapture
    #[tokio::test]
    async fn create_enqueues_booking_requested_outbox_event() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();
        let scheduled_at = "2026-06-22T10:00:00Z".parse::<DateTime<Utc>>().unwrap();
        let (lat, lng) = (13.7563, 100.5018);

        let created = create_booking(
            &pool,
            customer_id,
            &CreateBookingRequest {
                address: "1 Requested Rd".to_string(),
                scheduled_at,
                hours: 4,
                service_id: None,
                target_guard_id: None,
                guard_count: Some(2),
                tip: None,
                lat: Some(lat),
                lng: Some(lng),
            },
            2,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");
        assert_eq!(created.status, "requested");

        // EXACTLY ONE outbox row for this booking, carrying the booking.requested envelope.
        let rows: Vec<OutboxRow> = sqlx::query_as(
            "SELECT id, topic, payload FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1",
        )
        .bind(created.id.to_string())
        .fetch_all(&pool)
        .await
        .expect("query outbox");
        assert_eq!(rows.len(), 1, "exactly one event enqueued on create");
        assert_eq!(rows[0].topic, topics::BOOKING_REQUESTED);
        assert_eq!(rows[0].topic, "pguard.events.booking.requested");

        let envelope: EventEnvelope<Value> =
            serde_json::from_value(rows[0].payload.clone()).expect("valid envelope");
        assert_eq!(envelope.event_type, topics::BOOKING_REQUESTED);
        assert_eq!(envelope.correlation_id, correlation);
        let p = &envelope.payload;
        assert_eq!(p["booking_id"], serde_json::json!(created.id));
        assert_eq!(p["customer_id"], serde_json::json!(customer_id));
        assert_eq!(p["address"], serde_json::json!("1 Requested Rd"));
        assert_eq!(p["lat"], serde_json::json!(lat));
        assert_eq!(p["lng"], serde_json::json!(lng));
        assert_eq!(p["hours"], serde_json::json!(4));
        assert_eq!(p["guard_count"], serde_json::json!(2));
        // scheduled_at round-trips as the same instant.
        assert_eq!(
            p["scheduled_at"]
                .as_str()
                .and_then(|s| s.parse::<DateTime<Utc>>().ok()),
            Some(scheduled_at)
        );

        // cleanup
        let _ =
            sqlx::query("DELETE FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(created.id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
    }

    /// A booking created WITHOUT coordinates still enqueues exactly one booking.requested row,
    /// and the payload CARRIES lat/lng AS PRESENT JSON NULL (key present, value null) — so a
    /// radius-ranking consumer can distinguish "no coordinates" from a truncated payload.
    #[tokio::test]
    async fn create_enqueues_booking_requested_with_null_coords_present() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        let created = create_booking(
            &pool,
            customer_id,
            &CreateBookingRequest {
                address: "no-coords site".to_string(),
                scheduled_at: Utc::now(),
                hours: 3,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");

        let rows: Vec<OutboxRow> = sqlx::query_as(
            "SELECT id, topic, payload FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1",
        )
        .bind(created.id.to_string())
        .fetch_all(&pool)
        .await
        .expect("query outbox");
        assert_eq!(rows.len(), 1, "exactly one event enqueued on create");
        assert_eq!(rows[0].topic, topics::BOOKING_REQUESTED);
        let envelope: EventEnvelope<Value> =
            serde_json::from_value(rows[0].payload.clone()).expect("valid envelope");
        let p = &envelope.payload;
        // "carry lat/lng even when null": the keys are PRESENT, the values are JSON null.
        assert!(p.get("lat").is_some(), "lat key present");
        assert!(p.get("lng").is_some(), "lng key present");
        assert!(p["lat"].is_null(), "absent lat → JSON null");
        assert!(p["lng"].is_null(), "absent lng → JSON null");
        assert_eq!(p["guard_count"], serde_json::json!(1));

        let _ =
            sqlx::query("DELETE FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(created.id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
    }

    /// Admin-assign path (`POST /admin/bookings/{id}/assign`): the admin is the ACTOR but the
    /// assigned guard is a DIFFERENT user (the request target). Asserts the booking lands in
    /// `accepted` with `guard_id` = the TARGET (not the admin), fires `job_accepted` carrying
    /// the target guard, and a second assign on the now-assigned booking → 409 (no reassign).
    /// DATABASE_URL-gated (hermetic SKIP otherwise). This mirrors the exact repo call
    /// `admin_assign_guard` makes: `transition(.., admin, is_admin=true, Accepted, Some(target))`.
    #[tokio::test]
    async fn admin_assign_sets_target_guard_and_enqueues_event() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let admin_id = Uuid::new_v4(); // the ACTOR (admin) — must NOT become the guard
        let target_guard = Uuid::new_v4(); // the assigned guard (request body)
        let other_guard = Uuid::new_v4(); // a second guard for the reassign attempt
        let correlation = Uuid::new_v4();

        let created = create_booking(
            &pool,
            customer_id,
            &CreateBookingRequest {
                address: "9 Admin Assign Rd".to_string(),
                scheduled_at: Utc::now(),
                hours: 3,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");
        assert_eq!(created.status, "requested");

        let assigned = transition(
            &pool,
            created.id,
            admin_id,
            true, // is_admin
            BookingStatus::Accepted,
            Some(target_guard),
            None,
            correlation,
        )
        .await
        .expect("admin assign");
        assert_eq!(assigned.status, "accepted");
        assert_eq!(
            assigned.guard_id,
            Some(target_guard),
            "the ASSIGNED guard is the request target, not the admin actor"
        );

        // Filter to job_accepted — create_booking also enqueues a booking.requested row.
        let rows: Vec<OutboxRow> = sqlx::query_as(
            "SELECT id, topic, payload FROM booking.outbox \
             WHERE payload->'payload'->>'booking_id' = $1 AND topic = $2",
        )
        .bind(created.id.to_string())
        .bind(topics::BOOKING_JOB_ACCEPTED)
        .fetch_all(&pool)
        .await
        .expect("query outbox");
        assert_eq!(rows.len(), 1, "exactly one job_accepted enqueued on assign");
        assert_eq!(rows[0].topic, topics::BOOKING_JOB_ACCEPTED);
        let envelope: EventEnvelope<Value> =
            serde_json::from_value(rows[0].payload.clone()).expect("valid envelope");
        assert_eq!(
            envelope.payload["guard_id"],
            serde_json::json!(target_guard),
            "the event carries the assigned (target) guard"
        );

        // Reassigning an already-assigned booking → 409 (ClaimUnassigned conflict). Even as
        // admin: there is no reassign path (the in-lock check has no is_admin bypass).
        let err = transition(
            &pool,
            created.id,
            admin_id,
            true,
            BookingStatus::Accepted,
            Some(other_guard),
            None,
            Uuid::new_v4(),
        )
        .await
        .expect_err("re-assigning an assigned booking is a conflict");
        assert!(matches!(err, AppError::Conflict(_)));

        // cleanup
        let _ =
            sqlx::query("DELETE FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(created.id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
    }

    /// IDOR regression: a guard who is NOT the assigned guard cannot drive another guard's
    /// in-flight booking. DATABASE_URL-gated (hermetic when unset).
    #[tokio::test]
    async fn transition_rejects_non_assigned_guard() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let owner = Uuid::new_v4(); // the assigned guard
        let intruder = Uuid::new_v4(); // a different guard
        let correlation = Uuid::new_v4();

        let created = create_booking(
            &pool,
            customer_id,
            &CreateBookingRequest {
                address: "1 IDOR Rd".to_string(),
                scheduled_at: Utc::now(),
                hours: 2,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");
        transition(
            &pool,
            created.id,
            owner,
            false,
            BookingStatus::Accepted,
            Some(owner),
            None,
            correlation,
        )
        .await
        .expect("accept");

        // Intruder cannot move the owner's booking → Forbidden (not Conflict).
        let err = transition(
            &pool,
            created.id,
            intruder,
            false,
            BookingStatus::EnRoute,
            None,
            None,
            correlation,
        )
        .await
        .expect_err("non-assigned guard must be rejected");
        assert!(
            matches!(err, AppError::Forbidden(_)),
            "expected Forbidden, got {err:?}"
        );

        // The owner can — once the booking is PAID (the PRE-PAY gate). The payment is stamped by
        // the payment.completed consumer in prod; here the test shortcut stands in for it.
        mark_paid_now(&pool, created.id).await;
        transition(
            &pool,
            created.id,
            owner,
            false,
            BookingStatus::EnRoute,
            None,
            None,
            correlation,
        )
        .await
        .expect("owner en_route");

        let _ =
            sqlx::query("DELETE FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(created.id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
    }

    /// The full lifecycle through the customer-reviewed completion drives the right events:
    /// `start` stamps `work_started_at`; the guard's `complete` (→ pending_completion) emits
    /// NOTHING; only the customer's approve (→ completed) emits `booking.completed`, carrying
    /// `booked_hours` + a non-negative `actual_seconds` for payment's proration. DATABASE_URL-gated.
    #[tokio::test]
    async fn completed_event_carries_booked_hours_and_actual_seconds() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        let created = create_booking(
            &pool,
            customer_id,
            &CreateBookingRequest {
                address: "1 Worktime Rd".to_string(),
                scheduled_at: Utc::now(),
                hours: 4,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");

        // PRE-PAY: the booking must be paid before en_route (the payment.completed consumer
        // stamps this in prod). Guard drives accept → en_route → arrived (work_started_at NOT set yet).
        mark_paid_now(&pool, created.id).await;
        for (status, assign) in [
            (BookingStatus::Accepted, Some(guard_id)),
            (BookingStatus::EnRoute, None),
            (BookingStatus::Arrived, None),
        ] {
            transition(
                &pool,
                created.id,
                guard_id,
                false,
                status,
                assign,
                None,
                correlation,
            )
            .await
            .unwrap_or_else(|e| panic!("transition to {status}: {e:?}"));
        }

        // Cannot request completion before starting the job.
        let not_started = transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::PendingCompletion,
            None,
            None,
            correlation,
        )
        .await
        .expect_err("complete before start must be rejected");
        assert!(matches!(not_started, AppError::Conflict(_)));

        // start (stamps work_started_at, stays arrived) → complete (pending_completion).
        start_job(&pool, created.id, guard_id, false, None, None)
            .await
            .expect("start");
        let work_started: Option<chrono::DateTime<Utc>> =
            sqlx::query_scalar("SELECT work_started_at FROM booking.bookings WHERE id = $1")
                .bind(created.id)
                .fetch_one(&pool)
                .await
                .expect("read work_started_at");
        assert!(work_started.is_some(), "work_started_at stamped by start");

        // The start-of-work check-in is now REQUIRED before the guard may request completion —
        // file hour 1 so the completion gate passes (a job with zero reports 409s CHECK_IN_REQUIRED).
        create_progress_report(&pool, created.id, guard_id, &report(1), correlation)
            .await
            .expect("start check-in");

        let pending = transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::PendingCompletion,
            None,
            None,
            correlation,
        )
        .await
        .expect("complete → pending_completion");
        assert_eq!(pending.status, "pending_completion");

        // The guard's completion request emits NO booking.completed yet.
        let premature: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM booking.outbox WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::BOOKING_COMPLETED)
        .bind(created.id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count");
        assert_eq!(
            premature, 0,
            "no booking.completed until the customer approves"
        );

        // CUSTOMER approves → completed → emits booking.completed with proration inputs.
        let completed = transition(
            &pool,
            created.id,
            customer_id,
            false,
            BookingStatus::Completed,
            None,
            None,
            correlation,
        )
        .await
        .expect("customer approve → completed");
        assert_eq!(completed.status, "completed");

        // Feature G: completion STAMPS the worked duration onto the row, so the returned snapshot
        // (and every later booking read) carries the reconciled figure the guard's earnings screen
        // divides by 3600. It equals the event's `actual_seconds` (same source computation).
        let stamped = completed
            .actual_seconds
            .expect("actual_seconds stamped on the completed booking");
        assert!(
            stamped >= 0,
            "actual_seconds is non-negative, got {stamped}"
        );
        let reread = get_booking(&pool, created.id).await.expect("re-read");
        assert_eq!(
            reread.actual_seconds,
            Some(stamped),
            "the stamped actual_seconds is served by every booking read"
        );

        let payload: Value = sqlx::query_scalar(
            "SELECT payload->'payload' FROM booking.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::BOOKING_COMPLETED)
        .bind(created.id.to_string())
        .fetch_one(&pool)
        .await
        .expect("read completed event payload");
        assert_eq!(payload["booked_hours"], serde_json::json!(4));
        let actual = payload["actual_seconds"]
            .as_i64()
            .expect("actual_seconds is a number");
        assert!(actual >= 0, "actual_seconds is non-negative, got {actual}");
        // The row stamp (feature G) and the event carry the SAME computed duration.
        assert_eq!(actual, stamped, "row stamp == event actual_seconds");

        // cleanup
        let _ =
            sqlx::query("DELETE FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(created.id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
    }

    /// The guard's completion request (`arrived → pending_completion`) is REFUSED until at least
    /// one check-in exists: a started-but-never-checked-in job 409s `CHECK_IN_REQUIRED`, and the
    /// same request succeeds once the start-of-work check-in is filed. This is the server-side
    /// backstop for the "จบงาน without the start check-in photo" bug (the app also gates the
    /// button, but that is UX-only). DATABASE_URL-gated (hermetic when unset).
    #[tokio::test]
    async fn pending_completion_requires_a_check_in() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        let created = create_booking(
            &pool,
            customer_id,
            &CreateBookingRequest {
                address: "9 CheckIn Rd".to_string(),
                scheduled_at: Utc::now(),
                hours: 4,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");

        mark_paid_now(&pool, created.id).await;
        for (status, assign) in [
            (BookingStatus::Accepted, Some(guard_id)),
            (BookingStatus::EnRoute, None),
            (BookingStatus::Arrived, None),
        ] {
            transition(
                &pool,
                created.id,
                guard_id,
                false,
                status,
                assign,
                None,
                correlation,
            )
            .await
            .unwrap_or_else(|e| panic!("transition to {status}: {e:?}"));
        }
        start_job(&pool, created.id, guard_id, false, None, None)
            .await
            .expect("start");

        // Started but ZERO check-ins → completion request is refused with CHECK_IN_REQUIRED.
        let refused = transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::PendingCompletion,
            None,
            None,
            correlation,
        )
        .await
        .expect_err("complete with no check-in must be refused");
        assert!(
            matches!(
                refused,
                AppError::ConflictCode {
                    code: crate::domain::state::CHECK_IN_REQUIRED_CODE,
                    ..
                }
            ),
            "expected CHECK_IN_REQUIRED, got {refused:?}"
        );
        // The refusal did NOT advance the status (still arrived).
        let still: String =
            sqlx::query_scalar("SELECT status::text FROM booking.bookings WHERE id = $1")
                .bind(created.id)
                .fetch_one(&pool)
                .await
                .expect("read status");
        assert_eq!(
            still, "arrived",
            "a refused completion leaves the job arrived"
        );

        // File the start check-in → the same request now succeeds.
        create_progress_report(&pool, created.id, guard_id, &report(1), correlation)
            .await
            .expect("start check-in");
        let pending = transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::PendingCompletion,
            None,
            None,
            correlation,
        )
        .await
        .expect("complete → pending_completion once a check-in exists");
        assert_eq!(pending.status, "pending_completion");

        // cleanup
        let _ =
            sqlx::query("DELETE FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(created.id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM booking.progress_reports WHERE booking_id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
    }

    /// Cancellation is the request OWNER's move: a non-owner (here the assigned guard) is
    /// rejected with Forbidden, while the customer succeeds and enqueues exactly one
    /// `booking.cancelled` event. Also pins the migration-0009 reason: the validated code +
    /// note are PERSISTED on the row (and served back by every read) AND ride the event.
    /// DATABASE_URL-gated (hermetic when unset).
    #[tokio::test]
    async fn cancel_is_owner_only_and_emits_cancelled() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        let created = create_booking(
            &pool,
            customer_id,
            &CreateBookingRequest {
                address: "9 Cancel Rd".to_string(),
                scheduled_at: Utc::now(),
                hours: 2,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");

        // Guard accepts (now there is an assigned guard to test the non-owner path against).
        transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Accepted,
            Some(guard_id),
            None,
            correlation,
        )
        .await
        .expect("accept");

        // The assigned guard is NOT the request owner → cancel is Forbidden (IDOR guard).
        let err = transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Cancelled,
            None,
            None,
            correlation,
        )
        .await
        .expect_err("a guard cannot cancel the customer's booking");
        assert!(
            matches!(err, AppError::Forbidden(_)),
            "expected Forbidden, got {err:?}"
        );

        // The customer can cancel a PRE-ARRIVAL booking → cancelled, WITH a reason.
        let cancelled = transition(
            &pool,
            created.id,
            customer_id,
            false,
            BookingStatus::Cancelled,
            None,
            Some(Cancellation {
                reason: "changed_plan",
                note: Some("เปลี่ยนวันแล้ว".to_string()),
            }),
            correlation,
        )
        .await
        .expect("customer cancel");
        assert_eq!(cancelled.status, "cancelled");
        // The reason is persisted on the row (and therefore served by every booking read).
        assert_eq!(
            cancelled.cancellation_reason.as_deref(),
            Some("changed_plan")
        );
        assert_eq!(cancelled.cancellation_note.as_deref(), Some("เปลี่ยนวันแล้ว"));
        let reread = get_booking(&pool, created.id).await.expect("re-read");
        assert_eq!(reread.cancellation_reason.as_deref(), Some("changed_plan"));
        assert_eq!(reread.cancellation_note.as_deref(), Some("เปลี่ยนวันแล้ว"));

        // Exactly one booking.cancelled event enqueued.
        let cancelled_events: Vec<OutboxRow> = sqlx::query_as(
            "SELECT id, topic, payload FROM booking.outbox WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::BOOKING_CANCELLED)
        .bind(created.id.to_string())
        .fetch_all(&pool)
        .await
        .expect("read cancelled events");
        assert_eq!(
            cancelled_events.len(),
            1,
            "exactly one booking.cancelled emitted"
        );
        // ...carrying the reason (stable code) + note, so notification/the app never re-read
        // booking to tell the customer WHY.
        let payload = &cancelled_events[0].payload["payload"];
        assert_eq!(payload["cancellation_reason"], "changed_plan");
        assert_eq!(payload["cancellation_note"], "เปลี่ยนวันแล้ว");

        let _ =
            sqlx::query("DELETE FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(created.id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
    }

    /// CANCEL-AFTER-DECLINE (E): a guard-`declined` booking is terminal, EXCEPT the customer may
    /// ACK it into `cancelled`. Only the request owner may (a non-participant and the assigned
    /// guard are both Forbidden); the guard's decline reason is PRESERVED on the row (the ack
    /// carries none); exactly one `booking.cancelled` is emitted; and a SECOND ack (now the row is
    /// `cancelled`, a status Cancelled is illegal from) is a 409 — the endpoint is not a universal
    /// cancel bypass. DATABASE_URL-gated (hermetic when unset).
    #[tokio::test]
    async fn cancel_after_decline_is_owner_only_from_declined() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let stranger = Uuid::new_v4(); // neither the customer nor the assigned guard
        let correlation = Uuid::new_v4();

        let created = create_booking(
            &pool,
            customer_id,
            &CreateBookingRequest {
                address: "3 Withdraw Rd".to_string(),
                scheduled_at: Utc::now(),
                hours: 2,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");

        // Guard accepts, then WITHDRAWS pre-arrival → terminal `declined` WITH a guard reason.
        transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Accepted,
            Some(guard_id),
            None,
            correlation,
        )
        .await
        .expect("accept");
        let declined = transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Declined,
            None,
            Some(Cancellation {
                reason: "sick",
                note: Some("เป็นไข้".to_string()),
            }),
            correlation,
        )
        .await
        .expect("guard decline");
        assert_eq!(declined.status, "declined");
        assert_eq!(declined.cancellation_reason.as_deref(), Some("sick"));

        // A non-participant cannot ACK it (participation gate → Forbidden, NOT a status-leaking 409).
        let stranger_err = transition(
            &pool,
            created.id,
            stranger,
            false,
            BookingStatus::Cancelled,
            None,
            None,
            correlation,
        )
        .await
        .expect_err("a non-participant cannot cancel-after-decline");
        assert!(
            matches!(stranger_err, AppError::Forbidden(_)),
            "expected Forbidden, got {stranger_err:?}"
        );

        // The assigned GUARD cannot ACK it either — Declined → Cancelled is the request OWNER's move.
        let guard_err = transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Cancelled,
            None,
            None,
            correlation,
        )
        .await
        .expect_err("the guard cannot cancel-after-decline (owner-only)");
        assert!(
            matches!(guard_err, AppError::Forbidden(_)),
            "expected Forbidden, got {guard_err:?}"
        );

        // The CUSTOMER ACKs → terminal `cancelled`. The ack carries NO reason, so the guard's
        // decline reason/note are PRESERVED on the row (they already stand as the record of why).
        let cancelled = transition(
            &pool,
            created.id,
            customer_id,
            false,
            BookingStatus::Cancelled,
            None,
            None,
            correlation,
        )
        .await
        .expect("customer ack → cancelled");
        assert_eq!(cancelled.status, "cancelled");
        assert_eq!(
            cancelled.cancellation_reason.as_deref(),
            Some("sick"),
            "the guard's decline reason is preserved, not overwritten"
        );
        assert_eq!(cancelled.cancellation_note.as_deref(), Some("เป็นไข้"));

        // Exactly one booking.cancelled emitted (payment's cancel consumer NoOps it — the earlier
        // booking.declined already refunded; this row is not `completed`).
        let cancelled_events: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM booking.outbox WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::BOOKING_CANCELLED)
        .bind(created.id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count cancelled events");
        assert_eq!(cancelled_events, 1, "exactly one booking.cancelled emitted");

        // A SECOND ack now finds the row `cancelled` (Cancelled → Cancelled is illegal, and only
        // Declined → Cancelled is the special edge) → 409, so the endpoint is not a cancel bypass.
        let repeat_err = transition(
            &pool,
            created.id,
            customer_id,
            false,
            BookingStatus::Cancelled,
            None,
            None,
            correlation,
        )
        .await
        .expect_err("cancel-after-decline on a non-declined booking is rejected");
        assert!(
            matches!(repeat_err, AppError::Conflict(_)),
            "expected Conflict, got {repeat_err:?}"
        );

        let _ =
            sqlx::query("DELETE FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(created.id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
    }

    /// HIGH #1: the worked duration is measured at the guard's completion REQUEST
    /// (`arrived → pending_completion`), NOT at the customer's later approval. We drive to
    /// `pending_completion` (which stamps `completion_requested_at`), then backdate the clocks so
    /// the start→request interval is exactly 2h while "now" (the approval moment) sits 5h past the
    /// start. The stamped `actual_seconds` must be ~2h — an approval-time measurement would have
    /// billed ~5h, eating the whole review wait. DATABASE_URL-gated (hermetic when unset).
    #[tokio::test]
    async fn worked_duration_measured_at_completion_request_not_approval() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let (booking_id, customer_id, guard_id) = started_booking(&pool).await;
        let correlation = Uuid::new_v4();

        // The start-of-work check-in gates completion.
        create_progress_report(&pool, booking_id, guard_id, &report(1), correlation)
            .await
            .expect("start check-in");

        // Guard requests completion → pending_completion → `completion_requested_at` stamped.
        transition(
            &pool,
            booking_id,
            guard_id,
            false,
            BookingStatus::PendingCompletion,
            None,
            None,
            correlation,
        )
        .await
        .expect("request completion");
        let stamped: Option<DateTime<Utc>> = sqlx::query_scalar(
            "SELECT completion_requested_at FROM booking.bookings WHERE id = $1",
        )
        .bind(booking_id)
        .fetch_one(&pool)
        .await
        .expect("read completion_requested_at");
        assert!(
            stamped.is_some(),
            "completion_requested_at is stamped on the completion request"
        );

        // Worked interval start→request = 2h; the approval ("now") is 5h past the start. A bug that
        // measures now−start would bill ~5h; the fix measures request−start = ~2h.
        sqlx::query(
            "UPDATE booking.bookings \
             SET work_started_at = now() - interval '5 hours', \
                 completion_requested_at = now() - interval '3 hours' \
             WHERE id = $1",
        )
        .bind(booking_id)
        .execute(&pool)
        .await
        .expect("backdate the work + request clocks");

        let completed = transition(
            &pool,
            booking_id,
            customer_id,
            false,
            BookingStatus::Completed,
            None,
            None,
            correlation,
        )
        .await
        .expect("customer approve → completed");
        let secs = completed
            .actual_seconds
            .expect("actual_seconds stamped on completion");
        assert!(
            (7000..=7400).contains(&secs),
            "worked duration measured at the request (~7200s / 2h), got {secs}s"
        );
        assert!(
            secs < 4 * 3600,
            "the pending-completion review wait must NOT be counted as worked time, got {secs}s"
        );

        cleanup_booking(&pool, booking_id).await;
    }

    /// HIGH #1 (bounce): the customer's completion REJECT (`pending_completion → arrived`) CLEARS
    /// `completion_requested_at`, and a fresh completion request re-stamps it — so work resumed
    /// after a reject is re-measured from the NEXT request, not the stale first one.
    /// DATABASE_URL-gated (hermetic when unset).
    #[tokio::test]
    async fn completion_reject_clears_then_restamps_completion_requested_at() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let (booking_id, customer_id, guard_id) = started_booking(&pool).await;
        let correlation = Uuid::new_v4();
        create_progress_report(&pool, booking_id, guard_id, &report(1), correlation)
            .await
            .expect("start check-in");

        let read_stamp = |pool: sqlx::PgPool| async move {
            sqlx::query_scalar::<_, Option<DateTime<Utc>>>(
                "SELECT completion_requested_at FROM booking.bookings WHERE id = $1",
            )
            .bind(booking_id)
            .fetch_one(&pool)
            .await
            .expect("read completion_requested_at")
        };

        // First completion request → stamped.
        transition(
            &pool,
            booking_id,
            guard_id,
            false,
            BookingStatus::PendingCompletion,
            None,
            None,
            correlation,
        )
        .await
        .expect("first completion request");
        let first = read_stamp(pool.clone()).await;
        assert!(
            first.is_some(),
            "first request stamps completion_requested_at"
        );

        // Customer REJECTS → arrived → the stamp is CLEARED.
        transition(
            &pool,
            booking_id,
            customer_id,
            false,
            BookingStatus::Arrived,
            None,
            None,
            correlation,
        )
        .await
        .expect("customer reject → arrived");
        assert!(
            read_stamp(pool.clone()).await.is_none(),
            "the completion-reject bounce clears completion_requested_at"
        );

        // Guard requests completion AGAIN → re-stamped (a fresh, non-stale time).
        transition(
            &pool,
            booking_id,
            guard_id,
            false,
            BookingStatus::PendingCompletion,
            None,
            None,
            correlation,
        )
        .await
        .expect("second completion request");
        let second = read_stamp(pool.clone()).await;
        assert!(
            second.is_some() && second >= first,
            "the second request re-stamps completion_requested_at, got {second:?} vs {first:?}"
        );

        cleanup_booking(&pool, booking_id).await;
    }

    /// MED #5: the cancel-after-decline ACK (a `Cancelled` target carrying NO reason) is legal
    /// ONLY out of `declined`. Aimed at a still-active booking (here `accepted`) it must NOT commit
    /// a reasonless money-bearing terminal cancel — it is a typed 400 `CANCEL_REASON_REQUIRED`, and
    /// the booking is left untouched. DATABASE_URL-gated (hermetic when unset).
    #[tokio::test]
    async fn ack_path_on_an_active_booking_is_rejected_reason_required() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();
        let created = create_booking(
            &pool,
            customer_id,
            &booking_req("5 Ack Rd", 2, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");
        transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Accepted,
            Some(guard_id),
            None,
            correlation,
        )
        .await
        .expect("accept");

        // The ACK shape (Cancelled + None cancellation) from `accepted` — the MED #5 vector.
        let err = transition(
            &pool,
            created.id,
            customer_id,
            false,
            BookingStatus::Cancelled,
            None,
            None,
            correlation,
        )
        .await
        .expect_err("a reasonless cancel of an ACTIVE booking must be refused");
        match err {
            AppError::BadRequestCode { code, .. } => {
                assert_eq!(code, CANCEL_REASON_REQUIRED_CODE)
            }
            other => panic!("expected CANCEL_REASON_REQUIRED, got {other:?}"),
        }

        // Untouched: still `accepted`, no cancellation, and no booking.cancelled leaked.
        let core = get_booking_core(&pool, created.id).await.expect("re-read");
        assert_eq!(core.status, BookingStatus::Accepted);
        let leaked: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM booking.outbox WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::BOOKING_CANCELLED)
        .bind(created.id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count");
        assert_eq!(
            leaked, 0,
            "no booking.cancelled emitted for the rejected ack"
        );

        cleanup_booking(&pool, created.id).await;
    }

    /// LOW #29: the REGULAR `PUT /cancel` (which carries a validated CUSTOMER reason) sent on a
    /// booking the guard already `declined` must PRESERVE the guard's decline reason/note — the
    /// COALESCE used to let the customer's non-NULL reason overwrite the guard's, producing a
    /// mismatched reason/note pair. DATABASE_URL-gated (hermetic when unset).
    #[tokio::test]
    async fn regular_cancel_on_declined_preserves_the_guard_reason() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();
        let created = create_booking(
            &pool,
            customer_id,
            &booking_req("6 Preserve Rd", 2, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");
        transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Accepted,
            Some(guard_id),
            None,
            correlation,
        )
        .await
        .expect("accept");
        transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Declined,
            None,
            Some(Cancellation {
                reason: "sick",
                note: Some("รถเสียกลางทาง".to_string()),
            }),
            correlation,
        )
        .await
        .expect("guard decline");

        // The customer sends the REGULAR cancel WITH a customer reason (older app build / direct
        // HTTP). It must NOT overwrite the guard's recorded decline reason.
        let cancelled = transition(
            &pool,
            created.id,
            customer_id,
            false,
            BookingStatus::Cancelled,
            None,
            Some(Cancellation {
                reason: "changed_plan",
                note: None,
            }),
            correlation,
        )
        .await
        .expect("customer cancel on a declined booking");
        assert_eq!(cancelled.status, "cancelled");
        assert_eq!(
            cancelled.cancellation_reason.as_deref(),
            Some("sick"),
            "the guard's decline reason is preserved, not overwritten by the customer code"
        );
        assert_eq!(
            cancelled.cancellation_note.as_deref(),
            Some("รถเสียกลางทาง"),
            "the guard's decline note is preserved too"
        );

        cleanup_booking(&pool, created.id).await;
    }

    /// Cancellation-fee policy (booking side): the `charge_cancel_fee` flag on the emitted
    /// `booking.cancelled` event is TRUE only for a genuine customer-initiated cancel of a
    /// still-active booking, and FALSE for an admin cancel and for the cancel-after-decline ACK.
    /// DATABASE_URL-gated (hermetic when unset).
    #[tokio::test]
    async fn charge_cancel_fee_flag_reflects_the_initiator() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        // Read the `charge_cancel_fee` on the newest booking.cancelled event for a booking.
        async fn fee_flag(pool: &sqlx::PgPool, booking_id: Uuid) -> Value {
            let payload: Value = sqlx::query_scalar(
                "SELECT payload->'payload' FROM booking.outbox \
                 WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2 \
                 ORDER BY created_at DESC LIMIT 1",
            )
            .bind(topics::BOOKING_CANCELLED)
            .bind(booking_id.to_string())
            .fetch_one(pool)
            .await
            .expect("read booking.cancelled payload");
            payload["charge_cancel_fee"].clone()
        }

        // Drive a fresh booking to `accepted` and return its ids.
        async fn accepted(pool: &sqlx::PgPool, addr: &str) -> (Uuid, Uuid, Uuid) {
            let customer_id = Uuid::new_v4();
            let guard_id = Uuid::new_v4();
            let correlation = Uuid::new_v4();
            let created = create_booking(
                pool,
                customer_id,
                &booking_req(addr, 2, None),
                1,
                rust_decimal::Decimal::ZERO,
                None,
                correlation,
            )
            .await
            .expect("create");
            transition(
                pool,
                created.id,
                guard_id,
                false,
                BookingStatus::Accepted,
                Some(guard_id),
                None,
                correlation,
            )
            .await
            .expect("accept");
            (created.id, customer_id, guard_id)
        }

        let reason = || {
            Some(Cancellation {
                reason: "changed_plan",
                note: None,
            })
        };

        // (a) CUSTOMER cancels an active booking → fee flag TRUE.
        let (id_a, cust_a, _g) = accepted(&pool, "10a Fee Rd").await;
        transition(
            &pool,
            id_a,
            cust_a,
            false,
            BookingStatus::Cancelled,
            None,
            reason(),
            Uuid::new_v4(),
        )
        .await
        .expect("customer cancel");
        assert_eq!(
            fee_flag(&pool, id_a).await,
            serde_json::json!(true),
            "a customer cancel of an active booking charges the fee"
        );

        // (b) ADMIN cancels on the customer's behalf → fee flag FALSE.
        let (id_b, cust_b, _g) = accepted(&pool, "10b Fee Rd").await;
        transition(
            &pool,
            id_b,
            cust_b,
            true, // is_admin
            BookingStatus::Cancelled,
            None,
            reason(),
            Uuid::new_v4(),
        )
        .await
        .expect("admin cancel");
        assert_eq!(
            fee_flag(&pool, id_b).await,
            serde_json::json!(false),
            "an admin cancel must never charge the customer a fee"
        );

        // (c) cancel-after-decline ACK (declined → cancelled) → fee flag FALSE.
        let (id_c, cust_c, guard_c) = accepted(&pool, "10c Fee Rd").await;
        transition(
            &pool,
            id_c,
            guard_c,
            false,
            BookingStatus::Declined,
            None,
            Some(Cancellation {
                reason: "sick",
                note: None,
            }),
            Uuid::new_v4(),
        )
        .await
        .expect("guard decline");
        transition(
            &pool,
            id_c,
            cust_c,
            false,
            BookingStatus::Cancelled,
            None,
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("customer ack");
        assert_eq!(
            fee_flag(&pool, id_c).await,
            serde_json::json!(false),
            "the decline ACK is a fee-free full refund"
        );

        for id in [id_a, id_b, id_c] {
            cleanup_booking(&pool, id).await;
        }
    }

    /// Customer review REJECT branch: from `pending_completion` the owner sends the job back
    /// to `arrived` (the guard finishes); a non-owner is Forbidden, and no `booking.completed`
    /// leaks on the reject path. DATABASE_URL-gated (hermetic when unset).
    #[tokio::test]
    async fn review_reject_returns_to_arrived_owner_only() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        let created = create_booking(
            &pool,
            customer_id,
            &CreateBookingRequest {
                address: "7 Reject Rd".to_string(),
                scheduled_at: Utc::now(),
                hours: 3,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");

        // PRE-PAY gate: paid before en_route. Drive to pending_completion: accept → en_route →
        // arrived → start → complete.
        mark_paid_now(&pool, created.id).await;
        for (status, assign) in [
            (BookingStatus::Accepted, Some(guard_id)),
            (BookingStatus::EnRoute, None),
            (BookingStatus::Arrived, None),
        ] {
            transition(
                &pool,
                created.id,
                guard_id,
                false,
                status,
                assign,
                None,
                correlation,
            )
            .await
            .unwrap_or_else(|e| panic!("transition to {status}: {e:?}"));
        }
        start_job(&pool, created.id, guard_id, false, None, None)
            .await
            .expect("start");
        // Start-of-work check-in is required before completion can be requested.
        create_progress_report(&pool, created.id, guard_id, &report(1), correlation)
            .await
            .expect("start check-in");
        transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::PendingCompletion,
            None,
            None,
            correlation,
        )
        .await
        .expect("complete → pending_completion");

        // A non-owner (the guard) cannot review their own completion request → Forbidden.
        let err = transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Arrived,
            None,
            None,
            correlation,
        )
        .await
        .expect_err("guard cannot review their own completion");
        assert!(
            matches!(err, AppError::Forbidden(_)),
            "expected Forbidden, got {err:?}"
        );

        // The customer rejects → back to arrived (the guard keeps working).
        let rejected = transition(
            &pool,
            created.id,
            customer_id,
            false,
            BookingStatus::Arrived,
            None,
            None,
            correlation,
        )
        .await
        .expect("customer reject → arrived");
        assert_eq!(rejected.status, "arrived");

        // No booking.completed leaked on the reject path (reject emits no cross-service event).
        let completed_events: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM booking.outbox WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::BOOKING_COMPLETED)
        .bind(created.id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count completed events");
        assert_eq!(
            completed_events, 0,
            "reject must not emit booking.completed"
        );

        // The reject bounce (pending_completion → arrived) RE-fires booking.arrived so the
        // GUARD's live screen leaves "pending_completion" without a manual refresh: TWO arrived
        // events now exist — the original fresh arrival + the reject bounce.
        let arrived_events: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM booking.outbox WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::BOOKING_ARRIVED)
        .bind(created.id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count arrived events");
        assert_eq!(
            arrived_events, 2,
            "fresh arrival + reject bounce both emit booking.arrived (guard's live screen update)"
        );

        // The guard's completion REQUEST (arrived → pending_completion) emitted exactly one
        // booking.completion_requested — the live event that updates the CUSTOMER's screen.
        let completion_requested_events: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM booking.outbox WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::BOOKING_COMPLETION_REQUESTED)
        .bind(created.id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count completion_requested events");
        assert_eq!(
            completion_requested_events, 1,
            "the guard's completion request emits exactly one booking.completion_requested"
        );

        let _ =
            sqlx::query("DELETE FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(created.id.to_string())
                .execute(&pool)
                .await;
        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
    }

    /// IDOR / status-leak regression: a NON-participant (neither customer nor assigned guard)
    /// who attempts an ILLEGAL transition gets a generic `Forbidden` (403) — NOT a `Conflict`
    /// (409) whose body would disclose the booking's real current status. DATABASE_URL-gated.
    #[tokio::test]
    async fn non_participant_illegal_transition_is_forbidden_not_leaking_state() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let stranger = Uuid::new_v4(); // neither the customer nor the assigned guard
        let correlation = Uuid::new_v4();

        let created = create_booking(
            &pool,
            customer_id,
            &CreateBookingRequest {
                address: "5 Leak Rd".to_string(),
                scheduled_at: Utc::now(),
                hours: 2,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");
        transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Accepted,
            Some(guard_id),
            None,
            correlation,
        )
        .await
        .expect("accept");

        // Booking is now `accepted`. The stranger probes /complete (pending_completion), which is
        // ILLEGAL from accepted. They must NOT learn the booking is `accepted` — expect a generic
        // Forbidden, and the message must not contain the real current status.
        let err = transition(
            &pool,
            created.id,
            stranger,
            false,
            BookingStatus::PendingCompletion,
            None,
            None,
            correlation,
        )
        .await
        .expect_err("non-participant illegal transition must be rejected");
        assert!(
            matches!(err, AppError::Forbidden(_)),
            "expected Forbidden (no state leak), got {err:?}"
        );
        assert!(
            !err.to_string().to_lowercase().contains("accepted"),
            "error must not disclose the booking's current status, got: {err}"
        );

        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
    }

    /// Build a CreateBookingRequest for tests (optionally with site coordinates).
    fn booking_req(address: &str, hours: i32, coords: Option<(f64, f64)>) -> CreateBookingRequest {
        CreateBookingRequest {
            address: address.to_string(),
            scheduled_at: Utc::now(),
            hours,
            service_id: None,
            guard_count: None,
            tip: None,
            lat: coords.map(|c| c.0),
            lng: coords.map(|c| c.1),
            target_guard_id: None,
        }
    }

    /// Drive a fresh booking to `arrived` + started (the check-in-able state). Returns
    /// (booking_id, customer_id, guard_id).
    async fn started_booking(pool: &sqlx::PgPool) -> (Uuid, Uuid, Uuid) {
        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();
        let created = create_booking(
            pool,
            customer_id,
            &booking_req("1 CheckIn Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");
        // PRE-PAY gate: paid before en_route (the payment.completed consumer does this in prod).
        mark_paid_now(pool, created.id).await;
        for (status, assign) in [
            (BookingStatus::Accepted, Some(guard_id)),
            (BookingStatus::EnRoute, None),
            (BookingStatus::Arrived, None),
        ] {
            transition(
                pool,
                created.id,
                guard_id,
                false,
                status,
                assign,
                None,
                correlation,
            )
            .await
            .unwrap_or_else(|e| panic!("transition to {status}: {e:?}"));
        }
        start_job(pool, created.id, guard_id, false, None, None)
            .await
            .expect("start");
        (created.id, customer_id, guard_id)
    }

    fn report(hour: i32) -> NewProgressReport {
        NewProgressReport {
            hour_number: hour,
            photo_key: format!("booking/test/checkins/{}.jpg", Uuid::new_v4()),
            lat: Some(13.7563),
            lng: Some(100.5018),
            accuracy_m: Some(8.5),
            note: Some("perimeter clear".to_string()),
        }
    }

    async fn cleanup_booking(pool: &sqlx::PgPool, id: Uuid) {
        // progress_reports cascade-deletes with the booking (FK ON DELETE CASCADE).
        let _ =
            sqlx::query("DELETE FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(id.to_string())
                .execute(pool)
                .await;
        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(id)
            .execute(pool)
            .await;
    }

    /// Stamp `paid_at` directly (test shortcut for "the payment.completed consumer ran"), so a
    /// test that needs to drive the PRE-PAY-gated `accepted → en_route` transition can. The
    /// consumer's own idempotent stamp is exercised by `mark_paid_idempotent_*`.
    async fn mark_paid_now(pool: &sqlx::PgPool, id: Uuid) {
        sqlx::query("UPDATE booking.bookings SET paid_at = now() WHERE id = $1")
            .bind(id)
            .execute(pool)
            .await
            .expect("mark paid");
    }

    /// G1: a check-in filed AFTER the job's window closes (worked end `work_started_at + hours`,
    /// plus the 30-min grace) is 409 `CHECK_IN_WINDOW_CLOSED` — NOT the too-early `CONFLICT`. We
    /// backdate `work_started_at` so the whole window sits in the past. DATABASE_URL-gated.
    #[tokio::test]
    async fn check_in_after_window_closed_is_rejected() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let (booking_id, _customer_id, guard_id) = started_booking(&pool).await;
        let correlation = Uuid::new_v4();

        // hours = 4 → worked end at start+4h, window closes at +4h30m. Backdate the work clock 5h
        // so that boundary is already ~30min in the past (window closed, but no hour is too-early).
        sqlx::query(
            "UPDATE booking.bookings SET work_started_at = now() - interval '5 hours' WHERE id = $1",
        )
        .bind(booking_id)
        .execute(&pool)
        .await
        .expect("backdate work_started_at");

        let err = create_progress_report(&pool, booking_id, guard_id, &report(1), correlation)
            .await
            .expect_err("check-in after the window closes must be rejected");
        match err {
            AppError::ConflictCode { code, .. } => assert_eq!(
                code,
                crate::domain::progress::CHECK_IN_WINDOW_CLOSED_CODE,
                "expected CHECK_IN_WINDOW_CLOSED, got {code}"
            ),
            other => panic!("expected CHECK_IN_WINDOW_CLOSED ConflictCode, got {other:?}"),
        }

        cleanup_booking(&pool, booking_id).await;
    }

    /// The check-in's transactional outbox, end-to-end: a valid hour-1 check-in writes the
    /// report row AND exactly one `booking.progress_reported` outbox row in ONE tx (valid
    /// envelope, correct payload); a DUPLICATE hour is 409 and — atomicity of the failure
    /// path — enqueues NOTHING; a too-early future hour is 409; an out-of-range hour is 400.
    /// Run against a 0004-migrated DB:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///     cargo test -p pguard-booking -- progress_report_outbox --nocapture
    #[tokio::test]
    async fn progress_report_outbox_atomic_and_duplicate_hour_conflict() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let (booking_id, customer_id, guard_id) = started_booking(&pool).await;
        let correlation = Uuid::new_v4();

        // Valid hour-1 check-in → row + exactly one outbox event.
        let row = create_progress_report(&pool, booking_id, guard_id, &report(1), correlation)
            .await
            .expect("hour-1 check-in");
        assert_eq!(row.booking_id, booking_id);
        assert_eq!(row.guard_id, guard_id);
        assert_eq!(row.hour_number, 1);
        assert!(row.photo_key.starts_with("booking/"));

        let rows: Vec<OutboxRow> = sqlx::query_as(
            "SELECT id, topic, payload FROM booking.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::BOOKING_PROGRESS_REPORTED)
        .bind(booking_id.to_string())
        .fetch_all(&pool)
        .await
        .expect("query outbox");
        assert_eq!(
            rows.len(),
            1,
            "exactly one progress_reported event enqueued"
        );
        let envelope: EventEnvelope<Value> =
            serde_json::from_value(rows[0].payload.clone()).expect("valid envelope");
        assert_eq!(envelope.event_type, topics::BOOKING_PROGRESS_REPORTED);
        assert_eq!(envelope.correlation_id, correlation);
        assert_eq!(
            envelope.payload["customer_id"],
            serde_json::json!(customer_id),
            "event carries the notification-routing customer_id"
        );
        assert_eq!(envelope.payload["guard_id"], serde_json::json!(guard_id));
        assert_eq!(envelope.payload["report_id"], serde_json::json!(row.id));
        assert_eq!(envelope.payload["hour_number"], serde_json::json!(1));

        // The advisory pre-flight the handler runs before the S3 upload sees the row.
        assert!(progress_report_exists(&pool, booking_id, 1)
            .await
            .expect("exists check"));
        assert!(!progress_report_exists(&pool, booking_id, 2)
            .await
            .expect("exists check"));

        // DUPLICATE hour → 409 with the DUPLICATE_CHECK_IN sub-code (the unique-index 23505
        // race path), and the failed tx enqueues NO second event (atomicity).
        let dup = create_progress_report(&pool, booking_id, guard_id, &report(1), correlation)
            .await
            .expect_err("duplicate hour must be rejected");
        assert!(
            matches!(
                &dup,
                AppError::ConflictCode { code, .. }
                    if *code == crate::domain::progress::DUPLICATE_CHECK_IN_CODE
            ),
            "duplicate hour must carry DUPLICATE_CHECK_IN, got {dup:?}"
        );

        // Too-early FUTURE hour (work just started → only hour 1 open) → 409, nothing enqueued.
        // This stays a PLAIN Conflict (code `CONFLICT`) — the sub-code is duplicate-only.
        let early = create_progress_report(&pool, booking_id, guard_id, &report(2), correlation)
            .await
            .expect_err("hour 2 right after start must be too early");
        assert!(matches!(early, AppError::Conflict(_)), "got {early:?}");

        // Out-of-range hour → 400.
        let out = create_progress_report(&pool, booking_id, guard_id, &report(99), correlation)
            .await
            .expect_err("hour beyond the booked hours must be rejected");
        assert!(matches!(out, AppError::BadRequest(_)), "got {out:?}");

        let count: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM booking.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::BOOKING_PROGRESS_REPORTED)
        .bind(booking_id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count");
        assert_eq!(count, 1, "failed check-ins must enqueue no events");

        cleanup_booking(&pool, booking_id).await;
    }

    /// Overdue-check-ins admin signal against Postgres: a started 4-hour job whose
    /// `work_started_at` is backdated 3h15m has hours 1-4 OPEN (1@-3h15, 2@-2h15, 3@-1h15,
    /// 4@-0h15). Filing hour 1 leaves 3 gaps → `missed_count = 3`, `due_at` = hour-2's open
    /// time (the oldest gap, ≈ −2h15). The count query agrees (1 job). A NOT-started job and a
    /// fully-filed one do not appear. DATABASE_URL-gated.
    #[tokio::test]
    async fn overdue_checkins_lists_unfiled_past_due_hours() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let (booking_id, customer_id, guard_id) = started_booking(&pool).await;
        let correlation = Uuid::new_v4();

        // Backdate the proration clock so hours 1-4 have all opened (4-hour job).
        sqlx::query(
            "UPDATE booking.bookings SET work_started_at = now() - interval '3 hours 15 minutes' \
             WHERE id = $1",
        )
        .bind(booking_id)
        .execute(&pool)
        .await
        .expect("backdate work_started_at");

        // File ONLY hour 1 — hours 2,3,4 are now owed-but-unfiled past-due gaps.
        create_progress_report(&pool, booking_id, guard_id, &report(1), correlation)
            .await
            .expect("hour-1 check-in");

        let items = overdue_checkins(&pool, 50, 0).await.expect("overdue list");
        let row = items
            .iter()
            .find(|r| r.booking_id == booking_id)
            .expect("our job is overdue");
        assert_eq!(row.guard_id, guard_id);
        assert_eq!(row.customer_id, customer_id);
        assert_eq!(row.missed_count, 3, "hours 2,3,4 are unfiled past-due");
        // due_at = oldest gap = hour 2 opens at work_started_at + 1h ≈ now − 2h15m.
        let since = Utc::now() - row.due_at;
        assert!(
            since.num_minutes() >= 130 && since.num_minutes() <= 140,
            "due_at is hour-2's open time (~135m ago), got {}m",
            since.num_minutes()
        );

        let count = overdue_checkins_count(&pool).await.expect("overdue count");
        assert!(count >= 1, "the count query sees our overdue job");

        // Fill the remaining hours → the job drops off both the list and the count delta.
        for h in [2, 3, 4] {
            create_progress_report(&pool, booking_id, guard_id, &report(h), correlation)
                .await
                .unwrap_or_else(|e| panic!("hour-{h} check-in: {e:?}"));
        }
        let after = overdue_checkins(&pool, 50, 0).await.expect("overdue list");
        assert!(
            !after.iter().any(|r| r.booking_id == booking_id),
            "a fully-filed job is no longer overdue"
        );

        cleanup_booking(&pool, booking_id).await;
    }

    /// Check-in IDOR + state gates against Postgres: a STRANGER guard and the CUSTOMER are
    /// both Forbidden (generic — no job-state leak in the message); a not-yet-started
    /// booking is 409; and the strictness is owner-only (no admin path exists in the repo
    /// signature by design). DATABASE_URL-gated.
    #[tokio::test]
    async fn progress_report_rejects_strangers_and_unstarted_job() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let (booking_id, customer_id, _guard_id) = started_booking(&pool).await;
        let stranger = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        // Stranger → generic Forbidden; the message must not disclose the booking's status.
        let err = create_progress_report(&pool, booking_id, stranger, &report(1), correlation)
            .await
            .expect_err("stranger must not check in");
        assert!(matches!(err, AppError::Forbidden(_)), "got {err:?}");
        assert!(
            !err.to_string().to_lowercase().contains("arrived"),
            "error must not disclose the booking's status, got: {err}"
        );

        // The customer is a participant but NOT the assigned guard → Forbidden.
        let err = create_progress_report(&pool, booking_id, customer_id, &report(1), correlation)
            .await
            .expect_err("the customer cannot file the guard's check-in");
        assert!(matches!(err, AppError::Forbidden(_)), "got {err:?}");

        // A booking whose job was never started (still accepted) → Conflict for its OWN guard.
        let customer2 = Uuid::new_v4();
        let guard2 = Uuid::new_v4();
        let unstarted = create_booking(
            &pool,
            customer2,
            &booking_req("2 NotStarted Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");
        transition(
            &pool,
            unstarted.id,
            guard2,
            false,
            BookingStatus::Accepted,
            Some(guard2),
            None,
            correlation,
        )
        .await
        .expect("accept");
        let err = create_progress_report(&pool, unstarted.id, guard2, &report(1), correlation)
            .await
            .expect_err("check-in before the job is in progress must be rejected");
        assert!(matches!(err, AppError::Conflict(_)), "got {err:?}");

        // No rows and no events leaked from any rejected path.
        let reports: i64 =
            sqlx::query_scalar("SELECT count(*) FROM booking.progress_reports WHERE booking_id = $1 OR booking_id = $2")
                .bind(booking_id)
                .bind(unstarted.id)
                .fetch_one(&pool)
                .await
                .expect("count reports");
        assert_eq!(reports, 0, "every rejected path must persist nothing");

        cleanup_booking(&pool, booking_id).await;
        cleanup_booking(&pool, unstarted.id).await;
    }

    /// Open-job discovery filter: returns ONLY `requested AND guard_id IS NULL` rows —
    /// never another guard's accepted job; the geo filter returns only coordinate-bearing
    /// bookings within the radius (nearest first) and never the coordinate-less ones.
    /// Membership-only assertions (the shared test DB runs other suites concurrently).
    /// DATABASE_URL-gated.
    #[tokio::test]
    async fn open_jobs_filter_requested_unassigned_and_radius() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let correlation = Uuid::new_v4();
        // An isolated reference point in the Gulf of Thailand — far from anything other
        // concurrent tests might create (they create coordinate-less bookings anyway).
        let (ref_lat, ref_lng) = (10.123456, 101.654321);

        // A: requested + coords near the reference point → must appear in the geo search.
        let near = create_booking(
            &pool,
            customer,
            &booking_req("A Near Rd", 4, Some((ref_lat + 0.01, ref_lng))), // ~1.1km north
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create near");
        // B: requested, NO coords → in the plain list, never in a geo-filtered one.
        let no_coords = create_booking(
            &pool,
            customer,
            &booking_req("B NoCoords Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create no-coords");
        // C: near coords but ACCEPTED (assigned) → never an open job.
        let taken = create_booking(
            &pool,
            customer,
            &booking_req("C Taken Rd", 4, Some((ref_lat, ref_lng))),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create taken");
        transition(
            &pool,
            taken.id,
            guard,
            false,
            BookingStatus::Accepted,
            Some(guard),
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("accept C");
        // D: requested + coords ~110km away → outside the 5km radius.
        let far = create_booking(
            &pool,
            customer,
            &booking_req("D Far Rd", 4, Some((ref_lat + 1.0, ref_lng))),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create far");

        // Plain list (no geo): open jobs include A and B, never the accepted C.
        let viewer = Uuid::new_v4(); // a guard with no skips → sees every open job
        let open = list_open_bookings(&pool, viewer, None, 200, 0)
            .await
            .expect("plain open list");
        assert!(open.iter().any(|b| b.id == near.id), "A (near) is open");
        assert!(
            open.iter().any(|b| b.id == no_coords.id),
            "B (no coords) is open in the plain list"
        );
        assert!(
            !open.iter().any(|b| b.id == taken.id),
            "C (accepted) must never appear as an open job"
        );

        // Geo search (5km around the reference): only A — not B (no coords), not C
        // (assigned), not D (110km away). Nearest-first ordering is implicit (A is the
        // only in-radius row); the formula itself is pinned by the distance bound.
        let geo = list_open_bookings(
            &pool,
            viewer,
            Some(GeoFilter {
                lat: ref_lat,
                lng: ref_lng,
                radius_km: 5.0,
            }),
            200,
            0,
        )
        .await
        .expect("geo open list");
        assert!(geo.iter().any(|b| b.id == near.id), "A within 5km");
        assert!(
            !geo.iter().any(|b| b.id == no_coords.id),
            "coordinate-less bookings never match a radius filter"
        );
        assert!(!geo.iter().any(|b| b.id == taken.id), "C is assigned");
        assert!(!geo.iter().any(|b| b.id == far.id), "D is ~110km away");

        // The response rows carry the coordinates (mobile renders distance client-side).
        let a = geo.iter().find(|b| b.id == near.id).expect("A row");
        assert_eq!(a.lat, Some(ref_lat + 0.01));
        assert_eq!(a.lng, Some(ref_lng));

        // SKIP: the viewer passes on A → it disappears from THEIR open list (both plain + geo), but
        // stays open for a DIFFERENT guard, and the skip is idempotent.
        skip_job(&pool, viewer, near.id).await.expect("skip");
        skip_job(&pool, viewer, near.id)
            .await
            .expect("skip idempotent");
        let after = list_open_bookings(&pool, viewer, None, 200, 0)
            .await
            .unwrap();
        assert!(
            !after.iter().any(|b| b.id == near.id),
            "the viewer's skipped job A is excluded from their open list"
        );
        let other = list_open_bookings(&pool, Uuid::new_v4(), None, 200, 0)
            .await
            .unwrap();
        assert!(
            other.iter().any(|b| b.id == near.id),
            "A stays open for a different guard (skip is per-guard, not a cancel)"
        );

        for id in [near.id, no_coords.id, taken.id, far.id] {
            cleanup_booking(&pool, id).await;
        }
    }

    /// DIRECTED OFFER (C3), end-to-end against Postgres. A booking directed at ONE guard is
    /// (1) INVISIBLE to a non-target guard's discovery (plain AND geo), (2) VISIBLE to the target,
    /// (3) rejects a non-target `accept` with 403 `NOT_OFFERED_TO_YOU`, and (4) accepts fine for
    /// the target — while an OPEN (target NULL) booking stays claimable by ANY guard.
    /// DATABASE_URL-gated.
    #[tokio::test]
    async fn directed_offer_is_visible_and_acceptable_only_to_the_target() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer = Uuid::new_v4();
        let target = Uuid::new_v4();
        let other = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        // A directed CreateBookingRequest: identical to booking_req but with the chosen guard set.
        let directed_req = |addr: &str, tgt: Uuid| CreateBookingRequest {
            address: addr.to_string(),
            scheduled_at: Utc::now(),
            hours: 4,
            service_id: None,
            guard_count: None,
            tip: None,
            lat: None,
            lng: None,
            target_guard_id: Some(tgt),
        };

        // A DIRECTED booking (offered to `target`) and an OPEN one (legacy first-come).
        let directed = create_booking(
            &pool,
            customer,
            &directed_req("Directed Rd", target),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create directed");
        // The persisted row carries the target (it round-trips through the response).
        assert_eq!(
            directed.target_guard_id,
            Some(target),
            "the chosen guard is persisted as target_guard_id"
        );
        let open = create_booking(
            &pool,
            customer,
            &booking_req("Open Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create open");
        assert_eq!(open.target_guard_id, None, "an un-directed booking is open");

        // (1) DISCOVERY — a NON-target guard sees the OPEN job but NOT the directed one.
        let other_open = list_open_bookings(&pool, other, None, 200, 0)
            .await
            .expect("other open list");
        assert!(
            other_open.iter().any(|b| b.id == open.id),
            "a non-target guard sees the OPEN job"
        );
        assert!(
            !other_open.iter().any(|b| b.id == directed.id),
            "a non-target guard must NOT see a job directed at someone else"
        );

        // (2) DISCOVERY — the TARGET guard sees BOTH the directed job and the open one.
        let target_open = list_open_bookings(&pool, target, None, 200, 0)
            .await
            .expect("target open list");
        assert!(
            target_open.iter().any(|b| b.id == directed.id),
            "the target guard sees the job directed at them"
        );
        assert!(
            target_open.iter().any(|b| b.id == open.id),
            "the target guard also sees open jobs"
        );

        // (3) ACCEPT — a non-target guard is rejected with the typed 403.
        let err = transition(
            &pool,
            directed.id,
            other,
            false,
            BookingStatus::Accepted,
            Some(other),
            None,
            Uuid::new_v4(),
        )
        .await
        .expect_err("a non-target accept must be rejected");
        match err {
            AppError::ForbiddenCode { code, .. } => assert_eq!(code, "NOT_OFFERED_TO_YOU"),
            other => panic!("expected NOT_OFFERED_TO_YOU 403, got {other:?}"),
        }
        // ...and the booking is untouched — still requested, still unassigned.
        let still = get_booking_core(&pool, directed.id).await.expect("re-read");
        assert_eq!(still.status, BookingStatus::Requested);
        assert_eq!(still.guard_id, None, "the rejected accept assigned nobody");

        // (4a) ACCEPT — the TARGET guard claims the directed booking fine.
        let claimed = transition(
            &pool,
            directed.id,
            target,
            false,
            BookingStatus::Accepted,
            Some(target),
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("the target accepts fine");
        assert_eq!(claimed.status, "accepted");
        assert_eq!(claimed.guard_id, Some(target));

        // (4b) ACCEPT — the OPEN booking is claimable by ANY guard (here the non-target).
        let open_claimed = transition(
            &pool,
            open.id,
            other,
            false,
            BookingStatus::Accepted,
            Some(other),
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("any guard claims an open booking");
        assert_eq!(open_claimed.guard_id, Some(other));

        for id in [directed.id, open.id] {
            cleanup_booking(&pool, id).await;
        }
    }

    /// An admin may `/assign` ANY guard to a DIRECTED booking — the directed-offer gate is a
    /// guard-vs-guard rule, and support acting on behalf overrides it (is_admin bypass).
    /// DATABASE_URL-gated.
    #[tokio::test]
    async fn admin_assign_overrides_directed_offer() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer = Uuid::new_v4();
        let target = Uuid::new_v4();
        let someone_else = Uuid::new_v4();
        let admin = Uuid::new_v4();

        let directed = create_booking(
            &pool,
            customer,
            &CreateBookingRequest {
                address: "Admin Override Rd".to_string(),
                scheduled_at: Utc::now(),
                hours: 4,
                service_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
                target_guard_id: Some(target),
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("create directed");

        // Admin (is_admin = true) assigns a DIFFERENT guard than the target — allowed.
        let assigned = transition(
            &pool,
            directed.id,
            admin,
            true,
            BookingStatus::Accepted,
            Some(someone_else),
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("admin overrides the directed-offer gate");
        assert_eq!(assigned.guard_id, Some(someone_else));

        cleanup_booking(&pool, directed.id).await;
    }

    /// `start_job`'s three load-bearing guards, end-to-end against Postgres: (1) a second start
    /// is an idempotent no-op (work_started_at NOT re-stamped — the proration clock must not
    /// reset); (2) starting before `arrived` → Conflict; (3) a non-assigned guard → Forbidden
    /// (IDOR). DATABASE_URL-gated.
    #[tokio::test]
    async fn start_job_is_idempotent_state_guarded_and_owner_only() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let intruder = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        let created = create_booking(
            &pool,
            customer_id,
            &CreateBookingRequest {
                address: "3 Start Rd".to_string(),
                scheduled_at: Utc::now(),
                hours: 4,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");
        transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Accepted,
            Some(guard_id),
            None,
            correlation,
        )
        .await
        .expect("accept");

        // (2) start before arriving → Conflict (still only `accepted`).
        let too_early = start_job(&pool, created.id, guard_id, false, None, None)
            .await
            .expect_err("start before arrived must be rejected");
        assert!(
            matches!(too_early, AppError::Conflict(_)),
            "expected Conflict, got {too_early:?}"
        );

        // PRE-PAY gate: paid before en_route. advance to arrived
        mark_paid_now(&pool, created.id).await;
        for status in [BookingStatus::EnRoute, BookingStatus::Arrived] {
            transition(
                &pool,
                created.id,
                guard_id,
                false,
                status,
                None,
                None,
                correlation,
            )
            .await
            .unwrap_or_else(|e| panic!("transition to {status}: {e:?}"));
        }

        // (3) a non-assigned guard cannot start the job → Forbidden (IDOR).
        let intruder_err = start_job(&pool, created.id, intruder, false, None, None)
            .await
            .expect_err("non-assigned guard must not start the job");
        assert!(
            matches!(intruder_err, AppError::Forbidden(_)),
            "expected Forbidden, got {intruder_err:?}"
        );

        // first (real) start stamps work_started_at
        start_job(&pool, created.id, guard_id, false, None, None)
            .await
            .expect("first start");
        let first_ts: Option<chrono::DateTime<Utc>> =
            sqlx::query_scalar("SELECT work_started_at FROM booking.bookings WHERE id = $1")
                .bind(created.id)
                .fetch_one(&pool)
                .await
                .expect("read work_started_at");
        let first_ts = first_ts.expect("work_started_at stamped");

        // (1) a second start is idempotent: work_started_at UNCHANGED (the proration clock must
        // not reset — that would shrink actual_seconds and over-refund / overcharge).
        start_job(&pool, created.id, guard_id, false, None, None)
            .await
            .expect("second start (idempotent no-op)");
        let second_ts: Option<chrono::DateTime<Utc>> =
            sqlx::query_scalar("SELECT work_started_at FROM booking.bookings WHERE id = $1")
                .bind(created.id)
                .fetch_one(&pool)
                .await
                .expect("read work_started_at again");
        assert_eq!(
            Some(first_ts),
            second_ts,
            "second start must NOT re-stamp work_started_at"
        );

        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
    }

    /// G3: a start pressed before the booking's scheduled window opens (`scheduled_at − 15min`)
    /// is 409 `START_TOO_EARLY`; an admin bypasses the gate (support acts on behalf).
    /// DATABASE_URL-gated.
    #[tokio::test]
    async fn start_before_scheduled_window_is_too_early() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        // Scheduled well in the FUTURE (+2h) → now is far before the -15min grace boundary.
        let created = create_booking(
            &pool,
            customer_id,
            &CreateBookingRequest {
                address: "9 Early Rd".to_string(),
                scheduled_at: Utc::now() + chrono::Duration::hours(2),
                hours: 4,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");

        // Drive to `arrived` (accept → paid → en_route → arrived). None of these gate on time.
        transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Accepted,
            Some(guard_id),
            None,
            correlation,
        )
        .await
        .expect("accept");
        mark_paid_now(&pool, created.id).await;
        for status in [BookingStatus::EnRoute, BookingStatus::Arrived] {
            transition(
                &pool,
                created.id,
                guard_id,
                false,
                status,
                None,
                None,
                correlation,
            )
            .await
            .unwrap_or_else(|e| panic!("transition to {status}: {e:?}"));
        }

        // The assigned guard starting 2h early → 409 START_TOO_EARLY (before the geofence/GPS is
        // even consulted; a no-coords booking would otherwise skip the fence).
        let err = start_job(&pool, created.id, guard_id, false, None, None)
            .await
            .expect_err("start before scheduled window must be rejected");
        match err {
            AppError::ConflictCode { code, .. } => assert_eq!(
                code,
                crate::domain::scheduling::START_TOO_EARLY_CODE,
                "expected START_TOO_EARLY, got {code}"
            ),
            other => panic!("expected START_TOO_EARLY ConflictCode, got {other:?}"),
        }
        // work_started_at must NOT have been stamped by the rejected start.
        let ws: Option<chrono::DateTime<Utc>> =
            sqlx::query_scalar("SELECT work_started_at FROM booking.bookings WHERE id = $1")
                .bind(created.id)
                .fetch_one(&pool)
                .await
                .expect("read work_started_at");
        assert!(
            ws.is_none(),
            "rejected start must not stamp work_started_at"
        );

        // Admin bypasses the time gate (support acts on behalf) → start succeeds even 2h early.
        start_job(&pool, created.id, guard_id, true, None, None)
            .await
            .expect("admin start bypasses the time gate");
        let ws: Option<chrono::DateTime<Utc>> =
            sqlx::query_scalar("SELECT work_started_at FROM booking.bookings WHERE id = $1")
                .bind(created.id)
                .fetch_one(&pool)
                .await
                .expect("read work_started_at after admin start");
        assert!(ws.is_some(), "admin start must stamp work_started_at");

        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&pool)
            .await;
    }

    /// PRE-PAY gate: `accepted → en_route` is BLOCKED with a 409 `PAYMENT_REQUIRED` sub-code until
    /// the booking is paid (`paid_at` set); once paid, it succeeds. Everything after en_route is
    /// naturally gated (the state machine forbids skipping it), so this single point covers the
    /// gate. DATABASE_URL-gated.
    #[tokio::test]
    async fn en_route_requires_paid_at_else_payment_required_409() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let guard_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        let created = create_booking(
            &pool,
            customer_id,
            &booking_req("1 PrePay Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create");
        transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::Accepted,
            Some(guard_id),
            None,
            correlation,
        )
        .await
        .expect("accept");

        // UNPAID en_route → 409 with the PAYMENT_REQUIRED sub-code (machine-readable for the
        // mobile pay-step). The actor is the assigned guard, so this is NOT a 403 — the gate fires
        // after the ownership check, specifically for the missing payment.
        let blocked = transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::EnRoute,
            None,
            None,
            correlation,
        )
        .await
        .expect_err("en_route on an unpaid booking must be blocked");
        assert!(
            matches!(
                &blocked,
                AppError::ConflictCode { code, .. }
                    if *code == crate::domain::state::PAYMENT_REQUIRED_CODE
            ),
            "unpaid en_route must carry PAYMENT_REQUIRED, got {blocked:?}"
        );

        // No booking.guard_en_route event was enqueued for the blocked attempt (atomic rollback).
        let en_route_events: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM booking.outbox WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::BOOKING_GUARD_EN_ROUTE)
        .bind(created.id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count en_route events");
        assert_eq!(en_route_events, 0, "blocked en_route must enqueue no event");

        // Pay (the payment.completed consumer stamps paid_at in prod), then en_route succeeds.
        mark_paid_now(&pool, created.id).await;
        let en_route = transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::EnRoute,
            None,
            None,
            correlation,
        )
        .await
        .expect("en_route after payment");
        assert_eq!(en_route.status, "en_route");

        cleanup_booking(&pool, created.id).await;
    }

    /// The `payment.completed` consumer's repo half: `mark_paid_idempotent` stamps `paid_at` on
    /// the first delivery (claiming the event_id) and is a NO-OP on a redelivery (same event_id)
    /// AND on a different event for the same already-paid booking (the `paid_at IS NULL` guard
    /// preserves the first timestamp). DATABASE_URL-gated.
    #[tokio::test]
    async fn mark_paid_idempotent_stamps_once_and_dedupes() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let created = create_booking(
            &pool,
            customer_id,
            &booking_req("1 Paid Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("create");
        let pre: Option<DateTime<Utc>> =
            sqlx::query_scalar("SELECT paid_at FROM booking.bookings WHERE id = $1")
                .bind(created.id)
                .fetch_one(&pool)
                .await
                .expect("read paid_at");
        assert!(pre.is_none(), "sanity: a fresh booking starts unpaid");

        let event_id = Uuid::new_v4();
        // First delivery: claims the event + stamps paid_at.
        assert!(
            mark_paid_idempotent(&pool, event_id, topics::PAYMENT_COMPLETED, created.id)
                .await
                .expect("first mark_paid"),
            "first delivery newly claims the event"
        );
        let first_paid: Option<DateTime<Utc>> =
            sqlx::query_scalar("SELECT paid_at FROM booking.bookings WHERE id = $1")
                .bind(created.id)
                .fetch_one(&pool)
                .await
                .expect("read paid_at");
        let first_paid = first_paid.expect("paid_at stamped on first delivery");

        // Redelivery of the SAME event_id → no new claim, paid_at unchanged.
        assert!(
            !mark_paid_idempotent(&pool, event_id, topics::PAYMENT_COMPLETED, created.id)
                .await
                .expect("redelivery mark_paid"),
            "redelivery of the same event_id is a no-op"
        );

        // A DIFFERENT event_id for the already-paid booking still claims the new id, but the
        // `paid_at IS NULL` guard preserves the FIRST timestamp (first-write-wins).
        assert!(
            mark_paid_idempotent(&pool, Uuid::new_v4(), topics::PAYMENT_COMPLETED, created.id)
                .await
                .expect("second event mark_paid"),
        );
        let still_paid: Option<DateTime<Utc>> =
            sqlx::query_scalar("SELECT paid_at FROM booking.bookings WHERE id = $1")
                .bind(created.id)
                .fetch_one(&pool)
                .await
                .expect("read paid_at again");
        assert_eq!(
            Some(first_paid),
            still_paid,
            "paid_at must not be overwritten by a later payment.completed"
        );

        cleanup_booking(&pool, created.id).await;
    }

    /// The discovery active-assignment exclusion: `busy_guard_ids` returns exactly the guards
    /// holding a booking in accepted/en_route/arrived/pending_completion, and NEVER a guard whose
    /// only bookings are terminal (declined/cancelled/completed) or unassigned. Membership-only
    /// assertions (the shared DB runs other suites concurrently). DATABASE_URL-gated.
    #[tokio::test]
    async fn busy_guard_ids_returns_only_active_assignment_holders() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer = Uuid::new_v4();
        let busy_guard = Uuid::new_v4(); // holds an ACCEPTED booking → busy
        let free_guard = Uuid::new_v4(); // only a DECLINED booking → free
        let correlation = Uuid::new_v4();

        // busy_guard: accept (active assignment).
        let active = create_booking(
            &pool,
            customer,
            &booking_req("1 Busy Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create active");
        transition(
            &pool,
            active.id,
            busy_guard,
            false,
            BookingStatus::Accepted,
            Some(busy_guard),
            None,
            correlation,
        )
        .await
        .expect("busy_guard accepts");

        // free_guard: accept then DECLINE (withdraw) → terminal, not an active assignment.
        let withdrawn = create_booking(
            &pool,
            customer,
            &booking_req("2 Free Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create withdrawn");
        transition(
            &pool,
            withdrawn.id,
            free_guard,
            false,
            BookingStatus::Accepted,
            Some(free_guard),
            None,
            correlation,
        )
        .await
        .expect("free_guard accepts");
        transition(
            &pool,
            withdrawn.id,
            free_guard,
            false,
            BookingStatus::Declined,
            None,
            // A decline is a reason-bearing terminal — the repo now enforces the mandatory guard
            // reason the decline_booking handler always supplies (deep-review MED #5).
            Some(Cancellation {
                reason: "sick",
                note: None,
            }),
            correlation,
        )
        .await
        .expect("free_guard declines");

        let busy = busy_guard_ids(&pool).await.expect("busy_guard_ids");
        assert!(
            busy.contains(&busy_guard),
            "a guard with an accepted booking is busy"
        );
        assert!(
            !busy.contains(&free_guard),
            "a guard whose only booking is declined is NOT busy"
        );

        cleanup_booking(&pool, active.id).await;
        cleanup_booking(&pool, withdrawn.id).await;
    }

    /// Time-overlap busy: a guard with an accepted 4h job is busy for an OVERLAPPING window but free
    /// for a non-overlapping one — both via the discovery set and the per-booking accept gate.
    #[tokio::test]
    async fn overlap_busy_is_window_scoped_not_any_active_job() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        // A: guard accepts a [now, now+4h) job.
        let a = create_booking(
            &pool,
            customer,
            &booking_req("A Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create A");
        let a_start = a.scheduled_at;
        transition(
            &pool,
            a.id,
            guard,
            false,
            BookingStatus::Accepted,
            Some(guard),
            None,
            correlation,
        )
        .await
        .expect("guard accepts A");

        // B: an unassigned job in the SAME window → overlaps A.
        let b = create_booking(
            &pool,
            customer,
            &booking_req("B Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create B");
        // C: an unassigned job well AFTER A ends (now+1 day) → no overlap.
        let c = create_booking(
            &pool,
            customer,
            &booking_req("C Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create C");
        sqlx::query("UPDATE booking.bookings SET scheduled_at = $2 WHERE id = $1")
            .bind(c.id)
            .bind(a_start + chrono::Duration::days(1))
            .execute(&pool)
            .await
            .expect("push C a day out");

        // Accept gate: overlapping B is blocked, non-overlapping C is allowed.
        assert!(
            guard_has_overlapping_active_job(&pool, guard, b.id)
                .await
                .unwrap(),
            "accepting B (same window as A) must be blocked as overlapping"
        );
        assert!(
            !guard_has_overlapping_active_job(&pool, guard, c.id)
                .await
                .unwrap(),
            "accepting C (a day after A) must be allowed — non-overlapping"
        );

        // Discovery set: guard excluded for A's window, offered for C's.
        let busy_now = busy_guard_ids_overlapping(&pool, a_start, 4).await.unwrap();
        assert!(
            busy_now.contains(&guard),
            "guard is busy for the overlapping window"
        );
        let busy_later = busy_guard_ids_overlapping(&pool, a_start + chrono::Duration::days(1), 4)
            .await
            .unwrap();
        assert!(
            !busy_later.contains(&guard),
            "guard is free for a non-overlapping window"
        );

        cleanup_booking(&pool, a.id).await;
        cleanup_booking(&pool, b.id).await;
        cleanup_booking(&pool, c.id).await;
    }

    /// Regression for the heatmap-bucket rounding bug: `bucket = floor(hour / 2)` must use
    /// INTEGER (truncating) division, so the late-evening hours land in the LAST valid bucket
    /// (11), never a phantom bucket 12 that the contract / web-admin drop. Asserts the exact
    /// mapping at the boundary: hour 21 → 10, hour 22 → 11, hour 23 → 11. Uses a far-future,
    /// 1-day window so only the rows this test inserts fall inside it, and pins the session to
    /// UTC so `EXTRACT(hour ...)` reads the hour we stored (scheduled_at is TIMESTAMPTZ).
    /// DATABASE_URL-gated (hermetic SKIP otherwise).
    #[tokio::test]
    async fn utilization_bucket_uses_integer_truncating_division() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .after_connect(|conn, _| {
                Box::pin(async move {
                    // Pin EXTRACT(hour ...) to the stored UTC hour regardless of server tz.
                    sqlx::query("SET TIME ZONE 'UTC'").execute(conn).await?;
                    Ok(())
                })
            })
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();
        // A far-future Monday (2099-01-05 is a Monday), one row per boundary hour.
        let day = "2099-01-05T00:00:00Z"
            .parse::<DateTime<Utc>>()
            .expect("parse anchor day");
        let cases = [(21, 10_i32), (22, 11_i32), (23, 11_i32)];
        let mut ids = Vec::new();
        for (hour, _expected) in cases {
            let scheduled_at = day + chrono::Duration::hours(hour) + chrono::Duration::minutes(30);
            let created = create_booking(
                &pool,
                customer_id,
                &CreateBookingRequest {
                    address: format!("{hour}:30 Heatmap Rd"),
                    scheduled_at,
                    hours: 1,
                    service_id: None,
                    target_guard_id: None,
                    guard_count: None,
                    tip: None,
                    lat: None,
                    lng: None,
                },
                1,
                rust_decimal::Decimal::ZERO,
                None,
                correlation,
            )
            .await
            .expect("create");
            ids.push(created.id);
        }

        // Window: the whole far-future day. Only this test's rows fall inside it.
        let from = day;
        let to = day + chrono::Duration::days(1);
        let cells = utilization(&pool, from, to).await.expect("utilization");

        // dow of 2099-01-05 (Monday) is 1 in Postgres EXTRACT(dow ...).
        for (hour, expected_bucket) in cases {
            let cell = cells
                .iter()
                .find(|c| c.dow == 1 && c.bucket == expected_bucket)
                .unwrap_or_else(|| {
                    panic!("hour {hour} must map to bucket {expected_bucket}; got {cells:?}")
                });
            assert!(
                cell.bucket <= 11,
                "bucket must stay within the contract range 0..=11, got {}",
                cell.bucket
            );
        }
        // No phantom bucket 12 (the bug pushed hours 22-23 there).
        assert!(
            !cells.iter().any(|c| c.bucket >= 12),
            "no row may land in a bucket >= 12; got {cells:?}"
        );

        for id in ids {
            cleanup_booking(&pool, id).await;
        }
    }

    // ----- Service catalog → charge-path wiring (real DB; hermetic SKIP otherwise) -----

    /// Seed a catalog service with the given fee/min_hours (and 0/0 money knobs — the tests that
    /// care about those set them explicitly); the name carries a unique marker so the assertions
    /// can isolate this test's rows from any pre-existing catalog data.
    async fn seed_service(
        pool: &sqlx::PgPool,
        marker: &str,
        base_fee: &str,
        min_hours: i32,
    ) -> ServiceCatalogItem {
        let req = CreateServiceRequest {
            name_th: format!("th-{marker}"),
            name_en: format!("en-{marker}"),
            base_fee: base_fee.parse().expect("parse fee"),
            min_hours,
            commission_percent: rust_decimal::Decimal::ZERO,
            cancellation_fee: rust_decimal::Decimal::ZERO,
            notes: None,
        };
        create_service(pool, &req).await.expect("seed service")
    }

    async fn cleanup_service(pool: &sqlx::PgPool, id: Uuid) {
        let _ = sqlx::query("DELETE FROM booking.service_catalog WHERE id = $1")
            .bind(id)
            .execute(pool)
            .await;
    }

    /// `list_active_services` returns ACTIVE catalog services only (a deactivated one is
    /// excluded) and `get_active_service` resolves an active id but returns `None` for an
    /// inactive one. DATABASE_URL-gated.
    #[tokio::test]
    async fn list_active_services_excludes_inactive() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let marker = Uuid::new_v4().to_string();
        let active = seed_service(&pool, &marker, "230.00", 2).await;
        let inactive = seed_service(&pool, &marker, "999.00", 1).await;
        deactivate_service(&pool, inactive.id)
            .await
            .expect("deactivate");

        let items = list_active_services(&pool)
            .await
            .expect("list active services");
        // Only this test's rows (isolated by the unique marker).
        let mine: Vec<_> = items
            .iter()
            .filter(|s| s.name_en == format!("en-{marker}"))
            .collect();
        assert_eq!(mine.len(), 1, "exactly one ACTIVE service for this marker");
        assert_eq!(mine[0].id, active.id, "the active one, not the deactivated");
        assert_eq!(mine[0].base_fee, active.base_fee);
        assert_eq!(mine[0].min_hours, 2);

        // get_active_service: active id resolves, inactive id is None.
        assert_eq!(
            get_active_service(&pool, active.id)
                .await
                .expect("lookup active")
                .map(|s| s.id),
            Some(active.id)
        );
        assert!(
            get_active_service(&pool, inactive.id)
                .await
                .expect("lookup inactive")
                .is_none(),
            "a deactivated service must not resolve for the charge path"
        );
        // An unknown id is also None.
        assert!(get_active_service(&pool, Uuid::new_v4())
            .await
            .expect("lookup unknown")
            .is_none());

        cleanup_service(&pool, active.id).await;
        cleanup_service(&pool, inactive.id).await;
    }

    /// The charge-path wiring: `create_booking` with a [`PricingSnapshot`] (the catalog row)
    /// persists THAT rate, while `None` falls to the server-owned column DEFAULT (back-compat).
    /// Both branches also SNAPSHOT `commission_percent` + `cancellation_fee` onto the booking —
    /// the catalog's values, or a real 0/0 when no service was chosen (never NULL, which is
    /// reserved for pre-migration-0010 rows). DATABASE_URL-gated.
    #[tokio::test]
    async fn create_booking_uses_catalog_base_fee_else_default() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let customer_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();
        let catalog_fee: rust_decimal::Decimal = "230.00".parse().unwrap();
        let commission: rust_decimal::Decimal = "12.50".parse().unwrap();
        let cancel_fee: rust_decimal::Decimal = "150.00".parse().unwrap();

        // With a catalog snapshot → the booking carries the catalog rate AND its money knobs.
        let priced = create_booking(
            &pool,
            customer_id,
            &booking_req("1 Catalog Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            Some(PricingSnapshot {
                base_fee: catalog_fee,
                commission_percent: commission,
                cancellation_fee: cancel_fee,
            }),
            correlation,
        )
        .await
        .expect("create with catalog fee");
        assert_eq!(
            priced.base_fee, catalog_fee,
            "the booking's base_fee is the catalog rate, not the column default"
        );
        assert_eq!(
            priced.commission_percent,
            Some(commission),
            "the catalog's commission is snapshot onto the booking"
        );
        assert_eq!(
            priced.cancellation_fee,
            Some(cancel_fee),
            "the catalog's cancellation fee is snapshot onto the booking"
        );

        // Without a snapshot → the server-owned column DEFAULT (migration 0002 = 500.00), and
        // the money knobs are a real 0/0 ("no cut, no fee"), NOT NULL.
        let defaulted = create_booking(
            &pool,
            customer_id,
            &booking_req("2 Default Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
            correlation,
        )
        .await
        .expect("create without fee");
        assert_eq!(
            defaulted.base_fee,
            "500.00".parse::<rust_decimal::Decimal>().unwrap(),
            "no service → the server-owned base_fee column DEFAULT (back-compat)"
        );
        assert_eq!(
            defaulted.commission_percent,
            Some(rust_decimal::Decimal::ZERO),
            "no service → a real 0 commission, not NULL"
        );
        assert_eq!(
            defaulted.cancellation_fee,
            Some(rust_decimal::Decimal::ZERO),
            "no service → a real 0 cancellation fee, not NULL"
        );

        // The internal read (what payment sees over service-JWT) carries the same snapshot.
        let internal = get_internal(&pool, priced.id)
            .await
            .expect("internal read of the priced booking");
        assert_eq!(
            (internal.commission_percent, internal.cancellation_fee),
            (Some(commission), Some(cancel_fee)),
            "payment reads the booking's OWN snapshot, not today's catalog"
        );

        cleanup_booking(&pool, priced.id).await;
        cleanup_booking(&pool, defaulted.id).await;
    }

    /// The snapshot's REASON: an admin editing the catalog after the fact must not restate the
    /// money of a booking already made. Create a booking from a service, then raise both knobs
    /// on that same service — the booking's copies are unmoved, while a booking created AFTER
    /// the edit picks up the new terms. DATABASE_URL-gated.
    #[tokio::test]
    async fn editing_the_catalog_does_not_restate_an_existing_booking() {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .expect("connect real Postgres");

        let marker = Uuid::new_v4().to_string();
        let service = create_service(
            &pool,
            &CreateServiceRequest {
                name_th: format!("th-{marker}"),
                name_en: format!("en-{marker}"),
                base_fee: "230.00".parse().unwrap(),
                min_hours: 1,
                commission_percent: "10.00".parse().unwrap(),
                cancellation_fee: "150.00".parse().unwrap(),
                notes: None,
            },
        )
        .await
        .expect("seed service with money knobs");

        let snapshot_of = |s: &ServiceCatalogItem| PricingSnapshot {
            base_fee: s.base_fee,
            commission_percent: s.commission_percent,
            cancellation_fee: s.cancellation_fee,
        };

        let customer_id = Uuid::new_v4();
        let before = create_booking(
            &pool,
            customer_id,
            &booking_req("1 Old Terms Rd", 2, None),
            1,
            rust_decimal::Decimal::ZERO,
            Some(snapshot_of(&service)),
            Uuid::new_v4(),
        )
        .await
        .expect("book under the old terms");

        // The admin doubles the cut and the fee.
        let edited = update_service(
            &pool,
            service.id,
            &UpdateServiceRequest {
                name_th: format!("th-{marker}"),
                name_en: format!("en-{marker}"),
                base_fee: "230.00".parse().unwrap(),
                min_hours: 1,
                commission_percent: "20.00".parse().unwrap(),
                cancellation_fee: "300.00".parse().unwrap(),
                notes: None,
            },
        )
        .await
        .expect("edit the catalog");
        assert_eq!(edited.commission_percent, "20.00".parse().unwrap());
        assert_eq!(edited.cancellation_fee, "300.00".parse().unwrap());

        // The already-made booking is untouched — re-read from the DB, not from the handle.
        let reread = get_booking(&pool, before.id).await.expect("re-read");
        assert_eq!(
            reread.commission_percent,
            Some("10.00".parse().unwrap()),
            "the guard's cut is the one agreed when the job was booked"
        );
        assert_eq!(
            reread.cancellation_fee,
            Some("150.00".parse().unwrap()),
            "the customer's cancellation exposure is the one quoted at booking"
        );

        // A booking made AFTER the edit does get the new terms.
        let after = create_booking(
            &pool,
            customer_id,
            &booking_req("2 New Terms Rd", 2, None),
            1,
            rust_decimal::Decimal::ZERO,
            Some(snapshot_of(&edited)),
            Uuid::new_v4(),
        )
        .await
        .expect("book under the new terms");
        assert_eq!(after.commission_percent, Some("20.00".parse().unwrap()));
        assert_eq!(after.cancellation_fee, Some("300.00".parse().unwrap()));

        cleanup_booking(&pool, before.id).await;
        cleanup_booking(&pool, after.id).await;
        cleanup_service(&pool, service.id).await;
    }
}
