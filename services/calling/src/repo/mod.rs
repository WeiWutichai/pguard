//! Repository layer — the ONLY place that touches the `calling` schema.
//!
//! Runtime `sqlx::query`/`query_as` (no compile-time `query!` — no DATABASE_URL at build,
//! mirrors the other slices). Every state-changing write that maps to a cross-service event
//! writes the call row AND the `pguard.events.calling.*` outbox row in ONE transaction
//! (CLAUDE.md "Cross-tx consistency: transactional outbox").

use serde_json::Value;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::{topics, EventEnvelope};

use crate::domain::{can_transition, end_target, CallStatus};
use crate::models::{CallEventRow, CallResponse};

const CALL_COLUMNS: &str = "id, caller_id, callee_id, booking_id, call_type::text AS call_type, \
     status::text AS status, started_at, answered_at, ended_at, duration_seconds, end_reason, \
     created_at, updated_at";

/// Columns for one row of the per-call timeline (admin call-events read model).
const CALL_EVENT_COLUMNS: &str = "id, call_id, event_type, actor_id, detail, occurred_at";

/// Active statuses that make a callee "busy" (a fresh initiate is rejected).
const ACTIVE_STATUSES: &str = "('initiated', 'accepted', 'connected')";

// ----- Outbox row (for the relay) -----

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct OutboxRow {
    pub id: Uuid,
    pub topic: String,
    pub payload: Value,
}

// ----- Reads -----

/// Fetch one call by id (the handler then enforces participant/admin visibility).
pub async fn get_call(db: &sqlx::PgPool, id: Uuid) -> Result<CallResponse, AppError> {
    let sql = format!("SELECT {CALL_COLUMNS} FROM calling.call_logs WHERE id = $1");
    sqlx::query_as::<_, CallResponse>(&sql)
        .bind(id)
        .fetch_optional(db)
        .await?
        .ok_or_else(|| AppError::NotFound("Call not found".to_string()))
}

