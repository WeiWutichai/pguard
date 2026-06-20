//! Repository — the ONLY place that touches schema `presence`.
//!
//! Runtime `sqlx::query`/`query_as` (no compile-time `query!` — no DATABASE_URL at build,
//! mirrors the other slices). Owns: the `location_history` retention purge (PDPA §7.3), the
//! `guard_locations` live-position upsert + reads, and the `guard_assignments` event-derived
//! IDOR read-model (projected from `pguard.events.booking.*` by [`crate::events::consumer`]).

use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use shared::error::AppError;

use crate::domain::GpsUpdate;
use crate::models::{GuardLocationRow, HistoryRow};

/// Max rows deleted per statement — bounds each transaction so a large backlog catch-up never
/// locks an unbounded set in one go (this is a high-volume sensitive store).
const PURGE_BATCH: i64 = 10_000;
/// Hard cap on history page size, regardless of the client-requested `limit`.
const HISTORY_MAX_LIMIT: i64 = 1_000;
const HISTORY_DEFAULT_LIMIT: i64 = 100;
/// Hard cap on the admin bulk-locations response — bounds the live-map payload + the sort cost
/// on a large fleet (a sensitive-PII bulk read should never be unbounded). `online_only=true`
/// is the common map query and is served by the partial index; the cap backstops both.
const LOCATIONS_MAX: i64 = 5_000;

// =============================================================================
// Retention purge (PDPA §7.3) — established in C5.2 (0001).
// =============================================================================

/// Delete location-history rows older than `cutoff`, in bounded batches; returns the total
/// purged. The `idx_location_history_recorded_at` BRIN index makes each range-delete efficient
/// on the append-only store, and the `ctid IN (… LIMIT)` batching keeps any single statement's
/// lock/transaction footprint small even when clearing a large backlog.
pub async fn purge_older_than(pool: &PgPool, cutoff: DateTime<Utc>) -> Result<u64, sqlx::Error> {
    let mut total = 0u64;
    loop {
        let res = sqlx::query(
            "DELETE FROM presence.location_history \
             WHERE ctid IN ( \
               SELECT ctid FROM presence.location_history WHERE recorded_at < $1 LIMIT $2 \
             )",
        )
        .bind(cutoff)
        .bind(PURGE_BATCH)
        .execute(pool)
        .await?;
        let n = res.rows_affected();
        total += n;
        if n < PURGE_BATCH as u64 {
            break;
        }
    }
    Ok(total)
}

// =============================================================================
// Live position store (`guard_locations`) — WS ingress writes, reads serve the map/APIs.
// =============================================================================

/// Upsert the guard's CURRENT position from a (validated) fix: sets `is_online = true`, advances
/// `recorded_at` to the supplied server timestamp, and stamps the OWNING session's id so the
/// offline write can be fenced to it (see [`set_offline`]). Called only for a real GPS fix —
/// never for a keep-alive (so a guard who lost GPS but holds the socket does not stay fresh).
pub async fn upsert_location(
    db: &PgPool,
    guard_id: Uuid,
    session: Uuid,
    recorded_at: DateTime<Utc>,
    fix: &GpsUpdate,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO presence.guard_locations \
             (guard_id, lat, lng, accuracy, heading, speed, recorded_at, is_online, connected_session) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, true, $8) \
         ON CONFLICT (guard_id) DO UPDATE SET \
             lat = EXCLUDED.lat, lng = EXCLUDED.lng, \
             accuracy = EXCLUDED.accuracy, heading = EXCLUDED.heading, speed = EXCLUDED.speed, \
             recorded_at = EXCLUDED.recorded_at, is_online = true, \
             connected_session = EXCLUDED.connected_session",
    )
    .bind(guard_id)
    .bind(fix.lat)
    .bind(fix.lng)
    .bind(fix.accuracy)
    .bind(fix.heading)
    .bind(fix.speed)
    .bind(recorded_at)
    .bind(session)
    .execute(db)
    .await?;
    Ok(())
}

/// Append the fix to the immutable history (PDPA-retained; purged after 90 days). The history
/// store (0001) keeps lat/lng/accuracy + time only — heading/speed are live-only signals.
pub async fn insert_history(
    db: &PgPool,
    guard_id: Uuid,
    recorded_at: DateTime<Utc>,
    fix: &GpsUpdate,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO presence.location_history \
             (user_id, latitude, longitude, accuracy_m, recorded_at) \
         VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(guard_id)
    .bind(fix.lat)
    .bind(fix.lng)
    .bind(fix.accuracy)
    .bind(recorded_at)
    .execute(db)
    .await?;
    Ok(())
}

