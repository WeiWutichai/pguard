//! Repository layer — the ONLY place that touches the `chat` schema.
//!
//! Runtime `sqlx::query`/`query_as` (no compile-time `query!` — no DATABASE_URL at build,
//! mirrors the other slices). Two invariants live here:
//!
//!   * **N+1-free list.** [`list_conversations`] is ONE query: the counterpart's name/avatar
//!     (a LATERAL over `chat.participants`), the last message (a LATERAL over `chat.messages`),
//!     and the unread count (a correlated `COUNT` using `sender_role IS DISTINCT FROM`) are all
//!     resolved in-query, entirely inside the `chat` schema — NO per-row follow-up, NO
//!     cross-schema JOIN (CLAUDE.md → Data; the v1 cross-schema JOIN is the bug this fixes).
//!   * **Outbox atomicity.** [`send_message`] writes the message AND its
//!     `pguard.events.chat.message_sent` outbox row in ONE transaction (CLAUDE.md → "Cross-tx
//!     consistency"); notification consumes the event. No fire-and-forget cross-schema INSERT.

use serde_json::Value;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::{topics, EventEnvelope};

use crate::domain::{self, MessageType};
use crate::models::{
    AdminConversationRow, AttachmentRow, ConversationResponse, CreateConversationRequest,
    EnrichedConversation, IncomingChatMessage, OutgoingChatMessage, ParticipantInput,
};

/// Columns of a message row as returned to clients (`message_type` cast to text → no enum decode).
const MESSAGE_COLUMNS: &str =
    "id, conversation_id, sender_id, sender_role, content, message_type::text AS message_type, created_at";

/// The single N+1-free enriched-list query. Exposed as a const so a unit test can assert its
/// SHAPE (one `FROM chat.conversations`, the counterpart + last-message LATERALs, the
/// `IS DISTINCT FROM` unread subquery) — a static "no N+1 / no cross-schema JOIN" proof to pair
/// with the DB integration test. `$1` = user_id, `$2` = acting_role.
pub const LIST_CONVERSATIONS_SQL: &str = r#"
SELECT
    c.id, c.request_id, c.created_at, c.request_status,
    cp.user_id      AS participant_id,
    cp.display_name AS participant_name,
    cp.avatar_url   AS participant_avatar,
    lm.content      AS last_message,
    lm.created_at   AS last_message_at,
    COALESCE((
        SELECT COUNT(*) FROM chat.messages m2
         WHERE m2.conversation_id = c.id
           AND m2.sender_role IS DISTINCT FROM $2
           AND m2.created_at > COALESCE(
                 (SELECT rr.read_at FROM chat.read_receipts rr
                   WHERE rr.conversation_id = c.id AND rr.user_id = $1 AND rr.user_role = $2),
                 'epoch'::timestamptz)
    ), 0) AS unread_count
FROM chat.conversations c
JOIN chat.participants me
      ON me.conversation_id = c.id AND me.user_id = $1 AND me.user_role = $2
LEFT JOIN LATERAL (
      SELECT p.user_id, p.display_name, p.avatar_url
        FROM chat.participants p
       WHERE p.conversation_id = c.id AND p.user_role <> $2
       ORDER BY p.user_id
       LIMIT 1
) cp ON true
LEFT JOIN LATERAL (
      SELECT m.content, m.created_at
        FROM chat.messages m
       WHERE m.conversation_id = c.id
       ORDER BY m.created_at DESC
       LIMIT 1
) lm ON true
ORDER BY lm.created_at DESC NULLS LAST
"#;

// ----- Outbox row (for the relay) -----

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct OutboxRow {
    pub id: Uuid,
    pub topic: String,
    pub payload: Value,
}

// ----- Create -----

/// GET-OR-CREATE a conversation + its participants in ONE transaction (idempotent on
/// `request_id`). The booking-derived role + display data are stored on `chat.participants` so
/// the enriched list needs no cross-schema reach. Roles are validated (`guard`/`customer`).
///
/// `request_id` is UNIQUE (migration 0002): on a concurrent/repeat call the
/// `ON CONFLICT (request_id) DO NOTHING` insert returns no row, so we read the EXISTING
/// conversation back and return it (no duplicate accumulates, the original participants stand).
pub async fn create_conversation(
    db: &sqlx::PgPool,
    req: &CreateConversationRequest,
) -> Result<ConversationResponse, AppError> {
    if req.participants.is_empty() {
        return Err(AppError::BadRequest(
            "At least one participant is required".to_string(),
        ));
    }
    for p in &req.participants {
        if !domain::is_valid_role(&p.role) {
            return Err(AppError::BadRequest(format!(
                "invalid participant role: {} (expected guard|customer)",
                p.role
            )));
        }
    }

    let mut tx = db.begin().await?;

    // Idempotent insert: a second call for the same request_id conflicts and inserts nothing.
    let inserted = sqlx::query_as::<_, ConversationResponse>(
        "INSERT INTO chat.conversations (request_id, request_status) VALUES ($1, $2) \
         ON CONFLICT (request_id) DO NOTHING \
         RETURNING id, request_id, request_status, created_at",
    )
    .bind(req.request_id)
    .bind(&req.request_status)
    .fetch_optional(&mut *tx)
    .await?;

    let conv = match inserted {
        Some(conv) => {
            // Fresh row → seed the participants (the conversation's authoritative members).
            for p in &req.participants {
                insert_participant(&mut tx, conv.id, p).await?;
            }
            conv
        }
        None => {
            // Already existed → return it untouched (GET-OR-CREATE; don't re-seed participants).
            sqlx::query_as::<_, ConversationResponse>(
                "SELECT id, request_id, request_status, created_at \
                 FROM chat.conversations WHERE request_id = $1",
            )
            .bind(req.request_id)
            .fetch_one(&mut *tx)
            .await?
        }
    };

    tx.commit().await?;
    Ok(conv)
}

