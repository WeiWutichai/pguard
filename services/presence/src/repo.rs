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
use crate::models::{AssignmentWindowRow, GuardLocationRow, HistoryRow};

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
///
/// `available_for_work` is the session's CURRENT declared intent ("พร้อมรับงาน"), re-asserted on
/// every fix. Re-asserting matters for correctness, not just convenience: it is what stops a
/// PREVIOUS session's stale `true` from being inherited. A new session opened by a job-tracking
/// lease alone declares `false`, and its first fix overwrites whatever the row held — so merely
/// streaming GPS can never make a guard offerable again (the reported bug).
///
/// `last_seen_at` rides along with the fix (session liveness is trivially satisfied by a frame
/// that reached us), keeping the throttled keep-alive touch off the hot GPS path.
pub async fn upsert_location(
    db: &PgPool,
    guard_id: Uuid,
    session: Uuid,
    recorded_at: DateTime<Utc>,
    available_for_work: bool,
    fix: &GpsUpdate,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO presence.guard_locations \
             (guard_id, lat, lng, accuracy, heading, speed, recorded_at, is_online, \
              connected_session, available_for_work, last_seen_at) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, true, $8, $9, $7) \
         ON CONFLICT (guard_id) DO UPDATE SET \
             lat = EXCLUDED.lat, lng = EXCLUDED.lng, \
             accuracy = EXCLUDED.accuracy, heading = EXCLUDED.heading, speed = EXCLUDED.speed, \
             recorded_at = EXCLUDED.recorded_at, is_online = true, \
             connected_session = EXCLUDED.connected_session, \
             available_for_work = EXCLUDED.available_for_work, \
             last_seen_at = EXCLUDED.last_seen_at",
    )
    .bind(guard_id)
    .bind(fix.lat)
    .bind(fix.lng)
    .bind(fix.accuracy)
    .bind(fix.heading)
    .bind(fix.speed)
    .bind(recorded_at)
    .bind(session)
    .bind(available_for_work)
    .execute(db)
    .await?;
    Ok(())
}

/// Record the guard's "พร้อมรับงาน" toggle for the OWNING session, so flipping it mid-connection
/// takes effect at once instead of waiting for the next fix (a guard tracking a job may not move
/// for minutes). FENCED on `session` exactly like [`set_offline`]: a superseded socket can never
/// declare availability on a live reconnect's row.
///
/// A no-op when this session has not upserted a fix yet (no row, or `connected_session` still
/// points elsewhere) — harmless, because the session's very next fix carries the same intent
/// through [`upsert_location`]. `last_seen_at` is advanced too: the frame proves the session is
/// alive. `recorded_at` is NOT touched — this is not a position report.
pub async fn set_availability(
    db: &PgPool,
    guard_id: Uuid,
    session: Uuid,
    available: bool,
) -> Result<(), AppError> {
    sqlx::query(
        "UPDATE presence.guard_locations \
            SET available_for_work = $3, last_seen_at = now() \
          WHERE guard_id = $1 AND connected_session = $2",
    )
    .bind(guard_id)
    .bind(session)
    .bind(available)
    .execute(db)
    .await?;
    Ok(())
}