/// Mark the guard offline (WS disconnect / zombie reap). Does NOT touch `recorded_at` — the
/// last fix's timestamp is preserved so freshness reflects when GPS was actually last seen.
///
/// FENCED on `session`: only the session that currently OWNS the row (its id was stamped by the
/// last [`upsert_location`]) may flip it offline. A late-closing OLD socket whose
/// `connected_session` no longer matches is a no-op — so it can never clobber a freshly
/// reconnected LIVE session offline (last-disconnect-wins is gone). Also a no-op if the guard
/// never sent a fix (no row, or `connected_session` still NULL) — they were never on the map.
pub async fn set_offline(db: &PgPool, guard_id: Uuid, session: Uuid) -> Result<(), AppError> {
    sqlx::query(
        "UPDATE presence.guard_locations SET is_online = false \
         WHERE guard_id = $1 AND connected_session = $2",
    )
    .bind(guard_id)
    .bind(session)
    .execute(db)
    .await?;
    Ok(())
}

/// The guard's latest position, or `NotFound` if none recorded.
pub async fn latest_location(db: &PgPool, guard_id: Uuid) -> Result<GuardLocationRow, AppError> {
    sqlx::query_as::<_, GuardLocationRow>(
        "SELECT guard_id, lat, lng, accuracy, heading, speed, recorded_at, is_online \
         FROM presence.guard_locations WHERE guard_id = $1",
    )
    .bind(guard_id)
    .fetch_optional(db)
    .await?
    .ok_or_else(|| AppError::NotFound("No location recorded for this guard".to_string()))
}

