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

use crate::domain::state::{required_actor, BookingStatus, RequiredActor};
use crate::domain::{event_for_status, CompletionInfo, EventMapping};
use crate::models::{BookingResponse, CreateBookingRequest, InternalBooking};

const BOOKING_COLUMNS: &str = "id, customer_id, guard_id, status::text AS status, address, \
     scheduled_at, hours, base_fee, guard_count, tip, created_at, updated_at";

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

// ----- Writes -----

/// Insert a new booking in `requested` status. No event is emitted for a bare request.
///
/// `guard_count`/`tip` come from the request (defaulted by the handler); `base_fee` is NOT
/// set here — it falls to the server-owned column DEFAULT so the client can never set the
/// rate (CLAUDE.md money rules: authoritative pricing inputs are server-owned).
pub async fn create_booking(
    db: &sqlx::PgPool,
    customer_id: Uuid,
    req: &CreateBookingRequest,
    guard_count: i32,
    tip: rust_decimal::Decimal,
) -> Result<BookingResponse, AppError> {
    let sql = format!(
        r#"
        INSERT INTO booking.bookings (customer_id, status, address, scheduled_at, hours, guard_count, tip)
        VALUES ($1, 'requested'::booking.booking_status, $2, $3, $4, $5, $6)
        RETURNING {BOOKING_COLUMNS}
        "#
    );
    sqlx::query_as::<_, BookingResponse>(&sql)
        .bind(customer_id)
        .bind(&req.address)
        .bind(req.scheduled_at)
        .bind(req.hours)
        .bind(guard_count)
        .bind(tip)
        .fetch_one(db)
        .await
        .map_err(AppError::from)
}

/// A booking's locked current state for a transition decision.
struct LockedBooking {
    status: BookingStatus,
    customer_id: Uuid,
    guard_id: Option<Uuid>,
    hours: i32,
    /// When the guard STARTED work (set by `start_job`); the proration basis. `None` until then.
    work_started_at: Option<DateTime<Utc>>,
}

/// Raw row shape returned by [`locked_current`]'s query: status text, customer, guard,
/// booked hours, work-start clock. Aliased to keep the query type readable (clippy
/// `type_complexity`).
type LockedRow = (String, Uuid, Option<Uuid>, i32, Option<DateTime<Utc>>);

/// Read a booking's current status + ids + proration inputs inside a transaction
/// (row-locked) so a transition validates against state that cannot change underneath it.
async fn locked_current(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    id: Uuid,
) -> Result<LockedBooking, AppError> {
    let row: Option<LockedRow> = sqlx::query_as(
        "SELECT status::text, customer_id, guard_id, hours, work_started_at \
         FROM booking.bookings WHERE id = $1 FOR UPDATE",
    )
    .bind(id)
    .fetch_optional(&mut **tx)
    .await?;

    let (status_str, customer_id, guard_id, hours, work_started_at) =
        row.ok_or_else(|| AppError::NotFound("Booking not found".to_string()))?;
    let status = status_str
        .parse::<BookingStatus>()
        .map_err(AppError::Internal)?;
    Ok(LockedBooking {
        status,
        customer_id,
        guard_id,
        hours,
        work_started_at,
    })
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

    let LockedBooking {
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
    let LockedBooking {
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

/// Fetch up to `limit` unpublished outbox rows, oldest first.
pub async fn fetch_unpublished(db: &sqlx::PgPool, limit: i64) -> Result<Vec<OutboxRow>, AppError> {
    let rows = sqlx::query_as::<_, OutboxRow>(
        r#"
        SELECT id, topic, payload
        FROM booking.outbox
        WHERE published_at IS NULL
        ORDER BY created_at
        LIMIT $1
        "#,
    )
    .bind(limit)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Stamp one outbox row published (called only after a successful NATS publish).
pub async fn mark_published(db: &sqlx::PgPool, id: Uuid) -> Result<(), AppError> {
    sqlx::query("UPDATE booking.outbox SET published_at = now() WHERE id = $1")
        .bind(id)
        .execute(db)
        .await?;
    Ok(())
}

#[cfg(test)]
mod db_tests {
    use super::*;
    use chrono::Utc;
    use shared_events::topics;
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;

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
                guard_count: None,
                tip: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
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
                guard_count: None,
                tip: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
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
                guard_count: None,
                tip: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
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
                guard_count: None,
                tip: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
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
                guard_count: None,
                tip: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
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
                guard_count: None,
                tip: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
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
                guard_count: None,
                tip: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
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
}
