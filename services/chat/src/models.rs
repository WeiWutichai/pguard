//! DTOs for the chat service (transport shapes). Pure data — no I/O.
//!
//! `message_type` is read back as text (the `chat.message_type` enum cast to `::text`) so the
//! read path needs no enum decoding — the repo binds writes with a `::chat.message_type` cast
//! and the pure [`crate::domain::MessageType`] validates client-supplied kinds. This keeps the
//! `domain` layer DB-free (mirrors the calling slice's `status` handling).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::domain::MessageType;

// ----- Requests -----

/// A participant supplied at conversation creation. Carries the booking-derived `role`
/// (drives alignment + per-role receipts) and OPTIONAL denormalized display data so the
/// enriched list resolves the counterpart's name without a cross-schema JOIN.
#[derive(Debug, Clone, Deserialize)]
pub struct ParticipantInput {
    pub user_id: Uuid,
    /// `guard` or `customer` — this participant's role in THIS conversation.
    pub role: String,
    #[serde(default)]
    pub display_name: Option<String>,
    #[serde(default)]
    pub avatar_url: Option<String>,
}

/// Create a booking-scoped conversation. `participants` supersedes v1's bare `participant_ids[]`:
/// v2 forbids the cross-schema JOIN v1 used to resolve roles/names, so the creator (booking)
/// supplies the booking-derived role + display data inline.
#[derive(Debug, Deserialize)]
pub struct CreateConversationRequest {
    pub request_id: Uuid,
    /// Booking status at creation (e.g. `accepted`); drives the read-only gate. Optional.
    #[serde(default)]
    pub request_status: Option<String>,
    pub participants: Vec<ParticipantInput>,
}

/// Acting-role query param (`?role=guard|customer`) shared by the list + mark-read endpoints.
#[derive(Debug, Deserialize)]
pub struct RoleQuery {
    pub role: Option<String>,
}

/// Pagination for message history.
#[derive(Debug, Deserialize)]
pub struct ListMessagesQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// Internal (service-JWT): push a booking's lifecycle status onto its conversation(s).
#[derive(Debug, Deserialize)]
pub struct SetRequestStatusRequest {
    pub request_status: String,
}

/// An inbound WS frame from a client. `conversation_id` is sent PER-FRAME (never in the URL).
#[derive(Debug, Deserialize)]
pub struct IncomingChatMessage {
    pub conversation_id: Uuid,
    #[serde(default)]
    pub content: Option<String>,
    #[serde(default)]
    pub message_type: Option<MessageType>,
    /// Sender's role as DECLARED by the client — **advisory only, never trusted**. The
    /// authoritative `sender_role` is DERIVED from the sender's `chat.participants.user_role` in
    /// [`crate::repo::send_message`] (a client can't spoof a message as the counterpart's role).
    /// Accepted on the wire to match the AsyncAPI frame shape, then ignored — hence `dead_code`.
    #[serde(default)]
    #[allow(dead_code)]
    pub sender_role: Option<String>,
}

// ----- Responses -----

/// A conversation as returned to clients.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct ConversationResponse {
    pub id: Uuid,
    pub request_id: Uuid,
    pub request_status: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// One row of the N+1-free enriched conversation list. Every field is resolved in the single
/// `list_conversations` query — `participant_*` from `chat.participants` (the counterpart's
/// denormalized booking-derived data), `last_message*`/`unread_count` from `chat.messages` +
/// `chat.read_receipts`, `request_status` from `chat.conversations`. No cross-schema reach.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct EnrichedConversation {
    pub id: Uuid,
    pub request_id: Uuid,
    pub created_at: DateTime<Utc>,
    /// Counterpart user id (the participant whose role differs from the acting role).
    pub participant_id: Option<Uuid>,
    pub participant_name: Option<String>,
    pub participant_avatar: Option<String>,
    pub last_message: Option<String>,
    pub last_message_at: Option<DateTime<Utc>>,
    pub unread_count: i64,
    pub request_status: Option<String>,
}

/// A message row (read path). `message_type` is the enum cast to text. `sender_role` drives
/// client-side alignment.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OutgoingChatMessage {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub sender_id: Uuid,
    pub sender_role: Option<String>,
    pub content: Option<String>,
    pub message_type: String,
    pub created_at: DateTime<Utc>,
}

/// An attachment as returned to clients (with a fresh presigned `file_url`).
#[derive(Debug, Serialize)]
pub struct AttachmentResponse {
    pub id: Uuid,
    pub chat_id: Uuid,
    pub file_key: String,
    pub file_url: String,
    pub file_size: Option<i32>,
    pub mime_type: String,
    pub created_at: DateTime<Utc>,
}

/// Raw attachment row (the stored `file_url` may be a stale presigned URL — the handler always
/// regenerates a fresh one before returning).
#[derive(Debug, sqlx::FromRow)]
pub struct AttachmentRow {
    pub id: Uuid,
    pub chat_id: Uuid,
    #[allow(dead_code)]
    pub uploader_id: Uuid,
    pub file_key: String,
    #[allow(dead_code)]
    pub file_url: Option<String>,
    pub file_size: Option<i32>,
    pub mime_type: String,
    pub created_at: DateTime<Utc>,
}
