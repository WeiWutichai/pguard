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

use crate::domain::progress::GeoFilter;
use crate::domain::state::{required_actor, BookingStatus, RequiredActor};
use crate::domain::{event_for_progress_report, event_for_status, CompletionInfo, EventMapping};
use crate::models::{
    BookingResponse, CreateBookingRequest, CreateServiceRequest, CustomerBookingStat, DailyCount,
    InternalBooking, NewProgressReport, ProgressReportRow, PublicServiceItem, ServiceCatalogItem,
    UpdateServiceRequest, UtilizationCell,
};

const BOOKING_COLUMNS: &str = "id, customer_id, guard_id, status::text AS status, address, \
     scheduled_at, hours, base_fee, guard_count, tip, lat, lng, created_at, updated_at";

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
/// — the fields the payment service verifies a charge against. No `SELECT *` (CLAUDE.md
/// "Data"): the projection is explicit and narrow.
pub async fn get_internal(db: &sqlx::PgPool, id: Uuid) -> Result<InternalBooking, AppError> {
    sqlx::query_as::<_, InternalBooking>(
        "SELECT id, customer_id, guard_id, status::text AS status, hours, \
                base_fee, guard_count, tip \
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

// ----- Service catalog (admin pricing; standalone — not read by the charge path) -----

const SERVICE_COLUMNS: &str =
    "id, name_th, name_en, base_fee, min_hours, notes, is_active, created_at, updated_at";

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
/// [`PublicServiceItem`] (no `notes`/`is_active`/timestamps). Mirrors [`list_services`] but
/// filters `is_active = true`; covered by `idx_service_catalog_active`.
pub async fn list_active_services(db: &sqlx::PgPool) -> Result<Vec<PublicServiceItem>, AppError> {
    let rows = sqlx::query_as::<_, PublicServiceItem>(
        "SELECT id, name_th, name_en, base_fee, min_hours FROM booking.service_catalog \
         WHERE is_active = true ORDER BY created_at DESC LIMIT 200",
    )
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Look up one ACTIVE catalog service by id (the charge-path resolution). Returns the full
/// [`ServiceCatalogItem`] so the handler can read its authoritative `base_fee` + `min_hours`.
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

/// Insert a new catalog service. Fields are validated by the handler before this call.
pub async fn create_service(
    db: &sqlx::PgPool,
    req: &CreateServiceRequest,
) -> Result<ServiceCatalogItem, AppError> {
    let sql = format!(
        "INSERT INTO booking.service_catalog (name_th, name_en, base_fee, min_hours, notes) \
         VALUES ($1, $2, $3, $4, $5) RETURNING {SERVICE_COLUMNS}"
    );
    let row = sqlx::query_as::<_, ServiceCatalogItem>(&sql)
        .bind(&req.name_th)
        .bind(&req.name_en)
        .bind(req.base_fee)
        .bind(req.min_hours)
        .bind(req.notes.as_deref())
        .fetch_one(db)
        .await?;
    Ok(row)
}

/// Replace the editable fields of a catalog service. 404 if it does not exist.
pub async fn update_service(
    db: &sqlx::PgPool,
    id: Uuid,
    req: &UpdateServiceRequest,
) -> Result<ServiceCatalogItem, AppError> {
    let sql = format!(
        "UPDATE booking.service_catalog \
         SET name_th = $2, name_en = $3, base_fee = $4, min_hours = $5, notes = $6, updated_at = now() \
         WHERE id = $1 RETURNING {SERVICE_COLUMNS}"
    );
    sqlx::query_as::<_, ServiceCatalogItem>(&sql)
        .bind(id)
        .bind(&req.name_th)
        .bind(&req.name_en)
        .bind(req.base_fee)
        .bind(req.min_hours)
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

/// Insert a new booking in `requested` status. No event is emitted for a bare request.
///
/// `guard_count`/`tip` come from the request (defaulted by the handler). `base_fee` is ALWAYS
/// server-resolved (the client never sends it — CLAUDE.md money rules): `Some(fee)` when the
/// handler picked a catalog service (the catalog's authoritative rate), or `None` to fall to
/// the server-owned column DEFAULT (the back-compat path, no service chosen). Either way the
/// rate is server-owned, so the customer can never undercut the price.
pub async fn create_booking(
    db: &sqlx::PgPool,
    customer_id: Uuid,
    req: &CreateBookingRequest,
    guard_count: i32,
    tip: rust_decimal::Decimal,
    base_fee: Option<rust_decimal::Decimal>,
) -> Result<BookingResponse, AppError> {
    // `base_fee` is bound when a catalog service was picked; otherwise the column is omitted so
    // its server-owned DEFAULT applies (COALESCE($n, DEFAULT) is not valid, so branch the SQL).
    let sql = if base_fee.is_some() {
        format!(
            r#"
            INSERT INTO booking.bookings (customer_id, status, address, scheduled_at, hours, guard_count, tip, lat, lng, base_fee)
            VALUES ($1, 'requested'::booking.booking_status, $2, $3, $4, $5, $6, $7, $8, $9)
            RETURNING {BOOKING_COLUMNS}
            "#
        )
    } else {
        format!(
            r#"
            INSERT INTO booking.bookings (customer_id, status, address, scheduled_at, hours, guard_count, tip, lat, lng)
            VALUES ($1, 'requested'::booking.booking_status, $2, $3, $4, $5, $6, $7, $8)
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
        .bind(req.lng);
    if let Some(fee) = base_fee {
        query = query.bind(fee);
    }
    query.fetch_one(db).await.map_err(AppError::from)
}

/// A booking's authoritative decision inputs: status + participant ids + proration clock.
/// Read row-locked inside transactions ([`locked_current`]) and plain for handler
/// pre-flight checks ([`get_booking_core`]).
pub struct BookingCore {
    pub status: BookingStatus,
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub hours: i32,
    /// When the guard STARTED work (set by `start_job`); the proration basis. `None` until then.
    pub work_started_at: Option<DateTime<Utc>>,
}

/// Raw row shape returned by the core queries: status text, customer, guard, booked hours,
/// work-start clock. Aliased to keep the query type readable (clippy `type_complexity`).
type CoreRow = (String, Uuid, Option<Uuid>, i32, Option<DateTime<Utc>>);

const CORE_QUERY: &str = "SELECT status::text, customer_id, guard_id, hours, work_started_at \
     FROM booking.bookings WHERE id = $1";

fn core_from_row(row: Option<CoreRow>) -> Result<BookingCore, AppError> {
    let (status_str, customer_id, guard_id, hours, work_started_at) =
        row.ok_or_else(|| AppError::NotFound("Booking not found".to_string()))?;
    let status = status_str
        .parse::<BookingStatus>()
        .map_err(AppError::Internal)?;
    Ok(BookingCore {
        status,
        customer_id,
        guard_id,
        hours,
        work_started_at,
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
#[tracing::instrument(skip(db), fields(booking_id = %id, new_status = %new_status))]
pub async fn transition(
    db: &sqlx::PgPool,
    id: Uuid,
    actor: Uuid,
    is_admin: bool,
    new_status: BookingStatus,
    assign_guard: Option<Uuid>,
    correlation_id: Uuid,
) -> Result<BookingResponse, AppError> {
    let mut tx = db.begin().await?;

    let BookingCore {
        status: current,
        customer_id,
        guard_id: existing_guard,
        hours,
        work_started_at,
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
            if existing_guard.is_some() {
                tx.rollback().await?;
                return Err(AppError::Conflict(
                    "Booking already has an assigned guard".to_string(),
                ));
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

    // Completing (the guard's request) requires the job to have been STARTED — otherwise there
    // is no factual basis for the worked-hours proration the completion event carries.
    if new_status == BookingStatus::PendingCompletion && work_started_at.is_none() {
        tx.rollback().await?;
        return Err(AppError::Conflict(
            "Job has not been started; cannot request completion".to_string(),
        ));
    }

    let guard_id = assign_guard.or(existing_guard);

    // 1) the business change. `work_started_at` is owned by `start_job`, never touched here.
    let sql = format!(
        r#"
        UPDATE booking.bookings
        SET status = $2::booking.booking_status,
            guard_id = COALESCE($3, guard_id),
            updated_at = now()
        WHERE id = $1
        RETURNING {BOOKING_COLUMNS}
        "#
    );
    let updated = sqlx::query_as::<_, BookingResponse>(&sql)
        .bind(id)
        .bind(new_status.as_db_str())
        .bind(assign_guard)
        .fetch_one(&mut *tx)
        .await?;

    // On completion, compute the worked duration (now − work_started_at) so the event
    // carries the proration inputs. `None` work_started_at → `None` actual_seconds (payment
    // keeps the full charge; mirrors v1's "missing timestamps → skip proration").
    let completion = if new_status == BookingStatus::Completed {
        let actual_seconds = work_started_at.map(|started| (Utc::now() - started).num_seconds());
        Some(CompletionInfo {
            booked_hours: hours,
            actual_seconds,
            // Carry booking's server-owned pricing so the post-pay consumer bills self-contained.
            base_fee: updated.base_fee,
            guard_count: updated.guard_count,
            tip: updated.tip,
        })
    } else {
        None
    };

    // 2) the event — same transaction (transactional outbox). The mapping depends on the WHOLE
    // transition (`current → new_status`): e.g. the completion-reject bounce to `arrived` emits
    // nothing, unlike a fresh arrival.
    if let Some(EventMapping { topic, payload }) =
        event_for_status(current, new_status, id, customer_id, guard_id, completion)
    {
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
#[tracing::instrument(skip(db), fields(booking_id = %id))]
pub async fn start_job(
    db: &sqlx::PgPool,
    id: Uuid,
    actor: Uuid,
    is_admin: bool,
) -> Result<BookingResponse, AppError> {
    let mut tx = db.begin().await?;
    let BookingCore {
        status,
        guard_id: existing_guard,
        work_started_at,
        ..
    } = locked_current(&mut tx, id).await?;

    if !is_admin && existing_guard != Some(actor) {
        tx.rollback().await?;
        return Err(AppError::Forbidden(
            "Only the assigned guard can start this job".to_string(),
        ));
    }
    if status != BookingStatus::Arrived {
        tx.rollback().await?;
        return Err(AppError::Conflict(
            "Can only start a job after arriving at the location".to_string(),
        ));
    }
    // Idempotent: already started → return the current row unchanged.
    if work_started_at.is_some() {
        tx.rollback().await?;
        return get_booking(db, id).await;
    }

    let sql = format!(
        "UPDATE booking.bookings SET work_started_at = now(), updated_at = now() \
         WHERE id = $1 RETURNING {BOOKING_COLUMNS}"
    );
    let updated = sqlx::query_as::<_, BookingResponse>(&sql)
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
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
    geo: Option<GeoFilter>,
    limit: i64,
    offset: i64,
) -> Result<Vec<BookingResponse>, AppError> {
    let rows = match geo {
        None => {
            let sql = format!(
                r#"
                SELECT {BOOKING_COLUMNS}
                FROM booking.bookings
                WHERE status = 'requested'::booking.booking_status AND guard_id IS NULL
                ORDER BY created_at DESC
                LIMIT $1 OFFSET $2
                "#
            );
            sqlx::query_as::<_, BookingResponse>(&sql)
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
                SELECT id, customer_id, guard_id, status, address, scheduled_at, hours,
                       base_fee, guard_count, tip, lat, lng, created_at, updated_at
                FROM (
                    SELECT {BOOKING_COLUMNS},
                           2 * 6371 * asin(least(1, sqrt(
                               power(sin(radians(lat - $1) / 2), 2)
                               + cos(radians($1)) * cos(radians(lat))
                                 * power(sin(radians(lng - $2) / 2), 2)
                           ))) AS distance_km
                    FROM booking.bookings
                    WHERE status = 'requested'::booking.booking_status
                      AND guard_id IS NULL
                      AND lat IS NOT NULL AND lng IS NOT NULL
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
                .fetch_all(db)
                .await?
        }
    };
    Ok(rows)
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
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
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
            correlation,
        )
        .await
        .expect("accept");
        assert_eq!(accepted.status, "accepted");
        assert_eq!(accepted.guard_id, Some(guard_id));

        // exactly one outbox row for this booking, carrying a valid envelope
        let rows: Vec<OutboxRow> = sqlx::query_as(
            "SELECT id, topic, payload FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1",
        )
        .bind(created.id.to_string())
        .fetch_all(&pool)
        .await
        .expect("query outbox");
        assert_eq!(rows.len(), 1, "exactly one event enqueued for accept");
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
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
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

        let rows: Vec<OutboxRow> = sqlx::query_as(
            "SELECT id, topic, payload FROM booking.outbox WHERE payload->'payload'->>'booking_id' = $1",
        )
        .bind(created.id.to_string())
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
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
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
            correlation,
        )
        .await
        .expect_err("non-assigned guard must be rejected");
        assert!(
            matches!(err, AppError::Forbidden(_)),
            "expected Forbidden, got {err:?}"
        );

        // The owner can.
        transition(
            &pool,
            created.id,
            owner,
            false,
            BookingStatus::EnRoute,
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
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
        )
        .await
        .expect("create");

        // Guard drives accept → en_route → arrived (work_started_at NOT set yet).
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
            correlation,
        )
        .await
        .expect_err("complete before start must be rejected");
        assert!(matches!(not_started, AppError::Conflict(_)));

        // start (stamps work_started_at, stays arrived) → complete (pending_completion).
        start_job(&pool, created.id, guard_id, false)
            .await
            .expect("start");
        let work_started: Option<chrono::DateTime<Utc>> =
            sqlx::query_scalar("SELECT work_started_at FROM booking.bookings WHERE id = $1")
                .bind(created.id)
                .fetch_one(&pool)
                .await
                .expect("read work_started_at");
        assert!(work_started.is_some(), "work_started_at stamped by start");

        let pending = transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::PendingCompletion,
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
            correlation,
        )
        .await
        .expect("customer approve → completed");
        assert_eq!(completed.status, "completed");

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

    /// Cancellation is the request OWNER's move: a non-owner (here the assigned guard) is
    /// rejected with Forbidden, while the customer succeeds and enqueues exactly one
    /// `booking.cancelled` event. DATABASE_URL-gated (hermetic when unset).
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
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
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
            correlation,
        )
        .await
        .expect_err("a guard cannot cancel the customer's booking");
        assert!(
            matches!(err, AppError::Forbidden(_)),
            "expected Forbidden, got {err:?}"
        );

        // The customer can cancel a PRE-ARRIVAL booking → cancelled.
        let cancelled = transition(
            &pool,
            created.id,
            customer_id,
            false,
            BookingStatus::Cancelled,
            None,
            correlation,
        )
        .await
        .expect("customer cancel");
        assert_eq!(cancelled.status, "cancelled");

        // Exactly one booking.cancelled event enqueued.
        let cancelled_events: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM booking.outbox WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::BOOKING_CANCELLED)
        .bind(created.id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count cancelled events");
        assert_eq!(cancelled_events, 1, "exactly one booking.cancelled emitted");

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
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
        )
        .await
        .expect("create");

        // Drive to pending_completion: accept → en_route → arrived → start → complete.
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
                correlation,
            )
            .await
            .unwrap_or_else(|e| panic!("transition to {status}: {e:?}"));
        }
        start_job(&pool, created.id, guard_id, false)
            .await
            .expect("start");
        transition(
            &pool,
            created.id,
            guard_id,
            false,
            BookingStatus::PendingCompletion,
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

        // The reject bounce (pending_completion → arrived) must NOT re-fire booking.arrived:
        // exactly ONE arrived event exists — the original fresh arrival (en_route → arrived).
        let arrived_events: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM booking.outbox WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::BOOKING_ARRIVED)
        .bind(created.id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count arrived events");
        assert_eq!(
            arrived_events, 1,
            "only the fresh arrival emits; the reject bounce must add no booking.arrived"
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
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
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
        )
        .await
        .expect("create");
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
                correlation,
            )
            .await
            .unwrap_or_else(|e| panic!("transition to {status}: {e:?}"));
        }
        start_job(pool, created.id, guard_id, false)
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
        )
        .await
        .expect("create far");

        // Plain list (no geo): open jobs include A and B, never the accepted C.
        let open = list_open_bookings(&pool, None, 200, 0)
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

        for id in [near.id, no_coords.id, taken.id, far.id] {
            cleanup_booking(&pool, id).await;
        }
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
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
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
            correlation,
        )
        .await
        .expect("accept");

        // (2) start before arriving → Conflict (still only `accepted`).
        let too_early = start_job(&pool, created.id, guard_id, false)
            .await
            .expect_err("start before arrived must be rejected");
        assert!(
            matches!(too_early, AppError::Conflict(_)),
            "expected Conflict, got {too_early:?}"
        );

        // advance to arrived
        for status in [BookingStatus::EnRoute, BookingStatus::Arrived] {
            transition(
                &pool,
                created.id,
                guard_id,
                false,
                status,
                None,
                correlation,
            )
            .await
            .unwrap_or_else(|e| panic!("transition to {status}: {e:?}"));
        }

        // (3) a non-assigned guard cannot start the job → Forbidden (IDOR).
        let intruder_err = start_job(&pool, created.id, intruder, false)
            .await
            .expect_err("non-assigned guard must not start the job");
        assert!(
            matches!(intruder_err, AppError::Forbidden(_)),
            "expected Forbidden, got {intruder_err:?}"
        );

        // first (real) start stamps work_started_at
        start_job(&pool, created.id, guard_id, false)
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
        start_job(&pool, created.id, guard_id, false)
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
                    guard_count: None,
                    tip: None,
                    lat: None,
                    lng: None,
                },
                1,
                rust_decimal::Decimal::ZERO,
                None,
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

    /// Seed a catalog service with the given fee/min_hours; the name carries a unique marker so
    /// the assertions can isolate this test's rows from any pre-existing catalog data.
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

    /// The charge-path wiring: `create_booking` with `Some(base_fee)` (the catalog rate)
    /// persists THAT rate, while `None` falls to the server-owned column DEFAULT (back-compat).
    /// DATABASE_URL-gated.
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
        let catalog_fee: rust_decimal::Decimal = "230.00".parse().unwrap();

        // With a catalog fee → the booking carries the catalog rate.
        let priced = create_booking(
            &pool,
            customer_id,
            &booking_req("1 Catalog Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            Some(catalog_fee),
        )
        .await
        .expect("create with catalog fee");
        assert_eq!(
            priced.base_fee, catalog_fee,
            "the booking's base_fee is the catalog rate, not the column default"
        );

        // Without a fee → the server-owned column DEFAULT (migration 0002 = 500.00).
        let defaulted = create_booking(
            &pool,
            customer_id,
            &booking_req("2 Default Rd", 4, None),
            1,
            rust_decimal::Decimal::ZERO,
            None,
        )
        .await
        .expect("create without fee");
        assert_eq!(
            defaulted.base_fee,
            "500.00".parse::<rust_decimal::Decimal>().unwrap(),
            "no service → the server-owned base_fee column DEFAULT (back-compat)"
        );

        cleanup_booking(&pool, priced.id).await;
        cleanup_booking(&pool, defaulted.id).await;
    }
}