/// Admin cross-user call log — every call (NO participant filter; the admin-role gate is the
/// API layer's job), newest first, optional `status`/`call_type` filters + limit/offset.
/// `$n` placeholders come from a controlled counter; every value is a BOUND parameter.
pub async fn admin_list_calls(
    db: &sqlx::PgPool,
    status: Option<&str>,
    call_type: Option<&str>,
    limit: i64,
    offset: i64,
) -> Result<Vec<CallResponse>, AppError> {
    let mut sql = format!("SELECT {CALL_COLUMNS} FROM calling.call_logs");
    let mut conds: Vec<String> = Vec::new();
    let mut idx = 1;
    if status.is_some() {
        conds.push(format!("status = ${idx}::calling.call_status"));
        idx += 1;
    }
    if call_type.is_some() {
        conds.push(format!("call_type = ${idx}::calling.call_type"));
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
    let mut query = sqlx::query_as::<_, CallResponse>(&sql);
    if let Some(s) = status {
        query = query.bind(s);
    }
    if let Some(ct) = call_type {
        query = query.bind(ct);
    }
    let rows = query.bind(limit).bind(offset).fetch_all(db).await?;
    Ok(rows)
}

/// The two participants of a call (caller, callee) + its current status — used by the WS
/// relay to authorize, gate on liveness (refuse relaying on a terminal call), and route a
/// signal to the OTHER party. `None` if the call does not exist.
pub async fn participants(
    db: &sqlx::PgPool,
    id: Uuid,
) -> Result<Option<(Uuid, Uuid, CallStatus)>, AppError> {
    let row: Option<(Uuid, Uuid, String)> = sqlx::query_as(
        "SELECT caller_id, callee_id, status::text FROM calling.call_logs WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(db)
    .await?;
    match row {
        Some((caller, callee, status)) => {
            let status = status.parse::<CallStatus>().map_err(|e| {
                tracing::error!("call status decode failed: {e}");
                AppError::Internal("call state decode error".to_string())
            })?;
            Ok(Some((caller, callee, status)))
        }
        None => Ok(None),
    }
}

/// One call's ordered lifecycle timeline (admin call-events read model). Chronological
/// (`occurred_at` asc, then insertion `id` to break ties on identical timestamps). The admin-role
/// gate is the API layer's job (this is a cross-user read, like `admin_list_calls`).
pub async fn call_events(db: &sqlx::PgPool, call_id: Uuid) -> Result<Vec<CallEventRow>, AppError> {
    let sql = format!(
        "SELECT {CALL_EVENT_COLUMNS} FROM calling.call_events \
         WHERE call_id = $1 ORDER BY occurred_at ASC, id ASC"
    );
    let rows = sqlx::query_as::<_, CallEventRow>(&sql)
        .bind(call_id)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

// ----- Call-events read model (timeline) writes -----

/// Append one timeline event for a call (admin read model). IDEMPOTENT for the once-per-call
/// lifecycle milestones: they pass `dedupe_key = Some("<call_id>:<event_type>")` and a duplicate
/// INSERT is silently ignored (`ON CONFLICT DO NOTHING` on the partial unique index). Repeatable
/// signaling steps (offer/answer/ice_candidate/peer_offline) pass `dedupe_key = None` and always
/// append. Bound to a caller-supplied `Executor` so it can run inside the SAME transaction as a
/// state change (lifecycle milestones) or standalone on the pool (the WS relay's signaling steps).
async fn insert_call_event<'e, E>(
    exec: E,
    call_id: Uuid,
    event_type: &str,
    actor_id: Option<Uuid>,
    detail: Option<&Value>,
    dedupe_key: Option<String>,
) -> Result<(), AppError>
where
    E: sqlx::Executor<'e, Database = sqlx::Postgres>,
{
    sqlx::query(
        "INSERT INTO calling.call_events (call_id, event_type, actor_id, detail, dedupe_key) \
         VALUES ($1, $2, $3, $4, $5) ON CONFLICT (dedupe_key) DO NOTHING",
    )
    .bind(call_id)
    .bind(event_type)
    .bind(actor_id)
    .bind(detail)
    .bind(dedupe_key)
    .execute(exec)
    .await?;
    Ok(())
}

/// Record a once-per-call LIFECYCLE milestone (ringing/accepted/rejected/connected/ended/missed)
/// inside a state-change transaction. The `dedupe_key` makes a retried/replayed control call a
/// no-op (the lifecycle event is written at most once per call). A timeline-write failure must
/// NOT abort the authoritative state change, so this is best-effort within the tx: it returns
/// `Ok(())` even on a write error (logged) — the call_logs UPDATE + outbox event are the source of
/// truth; the read model is derived/advisory. (A unique-violation is already swallowed by
/// `ON CONFLICT`; this guards the rarer infra error.)
async fn record_lifecycle(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    call_id: Uuid,
    event_type: &str,
    actor_id: Option<Uuid>,
    detail: Option<Value>,
) {
    let dedupe = Some(format!("{call_id}:{event_type}"));
    if let Err(e) = insert_call_event(
        &mut **tx,
        call_id,
        event_type,
        actor_id,
        detail.as_ref(),
        dedupe,
    )
    .await
    {
        tracing::warn!(%call_id, event_type, "call-events timeline write failed (non-fatal): {e}");
    }
}

/// Record a SIGNALING step the WS relay observed (offer/answer/ice_candidate/peer_offline),
/// standalone on the pool. Best-effort: a failure here never breaks signal relaying (the read
/// model is advisory). `dedupe_key = None` → these always append (ICE trickles many candidates).
pub async fn record_signal_event(
    db: &sqlx::PgPool,
    call_id: Uuid,
    event_type: &str,
    actor_id: Option<Uuid>,
    detail: Option<Value>,
) {
    if let Err(e) =
        insert_call_event(db, call_id, event_type, actor_id, detail.as_ref(), None).await
    {
        tracing::warn!(%call_id, event_type, "call-events signal write failed (non-fatal): {e}");
    }
}

// ----- Writes -----

/// Initiate a call: reject if the callee is already in an active call, else INSERT the
/// `initiated` row AND enqueue `calling.initiated` — in ONE transaction. `callee_id` is the
/// booking's other participant (derived by the handler), never client-supplied.
#[tracing::instrument(skip(db), fields(caller_id = %caller_id, callee_id = %callee_id, booking_id = %booking_id))]
pub async fn initiate(
    db: &sqlx::PgPool,
    caller_id: Uuid,
    callee_id: Uuid,
    booking_id: Uuid,
    call_type: &str,
    correlation_id: Uuid,
) -> Result<CallResponse, AppError> {
    let mut tx = db.begin().await?;

    // Serialize concurrent initiations against the SAME callee. Without this, two concurrent
    // dials both pass the busy SELECT below under READ COMMITTED (neither sees the other's
    // uncommitted row) and both COMMIT → two simultaneous `initiated` calls. The transaction-
    // scoped advisory lock (keyed on callee_id) makes the busy check-then-INSERT atomic per
    // callee; it auto-releases at tx end (commit OR rollback), so no row/index is needed.
    sqlx::query("SELECT pg_advisory_xact_lock(hashtext($1::text))")
        .bind(callee_id)
        .execute(&mut *tx)
        .await?;

    // Busy guard: de-dupe rapid re-rings — a fresh dial within a 30s window of the callee's
    // last active call is refused. The window is intentionally bounded (anchored on
    // `started_at`) so a dead client mid-call can NEVER permanently lock the callee out; it is
    // NOT a full active-call lock (a >30s call no longer blocks). Mirrors v1's ring de-dupe.
    let busy: Option<Uuid> = sqlx::query_scalar(&format!(
        "SELECT id FROM calling.call_logs \
         WHERE callee_id = $1 AND status IN {ACTIVE_STATUSES} \
           AND started_at > now() - INTERVAL '30 seconds' LIMIT 1"
    ))
    .bind(callee_id)
    .fetch_optional(&mut *tx)
    .await?;
    if busy.is_some() {
        tx.rollback().await?;
        return Err(AppError::Conflict("Callee is busy".to_string()));
    }

    let sql = format!(
        "INSERT INTO calling.call_logs (caller_id, callee_id, booking_id, call_type, status) \
         VALUES ($1, $2, $3, $4::calling.call_type, 'initiated'::calling.call_status) \
         RETURNING {CALL_COLUMNS}"
    );
    let call = sqlx::query_as::<_, CallResponse>(&sql)
        .bind(caller_id)
        .bind(callee_id)
        .bind(booking_id)
        .bind(call_type)
        .fetch_one(&mut *tx)
        .await?;

    enqueue_event(&mut tx, topics::CALLING_INITIATED, &call, correlation_id).await?;
    // Timeline: the call is now ringing the callee. Same tx as the call_logs INSERT.
    record_lifecycle(&mut tx, call.id, "ringing", Some(caller_id), None).await;
    tx.commit().await?;
    Ok(call)
}

/// A participant action on a call. Each maps to a target [`CallStatus`] + the event it emits.
enum CallAction {
    Accept,
    Reject,
    Connected,
    End { reason: String },
}

/// Callee accepts a ringing call: `initiated → accepted` (+ `answered_at`), emit `accepted`.
pub async fn accept(
    db: &sqlx::PgPool,
    id: Uuid,
    actor: Uuid,
    corr: Uuid,
) -> Result<CallResponse, AppError> {
    apply_transition(db, id, actor, CallAction::Accept, corr).await
}

/// Callee rejects a ringing call: `initiated → rejected`, emit `rejected`.
pub async fn reject(
    db: &sqlx::PgPool,
    id: Uuid,
    actor: Uuid,
    corr: Uuid,
) -> Result<CallResponse, AppError> {
    apply_transition(db, id, actor, CallAction::Reject, corr).await
}

/// Either participant reports media connected: `accepted → connected`. A media milestone —
/// no cross-service event. (`corr` is unused; generated fresh for the uniform signature.)
pub async fn mark_connected(
    db: &sqlx::PgPool,
    id: Uuid,
    actor: Uuid,
) -> Result<CallResponse, AppError> {
    apply_transition(db, id, actor, CallAction::Connected, Uuid::new_v4()).await
}

/// Either participant ends a call: `initiated → missed`, else `→ ended`; computes
/// `duration_seconds` when answered; emit `ended`.
pub async fn end(
    db: &sqlx::PgPool,
    id: Uuid,
    actor: Uuid,
    reason: &str,
    corr: Uuid,
) -> Result<CallResponse, AppError> {
    apply_transition(
        db,
        id,
        actor,
        CallAction::End {
            reason: reason.to_string(),
        },
        corr,
    )
    .await
}

/// Apply a participant action: lock the row, authorize the actor, validate the move against
/// the PURE domain state machine ([`can_transition`]/[`end_target`] are the single source of
/// truth — the SQL never re-encodes the rules), write the new status (+ timestamps), and emit
/// the mapped event — all in ONE transaction.
async fn apply_transition(
    db: &sqlx::PgPool,
    id: Uuid,
    actor: Uuid,
    action: CallAction,
    correlation_id: Uuid,
) -> Result<CallResponse, AppError> {
    let mut tx = db.begin().await?;

    // Lock the row + read the authoritative current state.
    let row: Option<(Uuid, Uuid, String)> = sqlx::query_as(
        "SELECT caller_id, callee_id, status::text FROM calling.call_logs WHERE id = $1 FOR UPDATE",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await?;
    let (caller, callee, status_text) =
        row.ok_or_else(|| AppError::NotFound("Call not found".to_string()))?;
    let current = status_text.parse::<CallStatus>().map_err(|e| {
        tracing::error!("call status decode failed: {e}");
        AppError::Internal("call state decode error".to_string())
    })?;

    // Participant authz (IDOR): only the two participants can drive a call.
    if actor != caller && actor != callee {
        tx.rollback().await?;
        return Err(AppError::Forbidden(
            "Not a participant of this call".to_string(),
        ));
    }

    // Resolve the target status + the event (if any) + the end_reason for terminal moves.
    let (target, topic, reason): (CallStatus, Option<&str>, Option<String>) = match &action {
        CallAction::Accept => {
            if actor != callee {
                tx.rollback().await?;
                return Err(AppError::Forbidden(
                    "Only the callee can accept".to_string(),
                ));
            }
            (CallStatus::Accepted, Some(topics::CALLING_ACCEPTED), None)
        }
        CallAction::Reject => {
            if actor != callee {
                tx.rollback().await?;
                return Err(AppError::Forbidden(
                    "Only the callee can reject".to_string(),
                ));
            }
            (
                CallStatus::Rejected,
                Some(topics::CALLING_REJECTED),
                Some("rejected_by_callee".to_string()),
            )
        }
        CallAction::Connected => (CallStatus::Connected, None, None),
        CallAction::End { reason } => {
            let target = end_target(current)
                .ok_or_else(|| AppError::Conflict("Call already ended".to_string()))?;
            (target, Some(topics::CALLING_ENDED), Some(reason.clone()))
        }
    };

    // Legality — the pure machine is authoritative.
    if !can_transition(current, target) {
        tx.rollback().await?;
        return Err(AppError::Conflict(format!(
            "illegal call transition {current} → {target}"
        )));
    }

    let is_terminal = target.is_terminal();
    let set_answered = target == CallStatus::Accepted;
    let sql = format!(
        "UPDATE calling.call_logs SET \
             status = $2::calling.call_status, \
             answered_at = CASE WHEN $3 THEN now() ELSE answered_at END, \
             ended_at = CASE WHEN $4 THEN now() ELSE ended_at END, \
             end_reason = CASE WHEN $4 THEN $5 ELSE end_reason END, \
             duration_seconds = CASE WHEN $4 AND answered_at IS NOT NULL \
                 THEN GREATEST(0, EXTRACT(EPOCH FROM (now() - answered_at))::INTEGER) \
                 ELSE duration_seconds END, \
             updated_at = now() \
         WHERE id = $1 \
         RETURNING {CALL_COLUMNS}"
    );
    let call = sqlx::query_as::<_, CallResponse>(&sql)
        .bind(id)
        .bind(target.as_db_str())
        .bind(set_answered)
        .bind(is_terminal)
        .bind(&reason)
        .fetch_one(&mut *tx)
        .await?;

    if let Some(topic) = topic {
        enqueue_event(&mut tx, topic, &call, correlation_id).await?;
    }

    // Timeline: the target status IS the lifecycle event_type (accepted/rejected/connected/
    // ended/missed). Carry the end_reason for terminal moves. Same tx as the call_logs UPDATE;
    // de-duped per (call, event_type) so a retried control call doesn't double-append.
    let detail = reason.map(|r| serde_json::json!({ "end_reason": r }));
    record_lifecycle(&mut tx, id, target.as_db_str(), Some(actor), detail).await;

    tx.commit().await?;
    Ok(call)
}

/// Build + insert the `calling.*` event for a call into the outbox (same tx). Payload carries
/// the AsyncAPI-required `{ call_id, booking_id }` plus `caller_id`/`callee_id` so the
/// notification mapper can route incoming/missed-call pushes to the right recipient, and
/// `call_type` so the rung CALLEE's app opens the call as audio vs video (the mobile defaults to
/// audio only when this is absent — a video call would mis-init without it).
///
/// On the TERMINAL events (`calling.ended` / `.rejected`) the payload also carries
/// `duration_seconds`, `answered_at` and `end_reason` so the chat call-summary consumer can build
/// the pinned summary JSON: it derives the outcome (`completed` when answered — `answered_at`
/// present / `duration_seconds > 0`; `rejected` when status/end_reason indicate a decline;
/// otherwise `missed`) and the duration WITHOUT a follow-up read of calling's schema (v2 forbids
/// cross-schema reads). These are `null` on the non-terminal events (initiated/accepted), which is
/// correct — the consumer only summarizes terminal calls.
async fn enqueue_event(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    topic: &str,
    call: &CallResponse,
    correlation_id: Uuid,
) -> Result<(), AppError> {
    let payload = serde_json::json!({
        "call_id": call.id,
        "booking_id": call.booking_id,
        "caller_id": call.caller_id,
        "callee_id": call.callee_id,
        "call_type": call.call_type,
        "status": call.status,
        "duration_seconds": call.duration_seconds,
        "answered_at": call.answered_at,
        "end_reason": call.end_reason,
    });
    let envelope = EventEnvelope::new(topic, correlation_id, payload);
    let envelope_json = serde_json::to_value(&envelope)
        .map_err(|e| AppError::Internal(format!("serialize event envelope: {e}")))?;
    sqlx::query("INSERT INTO calling.outbox (topic, payload) VALUES ($1, $2)")
        .bind(topic)
        .bind(&envelope_json)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

// ----- Outbox relay support -----

pub async fn fetch_unpublished(db: &sqlx::PgPool, limit: i64) -> Result<Vec<OutboxRow>, AppError> {
    let rows = sqlx::query_as::<_, OutboxRow>(
        "SELECT id, topic, payload FROM calling.outbox \
         WHERE published_at IS NULL ORDER BY created_at LIMIT $1",
    )
    .bind(limit)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

pub async fn mark_published(db: &sqlx::PgPool, id: Uuid) -> Result<(), AppError> {
    sqlx::query("UPDATE calling.outbox SET published_at = now() WHERE id = $1")
        .bind(id)
        .execute(db)
        .await?;
    Ok(())
}

#[cfg(test)]
mod db_tests {
    use super::*;
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;

    async fn pool() -> Option<sqlx::PgPool> {
        let url = std::env::var("DATABASE_URL").ok()?;
        PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .ok()
    }

    /// initiate → accept → end, each emitting exactly one `calling.*` outbox event; a
    /// non-participant end is rejected. DATABASE_URL-gated.
    #[tokio::test]
    async fn lifecycle_emits_events_and_guards_participants() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let caller = Uuid::new_v4();
        let callee = Uuid::new_v4();
        let booking = Uuid::new_v4();
        let stranger = Uuid::new_v4();
        let corr = Uuid::new_v4();

        let call = initiate(&pool, caller, callee, booking, "audio", corr)
            .await
            .expect("initiate");
        assert_eq!(call.status, "initiated");

        // A stranger cannot end the call (not a participant) → Forbidden (explicit IDOR check).
        assert!(matches!(
            end(&pool, call.id, stranger, "hangup", corr).await,
            Err(AppError::Forbidden(_))
        ));

        // Callee accepts → accepted + answered_at.
        let accepted = accept(&pool, call.id, callee, corr).await.expect("accept");
        assert_eq!(accepted.status, "accepted");
        assert!(accepted.answered_at.is_some());

        // Caller ends → ended, with a duration (answered).
        let ended = end(&pool, call.id, caller, "hangup", corr)
            .await
            .expect("end");
        assert_eq!(ended.status, "ended");
        assert!(ended.duration_seconds.is_some());

        // exactly 3 events: initiated, accepted, ended.
        let count: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM calling.outbox WHERE payload->'payload'->>'call_id' = $1",
        )
        .bind(call.id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count");
        assert_eq!(count, 3, "initiated + accepted + ended");

        cleanup(&pool, call.id).await;
    }

    /// Ending a never-answered call yields `missed` (not `ended`) with no duration.
    #[tokio::test]
    async fn end_before_answer_is_missed() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let caller = Uuid::new_v4();
        let callee = Uuid::new_v4();
        let corr = Uuid::new_v4();
        let call = initiate(&pool, caller, callee, Uuid::new_v4(), "video", corr)
            .await
            .expect("initiate");
        let ended = end(&pool, call.id, caller, "cancelled", corr)
            .await
            .expect("end");
        assert_eq!(ended.status, "missed");
        assert!(ended.duration_seconds.is_none());
        cleanup(&pool, call.id).await;
    }

    /// reject (callee-only) → rejected + one event; the CALLER cannot accept/reject (callee
    /// gate); and a second initiate to a ringing callee is refused (busy). DATABASE_URL-gated.
    #[tokio::test]
    async fn reject_and_callee_gate_and_busy() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let caller = Uuid::new_v4();
        let callee = Uuid::new_v4();
        let corr = Uuid::new_v4();
        let call = initiate(&pool, caller, callee, Uuid::new_v4(), "audio", corr)
            .await
            .expect("initiate");

        // A second dial to the (ringing) callee is refused as busy.
        assert!(matches!(
            initiate(&pool, Uuid::new_v4(), callee, Uuid::new_v4(), "audio", corr).await,
            Err(AppError::Conflict(_))
        ));

        // The CALLER cannot accept/reject — only the callee may (403).
        assert!(matches!(
            accept(&pool, call.id, caller, corr).await,
            Err(AppError::Forbidden(_))
        ));
        assert!(matches!(
            reject(&pool, call.id, caller, corr).await,
            Err(AppError::Forbidden(_))
        ));

        // The callee rejects → rejected + reason; exactly one calling.rejected event.
        let rejected = reject(&pool, call.id, callee, corr).await.expect("reject");
        assert_eq!(rejected.status, "rejected");
        assert_eq!(rejected.end_reason.as_deref(), Some("rejected_by_callee"));

        // A rejected (terminal) call admits no further action.
        assert!(matches!(
            accept(&pool, call.id, callee, corr).await,
            Err(AppError::Conflict(_))
        ));

        let events: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM calling.outbox \
             WHERE topic = $1 AND payload->'payload'->>'call_id' = $2",
        )
        .bind(topics::CALLING_REJECTED)
        .bind(call.id.to_string())
        .fetch_one(&pool)
        .await
        .expect("count rejected events");
        assert_eq!(events, 1, "exactly one calling.rejected event");

        cleanup(&pool, call.id).await;
    }

    /// The call-events read model records the lifecycle timeline (ringing → accepted →
    /// connected → ended), de-duped per (call, event_type), AND the WS relay's signaling steps
    /// append (offer/answer/ice_candidate, no dedupe). DATABASE_URL-gated.
    #[tokio::test]
    async fn timeline_records_lifecycle_and_signaling_idempotently() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let caller = Uuid::new_v4();
        let callee = Uuid::new_v4();
        let corr = Uuid::new_v4();

        let call = initiate(&pool, caller, callee, Uuid::new_v4(), "audio", corr)
            .await
            .expect("initiate");
        accept(&pool, call.id, callee, corr).await.expect("accept");
        mark_connected(&pool, call.id, callee)
            .await
            .expect("connected");
        end(&pool, call.id, caller, "hangup", corr)
            .await
            .expect("end");

        // Signaling steps the relay would record (offer once, two trickled candidates).
        record_signal_event(&pool, call.id, "offer", Some(caller), None).await;
        record_signal_event(&pool, call.id, "ice_candidate", Some(caller), None).await;
        record_signal_event(&pool, call.id, "ice_candidate", Some(callee), None).await;

        let events = call_events(&pool, call.id).await.expect("timeline");
        let types: Vec<&str> = events.iter().map(|e| e.event_type.as_str()).collect();
        // The four lifecycle milestones are present, in chronological order, exactly once each.
        assert_eq!(
            types
                .iter()
                .copied()
                .filter(|t| matches!(*t, "ringing" | "accepted" | "connected" | "ended"))
                .collect::<Vec<_>>(),
            vec!["ringing", "accepted", "connected", "ended"],
            "lifecycle milestones in order"
        );
        // Two ICE candidates appended (no dedupe on signaling steps).
        assert_eq!(
            types.iter().filter(|t| **t == "ice_candidate").count(),
            2,
            "trickled candidates both append"
        );

        // Idempotency: re-recording a lifecycle milestone (same call+type) is a no-op.
        record_lifecycle_for_test(&pool, call.id, "ended", Some(caller)).await;
        let after = call_events(&pool, call.id).await.expect("timeline 2");
        assert_eq!(
            after.iter().filter(|e| e.event_type == "ended").count(),
            1,
            "ended recorded at most once per call"
        );

        cleanup(&pool, call.id).await;
    }

    /// Test-only helper: drive a lifecycle insert through the SAME dedupe path the repo uses
    /// (standalone tx) to prove the once-per-call guard.
    async fn record_lifecycle_for_test(
        pool: &sqlx::PgPool,
        call_id: Uuid,
        event_type: &str,
        actor: Option<Uuid>,
    ) {
        let dedupe = Some(format!("{call_id}:{event_type}"));
        super::insert_call_event(pool, call_id, event_type, actor, None, dedupe)
            .await
            .expect("insert");
    }

    async fn cleanup(pool: &sqlx::PgPool, call_id: Uuid) {
        // call_events cascades on the call_logs delete (FK ON DELETE CASCADE), but delete
        // explicitly too in case the FK isn't present in an older test DB.
        let _ = sqlx::query("DELETE FROM calling.call_events WHERE call_id = $1")
            .bind(call_id)
            .execute(pool)
            .await;
        let _ = sqlx::query("DELETE FROM calling.outbox WHERE payload->'payload'->>'call_id' = $1")
            .bind(call_id.to_string())
            .execute(pool)
            .await;
        let _ = sqlx::query("DELETE FROM calling.call_logs WHERE id = $1")
            .bind(call_id)
            .execute(pool)
            .await;
    }
}