/// All guard positions for the admin map, newest fix first. `online_only` restricts to
/// currently-connected guards (served by the partial `idx_guard_locations_online`).
///
/// NOTE: no guard NAME is joined here — v1 joined `auth.users`, which v2 forbids (no
/// cross-schema read). The admin map resolves names via the profile service separately.
pub async fn list_locations(
    db: &PgPool,
    online_only: bool,
) -> Result<Vec<GuardLocationRow>, AppError> {
    let base = "SELECT guard_id, lat, lng, accuracy, heading, speed, recorded_at, is_online \
                FROM presence.guard_locations";
    // `LOCATIONS_MAX` is a fixed constant (never user input) → no injection surface.
    let sql = if online_only {
        format!("{base} WHERE is_online ORDER BY recorded_at DESC LIMIT {LOCATIONS_MAX}")
    } else {
        format!("{base} ORDER BY recorded_at DESC LIMIT {LOCATIONS_MAX}")
    };
    let rows = sqlx::query_as::<_, GuardLocationRow>(&sql)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

/// Paginated GPS history for a guard, newest first. `limit` is clamped to [1, 1000].
pub async fn history(
    db: &PgPool,
    guard_id: Uuid,
    limit: Option<i64>,
    offset: Option<i64>,
) -> Result<Vec<HistoryRow>, AppError> {
    let limit = limit
        .unwrap_or(HISTORY_DEFAULT_LIMIT)
        .clamp(1, HISTORY_MAX_LIMIT);
    let offset = offset.unwrap_or(0).max(0);
    let rows = sqlx::query_as::<_, HistoryRow>(
        "SELECT latitude, longitude, accuracy_m, recorded_at \
         FROM presence.location_history WHERE user_id = $1 \
         ORDER BY recorded_at DESC LIMIT $2 OFFSET $3",
    )
    .bind(guard_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

// =============================================================================
// Event-derived IDOR read-model (`guard_assignments`).
// =============================================================================

/// Does `customer_id` have an ACTIVE booking with `guard_id`? The IDOR gate for a customer's
/// per-guard location/history read. Reads the projection built from `pguard.events.booking.*`
/// — presence never reads booking's tables.
pub async fn has_active_booking(
    db: &PgPool,
    customer_id: Uuid,
    guard_id: Uuid,
) -> Result<bool, AppError> {
    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS( \
            SELECT 1 FROM presence.guard_assignments \
            WHERE customer_id = $1 AND guard_id = $2 AND active \
         )",
    )
    .bind(customer_id)
    .bind(guard_id)
    .fetch_one(db)
    .await?;
    Ok(exists)
}

/// Project one booking event onto the read-model. `active` is true for `job_accepted`, false
/// for the terminal events. Last-writer-wins by `occurred_at` with a STRICT `>` guard: an
/// equal-or-older redelivered/reordered event is ignored, so at-least-once delivery (even an
/// exact-same-timestamp redelivery of an accept after a completion) can never reactivate a
/// finished booking. `COALESCE` keeps known ids when a terminal event omits them.
pub async fn upsert_assignment(
    db: &PgPool,
    booking_id: Uuid,
    customer_id: Option<Uuid>,
    guard_id: Option<Uuid>,
    active: bool,
    occurred_at: DateTime<Utc>,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO presence.guard_assignments \
             (booking_id, customer_id, guard_id, active, updated_at) \
         VALUES ($1, $2, $3, $4, $5) \
         ON CONFLICT (booking_id) DO UPDATE SET \
             customer_id = COALESCE(EXCLUDED.customer_id, presence.guard_assignments.customer_id), \
             guard_id    = COALESCE(EXCLUDED.guard_id, presence.guard_assignments.guard_id), \
             active      = EXCLUDED.active, \
             updated_at  = EXCLUDED.updated_at \
         WHERE EXCLUDED.updated_at > presence.guard_assignments.updated_at",
    )
    .bind(booking_id)
    .bind(customer_id)
    .bind(guard_id)
    .bind(active)
    .bind(occurred_at)
    .execute(db)
    .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    //! DB-gated proofs (a migrated DB with presence 0001 + 0002 applied); hermetic SKIP
    //! otherwise, so `cargo test` stays offline-safe. Run:
    //!   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    //!     cargo test -p pguard-presence -- --nocapture
    use super::*;
    use chrono::Duration;
    use sqlx::postgres::PgPoolOptions;

    async fn pool() -> Option<PgPool> {
        let url = std::env::var("DATABASE_URL").ok()?;
        PgPoolOptions::new()
            .acquire_timeout(std::time::Duration::from_secs(5))
            .connect(&url)
            .await
            .ok()
    }

    fn fix(lat: f64, lng: f64) -> GpsUpdate {
        GpsUpdate {
            lat,
            lng,
            accuracy: Some(8.0),
            heading: Some(180.0),
            speed: Some(2.0),
            assignment_id: None,
        }
    }

    #[tokio::test]
    async fn purge_deletes_old_keeps_recent() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL required for the presence retention purge test");
            return;
        };
        let user_id = Uuid::new_v4();
        let now = Utc::now();
        for (at, lat) in [
            (now - Duration::days(100), 13.7),
            (now - Duration::days(1), 13.8),
        ] {
            sqlx::query(
                "INSERT INTO presence.location_history (user_id, latitude, longitude, recorded_at) \
                 VALUES ($1, $2, $3, $4)",
            )
            .bind(user_id)
            .bind(lat)
            .bind(100.5)
            .bind(at)
            .execute(&pool)
            .await
            .expect("seed location_history");
        }
        let purged = purge_older_than(&pool, now - Duration::days(90))
            .await
            .expect("purge");
        assert!(purged >= 1);
        let remaining: i64 =
            sqlx::query_scalar("SELECT count(*) FROM presence.location_history WHERE user_id = $1")
                .bind(user_id)
                .fetch_one(&pool)
                .await
                .expect("count");
        assert_eq!(remaining, 1, "recent kept, old purged");
        let _ = sqlx::query("DELETE FROM presence.location_history WHERE user_id = $1")
            .bind(user_id)
            .execute(&pool)
            .await;
    }

    #[tokio::test]
    async fn upsert_then_offline_and_history_and_freshness() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL required for the live-store test");
            return;
        };
        let guard = Uuid::new_v4();
        let session = Uuid::new_v4();
        let now = Utc::now();

        upsert_location(&pool, guard, session, now, &fix(13.75, 100.50))
            .await
            .expect("upsert");
        insert_history(&pool, guard, now, &fix(13.75, 100.50))
            .await
            .expect("history");

        // After a fix: online + the row carries the bound recorded_at.
        let row = latest_location(&pool, guard).await.expect("latest");
        assert!(row.is_online, "a fix sets the guard online");
        assert_eq!(row.lat, 13.75);
        assert_eq!(row.accuracy, Some(8.0));

        // online_only bulk list includes the guard.
        let online = list_locations(&pool, true).await.expect("list online");
        assert!(online.iter().any(|r| r.guard_id == guard));

        // Disconnect → offline, recorded_at untouched. Fenced on the OWNING session.
        set_offline(&pool, guard, session).await.expect("offline");
        let row2 = latest_location(&pool, guard).await.expect("latest2");
        assert!(!row2.is_online, "disconnect sets offline");
        assert_eq!(
            row2.recorded_at, row.recorded_at,
            "offline must NOT touch recorded_at"
        );

        // History has the point.
        let hist = history(&pool, guard, Some(10), Some(0))
            .await
            .expect("history read");
        assert!(!hist.is_empty());

        // cleanup
        let _ = sqlx::query("DELETE FROM presence.guard_locations WHERE guard_id = $1")
            .bind(guard)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM presence.location_history WHERE user_id = $1")
            .bind(guard)
            .execute(&pool)
            .await;
    }

    /// The stale-socket clobber fix: a LATE-closing OLD session must NOT flip a freshly
    /// reconnected LIVE session offline. After session B's fix owns the row, session A's
    /// `set_offline` (stale `connected_session`) is a no-op — the guard stays online.
    #[tokio::test]
    async fn stale_session_offline_does_not_clobber_live_reconnect() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL required for the stale-session fence test");
            return;
        };
        let guard = Uuid::new_v4();
        let session_a = Uuid::new_v4();
        let session_b = Uuid::new_v4();
        let now = Utc::now();

        // Session A connects + sends a fix → owns the row, online.
        upsert_location(&pool, guard, session_a, now, &fix(13.75, 100.50))
            .await
            .expect("A upsert");
        // Guard reconnects as session B + sends a fix → B now owns the row.
        upsert_location(
            &pool,
            guard,
            session_b,
            now + Duration::seconds(1),
            &fix(13.76, 100.51),
        )
        .await
        .expect("B upsert");

        // A's late close fires set_offline for the OLD session → fenced out, no-op.
        set_offline(&pool, guard, session_a)
            .await
            .expect("A stale offline");
        let row = latest_location(&pool, guard).await.expect("latest");
        assert!(
            row.is_online,
            "a stale OLD session must not flip the live reconnected session offline"
        );

        // B's own close DOES set offline (it owns the row).
        set_offline(&pool, guard, session_b)
            .await
            .expect("B offline");
        let row2 = latest_location(&pool, guard).await.expect("latest2");
        assert!(!row2.is_online, "the owning session can set itself offline");

        let _ = sqlx::query("DELETE FROM presence.guard_locations WHERE guard_id = $1")
            .bind(guard)
            .execute(&pool)
            .await;
    }

    #[tokio::test]
    async fn idor_read_model_active_then_terminal() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL required for the IDOR read-model test");
            return;
        };
        let booking = Uuid::new_v4();
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let stranger = Uuid::new_v4();
        let t0 = Utc::now();

        // job_accepted → active link.
        upsert_assignment(&pool, booking, Some(customer), Some(guard), true, t0)
            .await
            .expect("accept");
        assert!(has_active_booking(&pool, customer, guard)
            .await
            .expect("q1"));
        // a stranger never has access.
        assert!(!has_active_booking(&pool, stranger, guard)
            .await
            .expect("q2"));

        // An OLDER duplicate of accept must not change anything (last-writer-wins).
        upsert_assignment(
            &pool,
            booking,
            Some(customer),
            Some(guard),
            true,
            t0 - Duration::seconds(5),
        )
        .await
        .expect("stale accept");
        assert!(has_active_booking(&pool, customer, guard)
            .await
            .expect("q3"));

        // completed (terminal, ids omitted) → inactive.
        upsert_assignment(
            &pool,
            booking,
            None,
            None,
            false,
            t0 + Duration::seconds(10),
        )
        .await
        .expect("complete");
        assert!(
            !has_active_booking(&pool, customer, guard)
                .await
                .expect("q4"),
            "after completion the customer can no longer track the guard"
        );

        // A redelivered (older) accept must NOT reactivate the finished booking.
        upsert_assignment(
            &pool,
            booking,
            Some(customer),
            Some(guard),
            true,
            t0 + Duration::seconds(1),
        )
        .await
        .expect("late accept redelivery");
        assert!(
            !has_active_booking(&pool, customer, guard)
                .await
                .expect("q5"),
            "stale redelivery never reactivates"
        );

        let _ = sqlx::query("DELETE FROM presence.guard_assignments WHERE booking_id = $1")
            .bind(booking)
            .execute(&pool)
            .await;
    }
}
