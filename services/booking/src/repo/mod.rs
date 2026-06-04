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

use serde_json::Value;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::EventEnvelope;

use crate::domain::state::{can_transition, BookingStatus};
use crate::domain::{event_for_status, EventMapping};
use crate::models::{BookingResponse, CreateBookingRequest, InternalBooking};

const BOOKING_COLUMNS: &str = "id, customer_id, guard_id, status::text AS status, address, scheduled_at, hours, created_at, updated_at";

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
        "SELECT id, customer_id, guard_id, status::text AS status, hours \
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
pub async fn create_booking(
    db: &sqlx::PgPool,
    customer_id: Uuid,
    req: &CreateBookingRequest,
) -> Result<BookingResponse, AppError> {
    let sql = format!(
        r#"
        INSERT INTO booking.bookings (customer_id, status, address, scheduled_at, hours)
        VALUES ($1, 'requested'::booking.booking_status, $2, $3, $4)
        RETURNING {BOOKING_COLUMNS}
        "#
    );
    sqlx::query_as::<_, BookingResponse>(&sql)
        .bind(customer_id)
        .bind(&req.address)
        .bind(req.scheduled_at)
        .bind(req.hours)
        .fetch_one(db)
        .await
        .map_err(AppError::from)
}

/// Read a booking's current status + ids inside a transaction (row-locked) so a
/// transition validates against state that cannot change underneath it.
async fn locked_current(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    id: Uuid,
) -> Result<(BookingStatus, Uuid, Option<Uuid>), AppError> {
    let row: Option<(String, Uuid, Option<Uuid>)> = sqlx::query_as(
        "SELECT status::text, customer_id, guard_id FROM booking.bookings WHERE id = $1 FOR UPDATE",
    )
    .bind(id)
    .fetch_optional(&mut **tx)
    .await?;

    let (status_str, customer_id, guard_id) =
        row.ok_or_else(|| AppError::NotFound("Booking not found".to_string()))?;
    let status = status_str
        .parse::<BookingStatus>()
        .map_err(AppError::Internal)?;
    Ok((status, customer_id, guard_id))
}

/// Atomically transition a booking to `new_status` and, when the change maps to an event,
/// enqueue that event into the outbox — both in ONE transaction.
///
/// `assign_guard`: when `Some`, the guard id to set (the accept path); when `None` the
/// existing `guard_id` is preserved. Rejects illegal transitions (state machine) with a
/// `Conflict` before any write. Returns the updated booking.
#[tracing::instrument(skip(db), fields(booking_id = %id, new_status = %new_status))]
pub async fn transition(
    db: &sqlx::PgPool,
    id: Uuid,
    actor: Uuid,
    new_status: BookingStatus,
    assign_guard: Option<Uuid>,
    correlation_id: Uuid,
) -> Result<BookingResponse, AppError> {
    let mut tx = db.begin().await?;

    let (current, customer_id, existing_guard) = locked_current(&mut tx, id).await?;

    // Authorization (inside the lock): the handler already checked role; here we enforce
    // assigned-guard OWNERSHIP so one guard cannot drive another guard's in-flight booking
    // (IDOR). Done before the state-machine check so a non-owner gets 403, not 409.
    match new_status {
        BookingStatus::EnRoute | BookingStatus::Arrived | BookingStatus::Completed => {
            if existing_guard != Some(actor) {
                tx.rollback().await?;
                return Err(AppError::Forbidden(
                    "Only the assigned guard can update this booking".to_string(),
                ));
            }
        }
        BookingStatus::Accepted => {
            // Accept claims an UNASSIGNED booking; never steal one already taken.
            if existing_guard.is_some() {
                tx.rollback().await?;
                return Err(AppError::Conflict(
                    "Booking already has an assigned guard".to_string(),
                ));
            }
        }
        // Declined is a pre-assignment offer rejection — the handler's guard-role gate is enough.
        _ => {}
    }

    if !can_transition(current, new_status) {
        tx.rollback().await?;
        return Err(AppError::Conflict(format!(
            "illegal transition {current} → {new_status}"
        )));
    }

    let guard_id = assign_guard.or(existing_guard);

    // 1) the business change
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

    // 2) the event — same transaction (transactional outbox)
    if let Some(EventMapping { topic, payload }) =
        event_for_status(new_status, id, customer_id, guard_id)
    {
        let envelope = EventEnvelope::new(topic, correlation_id, payload);
        let envelope_json = serde_json::to_value(&envelope)
            .map_err(|e| AppError::Internal(format!("serialize event envelope: {e}")))?;
        enqueue_outbox(&mut tx, topic, &envelope_json).await?;
    }

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
            },
        )
        .await
        .expect("create");
        assert_eq!(created.status, "requested");

        let accepted = transition(
            &pool,
            created.id,
            guard_id,
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
            },
        )
        .await
        .expect("create");
        transition(
            &pool,
            created.id,
            owner,
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
}