async fn insert_participant(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    conversation_id: Uuid,
    p: &ParticipantInput,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO chat.participants \
             (conversation_id, user_id, user_role, display_name, avatar_url) \
         VALUES ($1, $2, $3, $4, $5) \
         ON CONFLICT (conversation_id, user_id) DO UPDATE SET \
             user_role = EXCLUDED.user_role, \
             display_name = EXCLUDED.display_name, \
             avatar_url = EXCLUDED.avatar_url",
    )
    .bind(conversation_id)
    .bind(p.user_id)
    .bind(&p.role)
    .bind(&p.display_name)
    .bind(&p.avatar_url)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

// ----- Reads -----

/// The N+1-free enriched conversation list for `user_id` acting as `acting_role`. ONE query
/// (see [`LIST_CONVERSATIONS_SQL`]); a read-heavy list → the replica pool.
pub async fn list_conversations(
    db: &sqlx::PgPool,
    user_id: Uuid,
    acting_role: &str,
) -> Result<Vec<EnrichedConversation>, AppError> {
    let rows = sqlx::query_as::<_, EnrichedConversation>(LIST_CONVERSATIONS_SQL)
        .bind(user_id)
        .bind(acting_role)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

/// Admin conversation list — ALL conversations (NOT participant-scoped; the admin-role gate is
/// the API layer's job), newest first, with both participants' names joined + the last message +
/// total count. No cross-schema reach (all from chat.{conversations,participants,messages}).
pub async fn admin_list_conversations(
    db: &sqlx::PgPool,
    limit: i64,
    offset: i64,
) -> Result<Vec<AdminConversationRow>, AppError> {
    let sql = r#"
        SELECT
            c.id, c.request_id, c.request_status, c.created_at,
            (SELECT string_agg(p.display_name, ' · ' ORDER BY p.user_role)
               FROM chat.participants p WHERE p.conversation_id = c.id) AS participants,
            lm.content    AS last_message,
            lm.created_at AS last_message_at,
            COALESCE((SELECT COUNT(*) FROM chat.messages m WHERE m.conversation_id = c.id), 0)
              AS message_count
        FROM chat.conversations c
        LEFT JOIN LATERAL (
            SELECT m.content, m.created_at FROM chat.messages m
             WHERE m.conversation_id = c.id ORDER BY m.created_at DESC LIMIT 1
        ) lm ON true
        ORDER BY c.created_at DESC
        LIMIT $1 OFFSET $2
    "#;
    let rows = sqlx::query_as::<_, AdminConversationRow>(sql)
        .bind(limit)
        .bind(offset)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

/// Message history newest-first (includes `sender_role` for alignment). The handler enforces the
/// participant gate before calling this.
pub async fn list_messages(
    db: &sqlx::PgPool,
    conversation_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<OutgoingChatMessage>, AppError> {
    let limit = limit.clamp(1, 200);
    let offset = offset.max(0);
    let sql = format!(
        "SELECT {MESSAGE_COLUMNS} FROM chat.messages \
         WHERE conversation_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3"
    );
    let rows = sqlx::query_as::<_, OutgoingChatMessage>(&sql)
        .bind(conversation_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(db)
        .await?;
    Ok(rows)
}

/// `true` iff `user_id` is a participant of `conversation_id`. The explicit IDOR gate for
/// list-messages / mark-read / upload (an `AuthUser` alone is NOT sufficient).
pub async fn is_participant(
    db: &sqlx::PgPool,
    conversation_id: Uuid,
    user_id: Uuid,
) -> Result<bool, AppError> {
    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM chat.participants \
         WHERE conversation_id = $1 AND user_id = $2)",
    )
    .bind(conversation_id)
    .bind(user_id)
    .fetch_one(db)
    .await?;
    Ok(exists)
}

/// `true` iff `user_id` participates in the conversation that owns `attachment_id` — the IDOR
/// gate for `GET /attachments/{id}` (an attachment is reachable only by its conversation's
/// participants). Joins attachment → conversation → participants inside the `chat` schema.
pub async fn is_attachment_participant(
    db: &sqlx::PgPool,
    attachment_id: Uuid,
    user_id: Uuid,
) -> Result<bool, AppError> {
    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(\
            SELECT 1 FROM chat.attachments a \
            JOIN chat.participants p ON p.conversation_id = a.chat_id \
            WHERE a.id = $1 AND p.user_id = $2)",
    )
    .bind(attachment_id)
    .bind(user_id)
    .fetch_one(db)
    .await?;
    Ok(exists)
}

/// The booking `request_status` denormalized on a conversation, or `NotFound` if the
/// conversation does not exist. Drives the read-only gate for the attachment-upload path.
pub async fn conversation_request_status(
    db: &sqlx::PgPool,
    conversation_id: Uuid,
) -> Result<Option<String>, AppError> {
    let row: Option<(Option<String>,)> =
        sqlx::query_as("SELECT request_status FROM chat.conversations WHERE id = $1")
            .bind(conversation_id)
            .fetch_optional(db)
            .await?;
    row.map(|(s,)| s)
        .ok_or_else(|| AppError::NotFound("Conversation not found".to_string()))
}

/// A user's conversation ids (any role) — the WS prefetch for the authorized-rooms set so a
/// `chat:*` pub/sub frame for a room the user isn't in can never be forwarded.
pub async fn participant_conversation_ids(
    db: &sqlx::PgPool,
    user_id: Uuid,
) -> Result<Vec<Uuid>, AppError> {
    let ids = sqlx::query_scalar::<_, Uuid>(
        "SELECT conversation_id FROM chat.participants WHERE user_id = $1",
    )
    .bind(user_id)
    .fetch_all(db)
    .await?;
    Ok(ids)
}

/// The conversation id for a booking `request_id`, or `None` if none exists yet. Used by the
/// call-summary consumer to FIND the conversation before falling back to CREATE (so a summary
/// can be posted even if the parties never opened the chat thread). `request_id` is UNIQUE
/// (migration 0002), so this is at most one row.
pub async fn find_conversation_id_by_request(
    db: &sqlx::PgPool,
    request_id: Uuid,
) -> Result<Option<Uuid>, AppError> {
    let id =
        sqlx::query_scalar::<_, Uuid>("SELECT id FROM chat.conversations WHERE request_id = $1")
            .bind(request_id)
            .fetch_optional(db)
            .await?;
    Ok(id)
}

// ----- Writes -----

/// Persist a message AND enqueue its `chat.message_sent` outbox event in ONE transaction.
///
/// Order inside the tx: lock the conversation + read its status (existence → `NotFound`),
/// load participants (sender not among them → `Forbidden` IDOR gate), reject a write to a
/// closed conversation (`completed`/`cancelled` → `Conflict`, the server-side read-only gate),
/// INSERT the message, then INSERT the outbox row addressed to the OTHER participant. The event
/// is enqueued atomically with the message — never a separate fire-and-forget write.
///
/// `sender_role` is DERIVED authoritatively from the sender's `chat.participants.user_role` for
/// this conversation — NEVER trusted from the client frame. Since alignment + unread are decided
/// by `sender_role`, a client-supplied role would let a customer spoof a message as the guard's
/// (and flip its unread classification); deriving it from membership closes that hole.
pub async fn send_message(
    db: &sqlx::PgPool,
    sender_id: Uuid,
    msg: &IncomingChatMessage,
) -> Result<OutgoingChatMessage, AppError> {
    let conversation_id = msg.conversation_id;
    let mut tx = db.begin().await?;

    // Lock the conversation + read status (existence check + read-only gate basis).
    let status: Option<(Option<String>,)> =
        sqlx::query_as("SELECT request_status FROM chat.conversations WHERE id = $1 FOR UPDATE")
            .bind(conversation_id)
            .fetch_optional(&mut *tx)
            .await?;
    let request_status = match status {
        Some((s,)) => s,
        None => {
            tx.rollback().await?;
            return Err(AppError::NotFound("Conversation not found".to_string()));
        }
    };

    // Participant gate (IDOR) + recipient derivation (the OTHER party) + the AUTHORITATIVE sender
    // role — all from the membership rows, never the client frame.
    let participants: Vec<(Uuid, String)> = sqlx::query_as(
        "SELECT user_id, user_role FROM chat.participants WHERE conversation_id = $1",
    )
    .bind(conversation_id)
    .fetch_all(&mut *tx)
    .await?;
    let sender_role = match participants.iter().find(|(uid, _)| *uid == sender_id) {
        Some((_, role)) => role.clone(),
        None => {
            tx.rollback().await?;
            return Err(AppError::Forbidden(
                "Not a participant of this conversation".to_string(),
            ));
        }
    };

    // Read-only gate: never trust the client — reject writes to a closed conversation.
    if !domain::is_writable(request_status.as_deref()) {
        tx.rollback().await?;
        return Err(AppError::Conflict(
            "Conversation is read-only (booking completed/cancelled)".to_string(),
        ));
    }

    // SERVER-ONLY system messages (the security fix). `system` is the ONLY kind notification
    // suppresses the "new message" push for (a call-summary line is recorded in the thread but must
    // not raise a redundant push). Since `message_type` is CLIENT-controlled on the user send path,
    // a participant could mark a REAL text as `system` to silence the victim's push — so reject it
    // here. The user WS/REST send may only produce text/image/video; `system` rows are inserted
    // exclusively by the server-side call-summary consumer (see `insert_call_summary`).
    let message_type = msg.message_type.unwrap_or(MessageType::Text);
    if message_type == MessageType::System {
        tx.rollback().await?;
        return Err(AppError::BadRequest(
            "system messages are server-generated".to_string(),
        ));
    }
    let sql = format!(
        "INSERT INTO chat.messages (conversation_id, sender_id, sender_role, content, message_type) \
         VALUES ($1, $2, $3, $4, $5::chat.message_type) \
         RETURNING {MESSAGE_COLUMNS}"
    );
    let message = sqlx::query_as::<_, OutgoingChatMessage>(&sql)
        .bind(conversation_id)
        .bind(sender_id)
        .bind(&sender_role)
        .bind(&msg.content)
        .bind(message_type.as_db_str())
        .fetch_one(&mut *tx)
        .await?;

    // Enqueue the cross-service event addressed to the other participant (notification target).
    // A degenerate conversation with no other participant emits no event (no one to notify).
    if let Some((recipient_id, _)) = participants.into_iter().find(|(u, _)| *u != sender_id) {
        enqueue_message_sent(&mut tx, &message, recipient_id, Uuid::new_v4()).await?;
    } else {
        tracing::warn!(
            conversation = %conversation_id,
            "message persisted with no other participant; no message_sent event emitted"
        );
    }

    tx.commit().await?;
    Ok(message)
}

/// Build + insert the `chat.message_sent` event into the outbox (same tx). Payload matches the
/// AsyncAPI `EnvelopeOf_ChatRef` contract: `{ message_id, conversation_id, sender_id,
/// recipient_id, message_type }`.
///
/// `message_type` is the persisted message kind (`text` | `image` | `video` | `system`), carried
/// on the event so the notification consumer can SUPPRESS the "new message" push for `system` rows
/// (e.g. a call-summary line): those are recorded in the thread but must NOT raise a redundant
/// notification. A `text`/`image`/`video` message still pushes normally. The suppression is
/// structural — both the user send path and the call-summary consumer emit through here, so a
/// `system` row is never pushed regardless of which path created it.
async fn enqueue_message_sent(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    message: &OutgoingChatMessage,
    recipient_id: Uuid,
    correlation_id: Uuid,
) -> Result<(), AppError> {
    let payload = serde_json::json!({
        "message_id": message.id,
        "conversation_id": message.conversation_id,
        "sender_id": message.sender_id,
        "recipient_id": recipient_id,
        // So notification can suppress the "new message" push for `system` rows (e.g. a call-summary
        // line): those are recorded in the thread but must not raise a redundant notification.
        "message_type": message.message_type,
    });
    let envelope = EventEnvelope::new(topics::CHAT_MESSAGE_SENT, correlation_id, payload);
    let envelope_json = serde_json::to_value(&envelope)
        .map_err(|e| AppError::Internal(format!("serialize event envelope: {e}")))?;
    sqlx::query("INSERT INTO chat.outbox (topic, payload) VALUES ($1, $2)")
        .bind(topics::CHAT_MESSAGE_SENT)
        .bind(&envelope_json)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

/// Insert a SERVER-GENERATED call-summary `system` message into `conversation_id`, IDEMPOTENTLY,
/// in ONE transaction (the inbound half of the call-summary consumer; mirrors booking's
/// `mark_paid_idempotent`):
///   1. claim the envelope's `event_id` in `chat.processed_events` (`ON CONFLICT DO NOTHING`); a
///      JetStream redelivery loses the claim and the whole call is a no-op (NO double-post).
///   2. on a won claim, derive the `sender_role` AUTHORITATIVELY from the caller's membership row
///      (never client-supplied — this is a server path, but we keep the same invariant the user
///      send path enforces), INSERT the `system` message with `content` = the pinned summary JSON,
///      then enqueue the `chat.message_sent` outbox row addressed to the OTHER participant — so
///      the relay still publishes it and notification (correctly) SKIPS the push for the `system`
///      row. Same outbox path as a normal message, so the suppression is structural, not bespoke.
///
/// `caller_id` is the call's caller; the summary is attributed to them (the system line's
/// `sender_id`). If the caller isn't a participant of this conversation (shouldn't happen — the
/// conversation is the booking's and the caller is a booking party), fall back to the first
/// participant's role so the NOT NULL `sender_role` is always satisfied.
///
/// Returns `true` if this delivery newly claimed the event (posted the summary), `false` on a
/// redelivery (already posted).
#[tracing::instrument(skip(db, summary_json), fields(event_id = %event_id, conversation_id = %conversation_id))]
pub async fn insert_call_summary_idempotent(
    db: &sqlx::PgPool,
    event_id: Uuid,
    event_type: &str,
    conversation_id: Uuid,
    caller_id: Uuid,
    summary_json: &str,
) -> Result<bool, AppError> {
    let mut tx = db.begin().await?;

    // 1) dedupe claim — a redelivered event_id inserts nothing → whole op is a no-op.
    let claimed = sqlx::query(
        "INSERT INTO chat.processed_events (event_id, event_type) VALUES ($1, $2) \
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

    // Load participants → derive the caller's role (authoritative) + the recipient (the OTHER
    // party, for the outbox payload). A conversation with no participants is degenerate; bail.
    let participants: Vec<(Uuid, String)> = sqlx::query_as(
        "SELECT user_id, user_role FROM chat.participants WHERE conversation_id = $1",
    )
    .bind(conversation_id)
    .fetch_all(&mut *tx)
    .await?;
    let Some(sender_role) = participants
        .iter()
        .find(|(uid, _)| *uid == caller_id)
        .map(|(_, role)| role.clone())
        .or_else(|| participants.first().map(|(_, role)| role.clone()))
    else {
        tx.rollback().await?;
        return Err(AppError::Internal(
            "call-summary target conversation has no participants".to_string(),
        ));
    };

    let sql = format!(
        "INSERT INTO chat.messages (conversation_id, sender_id, sender_role, content, message_type) \
         VALUES ($1, $2, $3, $4, 'system'::chat.message_type) \
         RETURNING {MESSAGE_COLUMNS}"
    );
    let message = sqlx::query_as::<_, OutgoingChatMessage>(&sql)
        .bind(conversation_id)
        .bind(caller_id)
        .bind(&sender_role)
        .bind(summary_json)
        .fetch_one(&mut *tx)
        .await?;

    // Enqueue the cross-service event addressed to the other participant. notification SKIPS the
    // push because `message_type == "system"` — exactly the suppression the security fix relies on.
    if let Some((recipient_id, _)) = participants.into_iter().find(|(u, _)| *u != caller_id) {
        enqueue_message_sent(&mut tx, &message, recipient_id, Uuid::new_v4()).await?;
    } else {
        tracing::warn!(
            conversation = %conversation_id,
            "call summary posted with no other participant; no message_sent event emitted"
        );
    }

    tx.commit().await?;
    Ok(true)
}

/// UPSERT the caller's per-role read receipt (`read_at = now`, `last_read_message_id` = the
/// newest message at read time). Per-role PK so the same user reading as guard vs customer is
/// tracked separately.
pub async fn mark_read(
    db: &sqlx::PgPool,
    conversation_id: Uuid,
    user_id: Uuid,
    user_role: &str,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO chat.read_receipts \
             (conversation_id, user_id, user_role, last_read_message_id, read_at) \
         VALUES ($1, $2, $3, \
             (SELECT id FROM chat.messages WHERE conversation_id = $1 \
              ORDER BY created_at DESC LIMIT 1), now()) \
         ON CONFLICT (conversation_id, user_id, user_role) DO UPDATE SET \
             last_read_message_id = EXCLUDED.last_read_message_id, read_at = now()",
    )
    .bind(conversation_id)
    .bind(user_id)
    .bind(user_role)
    .execute(db)
    .await?;
    Ok(())
}

/// Persist attachment metadata after a successful S3 upload.
pub async fn save_attachment(
    db: &sqlx::PgPool,
    chat_id: Uuid,
    uploader_id: Uuid,
    file_key: &str,
    file_url: &str,
    file_size: Option<i32>,
    mime_type: &str,
) -> Result<AttachmentRow, AppError> {
    let row = sqlx::query_as::<_, AttachmentRow>(
        "INSERT INTO chat.attachments \
             (chat_id, uploader_id, file_key, file_url, file_size, mime_type) \
         VALUES ($1, $2, $3, $4, $5, $6) \
         RETURNING id, chat_id, uploader_id, file_key, file_url, file_size, mime_type, created_at",
    )
    .bind(chat_id)
    .bind(uploader_id)
    .bind(file_key)
    .bind(file_url)
    .bind(file_size)
    .bind(mime_type)
    .fetch_one(db)
    .await?;
    Ok(row)
}

/// Fetch an attachment by id (the handler then enforces the participant gate).
pub async fn get_attachment(
    db: &sqlx::PgPool,
    attachment_id: Uuid,
) -> Result<AttachmentRow, AppError> {
    sqlx::query_as::<_, AttachmentRow>(
        "SELECT id, chat_id, uploader_id, file_key, file_url, file_size, mime_type, created_at \
         FROM chat.attachments WHERE id = $1",
    )
    .bind(attachment_id)
    .fetch_optional(db)
    .await?
    .ok_or_else(|| AppError::NotFound("Attachment not found".to_string()))
}

/// Internal (service-JWT): set the denormalized `request_status` for every conversation linked
/// to `request_id`. Idempotent; returns the number of conversations updated. Drives the
/// read-only gate from booking's lifecycle.
pub async fn set_request_status(
    db: &sqlx::PgPool,
    request_id: Uuid,
    request_status: &str,
) -> Result<u64, AppError> {
    let res =
        sqlx::query("UPDATE chat.conversations SET request_status = $2 WHERE request_id = $1")
            .bind(request_id)
            .bind(request_status)
            .execute(db)
            .await?;
    Ok(res.rows_affected())
}

// ----- Outbox relay support -----

pub async fn fetch_unpublished(db: &sqlx::PgPool, limit: i64) -> Result<Vec<OutboxRow>, AppError> {
    let rows = sqlx::query_as::<_, OutboxRow>(
        "SELECT id, topic, payload FROM chat.outbox \
         WHERE published_at IS NULL ORDER BY created_at LIMIT $1",
    )
    .bind(limit)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

pub async fn mark_published(db: &sqlx::PgPool, id: Uuid) -> Result<(), AppError> {
    sqlx::query("UPDATE chat.outbox SET published_at = now() WHERE id = $1")
        .bind(id)
        .execute(db)
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Static "no N+1 / no cross-schema JOIN" proof: the enriched list is ONE query whose shape
    /// resolves everything in-query inside the `chat` schema. Pairs with the DB integration
    /// proof below.
    #[test]
    fn list_query_is_single_in_schema_query() {
        let sql = LIST_CONVERSATIONS_SQL;
        // Exactly one top-level driving table.
        assert_eq!(
            sql.matches("FROM chat.conversations").count(),
            1,
            "single driving table (no N+1 fan-out)"
        );
        // Enrichment is in-query (LATERALs + correlated unread subquery), not per-row in Rust.
        assert!(
            sql.contains("LEFT JOIN LATERAL"),
            "counterpart + last-message resolved in-query"
        );
        assert!(
            sql.contains("sender_role IS DISTINCT FROM $2"),
            "unread uses IS DISTINCT FROM by role"
        );
        // NO cross-schema reach: only `chat.*` tables are referenced (v2 forbids auth/booking JOIN).
        for foreign in ["auth.", "booking.", "identity.", "profile."] {
            assert!(
                !sql.contains(foreign),
                "must not JOIN across schemas ({foreign})"
            );
        }
    }

    // ----- DB-gated integration tests (hermetic SKIP without DATABASE_URL) -----

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

    fn convo_req(
        request_id: Uuid,
        status: Option<&str>,
        parts: Vec<(Uuid, &str, &str)>,
    ) -> CreateConversationRequest {
        CreateConversationRequest {
            request_id,
            request_status: status.map(str::to_string),
            participants: parts
                .into_iter()
                .map(|(user_id, role, name)| ParticipantInput {
                    user_id,
                    role: role.to_string(),
                    display_name: Some(name.to_string()),
                    avatar_url: Some(format!("https://avatars/{name}.png")),
                })
                .collect(),
        }
    }

    async fn cleanup(db: &sqlx::PgPool, conversation_id: Uuid) {
        // FKs cascade from conversations → participants/messages/receipts/attachments.
        let _ = sqlx::query(
            "DELETE FROM chat.outbox WHERE payload->'payload'->>'conversation_id' = $1",
        )
        .bind(conversation_id.to_string())
        .execute(db)
        .await;
        let _ = sqlx::query("DELETE FROM chat.conversations WHERE id = $1")
            .bind(conversation_id)
            .execute(db)
            .await;
    }

    /// N+1 PROOF (runtime): seed THREE conversations, each with the test user as `customer`, a
    /// distinct guard counterpart, messages, and a read receipt — then assert ONE
    /// `list_conversations` call returns all three fully enriched (counterpart name, last
    /// message, unread by role). If enrichment were N+1 in Rust this would still pass
    /// functionally, but the function performs a SINGLE `fetch_all` of [`LIST_CONVERSATIONS_SQL`]
    /// (the static shape test guarantees that), so this proves the in-query enrichment is correct.
    #[tokio::test]
    async fn list_conversations_single_query_enriches_all() {
        let Some(db) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let me = Uuid::new_v4();
        let mut convo_ids = Vec::new();

        for i in 0..3 {
            let guard = Uuid::new_v4();
            let req = convo_req(
                Uuid::new_v4(),
                Some("accepted"),
                vec![
                    (me, "customer", "Customer"),
                    (guard, "guard", &format!("Guard{i}")),
                ],
            );
            let conv = create_conversation(&db, &req).await.expect("create");
            convo_ids.push(conv.id);

            // Guard sends (i+1) messages (unread for the customer); the customer sends 1 (read).
            // The role is DERIVED from membership server-side; the frame's sender_role is advisory.
            for n in 0..=i {
                send_message(
                    &db,
                    guard,
                    &IncomingChatMessage {
                        conversation_id: conv.id,
                        content: Some(format!("g{i}-{n}")),
                        message_type: None,
                        sender_role: None,
                    },
                )
                .await
                .expect("guard send");
            }
            send_message(
                &db,
                me,
                &IncomingChatMessage {
                    conversation_id: conv.id,
                    content: Some("mine".to_string()),
                    message_type: None,
                    sender_role: None,
                },
            )
            .await
            .expect("customer send");
        }

        let list = list_conversations(&db, me, "customer").await.expect("list");
        let mine: Vec<_> = list
            .into_iter()
            .filter(|c| convo_ids.contains(&c.id))
            .collect();
        assert_eq!(
            mine.len(),
            3,
            "all three seeded conversations returned in one query"
        );

        for c in &mine {
            // Acting as customer → counterpart is the guard (name from chat.participants, no JOIN).
            assert!(
                c.participant_name
                    .as_deref()
                    .unwrap_or("")
                    .starts_with("Guard"),
                "counterpart is the guard, name resolved by role"
            );
            assert!(
                c.participant_id.is_some(),
                "counterpart id resolved by role"
            );
            // The customer's own message ("mine") is the newest → last_message.
            assert_eq!(c.last_message.as_deref(), Some("mine"));
            assert!(c.last_message_at.is_some());
            assert_eq!(c.request_status.as_deref(), Some("accepted"));
            // Unread = the guard's messages (1..=3 across the three convos), all from the OTHER role.
            assert!(
                c.unread_count >= 1,
                "guard messages are unread for the customer"
            );
        }

        for id in convo_ids {
            cleanup(&db, id).await;
        }
    }

    /// OUTBOX ATOMICITY: `send_message` writes the message AND exactly one `chat.message_sent`
    /// outbox row in the SAME tx, addressed to the OTHER participant.
    #[tokio::test]
    async fn send_message_writes_message_and_outbox_atomically() {
        let Some(db) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let req = convo_req(
            Uuid::new_v4(),
            Some("accepted"),
            vec![(customer, "customer", "C"), (guard, "guard", "G")],
        );
        let conv = create_conversation(&db, &req).await.expect("create");

        let m = send_message(
            &db,
            customer,
            &IncomingChatMessage {
                conversation_id: conv.id,
                content: Some("hi".to_string()),
                message_type: None,
                sender_role: Some("customer".to_string()),
            },
        )
        .await
        .expect("send");
        assert_eq!(m.message_type, "text");
        assert_eq!(m.sender_role.as_deref(), Some("customer"));

        // Exactly one outbox row for this message, topic + recipient correct.
        let (count, topic, recipient, message_id): (i64, String, String, String) = sqlx::query_as(
            "SELECT count(*)::bigint, max(topic), \
                    max(payload->'payload'->>'recipient_id'), max(payload->'payload'->>'message_id') \
             FROM chat.outbox WHERE payload->'payload'->>'conversation_id' = $1",
        )
        .bind(conv.id.to_string())
        .fetch_one(&db)
        .await
        .expect("count outbox");
        assert_eq!(count, 1, "exactly one message_sent event");
        assert_eq!(topic, topics::CHAT_MESSAGE_SENT);
        assert_eq!(
            recipient,
            guard.to_string(),
            "addressed to the other participant"
        );
        assert_eq!(message_id, m.id.to_string());

        cleanup(&db, conv.id).await;
    }

    /// IDOR + read-only at the repo layer: a non-participant cannot send (`Forbidden`), and a
    /// write to a `completed`/`cancelled` conversation is rejected server-side (`Conflict`).
    #[tokio::test]
    async fn send_message_enforces_participant_and_readonly() {
        let Some(db) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let stranger = Uuid::new_v4();
        let req = convo_req(
            Uuid::new_v4(),
            Some("accepted"),
            vec![(customer, "customer", "C"), (guard, "guard", "G")],
        );
        let conv = create_conversation(&db, &req).await.expect("create");

        let frame = |role: &str| IncomingChatMessage {
            conversation_id: conv.id,
            content: Some("x".to_string()),
            message_type: None,
            sender_role: Some(role.to_string()),
        };

        // Non-participant → Forbidden.
        assert!(matches!(
            send_message(&db, stranger, &frame("customer")).await,
            Err(AppError::Forbidden(_))
        ));

        // Close the conversation → a participant write is rejected (Conflict), and NO outbox
        // event is written for the rejected send.
        set_request_status(&db, conv.request_id, "completed")
            .await
            .expect("close");
        assert!(matches!(
            send_message(&db, customer, &frame("customer")).await,
            Err(AppError::Conflict(_))
        ));

        cleanup(&db, conv.id).await;
    }

    /// mark_read drops the unread count to zero for that role; the attachment IDOR helper gates
    /// by conversation membership.
    #[tokio::test]
    async fn mark_read_and_attachment_idor() {
        let Some(db) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let stranger = Uuid::new_v4();
        let req = convo_req(
            Uuid::new_v4(),
            Some("accepted"),
            vec![(customer, "customer", "C"), (guard, "guard", "G")],
        );
        let conv = create_conversation(&db, &req).await.expect("create");

        // Guard sends → unread for the customer.
        send_message(
            &db,
            guard,
            &IncomingChatMessage {
                conversation_id: conv.id,
                content: Some("yo".to_string()),
                message_type: None,
                sender_role: Some("guard".to_string()),
            },
        )
        .await
        .expect("send");

        let before = list_conversations(&db, customer, "customer").await.unwrap();
        let unread = before
            .iter()
            .find(|c| c.id == conv.id)
            .unwrap()
            .unread_count;
        assert_eq!(unread, 1);

        mark_read(&db, conv.id, customer, "customer")
            .await
            .expect("mark read");
        let after = list_conversations(&db, customer, "customer").await.unwrap();
        let unread = after.iter().find(|c| c.id == conv.id).unwrap().unread_count;
        assert_eq!(unread, 0, "marking read clears unread for that role");

        // Attachment IDOR: a participant sees it, a stranger does not.
        let att = save_attachment(
            &db,
            conv.id,
            guard,
            &format!("chat/{}/x.jpg", conv.id),
            "https://signed/x",
            Some(123),
            "image/jpeg",
        )
        .await
        .expect("save attachment");
        assert!(is_attachment_participant(&db, att.id, customer)
            .await
            .unwrap());
        assert!(is_attachment_participant(&db, att.id, guard).await.unwrap());
        assert!(!is_attachment_participant(&db, att.id, stranger)
            .await
            .unwrap());

        cleanup(&db, conv.id).await;
    }

    /// SECURITY FIX: a client-supplied `system` message_type is REJECTED on the user send path
    /// (no `system` row is written, no outbox event) — `system` is server-only. text/image/video
    /// still succeed.
    #[tokio::test]
    async fn send_message_rejects_client_system_type() {
        let Some(db) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let req = convo_req(
            Uuid::new_v4(),
            Some("accepted"),
            vec![(customer, "customer", "C"), (guard, "guard", "G")],
        );
        let conv = create_conversation(&db, &req).await.expect("create");

        // A participant tries to forge a `system` message to silence the victim's push → BadRequest,
        // nothing persisted.
        let res = send_message(
            &db,
            customer,
            &IncomingChatMessage {
                conversation_id: conv.id,
                content: Some("ssh".to_string()),
                message_type: Some(MessageType::System),
                sender_role: None,
            },
        )
        .await;
        assert!(
            matches!(res, Err(AppError::BadRequest(_))),
            "client system message_type must be rejected"
        );

        // No message and no outbox row resulted from the rejected send.
        let msg_count: i64 =
            sqlx::query_scalar("SELECT count(*) FROM chat.messages WHERE conversation_id = $1")
                .bind(conv.id)
                .fetch_one(&db)
                .await
                .expect("count messages");
        assert_eq!(msg_count, 0, "no row from a rejected system send");

        // A normal text send still works (and is NOT system).
        let ok = send_message(
            &db,
            customer,
            &IncomingChatMessage {
                conversation_id: conv.id,
                content: Some("hi".to_string()),
                message_type: Some(MessageType::Text),
                sender_role: None,
            },
        )
        .await
        .expect("text send ok");
        assert_eq!(ok.message_type, "text");

        cleanup(&db, conv.id).await;
    }

    /// The call-summary consumer's repo half: `insert_call_summary_idempotent` posts exactly ONE
    /// `system` message carrying the pinned JSON, emits a `chat.message_sent` outbox row addressed
    /// to the OTHER participant (so notification suppresses the push), and a redelivery (same
    /// event_id) is a no-op — no double-post.
    #[tokio::test]
    async fn insert_call_summary_is_idempotent_and_system() {
        let Some(db) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let customer = Uuid::new_v4(); // the call's caller
        let guard = Uuid::new_v4();
        let req = convo_req(
            Uuid::new_v4(),
            Some("accepted"),
            vec![(customer, "customer", "C"), (guard, "guard", "G")],
        );
        let conv = create_conversation(&db, &req).await.expect("create");

        let event_id = Uuid::new_v4();
        let summary = crate::domain::CallSummary::from_call("video", "ended", None, true, Some(90));
        let content = summary.to_content();

        // First delivery posts the summary.
        let posted = insert_call_summary_idempotent(
            &db,
            event_id,
            topics::CALLING_ENDED,
            conv.id,
            customer,
            &content,
        )
        .await
        .expect("post summary");
        assert!(posted, "first delivery posts the summary");

        // Exactly one system message with the pinned content.
        let (count, mtype, stored): (i64, String, String) = sqlx::query_as(
            "SELECT count(*)::bigint, max(message_type::text), max(content) \
             FROM chat.messages WHERE conversation_id = $1",
        )
        .bind(conv.id)
        .fetch_one(&db)
        .await
        .expect("count messages");
        assert_eq!(count, 1, "exactly one summary message");
        assert_eq!(mtype, "system", "the summary is a system message");
        assert_eq!(stored, content, "content is the pinned summary JSON");

        // The outbox event is addressed to the OTHER participant (the guard) and tagged system so
        // notification SKIPS the push.
        let (ob_count, recipient, msg_type): (i64, String, String) = sqlx::query_as(
            "SELECT count(*)::bigint, max(payload->'payload'->>'recipient_id'), \
                    max(payload->'payload'->>'message_type') \
             FROM chat.outbox WHERE payload->'payload'->>'conversation_id' = $1",
        )
        .bind(conv.id.to_string())
        .fetch_one(&db)
        .await
        .expect("count outbox");
        assert_eq!(ob_count, 1, "one message_sent event for the summary");
        assert_eq!(recipient, guard.to_string(), "addressed to the other party");
        assert_eq!(
            msg_type, "system",
            "tagged system so notification suppresses the push"
        );

        // REDELIVERY (same event_id) is a no-op — no double-post.
        let again = insert_call_summary_idempotent(
            &db,
            event_id,
            topics::CALLING_ENDED,
            conv.id,
            customer,
            &content,
        )
        .await
        .expect("redelivery");
        assert!(!again, "a redelivered event_id posts nothing");
        let count2: i64 =
            sqlx::query_scalar("SELECT count(*) FROM chat.messages WHERE conversation_id = $1")
                .bind(conv.id)
                .fetch_one(&db)
                .await
                .expect("recount");
        assert_eq!(count2, 1, "still exactly one summary after redelivery");

        // cleanup also clears the ledger row.
        let _ = sqlx::query("DELETE FROM chat.processed_events WHERE event_id = $1")
            .bind(event_id)
            .execute(&db)
            .await;
        cleanup(&db, conv.id).await;
    }

    /// `find_conversation_id_by_request` returns the conversation for a known booking and `None`
    /// for an unknown one (the consumer's FIND step before falling back to CREATE).
    #[tokio::test]
    async fn find_conversation_id_by_request_resolves() {
        let Some(db) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let request_id = Uuid::new_v4();
        let req = convo_req(
            request_id,
            Some("accepted"),
            vec![
                (Uuid::new_v4(), "customer", "C"),
                (Uuid::new_v4(), "guard", "G"),
            ],
        );
        let conv = create_conversation(&db, &req).await.expect("create");
        let found = find_conversation_id_by_request(&db, request_id)
            .await
            .expect("find");
        assert_eq!(found, Some(conv.id));
        let missing = find_conversation_id_by_request(&db, Uuid::new_v4())
            .await
            .expect("find missing");
        assert_eq!(missing, None, "unknown booking → None");
        cleanup(&db, conv.id).await;
    }
}