/// Advance SESSION liveness for the owning session — the throttled keep-alive touch driven by
/// ANY inbound frame (Pong included). Deliberately does NOT touch `recorded_at`, `is_online`, or
/// `available_for_work`: this says "the socket is alive", never "the guard moved" or "the guard
/// wants work". Fenced on `session` so a dying socket cannot keep a reconnected one's row warm.
///
/// `last_seen_at` is the only column written and is intentionally unindexed, so this stays a HOT
/// update (no index maintenance) even at one write per live guard per 30s.
pub async fn touch_seen(db: &PgPool, guard_id: Uuid, session: Uuid) -> Result<(), AppError> {
    sqlx::query(
        "UPDATE presence.guard_locations SET last_seen_at = now() \
          WHERE guard_id = $1 AND connected_session = $2",
    )
    .bind(guard_id)
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
/// Also CLEARS `available_for_work`: "พร้อมรับงาน" is an intent declared on a session, so it must
/// die with the session. Leaving it set would let the next connection — one a job-tracking lease
/// opens with the toggle OFF — inherit a stale `true` and put the guard back in front of
/// customers, which is the bug this whole change removes.
///
/// FENCED on `session`: only the session that currently OWNS the row (its id was stamped by the
/// last [`upsert_location`]) may flip it offline. A late-closing OLD socket whose
/// `connected_session` no longer matches is a no-op — so it can never clobber a freshly
/// reconnected LIVE session offline (last-disconnect-wins is gone). Also a no-op if the guard
/// never sent a fix (no row, or `connected_session` still NULL) — they were never on the map.
pub async fn set_offline(db: &PgPool, guard_id: Uuid, session: Uuid) -> Result<(), AppError> {
    sqlx::query(
        "UPDATE presence.guard_locations SET is_online = false, available_for_work = false \
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
        "SELECT guard_id, lat, lng, accuracy, heading, speed, recorded_at, is_online, \
                available_for_work, last_seen_at \
         FROM presence.guard_locations WHERE guard_id = $1",
    )
    .bind(guard_id)
    .fetch_optional(db)
    .await?
    .ok_or_else(|| AppError::NotFound("No location recorded for this guard".to_string()))
}

/// All guard positions for the admin map, newest fix first. `online_only` restricts to guards
/// who hold a LIVE session — the stored `is_online` flag AND `last_seen_at` inside `cutoff`
/// ([`crate::domain::session_liveness_cutoff`]), the same liveness bound the read DTO's computed
/// `is_online` applies. Without it, `?online_only=true` would keep listing rows stranded by a
/// presence crash while every one of them rendered as offline — the filter and the flag would
/// disagree. Served by the partial `idx_guard_locations_online`.
///
/// NOTE: no guard NAME is joined here — v1 joined `auth.users`, which v2 forbids (no
/// cross-schema read). The admin map resolves names via the profile service separately.
pub async fn list_locations(
    db: &PgPool,
    online_only: bool,
    cutoff: DateTime<Utc>,
) -> Result<Vec<GuardLocationRow>, AppError> {
    let base = "SELECT guard_id, lat, lng, accuracy, heading, speed, recorded_at, is_online, \
                       available_for_work, last_seen_at \
                FROM presence.guard_locations";
    // `LOCATIONS_MAX` is a fixed constant (never user input) → no injection surface; the cutoff
    // is a bound parameter.
    let sql = if online_only {
        format!(
            "{base} WHERE is_online AND last_seen_at > $1 \
             ORDER BY recorded_at DESC LIMIT {LOCATIONS_MAX}"
        )
    } else {
        format!("{base} ORDER BY recorded_at DESC LIMIT {LOCATIONS_MAX}")
    };
    // Bind CONDITIONALLY: the unfiltered branch has no `$1`, and sqlx rejects a query whose
    // argument count does not match its placeholders.
    let query = sqlx::query_as::<_, GuardLocationRow>(&sql);
    let query = if online_only {
        query.bind(cutoff)
    } else {
        query
    };
    let rows = query.fetch_all(db).await?;
    Ok(rows)
}

/// The guards who are currently OFFERABLE for discovery, carrying each guard's LATEST fix
/// position `(guard_id, lat, lng)`, which booking's `/available-guards` uses BOTH to drop
/// non-offerable guards from the customer list AND to sort the survivors nearest-to-meetup (C2).
/// One cheap round-trip (not a bulk PII pull).
///
/// Membership is three predicates, each load bearing:
///   1. `available_for_work` — the guard DECLARED "พร้อมรับงาน" on this session. This is the
///      requirement ("Guard ที่ยังไม่ได้เปิด Online Status ต้องไม่แสดง") and the whole reason 0005
///      exists: before it, membership keyed on `is_online`, which the ARRIVAL OF A GPS FIX sets —
///      so a guard streaming GPS for an active job with the toggle OFF was offered to customers.
///   2. `is_online` — a session is held (flipped false by [`set_offline`] on any clean
///      disconnect/zombie reap).
///   3. `last_seen_at > cutoff` — that session has actually been heard from. `set_offline` runs
///      only inside the WS task, so a presence crash/redeploy strands rows at `is_online = true`
///      forever; this bound expires them without a boot-time reset (wrong under multiple replicas).
///
/// `recorded_at` GPS freshness is STILL not a predicate here (bug B): the movement-gated mobile
/// uplink lets a stationary online guard's last fix age out while the socket is up, and gating on
/// it dropped connected, willing guards from discovery. Liveness keys on `last_seen_at` instead,
/// which keep-alives advance. Freshness survives ONLY as the green-dot `is_live` DISPLAY
/// ([`crate::domain::is_live`] in `to_location`).
///
/// `cutoff` comes from [`crate::domain::session_liveness_cutoff`] so the rule lives in `domain`
/// and the SQL only carries the bound. Served by the partial `idx_guard_locations_offerable`
/// (0005). Narrow projection (id + position only, no heading/speed/accuracy) — least-privilege
/// for the cross-service consult.
pub async fn online_guard_locations(
    db: &PgPool,
    cutoff: DateTime<Utc>,
) -> Result<Vec<(Uuid, f64, f64)>, AppError> {
    let rows: Vec<(Uuid, f64, f64)> = sqlx::query_as(
        "SELECT guard_id, lat, lng FROM presence.guard_locations \
          WHERE available_for_work AND is_online AND last_seen_at > $1",
    )
    .bind(cutoff)
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

/// The GPS track for a guard within an explicit `[from, to)` time window, OLDEST-first (a route
/// replay plays forward in time). Used by both replay modes: the by-guard+from/to playback and
/// the by-booking playback (after the window is derived from the assignment). `limit` is clamped
/// to [1, 1000] (the 500-point playback cap is applied by the caller via this bound). Served by
/// the `idx_location_history_user_time` btree on `(user_id, recorded_at DESC)` (0001) — the index
/// also satisfies the ASC order by a backwards scan.
///
/// Half-open `[from, to)`: `recorded_at >= from AND recorded_at < to`, so back-to-back job windows
/// (one job's `ended_at` == the next's `started_at`) never double-count the boundary point.
pub async fn history_between(
    db: &PgPool,
    guard_id: Uuid,
    from: DateTime<Utc>,
    to: DateTime<Utc>,
    limit: i64,
) -> Result<Vec<HistoryRow>, AppError> {
    let limit = limit.clamp(1, HISTORY_MAX_LIMIT);
    let rows = sqlx::query_as::<_, HistoryRow>(
        "SELECT latitude, longitude, accuracy_m, recorded_at \
         FROM presence.location_history \
         WHERE user_id = $1 AND recorded_at >= $2 AND recorded_at < $3 \
         ORDER BY recorded_at ASC LIMIT $4",
    )
    .bind(guard_id)
    .bind(from)
    .bind(to)
    .bind(limit)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// The job-window anchors for a booking, from the event-derived read-model (0004): the assigned
/// `guard_id`, the `started_at` (accept), and the `ended_at` (terminal, NULL while still active).
/// `NotFound` if the booking was never projected (e.g. an old booking that predates 0004, or an
/// unknown id) — the by-booking replay then 404s rather than guessing a window. Returns the raw
/// `Option`s so the handler can apply the "open window ends at now()" rule + flag a missing start.
pub async fn assignment_window(
    db: &PgPool,
    booking_id: Uuid,
) -> Result<AssignmentWindowRow, AppError> {
    sqlx::query_as::<_, AssignmentWindowRow>(
        "SELECT guard_id, started_at, ended_at \
         FROM presence.guard_assignments WHERE booking_id = $1",
    )
    .bind(booking_id)
    .fetch_optional(db)
    .await?
    .ok_or_else(|| AppError::NotFound("No assignment recorded for this booking".to_string()))
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
///
/// The job-window anchors (`started_at`/`ended_at`, 0004) are projected ALONGSIDE the authz
/// flip so the admin by-booking replay can derive the window from this same read-model:
///   * `is_start = true` (the `job_accepted` event) stamps `started_at` first-wins —
///     `LEAST(existing, new)` so an at-least-once redelivery never moves the start forward, and a
///     reordered terminal-before-accept still records the earliest accept time. `ended_at` is
///     untouched by an accept.
///   * `is_start = false` (a terminal event) stamps `ended_at` last-wins (`GREATEST`) so the end
///     reflects the latest terminal seen. `started_at` is untouched by a terminal event.
///
/// The window columns are advanced INDEPENDENTLY of the `updated_at` last-writer guard above so a
/// terminal event that arrives after the accept (the normal order) still records `ended_at` even
/// though it also flips `active=false` under the same `WHERE updated_at >` clause.
pub async fn upsert_assignment(
    db: &PgPool,
    booking_id: Uuid,
    customer_id: Option<Uuid>,
    guard_id: Option<Uuid>,
    active: bool,
    is_start: bool,
    occurred_at: DateTime<Utc>,
) -> Result<(), AppError> {
    // The accept event seeds `started_at`; a terminal event seeds `ended_at`. The other column is
    // NULL in the INSERT row and left untouched on UPDATE (COALESCE keeps the stored value).
    let (start_seed, end_seed) = if is_start {
        (Some(occurred_at), None)
    } else {
        (None, Some(occurred_at))
    };
    sqlx::query(
        "INSERT INTO presence.guard_assignments \
             (booking_id, customer_id, guard_id, active, updated_at, started_at, ended_at) \
         VALUES ($1, $2, $3, $4, $5, $6, $7) \
         ON CONFLICT (booking_id) DO UPDATE SET \
             customer_id = COALESCE(EXCLUDED.customer_id, presence.guard_assignments.customer_id), \
             guard_id    = COALESCE(EXCLUDED.guard_id, presence.guard_assignments.guard_id), \
             active      = CASE WHEN EXCLUDED.updated_at > presence.guard_assignments.updated_at \
                                THEN EXCLUDED.active ELSE presence.guard_assignments.active END, \
             updated_at  = GREATEST(EXCLUDED.updated_at, presence.guard_assignments.updated_at), \
             started_at  = LEAST(EXCLUDED.started_at, presence.guard_assignments.started_at), \
             ended_at    = GREATEST(EXCLUDED.ended_at, presence.guard_assignments.ended_at)",
    )
    .bind(booking_id)
    .bind(customer_id)
    .bind(guard_id)
    .bind(active)
    .bind(occurred_at)
    .bind(start_seed)
    .bind(end_seed)
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
    use chrono::{Duration, SubsecRound};
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

        upsert_location(&pool, guard, session, now, true, &fix(13.75, 100.50))
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

        // online_only bulk list includes the guard (live session, inside the liveness window).
        let online = list_locations(&pool, true, crate::domain::session_liveness_cutoff(now))
            .await
            .expect("list online");
        assert!(online.iter().any(|r| r.guard_id == guard));

        // Disconnect → offline, recorded_at untouched. Fenced on the OWNING session.
        set_offline(&pool, guard, session).await.expect("offline");
        let row2 = latest_location(&pool, guard).await.expect("latest2");
        assert!(!row2.is_online, "disconnect sets offline");
        assert!(
            !row2.available_for_work,
            "disconnect also revokes the พร้อมรับงาน declaration — intent dies with the session"
        );
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

    /// `online_guard_locations` is the discovery OFFERABLE set. This is the QA 08/09/2569 rule
    /// ("Guard ที่ยังไม่ได้เปิด Online Status ต้องไม่แสดงอยู่ในหน้าเลือก Guard") proved end-to-end
    /// against a real DB, across all four ways a row can fail to be offerable:
    ///
    ///  * DECLINED — connected and streaming GPS but never declared availability. THE reported
    ///    bug: the app opens this same socket to track an active job with the toggle OFF, so
    ///    membership keyed on "a fix arrived" put guards who never opted in in front of customers.
    ///  * OFFLINE — the session disconnected (`set_offline`), which also revokes the declaration.
    ///  * DEAD — declared + `is_online`, but nothing has been heard from the session inside the
    ///    liveness window (the crash/redeploy ghost: `set_offline` only runs in the WS task).
    ///  * STALE GPS — declared, connected, heard from, but the last FIX is 10 minutes old. This
    ///    one IS still offerable: the mobile uplink is movement-gated, so a stationary guard's
    ///    `recorded_at` ages out while the socket is fine (bug B — do not re-gate on it).
    #[tokio::test]
    async fn online_guard_locations_requires_declared_availability_and_a_live_session() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL required for the online-guards membership test");
            return;
        };
        let available_guard = Uuid::new_v4();
        let declined_guard = Uuid::new_v4();
        let stale_gps_guard = Uuid::new_v4();
        let dead_session_guard = Uuid::new_v4();
        let session = Uuid::new_v4();
        let now = Utc::now();
        let cutoff = crate::domain::session_liveness_cutoff(now);

        // Declared available, fix at `now`.
        upsert_location(
            &pool,
            available_guard,
            session,
            now,
            true,
            &fix(13.75, 100.50),
        )
        .await
        .expect("available upsert");
        // Streaming GPS for a job, toggle OFF — the guard never declared availability.
        upsert_location(
            &pool,
            declined_guard,
            session,
            now,
            false,
            &fix(13.80, 100.60),
        )
        .await
        .expect("declined upsert");
        // Declared available; last FIX 10 minutes old (> the 5-minute freshness window) but the
        // session was heard from just now — the stationary-guard case.
        upsert_location(
            &pool,
            stale_gps_guard,
            session,
            now - Duration::minutes(10),
            true,
            &fix(13.76, 100.51),
        )
        .await
        .expect("stale-gps upsert");
        touch_seen(&pool, stale_gps_guard, session)
            .await
            .expect("stale-gps stays session-live");
        // Declared available and still flagged online, but nothing heard for 10 minutes — the row
        // a crashed/redeployed presence left behind.
        upsert_location(
            &pool,
            dead_session_guard,
            session,
            now,
            true,
            &fix(13.77, 100.52),
        )
        .await
        .expect("dead-session upsert");
        sqlx::query("UPDATE presence.guard_locations SET last_seen_at = $2 WHERE guard_id = $1")
            .bind(dead_session_guard)
            .bind(now - Duration::minutes(10))
            .execute(&pool)
            .await
            .expect("age the dead session");

        let live = online_guard_locations(&pool, cutoff)
            .await
            .expect("online locations");

        // The declared, connected, live guard IS offerable and carries its coords for the C2 sort.
        let offered = live.iter().find(|(id, _, _)| *id == available_guard);
        assert!(
            offered.is_some(),
            "a guard who switched Online Status on is offerable"
        );
        let (_, lat, lng) = offered.expect("offered row");
        assert!(
            (*lat - 13.75).abs() < 1e-6 && (*lng - 100.50).abs() < 1e-6,
            "offerable row carries the latest fix coords, got ({lat}, {lng})"
        );

        // THE FIX: streaming GPS without declaring availability never reaches a customer.
        assert!(
            !live.iter().any(|(id, _, _)| *id == declined_guard),
            "a guard who never switched Online Status on must NEVER be offerable, \
             even while streaming GPS for an active job"
        );

        // Bug B stays fixed: a stale FIX does not evict a live, willing guard.
        let stale = live.iter().find(|(id, _, _)| *id == stale_gps_guard);
        assert!(
            stale.is_some(),
            "a stationary guard whose GPS fix aged out is STILL offerable (bug B)"
        );
        let (_, slat, slng) = stale.expect("stale row");
        assert!(
            (*slat - 13.76).abs() < 1e-6 && (*slng - 100.51).abs() < 1e-6,
            "stale-GPS offerable row carries its last fix coords, got ({slat}, {slng})"
        );

        // The ghost expires itself — no boot-time reset needed.
        assert!(
            !live.iter().any(|(id, _, _)| *id == dead_session_guard),
            "a row whose session went silent (presence crash/redeploy) stops being offerable"
        );

        // GPS freshness survives ONLY as the green-dot display; it gates nothing above.
        assert!(
            crate::domain::is_live(true, now, now),
            "a fresh online fix displays live"
        );
        assert!(
            !crate::domain::is_live(true, now - Duration::minutes(10), now),
            "a stale online fix displays not-live (green-dot only, does not gate offerability)"
        );

        // Disconnect revokes BOTH the session and the declaration.
        set_offline(&pool, available_guard, session)
            .await
            .expect("offline");
        let live2 = online_guard_locations(&pool, cutoff)
            .await
            .expect("online locations 2");
        assert!(
            !live2.iter().any(|(id, _, _)| *id == available_guard),
            "a disconnected guard is never offerable, even with a fresh last fix"
        );
        let row = latest_location(&pool, available_guard)
            .await
            .expect("row after offline");
        assert!(
            !row.available_for_work,
            "the declaration is revoked on disconnect, so the NEXT session (e.g. one a job-\
             tracking lease opens) cannot inherit it"
        );

        let _ = sqlx::query("DELETE FROM presence.guard_locations WHERE guard_id = ANY($1)")
            .bind(vec![
                available_guard,
                declined_guard,
                stale_gps_guard,
                dead_session_guard,
            ])
            .execute(&pool)
            .await;
    }

    /// The availability frame (`{"type":"availability"}`) flips offerability WITHOUT waiting for
    /// the next GPS fix — a guard tracking a stationary job may not send one for 90 s, and every
    /// one of those seconds after they tap "off" is a customer able to book them. It is FENCED on
    /// the owning session, exactly like `set_offline`, so a superseded socket cannot declare
    /// availability on a live reconnect's row.
    #[tokio::test]
    async fn set_availability_toggles_offerability_and_is_session_fenced() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL required for the availability-toggle test");
            return;
        };
        let guard = Uuid::new_v4();
        let session = Uuid::new_v4();
        let stale_session = Uuid::new_v4();
        let now = Utc::now();
        let cutoff = crate::domain::session_liveness_cutoff(now);
        let offerable = |set: &[(Uuid, f64, f64)]| set.iter().any(|(id, _, _)| *id == guard);

        // Connected with the toggle OFF (the job-tracking case) → not offerable.
        upsert_location(&pool, guard, session, now, false, &fix(13.75, 100.50))
            .await
            .expect("upsert");
        let set = online_guard_locations(&pool, cutoff).await.expect("set 0");
        assert!(!offerable(&set), "toggle off → not offered");

        // Guard taps "พร้อมรับงาน" → offerable immediately, no new fix required.
        set_availability(&pool, guard, session, true)
            .await
            .expect("declare available");
        let set = online_guard_locations(&pool, cutoff).await.expect("set 1");
        assert!(offerable(&set), "declaring availability offers the guard");

        // A SUPERSEDED socket's declaration is fenced out — it does not own the row.
        set_availability(&pool, guard, stale_session, false)
            .await
            .expect("stale declaration");
        let set = online_guard_locations(&pool, cutoff).await.expect("set 2");
        assert!(
            offerable(&set),
            "a stale session must not revoke the live session's declaration"
        );

        // Guard taps it off → gone from discovery at once (still connected, still streaming).
        set_availability(&pool, guard, session, false)
            .await
            .expect("revoke");
        let set = online_guard_locations(&pool, cutoff).await.expect("set 3");
        assert!(
            !offerable(&set),
            "toggling off removes the guard immediately"
        );
        let row = latest_location(&pool, guard).await.expect("row");
        assert!(
            row.is_online,
            "the guard is still CONNECTED (the customer's live map keeps working) — only the \
             offer is withdrawn"
        );

        let _ = sqlx::query("DELETE FROM presence.guard_locations WHERE guard_id = $1")
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
        upsert_location(&pool, guard, session_a, now, true, &fix(13.75, 100.50))
            .await
            .expect("A upsert");
        // Guard reconnects as session B + sends a fix → B now owns the row.
        upsert_location(
            &pool,
            guard,
            session_b,
            now + Duration::seconds(1),
            true,
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
        // Postgres timestamptz stores microseconds; truncate so a read-back equals t0 exactly
        // (Utc::now() carries nanoseconds, which PG drops → an == against the round-trip would fail).
        let t0 = Utc::now().trunc_subsecs(6);

        // job_accepted → active link.
        upsert_assignment(&pool, booking, Some(customer), Some(guard), true, true, t0)
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

    /// The job-window projection (0004) + the two replay reads:
    ///   * `upsert_assignment` stamps `started_at` (accept) + `ended_at` (terminal), first-/last-
    ///     wins so a redelivery never moves them.
    ///   * `assignment_window` returns those anchors for the by-booking replay.
    ///   * `history_between` returns only the points inside the half-open `[from, to)` window,
    ///     oldest-first — the time-range filter for both replay modes.
    #[tokio::test]
    async fn window_projection_and_replay_reads() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL required for the replay window test");
            return;
        };
        let booking = Uuid::new_v4();
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        // Postgres timestamptz stores microseconds; truncate so a read-back equals t0 exactly
        // (Utc::now() carries nanoseconds, which PG drops → an == against the round-trip would fail).
        let t0 = Utc::now().trunc_subsecs(6);

        // job_accepted at t0 → started_at = t0, ended_at = NULL (window still open).
        upsert_assignment(&pool, booking, Some(customer), Some(guard), true, true, t0)
            .await
            .expect("accept");
        let w = assignment_window(&pool, booking).await.expect("window");
        assert_eq!(w.guard_id, Some(guard));
        assert_eq!(w.started_at, Some(t0));
        assert!(w.ended_at.is_none(), "active job has no end yet");

        // A redelivered LATER accept must NOT move started_at forward (first-wins).
        upsert_assignment(
            &pool,
            booking,
            Some(customer),
            Some(guard),
            true,
            true,
            t0 + Duration::seconds(30),
        )
        .await
        .expect("accept redelivery");
        let w = assignment_window(&pool, booking).await.expect("window2");
        assert_eq!(w.started_at, Some(t0), "started_at is first-wins (LEAST)");

        // Seed five history points: two BEFORE the job, three DURING (t0..t0+3h).
        for (mins, lat) in [
            (-60i64, 13.70), // before accept
            (-1, 13.71),     // just before accept
            (10, 13.72),     // during
            (60, 13.73),     // during
            (170, 13.74),    // during (< 3h)
        ] {
            insert_history(&pool, guard, t0 + Duration::minutes(mins), &fix(lat, 100.5))
                .await
                .expect("seed history");
        }

        // completed at t0+3h → ended_at = t0+3h, active=false.
        let t_end = t0 + Duration::hours(3);
        upsert_assignment(&pool, booking, None, None, false, false, t_end)
            .await
            .expect("complete");
        let w = assignment_window(&pool, booking).await.expect("window3");
        assert_eq!(w.ended_at, Some(t_end), "terminal stamps ended_at");
        assert_eq!(w.started_at, Some(t0), "terminal leaves started_at");

        // The by-booking window read [t0, t0+3h) returns the 3 DURING points, oldest-first.
        let pts = history_between(&pool, guard, t0, t_end, 500)
            .await
            .expect("between");
        assert_eq!(pts.len(), 3, "only the 3 in-window points");
        assert!(
            pts[0].recorded_at < pts[1].recorded_at && pts[1].recorded_at < pts[2].recorded_at,
            "oldest-first"
        );
        assert_eq!(pts[0].latitude, 13.72, "first in-window point");

        // A redelivered (older) terminal must NOT move ended_at backward (GREATEST).
        upsert_assignment(
            &pool,
            booking,
            None,
            None,
            false,
            false,
            t0 + Duration::hours(1),
        )
        .await
        .expect("stale terminal");
        let w = assignment_window(&pool, booking).await.expect("window4");
        assert_eq!(w.ended_at, Some(t_end), "ended_at is last-wins (GREATEST)");

        // The limit caps the points (proves the 500-cap path; clamp to 2 here).
        let capped = history_between(&pool, guard, t0, t_end, 2)
            .await
            .expect("capped");
        assert_eq!(capped.len(), 2, "limit caps the window read");

        // assignment_window for an unknown booking → NotFound (by-booking replay then 404s).
        let missing = assignment_window(&pool, Uuid::new_v4()).await;
        assert!(matches!(missing, Err(AppError::NotFound(_))));

        // cleanup
        let _ = sqlx::query("DELETE FROM presence.guard_assignments WHERE booking_id = $1")
            .bind(booking)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM presence.location_history WHERE user_id = $1")
            .bind(guard)
            .execute(&pool)
            .await;
    }
}
