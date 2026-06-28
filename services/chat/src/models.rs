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

/// An admin conversation-list row (`GET /admin/conversations`). Unlike [`EnrichedConversation`]
/// (which is scoped to a participant + their counterpart), the admin view is NOT a participant,
/// so it carries BOTH participants' names joined + the last message + a total count — no
/// "me"/"counterpart"/"unread" notion.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct AdminConversationRow {
    pub id: Uuid,
    pub request_id: Uuid,
    pub request_status: Option<String>,
    pub created_at: DateTime<Utc>,
    /// Participant display names joined with " · " (NULLs ignored).
    pub participants: Option<String>,
    pub last_message: Option<String>,
    pub last_message_at: Option<DateTime<Utc>>,
    pub message_count: i64,
}

/// Query params for `GET /admin/conversations` (house limit/offset pagination).
#[derive(Debug, Deserialize)]
pub struct AdminListConversationsQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

// ----- Admin moderation (Phase D) requests -----

/// Body for `DELETE /admin/messages/{id}` (redact a message) — an OPTIONAL audited reason.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct RedactMessageRequest {
    pub reason: Option<String>,
}

/// Body for `PUT /admin/conversations/{id}/status` — set the conversation's MODERATION status
/// (`active` | `archived`; distinct from the booking `request_status`). Archiving freezes writes.
#[derive(Debug, Deserialize)]
pub struct SetModerationStatusRequest {
    pub moderation_status: String,
    #[serde(default)]
    pub reason: Option<String>,
}

/// Body for `PUT /admin/users/{user_id}/block` and `DELETE …/block` (unblock) — an OPTIONAL
/// audited reason. Block/unblock are idempotent.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct BlockUserRequest {
    pub reason: Option<String>,
}

// ----- Admin moderation (Phase D) responses -----

/// The result of a moderation write — `applied` distinguishes a state-changing call from an
/// idempotent no-op (e.g. re-redacting an already-redacted message, re-blocking a blocked user).
/// The web admin can show "already done" vs "done" without a follow-up read.
#[derive(Debug, Serialize)]
pub struct ModerationResult {
    /// `true` if this call changed state; `false` if it was an idempotent repeat (already in the
    /// target state) — both are success (200), never an error.
    pub applied: bool,
    /// Echo of the resulting state for the convenience of the caller (e.g. `archived`, `blocked`).
    pub status: String,
}

/// A message row (read path). `message_type` is the enum cast to text. `sender_role` drives
/// client-side alignment.
///
/// `redacted` is `true` when an admin soft-deleted the message (Phase D moderation): the read
/// queries SUPPRESS the original `content` (substituting [`crate::domain::REDACTED_CONTENT_PLACEHOLDER`])
/// so a removed message shows as removed without leaking the original text/attachment. A freshly
/// sent message is never redacted. `#[serde(default)]` keeps the WS frame backward-compatible.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OutgoingChatMessage {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub sender_id: Uuid,
    pub sender_role: Option<String>,
    pub content: Option<String>,
    pub message_type: String,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub redacted: bool,
}

/// An ADMIN-ENRICHED message (`GET /admin/conversations/{id}/messages`). Unlike
/// [`OutgoingChatMessage`] (which returns `content` RAW — an attachment UUID for image/video, the
/// pinned call JSON for a `system` line — and leaves rendering to the mobile client), this read
/// model resolves `content` into RENDERABLE data so the web admin console can show the real thing
/// (an image thumbnail, a video indicator, a parsed call event, plain text) WITHOUT a second
/// round-trip per message. READ-ONLY (moderation is Phase D). All raw fields are carried through
/// so the web can fall back / show metadata; the enrichment adds `kind` + the per-kind fields.
#[derive(Debug, Serialize)]
pub struct AdminEnrichedMessage {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub sender_id: Uuid,
    pub sender_role: Option<String>,
    pub message_type: String,
    pub created_at: DateTime<Utc>,
    /// The PARSED render kind the web switches on: `text` | `image` | `video` | `call-event` |
    /// `system` (unrecognized system JSON) | `unknown`. Distinct from `message_type` (the stored
    /// enum) because a `system` row is further parsed into `call-event` when its content is the
    /// pinned call summary.
    pub kind: String,
    /// Plain text for a `text` message (the raw `content`); `null` otherwise.
    pub text: Option<String>,
    /// Resolved attachment for an `image`/`video` message (fresh presigned URL, admin-gated).
    /// `null` for non-media or if the referenced attachment can't be resolved (the raw id is
    /// then surfaced via `attachment_id` so the admin still sees there WAS an attachment).
    pub attachment: Option<AdminAttachmentView>,
    /// The raw attachment id carried in a media message's `content` (echoed even if resolution
    /// fails, so the admin isn't shown a blank). `null` for non-media.
    pub attachment_id: Option<String>,
    /// Parsed call event for a `system` call-summary line; `null` otherwise.
    pub call_event: Option<AdminCallEvent>,
    /// `true` when an admin soft-deleted (redacted) this message (Phase D). The admin audit view
    /// STILL surfaces the redaction so a moderator sees a removed message exists; the per-kind
    /// fields above reflect the SUPPRESSED content (text/attachment carry the placeholder/null),
    /// not the original — the original is never re-exposed, even to an admin, through this view.
    pub redacted: bool,
}

/// The resolvable bits of an attachment for the admin message view — a fresh presigned URL plus
/// the MIME so the web can render an `<img>` thumbnail or a video indicator. Reuses the chat
/// attachment storage download URL (`S3Client::download_url`), admin-gated by the endpoint.
#[derive(Debug, Serialize)]
pub struct AdminAttachmentView {
    pub id: Uuid,
    /// Fresh presigned download URL (TTL 1h) — the admin-viewable thumbnail/source.
    pub url: String,
    pub mime_type: String,
    pub file_size: Option<i32>,
    /// `true` for `video/*` — lets the web show a video indicator vs an image thumbnail.
    pub is_video: bool,
}

/// A parsed call-summary `system` message — the structured form of the pinned
/// `{"k":"call","ct":...,"oc":...,"ds":...}` JSON so the web renders a real call event instead
/// of raw JSON. `call_type` = audio|video, `outcome` = completed|missed|rejected, `duration_seconds`
/// = whole seconds for an answered call (else null).
#[derive(Debug, Serialize)]
pub struct AdminCallEvent {
    pub call_type: String,
    pub outcome: String,
    pub duration_seconds: Option<i32>,
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
