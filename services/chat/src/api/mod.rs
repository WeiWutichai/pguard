//! API layer — thin Axum transport handlers (REST) + the WS module. No business logic beyond
//! authz gating (AuthUser/ServiceCaller + the explicit participant IDOR check + the read-only
//! gate) and orchestration of `domain` (pure validation), `repo` (DB + outbox), `s3` (upload +
//! presign), and `events` (pub/sub fan-out).
//!
//! Client handlers are generic over [`ChatDeps`] and the internal one over [`ChatInternalDeps`]
//! so the guards + IDOR logic are unit-testable with a lightweight state (mirrors profile).

pub mod ws;

use axum::extract::{Multipart, Path, Query, State};
use axum::Json;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;
use shared::service_jwt::ServiceCaller;

use crate::booking_client::BookingReader;
use crate::domain;
use crate::events;
use crate::models::{
    AdminAttachmentView, AdminCallEvent, AdminConversationRow, AdminEnrichedMessage,
    AdminListConversationsQuery, AttachmentResponse, AttachmentRow, BlockUserRequest,
    ConversationResponse, CreateConversationRequest, EnrichedConversation, IncomingChatMessage,
    ListMessagesQuery, ModerationResult, OutgoingChatMessage, RedactMessageRequest, RoleQuery,
    SetModerationStatusRequest, SetRequestStatusRequest,
};
use crate::repo;
use crate::state::{ChatDeps, ChatInternalDeps};

const ROLE_ADMIN: &str = "admin";
const DEFAULT_LIMIT: i64 = 50;

/// The acting role for this request. A NON-admin always acts in their own (token) role — a
/// client-supplied `?role=` is ignored so a customer can't query/receipt as the guard (no role
/// spoofing; v1-audit #3). An admin (moderation) may pass an explicit `?role=`.
fn acting_role<'a>(query: &'a RoleQuery, user: &'a AuthUser) -> &'a str {
    if user.role == ROLE_ADMIN {
        query.role.as_deref().unwrap_or(&user.role)
    } else {
        &user.role
    }
}

/// Build the client-facing attachment view with a fresh presigned URL (TTL 1h). The stored
/// `file_url` may be stale, so we always re-sign from `file_key` — the bucket is never exposed.
fn attachment_view(row: AttachmentRow, file_url: String) -> AttachmentResponse {
    AttachmentResponse {
        id: row.id,
        chat_id: row.chat_id,
        file_key: row.file_key,
        file_url,
        file_size: row.file_size,
        mime_type: row.mime_type,
        created_at: row.created_at,
    }
}

// ----- POST /conversations -----

const ROLE_CUSTOMER: &str = "customer";
const ROLE_GUARD: &str = "guard";

/// Create (or fetch) a booking-scoped conversation. The conversation's IDENTITY — who the
/// parties are, their roles, and the lifecycle status — is AUTHORITATIVE from booking, never
/// trusted from the client. This closes the IDOR where a client could fabricate a conversation
/// with any victim's `user_id` for any `request_id`, inject display text into the victim's list,
/// or set `request_status='accepted'` to bypass the read-only gate.
///
/// Flow (non-admin): GET booking's `/internal/bookings/{request_id}` (service-JWT'd). A 404 or a
/// caller who is neither the booking's customer nor its assigned guard → `403` (same denial, no
/// existence oracle). Then BUILD the participants from the booking (customer + guard-when-present)
/// and take `request_status` from `booking.status` — `req.participants`/`req.request_status` are
/// ignored for identity/role/status. `display_name`/`avatar_url` are carried through ONLY for the
/// now-validated `user_id`s (the client may denormalize the counterpart's name; it can't forge an
/// identity). The repo is GET-OR-CREATE (idempotent on `request_id`), so a repeat POST returns the
/// EXISTING conversation. An admin (moderation) may create directly from the request body.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, request_id = %req.request_id))]
pub async fn create_conversation<S: ChatDeps>(
    State(state): State<S>,
    user: AuthUser,
    Json(req): Json<CreateConversationRequest>,
) -> Result<Json<ApiResponse<ConversationResponse>>, AppError> {
    // Admin (moderation) bypass: trust the body as supplied.
    if user.role == ROLE_ADMIN {
        let conv = repo::create_conversation(state.db(), &req).await?;
        return Ok(Json(ApiResponse::success(conv)));
    }

    // Authoritative booking → who the parties are + the lifecycle status. A missing booking is a
    // `NotFound` from the client; normalize it to `403` so it's indistinguishable from "not your
    // booking" (no existence oracle on request_ids).
    let booking = match state.booking().get_booking(req.request_id).await {
        Ok(b) => b,
        Err(AppError::NotFound(_)) => {
            return Err(AppError::Forbidden(
                "You must be a party of this booking".to_string(),
            ))
        }
        Err(e) => return Err(e),
    };

    // The caller MUST be the booking's customer or its assigned guard.
    let is_party = user.user_id == booking.customer_id || booking.guard_id == Some(user.user_id);
    if !is_party {
        return Err(AppError::Forbidden(
            "You must be a party of this booking".to_string(),
        ));
    }

    // Build the participants from the AUTHORITATIVE booking, not the client. display_name/avatar
    // may be denormalized from the client's matching entry (identities are now validated), else
    // null. status comes from the booking (drives the read-only gate).
    let authoritative = CreateConversationRequest {
        request_id: req.request_id,
        request_status: Some(booking.status.clone()),
        participants: authoritative_participants(&booking, &req.participants),
    };
    let conv = repo::create_conversation(state.db(), &authoritative).await?;
    Ok(Json(ApiResponse::success(conv)))
}

/// Build the authoritative participant set from the booking: the customer (role `customer`) and
/// the assigned guard (role `guard`) when present. `display_name`/`avatar_url` are carried over
/// ONLY from the client entry whose `user_id` matches a validated party — a client can denormalize
/// the counterpart's name but cannot forge an identity, role, or inject a phantom participant.
fn authoritative_participants(
    booking: &crate::booking_client::InternalBooking,
    client: &[crate::models::ParticipantInput],
) -> Vec<crate::models::ParticipantInput> {
    let denorm = |user_id: Uuid, role: &str| {
        let hint = client.iter().find(|p| p.user_id == user_id);
        crate::models::ParticipantInput {
            user_id,
            role: role.to_string(),
            display_name: hint.and_then(|p| p.display_name.clone()),
            avatar_url: hint.and_then(|p| p.avatar_url.clone()),
        }
    };
    let mut parts = vec![denorm(booking.customer_id, ROLE_CUSTOMER)];
    if let Some(guard_id) = booking.guard_id {
        parts.push(denorm(guard_id, ROLE_GUARD));
    }
    parts
}

// ----- GET /conversations?role= -----

/// The N+1-free enriched list for the caller in `acting_role` (read replica).
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn list_conversations<S: ChatDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(query): Query<RoleQuery>,
) -> Result<Json<ApiResponse<Vec<EnrichedConversation>>>, AppError> {
    let role = acting_role(&query, &user);
    let convos = repo::list_conversations(state.db_read(), user.user_id, role).await?;
    Ok(Json(ApiResponse::success(convos)))
}

/// GET /admin/conversations — admin cross-user conversation list (read-only). Admin only (the
/// edge proves identity, not role). The per-conversation message pane reuses the existing
/// `GET /conversations/{id}/messages` (admin already bypasses the participant gate). Moderation
/// actions (flag/delete/block/archive) in the design have no v2 endpoint and are out of scope.
#[tracing::instrument(skip(state, query), fields(user = %user.user_id))]
pub async fn admin_list_conversations<S: ChatDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(query): Query<AdminListConversationsQuery>,
) -> Result<Json<ApiResponse<Vec<AdminConversationRow>>>, AppError> {
    require_admin(&user)?;
    let limit = query.limit.unwrap_or(50).clamp(1, 200);
    let offset = query.offset.unwrap_or(0).max(0);
    let convos = repo::admin_list_conversations(state.db_read(), limit, offset).await?;
    Ok(Json(ApiResponse::success(convos)))
}

// ----- GET /conversations/{id}/messages -----

/// Message history (newest-first). Participant-only (admin bypasses) — the explicit IDOR gate.
#[tracing::instrument(skip(state), fields(user = %user.user_id, conversation_id = %id))]
pub async fn list_messages<S: ChatDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Query(query): Query<ListMessagesQuery>,
) -> Result<Json<ApiResponse<Vec<OutgoingChatMessage>>>, AppError> {
    require_participant(&state, id, &user).await?;
    let limit = query.limit.unwrap_or(DEFAULT_LIMIT);
    let offset = query.offset.unwrap_or(0);
    let messages = repo::list_messages(state.db(), id, limit, offset).await?;
    Ok(Json(ApiResponse::success(messages)))
}

// ----- GET /admin/conversations/{id}/messages -----

/// ADMIN message audit (read-only). Same newest-first history as `list_messages`, but each row is
/// ENRICHED into renderable data so the web console shows what was ACTUALLY sent — not the raw
/// `content` (an attachment UUID for image/video, the pinned call JSON for a `system` line). For
/// each message it returns a parsed `kind`, the `text` for text rows, a resolved `attachment`
/// (fresh presigned URL + MIME so the web renders an image thumbnail / video indicator) for
/// media rows, and a structured `call_event` for a call-summary `system` row. Admin-only (the
/// edge proves identity, not role — same gate as `admin_list_conversations`). READ-ONLY: no
/// moderation (Phase D).
///
/// Attachments are resolved in ONE batch query (the ids referenced across all media messages),
/// then each gets a freshly-signed URL — no N+1, and the bucket is never exposed.
#[tracing::instrument(skip(state, query), fields(user = %user.user_id, conversation_id = %id))]
pub async fn admin_list_messages<S: ChatDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Query(query): Query<ListMessagesQuery>,
) -> Result<Json<ApiResponse<Vec<AdminEnrichedMessage>>>, AppError> {
    require_admin(&user)?;
    let limit = query.limit.unwrap_or(DEFAULT_LIMIT);
    let offset = query.offset.unwrap_or(0);
    let messages = repo::list_messages(state.db_read(), id, limit, offset).await?;

    // Collect the attachment ids referenced by image/video messages (the id rides in `content`),
    // resolve them in ONE batch query, and index by id so enrichment is a map lookup (no N+1).
    let attachment_ids: Vec<Uuid> = messages
        .iter()
        .filter(|m| is_media_type(&m.message_type))
        .filter_map(|m| m.content.as_deref().and_then(|c| c.parse::<Uuid>().ok()))
        .collect();
    let attachments = repo::get_attachments_by_ids(state.db_read(), &attachment_ids).await?;
    let by_id: std::collections::HashMap<Uuid, AttachmentRow> =
        attachments.into_iter().map(|a| (a.id, a)).collect();

    let enriched = messages
        .into_iter()
        .map(|m| enrich_message(m, &by_id, state.s3()))
        .collect::<Vec<_>>();
    Ok(Json(ApiResponse::success(enriched)))
}

const MSG_TYPE_TEXT: &str = "text";
const MSG_TYPE_IMAGE: &str = "image";
const MSG_TYPE_VIDEO: &str = "video";
const MSG_TYPE_SYSTEM: &str = "system";

/// `true` for the media message types whose `content` is an attachment id.
fn is_media_type(message_type: &str) -> bool {
    message_type == MSG_TYPE_IMAGE || message_type == MSG_TYPE_VIDEO
}

/// Enrich one raw message into the admin render model. Resolves media `content` (an attachment id)
/// to a presigned view via the pre-fetched `by_id` map + a fresh signed URL, and a `system`
/// call-summary `content` into a structured call event. Pure aside from `s3.download_url` (a
/// deterministic local signer — no I/O), so the per-row mapping stays cheap.
fn enrich_message(
    m: OutgoingChatMessage,
    by_id: &std::collections::HashMap<Uuid, AttachmentRow>,
    s3: &crate::s3::S3Client,
) -> AdminEnrichedMessage {
    let mut kind = m.message_type.clone();
    let mut text: Option<String> = None;
    let mut attachment: Option<AdminAttachmentView> = None;
    let mut attachment_id: Option<String> = None;
    let mut call_event: Option<AdminCallEvent> = None;

    // A REDACTED (soft-deleted) message: the read path already SUPPRESSED `content` (it now holds
    // the placeholder, not the original text / attachment id). Surface the redaction marker and the
    // placeholder text, but do NOT attempt to resolve an attachment or parse a call event from the
    // suppressed content — the original is never re-exposed, even to an admin, through this view.
    if m.redacted {
        return AdminEnrichedMessage {
            id: m.id,
            conversation_id: m.conversation_id,
            sender_id: m.sender_id,
            sender_role: m.sender_role,
            message_type: m.message_type,
            created_at: m.created_at,
            kind: "redacted".to_string(),
            text: m.content,
            attachment: None,
            attachment_id: None,
            call_event: None,
            redacted: true,
        };
    }

    match m.message_type.as_str() {
        MSG_TYPE_TEXT => {
            text = m.content.clone();
        }
        MSG_TYPE_IMAGE | MSG_TYPE_VIDEO => {
            // The raw id is echoed even if resolution fails (so the admin still sees there WAS an
            // attachment, not a blank), then resolved to a presigned view when found.
            attachment_id = m.content.clone();
            if let Some(att) = m
                .content
                .as_deref()
                .and_then(|c| c.parse::<Uuid>().ok())
                .and_then(|aid| by_id.get(&aid))
            {
                attachment = Some(AdminAttachmentView {
                    id: att.id,
                    url: s3.download_url(&att.file_key),
                    mime_type: att.mime_type.clone(),
                    file_size: att.file_size,
                    is_video: domain::is_video_mime(&att.mime_type),
                });
            }
        }
        MSG_TYPE_SYSTEM => {
            // A `system` row is a call-summary line when its content is the pinned call JSON;
            // otherwise it stays a generic `system` kind (future system kinds render plainly).
            if let Some(parsed) = m.content.as_deref().and_then(domain::parse_call_summary) {
                kind = "call-event".to_string();
                call_event = Some(AdminCallEvent {
                    call_type: parsed.call_type,
                    outcome: parsed.outcome,
                    duration_seconds: parsed.duration_seconds,
                });
            }
        }
        _ => {
            // Unknown stored type (defensive) — surface as-is so the admin sees the raw kind.
            kind = "unknown".to_string();
        }
    }

    AdminEnrichedMessage {
        id: m.id,
        conversation_id: m.conversation_id,
        sender_id: m.sender_id,
        sender_role: m.sender_role,
        message_type: m.message_type,
        created_at: m.created_at,
        kind,
        text,
        attachment,
        attachment_id,
        call_event,
        redacted: false,
    }
}

/// Admin-role gate shared by the moderation writes. The gateway proves IDENTITY (a valid token)
/// and routes the `/admin/*` prefix to chat, but the ROLE check is the service's job (CLAUDE.md:
/// "admin endpoints role-gated at gateway + handler require_role(admin)"). A non-admin gets `403`
/// before any DB access.
fn require_admin(user: &AuthUser) -> Result<(), AppError> {
    if user.role == ROLE_ADMIN {
        Ok(())
    } else {
        Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ))
    }
}

// ----- DELETE /admin/messages/{id} (redact a message) -----

/// ADMIN: REDACT (soft-delete) a message. The message stays in the table (never hard-deleted —
/// audit/PDPA), but every read path SUPPRESSES its content (shows "[message removed by
/// moderator]") and the admin audit view marks it `redacted`. Who/when/why is recorded on the
/// message row AND in the `chat.moderation_actions` ledger (one transaction). Admin only (else
/// 403). IDEMPOTENT: re-redacting an already-redacted message returns 200 with `applied:false`
/// (no second audit row). A non-existent message → 404.
#[tracing::instrument(skip(state, body), fields(user = %user.user_id, message_id = %id))]
pub async fn admin_redact_message<S: ChatDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    body: Option<Json<RedactMessageRequest>>,
) -> Result<Json<ApiResponse<ModerationResult>>, AppError> {
    require_admin(&user)?;
    let reason = body.and_then(|Json(b)| b.reason);
    let applied = repo::redact_message(state.db(), id, user.user_id, reason.as_deref()).await?;
    Ok(Json(ApiResponse::success(ModerationResult {
        applied,
        status: "redacted".to_string(),
    })))
}

// ----- PUT /admin/conversations/{id}/status (moderation status / archive) -----

/// ADMIN: set a conversation's MODERATION status (`active` | `archived`). This is DISTINCT from the
/// booking `request_status` (lifecycle): archiving freezes the thread to new writes regardless of
/// the booking state, and reactivating reopens it. Audited (who/when/why → `chat.moderation_actions`).
/// Admin only (else 403). IDEMPOTENT: setting the status it already holds returns `applied:false`.
/// Rejects an unknown status (400). A non-existent conversation → 404.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, conversation_id = %id, status = %req.moderation_status))]
pub async fn admin_set_moderation_status<S: ChatDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<SetModerationStatusRequest>,
) -> Result<Json<ApiResponse<ModerationResult>>, AppError> {
    require_admin(&user)?;
    if !domain::is_valid_moderation_status(&req.moderation_status) {
        return Err(AppError::BadRequest(
            "moderation_status must be 'active' or 'archived'".to_string(),
        ));
    }
    let applied = repo::set_moderation_status(
        state.db(),
        id,
        user.user_id,
        &req.moderation_status,
        req.reason.as_deref(),
    )
    .await?;
    Ok(Json(ApiResponse::success(ModerationResult {
        applied,
        status: req.moderation_status,
    })))
}

// ----- PUT/DELETE /admin/users/{user_id}/block (chat-level block) -----

/// ADMIN: BLOCK a user from chat (a chat-level ban). A blocked user cannot SEND in any conversation
/// (enforced server-side in `repo::send_message`). Audited. Admin only (else 403). IDEMPOTENT:
/// re-blocking an already-blocked user returns `applied:false`.
#[tracing::instrument(skip(state, body), fields(user = %user.user_id, target = %target_user_id))]
pub async fn admin_block_user<S: ChatDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(target_user_id): Path<Uuid>,
    body: Option<Json<BlockUserRequest>>,
) -> Result<Json<ApiResponse<ModerationResult>>, AppError> {
    require_admin(&user)?;
    let reason = body.and_then(|Json(b)| b.reason);
    let applied =
        repo::block_user(state.db(), target_user_id, user.user_id, reason.as_deref()).await?;
    Ok(Json(ApiResponse::success(ModerationResult {
        applied,
        status: "blocked".to_string(),
    })))
}

/// ADMIN: UNBLOCK a user (lift the active chat block; the block row is kept for audit). Audited.
/// Admin only (else 403). IDEMPOTENT: unblocking a user with no active block returns `applied:false`.
#[tracing::instrument(skip(state, body), fields(user = %user.user_id, target = %target_user_id))]
pub async fn admin_unblock_user<S: ChatDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(target_user_id): Path<Uuid>,
    body: Option<Json<BlockUserRequest>>,
) -> Result<Json<ApiResponse<ModerationResult>>, AppError> {
    require_admin(&user)?;
    let reason = body.and_then(|Json(b)| b.reason);
    let applied =
        repo::unblock_user(state.db(), target_user_id, user.user_id, reason.as_deref()).await?;
    Ok(Json(ApiResponse::success(ModerationResult {
        applied,
        status: "unblocked".to_string(),
    })))
}

// ----- PUT /conversations/{id}/read?role= -----

/// UPSERT the caller's per-role read receipt. Participant-only (admin bypasses).
#[tracing::instrument(skip(state), fields(user = %user.user_id, conversation_id = %id))]
pub async fn mark_read<S: ChatDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Query(query): Query<RoleQuery>,
) -> Result<Json<ApiResponse<()>>, AppError> {
    require_participant(&state, id, &user).await?;
    let role = acting_role(&query, &user);
    repo::mark_read(state.db(), id, user.user_id, role).await?;
    Ok(Json(ApiResponse::success(())))
}

// ----- POST /attachments (multipart) -----

/// Upload an image/video to a conversation. Order: parse → participant gate → read-only gate →
/// validate (size before magic bytes) → S3 upload → persist → return a presigned URL.
///
/// Memory note: the field body is buffered into a `Vec<u8>` before the per-kind size gate fires,
/// so peak allocation per upload is bounded by the route's `DefaultBodyLimit` (`MAX_UPLOAD_BYTES`,
/// ~210MB to cover the 200MB video path) rather than the per-kind cap. A truly pre-allocation cap
/// would require streaming the multipart field in chunks (deferred — matches the profile S3 pattern).
#[tracing::instrument(skip(state, multipart), fields(user = %user.user_id))]
pub async fn upload_attachment<S: ChatDeps>(
    State(state): State<S>,
    user: AuthUser,
    mut multipart: Multipart,
) -> Result<Json<ApiResponse<AttachmentResponse>>, AppError> {
    let mut conversation_id: Option<Uuid> = None;
    let mut file_data: Option<Vec<u8>> = None;
    let mut declared_mime: Option<String> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| AppError::BadRequest(format!("Failed to read multipart: {e}")))?
    {
        match field.name().unwrap_or("") {
            "conversation_id" => {
                let text = field
                    .text()
                    .await
                    .map_err(|e| AppError::BadRequest(format!("Invalid conversation_id: {e}")))?;
                conversation_id = Some(
                    text.parse::<Uuid>()
                        .map_err(|e| AppError::BadRequest(format!("Invalid UUID: {e}")))?,
                );
            }
            "file" => {
                declared_mime = field.content_type().map(|s| s.to_string());
                file_data = Some(
                    field
                        .bytes()
                        .await
                        .map_err(|e| AppError::BadRequest(format!("Failed to read file: {e}")))?
                        .to_vec(),
                );
            }
            _ => {}
        }
    }

    let conversation_id = conversation_id
        .ok_or_else(|| AppError::BadRequest("conversation_id is required".to_string()))?;
    let data = file_data.ok_or_else(|| AppError::BadRequest("file is required".to_string()))?;
    let declared_mime = declared_mime.unwrap_or_else(|| "application/octet-stream".to_string());

    // Participant gate (IDOR) + read-only gate (server-side; never trust the client).
    require_participant(&state, conversation_id, &user).await?;
    let request_status = repo::conversation_request_status(state.db(), conversation_id).await?;
    if !domain::is_writable(request_status.as_deref()) {
        return Err(AppError::Conflict(
            "Conversation is read-only (booking completed/cancelled)".to_string(),
        ));
    }

    // Validate (size BEFORE magic bytes) — returns the canonical (detected) MIME.
    let canonical_mime = domain::validate_upload(&declared_mime, data.len(), &data)?;
    // `validate_upload` already capped the length well under i32::MAX; try_from makes the
    // narrowing explicit so a future cap increase can't silently persist a negative size.
    let size = i32::try_from(data.len())
        .map_err(|_| AppError::BadRequest("File too large".to_string()))?;
    let ext = domain::mime_to_extension(canonical_mime);
    let file_key = format!("chat/{conversation_id}/{}.{ext}", Uuid::new_v4());

    // Upload (server → MinIO internal), then sign a fresh client-facing GET URL.
    state.s3().upload(&file_key, data, canonical_mime).await?;
    let file_url = state.s3().download_url(&file_key);

    let row = repo::save_attachment(
        state.db(),
        conversation_id,
        user.user_id,
        &file_key,
        &file_url,
        Some(size),
        canonical_mime,
    )
    .await?;

    Ok(Json(ApiResponse::success(attachment_view(row, file_url))))
}

// ----- GET /attachments/{id} -----

/// Fetch an attachment with a freshly-signed download URL. Participant of the attachment's
/// conversation only (admin bypasses) — the IDOR gate.
#[tracing::instrument(skip(state), fields(user = %user.user_id, attachment_id = %id))]
pub async fn get_attachment<S: ChatDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<AttachmentResponse>>, AppError> {
    // IDOR gate FIRST, before any fetch, so existence is never leaked: a non-admin who is not a
    // participant gets a generic 403 whether or not the attachment exists (`is_attachment_participant`
    // returns false for a missing id too) — closing the 403-vs-404 existence oracle.
    if user.role != ROLE_ADMIN
        && !repo::is_attachment_participant(state.db(), id, user.user_id).await?
    {
        return Err(AppError::Forbidden(
            "You do not have access to this attachment".to_string(),
        ));
    }
    let row = repo::get_attachment(state.db(), id).await?;
    let file_url = state.s3().download_url(&row.file_key);
    Ok(Json(ApiResponse::success(attachment_view(row, file_url))))
}

// ----- PUT /internal/conversations/by-request/{request_id}/status (service-JWT) -----

/// Booking pushes a lifecycle status onto the conversation(s) for a request so chat's
/// denormalized `request_status` (and thus the read-only gate) stays current. `ServiceCaller`-
/// gated; never reachable from the edge (the gateway blocks `/internal/`). Idempotent.
#[tracing::instrument(skip(state, req), fields(caller = %caller.service, request_id = %request_id))]
pub async fn internal_set_request_status<S: ChatInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Path(request_id): Path<Uuid>,
    Json(req): Json<SetRequestStatusRequest>,
) -> Result<Json<ApiResponse<()>>, AppError> {
    let _ = &caller; // presence of a valid service-JWT is the authorization
    let updated = repo::set_request_status(state.db(), request_id, &req.request_status).await?;
    tracing::info!(updated, status = %req.request_status, "request_status pushed to conversations");
    Ok(Json(ApiResponse::success(())))
}

/// The explicit participant IDOR gate shared by list-messages / mark-read / upload. Admin
/// bypasses. A non-participant gets a generic `403` (never `_user: AuthUser` ignored).
async fn require_participant<S: ChatDeps>(
    state: &S,
    conversation_id: Uuid,
    user: &AuthUser,
) -> Result<(), AppError> {
    if user.role == ROLE_ADMIN {
        return Ok(());
    }
    if repo::is_participant(state.db(), conversation_id, user.user_id).await? {
        Ok(())
    } else {
        Err(AppError::Forbidden(
            "You are not a participant of this conversation".to_string(),
        ))
    }
}

// Re-exported for the WS module (persists + broadcasts). The sender's role is DERIVED inside
// `repo::send_message` from their conversation membership — the client `frame.sender_role` is
// advisory only and never trusted (no attribution spoofing).
pub(crate) async fn persist_and_broadcast<S: ChatDeps>(
    state: &S,
    sender: &AuthUser,
    frame: &IncomingChatMessage,
) -> Result<OutgoingChatMessage, AppError> {
    let message = repo::send_message(state.db(), sender.user_id, frame).await?;
    events::publish_chat_message(state.pubsub_conn(), &message).await;
    Ok(message)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::s3::S3Client;
    use crate::state::ChatInternalDeps;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::{get, post, put};
    use axum::Router;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use shared::auth::{encode_jwt_with_key, HasJwtSecret};
    use shared::service_jwt::{encode_service_jwt, HasServiceJwt};
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;
    use std::time::Duration;
    use tower::ServiceExt;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-chat-test!!!!!!!";
    const SERVICE_SECRET: &str =
        "service-secret-at-least-64-characters-long-for-internal-hs256-chat!!";

    use crate::booking_client::{BookingReader, InternalBooking};

    /// In-memory [`BookingReader`] stub: returns a fixed booking (or `NotFound`) so the
    /// create-conversation authz path is testable without a live booking service.
    #[derive(Clone)]
    struct StubBooking {
        booking: Option<InternalBooking>,
    }
    impl BookingReader for StubBooking {
        async fn get_booking(&self, _booking_id: Uuid) -> Result<InternalBooking, AppError> {
            self.booking
                .clone()
                .ok_or_else(|| AppError::NotFound("Booking not found".to_string()))
        }
    }

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        svc_dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
        redis: redis::aio::ConnectionManager,
        pubsub_client: redis::Client,
        s3: S3Client,
        booking: StubBooking,
    }
    impl HasJwtSecret for TestDeps {
        fn jwt_secret(&self) -> &str {
            SECRET
        }
        fn decoding_key(&self) -> &DecodingKey {
            &self.dec
        }
        fn redis_conn(&self) -> &redis::aio::ConnectionManager {
            &self.redis
        }
    }
    impl HasServiceJwt for TestDeps {
        fn service_decoding_key(&self) -> &DecodingKey {
            &self.svc_dec
        }
    }
    impl ChatDeps for TestDeps {
        type Booking = StubBooking;
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn db_read(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn pubsub_conn(&self) -> &redis::aio::ConnectionManager {
            &self.redis
        }
        fn pubsub_client(&self) -> &redis::Client {
            &self.pubsub_client
        }
        fn s3(&self) -> &S3Client {
            &self.s3
        }
        fn booking(&self) -> &StubBooking {
            &self.booking
        }
    }
    impl ChatInternalDeps for TestDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
    }

    fn s3_stub() -> S3Client {
        S3Client::new(
            reqwest::Client::new(),
            "http://localhost:9000".to_string(),
            None,
            "test".to_string(),
            "us-east-1".to_string(),
            "k".to_string(),
            "s".to_string(),
        )
    }

    /// Lazy pool to a closed port — used by the hermetic auth tests, whose paths short-circuit
    /// (401 at the extractor / 403 at the in-memory participant gate) before any DB access.
    fn lazy_pool() -> sqlx::PgPool {
        PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool")
    }

    async fn deps(db: sqlx::PgPool) -> Option<TestDeps> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        let redis_client = redis::Client::open(redis_url).ok()?;
        Some(TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            svc_dec: Arc::new(DecodingKey::from_secret(SERVICE_SECRET.as_bytes())),
            db,
            redis,
            pubsub_client: redis_client,
            s3: s3_stub(),
            // Default: no booking (create-conversation denies). Tests that exercise the create
            // path set an authoritative booking via `with_booking`.
            booking: StubBooking { booking: None },
        })
    }

    impl TestDeps {
        /// Configure the stub booking the create-conversation authz path reads.
        fn with_booking(mut self, booking: InternalBooking) -> Self {
            self.booking = StubBooking {
                booking: Some(booking),
            };
            self
        }
    }

    fn router(deps: TestDeps) -> Router {
        Router::new()
            .route("/conversations", post(create_conversation::<TestDeps>))
            .route("/conversations", get(list_conversations::<TestDeps>))
            .route(
                "/admin/conversations",
                get(admin_list_conversations::<TestDeps>),
            )
            .route(
                "/admin/conversations/{id}/messages",
                get(admin_list_messages::<TestDeps>),
            )
            .route(
                "/admin/conversations/{id}/status",
                put(admin_set_moderation_status::<TestDeps>),
            )
            .route(
                "/admin/messages/{id}",
                axum::routing::delete(admin_redact_message::<TestDeps>),
            )
            .route(
                "/admin/users/{user_id}/block",
                put(admin_block_user::<TestDeps>).delete(admin_unblock_user::<TestDeps>),
            )
            .route(
                "/conversations/{id}/messages",
                get(list_messages::<TestDeps>),
            )
            .route("/conversations/{id}/read", put(mark_read::<TestDeps>))
            .route("/attachments/{id}", get(get_attachment::<TestDeps>))
            .route(
                "/internal/conversations/by-request/{request_id}/status",
                put(internal_set_request_status::<TestDeps>),
            )
            .with_state(deps)
    }

    fn token(user_id: Uuid, role: &str) -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        encode_jwt_with_key(user_id, role, 0, &ek, 60).unwrap().0
    }

    fn svc_token() -> String {
        let ek = EncodingKey::from_secret(SERVICE_SECRET.as_bytes());
        encode_service_jwt("booking", &ek, 60).unwrap()
    }

    async fn status_of(app: Router, req: Request<Body>) -> StatusCode {
        app.oneshot(req).await.unwrap().status()
    }

    // ----- 401: every client route rejects a missing token (hermetic) -----

    #[tokio::test]
    async fn routes_reject_missing_token() {
        let Some(deps) = deps(lazy_pool()).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        let cases = [
            Request::builder()
                .method("GET")
                .uri("/conversations")
                .body(Body::empty())
                .unwrap(),
            Request::builder()
                .method("GET")
                .uri(format!("/conversations/{id}/messages"))
                .body(Body::empty())
                .unwrap(),
            Request::builder()
                .method("PUT")
                .uri(format!("/conversations/{id}/read"))
                .body(Body::empty())
                .unwrap(),
            Request::builder()
                .method("GET")
                .uri(format!("/attachments/{id}"))
                .body(Body::empty())
                .unwrap(),
        ];
        for req in cases {
            assert_eq!(
                status_of(router(deps.clone()), req).await,
                StatusCode::UNAUTHORIZED
            );
        }
    }

    #[tokio::test]
    async fn admin_list_conversations_rejects_non_admin() {
        let Some(deps) = deps(lazy_pool()).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not list every conversation cross-user (the 403 fires before any DB).
        let req = Request::builder()
            .method("GET")
            .uri("/admin/conversations")
            .header(
                "authorization",
                format!("Bearer {}", token(Uuid::new_v4(), "customer")),
            )
            .body(Body::empty())
            .unwrap();
        assert_eq!(status_of(router(deps), req).await, StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_list_messages_rejects_non_admin() {
        let Some(deps) = deps(lazy_pool()).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // The enriched audit view is admin-only — a non-admin (even a participant) gets 403 BEFORE
        // any DB read (the role gate fires first, like admin_list_conversations).
        let id = Uuid::new_v4();
        let req = Request::builder()
            .method("GET")
            .uri(format!("/admin/conversations/{id}/messages"))
            .header(
                "authorization",
                format!("Bearer {}", token(Uuid::new_v4(), "guard")),
            )
            .body(Body::empty())
            .unwrap();
        assert_eq!(status_of(router(deps), req).await, StatusCode::FORBIDDEN);
    }

    /// The Phase-D moderation WRITES are admin-only — a non-admin (even a participant) gets 403
    /// BEFORE any DB access (the require_admin gate fires first, like the read views). Covers
    /// redact-message, set-status, block, unblock.
    #[tokio::test]
    async fn moderation_writes_reject_non_admin() {
        let Some(deps) = deps(lazy_pool()).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        let tok = token(Uuid::new_v4(), "guard");
        let cases = [
            Request::builder()
                .method("DELETE")
                .uri(format!("/admin/messages/{id}"))
                .header("authorization", format!("Bearer {tok}"))
                .body(Body::empty())
                .unwrap(),
            Request::builder()
                .method("PUT")
                .uri(format!("/admin/conversations/{id}/status"))
                .header("authorization", format!("Bearer {tok}"))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"moderation_status":"archived"}"#))
                .unwrap(),
            Request::builder()
                .method("PUT")
                .uri(format!("/admin/users/{id}/block"))
                .header("authorization", format!("Bearer {tok}"))
                .body(Body::empty())
                .unwrap(),
            Request::builder()
                .method("DELETE")
                .uri(format!("/admin/users/{id}/block"))
                .header("authorization", format!("Bearer {tok}"))
                .body(Body::empty())
                .unwrap(),
        ];
        for req in cases {
            assert_eq!(
                status_of(router(deps.clone()), req).await,
                StatusCode::FORBIDDEN
            );
        }
    }

    /// An invalid `moderation_status` is rejected with 400 — but only AFTER the admin gate (an
    /// admin token + a bad status → 400; a non-admin → 403 regardless). The 400 path needs no DB
    /// (the validation fires before the repo call).
    #[tokio::test]
    async fn set_moderation_status_rejects_invalid_status() {
        let Some(deps) = deps(lazy_pool()).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        let req = Request::builder()
            .method("PUT")
            .uri(format!("/admin/conversations/{id}/status"))
            .header(
                "authorization",
                format!("Bearer {}", token(Uuid::new_v4(), "admin")),
            )
            .header("content-type", "application/json")
            .body(Body::from(r#"{"moderation_status":"deleted"}"#))
            .unwrap();
        assert_eq!(status_of(router(deps), req).await, StatusCode::BAD_REQUEST);
    }

    /// PURE enrichment: `enrich_message` resolves a text row to `text`, a media row to a presigned
    /// `attachment` view (image vs video by MIME), an unresolved media id to `attachment_id` only,
    /// and a call-summary `system` row to a structured `call_event` (kind `call-event`).
    #[test]
    fn enrich_message_renders_each_kind() {
        let s3 = s3_stub();
        let convo = Uuid::new_v4();
        let sender = Uuid::new_v4();

        let mk = |mtype: &str, content: Option<String>| OutgoingChatMessage {
            id: Uuid::new_v4(),
            conversation_id: convo,
            sender_id: sender,
            sender_role: Some("customer".to_string()),
            content,
            message_type: mtype.to_string(),
            created_at: chrono::Utc::now(),
            redacted: false,
        };

        // Build the attachment index the handler would have batch-fetched.
        let img_id = Uuid::new_v4();
        let vid_id = Uuid::new_v4();
        let mut by_id = std::collections::HashMap::new();
        by_id.insert(
            img_id,
            AttachmentRow {
                id: img_id,
                chat_id: convo,
                uploader_id: sender,
                file_key: format!("chat/{convo}/a.jpg"),
                file_url: None,
                file_size: Some(2048),
                mime_type: "image/jpeg".to_string(),
                created_at: chrono::Utc::now(),
            },
        );
        by_id.insert(
            vid_id,
            AttachmentRow {
                id: vid_id,
                chat_id: convo,
                uploader_id: sender,
                file_key: format!("chat/{convo}/b.mp4"),
                file_url: None,
                file_size: Some(4096),
                mime_type: "video/mp4".to_string(),
                created_at: chrono::Utc::now(),
            },
        );

        // text → kind=text, text carried, no attachment/call.
        let t = enrich_message(mk("text", Some("hello".to_string())), &by_id, &s3);
        assert_eq!(t.kind, "text");
        assert_eq!(t.text.as_deref(), Some("hello"));
        assert!(t.attachment.is_none() && t.call_event.is_none());

        // image → resolved presigned view, is_video=false.
        let i = enrich_message(mk("image", Some(img_id.to_string())), &by_id, &s3);
        assert_eq!(i.kind, "image");
        assert_eq!(
            i.attachment_id.as_deref(),
            Some(img_id.to_string().as_str())
        );
        let av = i.attachment.expect("image resolves to a view");
        assert_eq!(av.mime_type, "image/jpeg");
        assert!(!av.is_video);
        assert!(av.url.contains(&av.id.to_string()) || av.url.contains("a.jpg"));

        // video → is_video=true.
        let v = enrich_message(mk("video", Some(vid_id.to_string())), &by_id, &s3);
        let vv = v.attachment.expect("video resolves to a view");
        assert!(vv.is_video, "video mime flagged");

        // image referencing an UNKNOWN id → attachment_id echoed, attachment None (not blank).
        let missing = Uuid::new_v4();
        let u = enrich_message(mk("image", Some(missing.to_string())), &by_id, &s3);
        assert_eq!(
            u.attachment_id.as_deref(),
            Some(missing.to_string().as_str())
        );
        assert!(
            u.attachment.is_none(),
            "unresolved id → no view, id still surfaced"
        );

        // system call-summary → kind=call-event with parsed fields.
        let summary = crate::domain::CallSummary::from_call("video", "ended", None, true, Some(42));
        let c = enrich_message(mk("system", Some(summary.to_content())), &by_id, &s3);
        assert_eq!(c.kind, "call-event");
        let ce = c.call_event.expect("call summary parses");
        assert_eq!(ce.call_type, "video");
        assert_eq!(ce.outcome, "completed");
        assert_eq!(ce.duration_seconds, Some(42));

        // system NON-call JSON → stays kind=system, no call_event.
        let sys = enrich_message(
            mk("system", Some(r#"{"k":"other"}"#.to_string())),
            &by_id,
            &s3,
        );
        assert_eq!(sys.kind, "system");
        assert!(sys.call_event.is_none());

        // A REDACTED message (the read path already suppressed content to the placeholder) →
        // kind=redacted, the placeholder surfaced as text, and NO attachment/call resolution even
        // for what was a media row (the original is never re-exposed through the audit view).
        let mut redacted_media = mk(
            "image",
            Some(domain::REDACTED_CONTENT_PLACEHOLDER.to_string()),
        );
        redacted_media.redacted = true;
        let r = enrich_message(redacted_media, &by_id, &s3);
        assert_eq!(r.kind, "redacted");
        assert!(r.redacted);
        assert_eq!(
            r.text.as_deref(),
            Some(domain::REDACTED_CONTENT_PLACEHOLDER)
        );
        assert!(
            r.attachment.is_none() && r.attachment_id.is_none() && r.call_event.is_none(),
            "a redacted message resolves no attachment/call"
        );
    }

    /// Build an authoritative booking the stub reader returns for create-conversation.
    fn stub_booking(customer_id: Uuid, guard_id: Option<Uuid>, status: &str) -> InternalBooking {
        InternalBooking {
            id: Uuid::new_v4(),
            customer_id,
            guard_id,
            status: status.to_string(),
        }
    }

    fn create_req(caller: Uuid, role: &str, body: serde_json::Value) -> Request<Body> {
        Request::builder()
            .method("POST")
            .uri("/conversations")
            .header("authorization", format!("Bearer {}", token(caller, role)))
            .header("content-type", "application/json")
            .body(Body::from(body.to_string()))
            .unwrap()
    }

    #[tokio::test]
    async fn create_conversation_rejects_non_party_of_booking() {
        // Authenticated, but the caller is NEITHER the booking's customer NOR its assigned guard
        // → 403. Even though the client claims to be a participant in the body, identity is taken
        // from the AUTHORITATIVE booking (the stub), so the spoofed `participants` is ignored. The
        // 403 fires before any conversation INSERT (in-memory party check).
        let Some(deps) = deps(lazy_pool()).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let caller = Uuid::new_v4(); // NOT the booking's customer or guard
        let real_customer = Uuid::new_v4();
        let real_guard = Uuid::new_v4();
        let deps = deps.with_booking(stub_booking(real_customer, Some(real_guard), "accepted"));
        // The caller lies and lists THEMSELVES as the customer — must not matter.
        let body = serde_json::json!({
            "request_id": Uuid::new_v4(),
            "request_status": "accepted",
            "participants": [
                { "user_id": caller, "role": "customer" },
                { "user_id": real_guard, "role": "guard" }
            ]
        });
        assert_eq!(
            status_of(router(deps), create_req(caller, "customer", body)).await,
            StatusCode::FORBIDDEN
        );
    }

    #[tokio::test]
    async fn create_conversation_rejects_unknown_booking() {
        // No such booking (the stub returns NotFound) → 403, indistinguishable from "not your
        // booking" (no existence oracle on request_ids).
        let Some(deps) = deps(lazy_pool()).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // `deps` defaults to `booking: None` → the reader returns NotFound.
        let caller = Uuid::new_v4();
        let body = serde_json::json!({
            "request_id": Uuid::new_v4(),
            "participants": [{ "user_id": caller, "role": "customer" }]
        });
        assert_eq!(
            status_of(router(deps), create_req(caller, "customer", body)).await,
            StatusCode::FORBIDDEN
        );
    }

    // ----- internal endpoint: service-JWT guard (no DB needed to prove the guard) -----

    #[tokio::test]
    async fn internal_status_rejects_missing_and_invalid_service_token() {
        let Some(deps) = deps(lazy_pool()).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let rid = Uuid::new_v4();
        let uri = format!("/internal/conversations/by-request/{rid}/status");
        let missing = Request::builder()
            .method("PUT")
            .uri(&uri)
            .header("content-type", "application/json")
            .body(Body::from("{\"request_status\":\"completed\"}"))
            .unwrap();
        assert_eq!(
            status_of(router(deps.clone()), missing).await,
            StatusCode::UNAUTHORIZED
        );

        let invalid = Request::builder()
            .method("PUT")
            .uri(&uri)
            .header("authorization", "Bearer not.a.jwt")
            .header("content-type", "application/json")
            .body(Body::from("{\"request_status\":\"completed\"}"))
            .unwrap();
        assert_eq!(
            status_of(router(deps), invalid).await,
            StatusCode::UNAUTHORIZED
        );
    }

    // ----- DB+Redis-gated IDOR: non-participant → 403 on messages / mark-read / attachments -----

    async fn real_deps() -> Option<TestDeps> {
        let url = std::env::var("DATABASE_URL").ok()?;
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .ok()?;
        deps(db).await
    }

    /// Parse a `ConversationResponse` out of an `{ success, data }` body.
    async fn conv_from_response(res: axum::response::Response) -> serde_json::Value {
        let bytes = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .expect("read body");
        let v: serde_json::Value = serde_json::from_slice(&bytes).expect("json");
        v["data"].clone()
    }

    /// create_conversation DERIVES participants + status from the AUTHORITATIVE booking, ignoring
    /// the client-supplied identity/role/status — and is GET-OR-CREATE (a second POST for the same
    /// request_id returns the SAME conversation, no duplicate).
    #[tokio::test]
    async fn create_conversation_derives_from_booking_and_is_idempotent() {
        let Some(deps) = real_deps().await else {
            eprintln!(
                "SKIP: DATABASE_URL + TEST_REDIS_URL required for the create-conversation test"
            );
            return;
        };
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let request_id = Uuid::new_v4();
        // The booking is the source of truth (status `accepted`); the client will LIE below.
        let deps = deps.with_booking(stub_booking(customer, Some(guard), "accepted"));

        // The customer POSTs a body that injects a PHANTOM participant, a forged role, and a
        // forged status — none of which must survive (identity is booking-authoritative).
        let phantom = Uuid::new_v4();
        let body = serde_json::json!({
            "request_id": request_id,
            "request_status": "completed", // forged: would wrongly make it read-only
            "participants": [
                { "user_id": customer, "role": "guard", "display_name": "Me" }, // forged role
                { "user_id": phantom, "role": "customer", "display_name": "Phantom" } // injected
            ]
        });
        let res = router(deps.clone())
            .oneshot(create_req(customer, "customer", body))
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let data = conv_from_response(res).await;
        let conv_id: Uuid = serde_json::from_value(data["id"].clone()).unwrap();
        // Status comes from the booking (`accepted`), NOT the forged `completed`.
        assert_eq!(data["request_status"], serde_json::json!("accepted"));

        // Participants are exactly the booking's parties with their AUTHORITATIVE roles; the
        // phantom is absent, and the customer keeps role `customer` (not the forged `guard`).
        let parts: Vec<(Uuid, String)> = sqlx::query_as(
            "SELECT user_id, user_role FROM chat.participants WHERE conversation_id = $1 ORDER BY user_role",
        )
        .bind(conv_id)
        .fetch_all(&deps.db)
        .await
        .expect("load participants");
        assert_eq!(parts.len(), 2, "only the booking's two parties");
        assert!(
            parts.iter().any(|(u, r)| *u == customer && r == "customer"),
            "customer keeps role customer (forged guard role ignored)"
        );
        assert!(
            parts.iter().any(|(u, r)| *u == guard && r == "guard"),
            "the booking's guard is the other party"
        );
        assert!(
            !parts.iter().any(|(u, _)| *u == phantom),
            "the injected phantom participant is rejected"
        );

        // GET-OR-CREATE: a SECOND POST (now by the guard) for the same request_id returns the
        // SAME conversation — no duplicate row.
        let body2 = serde_json::json!({
            "request_id": request_id,
            "participants": [{ "user_id": guard, "role": "guard" }]
        });
        let res2 = router(deps.clone())
            .oneshot(create_req(guard, "guard", body2))
            .await
            .unwrap();
        assert_eq!(res2.status(), StatusCode::OK);
        let data2 = conv_from_response(res2).await;
        let conv_id2: Uuid = serde_json::from_value(data2["id"].clone()).unwrap();
        assert_eq!(
            conv_id2, conv_id,
            "second create returns the existing conversation"
        );

        let count: i64 =
            sqlx::query_scalar("SELECT count(*) FROM chat.conversations WHERE request_id = $1")
                .bind(request_id)
                .fetch_one(&deps.db)
                .await
                .expect("count");
        assert_eq!(
            count, 1,
            "exactly one conversation per request_id (idempotent)"
        );

        let _ = sqlx::query("DELETE FROM chat.conversations WHERE id = $1")
            .bind(conv_id)
            .execute(&deps.db)
            .await;
    }

    #[tokio::test]
    async fn idor_non_participant_forbidden_participant_ok() {
        let Some(deps) = real_deps().await else {
            eprintln!("SKIP: DATABASE_URL + TEST_REDIS_URL required for the IDOR router test");
            return;
        };
        use crate::models::{CreateConversationRequest, ParticipantInput};
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let stranger = Uuid::new_v4();
        let req = CreateConversationRequest {
            request_id: Uuid::new_v4(),
            request_status: Some("accepted".to_string()),
            participants: vec![
                ParticipantInput {
                    user_id: customer,
                    role: "customer".into(),
                    display_name: Some("C".into()),
                    avatar_url: None,
                },
                ParticipantInput {
                    user_id: guard,
                    role: "guard".into(),
                    display_name: Some("G".into()),
                    avatar_url: None,
                },
            ],
        };
        let conv = repo::create_conversation(&deps.db, &req)
            .await
            .expect("seed convo");
        let att = repo::save_attachment(
            &deps.db,
            conv.id,
            guard,
            &format!("chat/{}/x.jpg", conv.id),
            "https://s/x",
            Some(1),
            "image/jpeg",
        )
        .await
        .expect("seed attachment");

        let get_msgs = |tok: &str| {
            Request::builder()
                .method("GET")
                .uri(format!("/conversations/{}/messages", conv.id))
                .header("authorization", format!("Bearer {tok}"))
                .body(Body::empty())
                .unwrap()
        };
        let mark = |tok: &str| {
            Request::builder()
                .method("PUT")
                .uri(format!("/conversations/{}/read?role=customer", conv.id))
                .header("authorization", format!("Bearer {tok}"))
                .body(Body::empty())
                .unwrap()
        };
        let get_att = |tok: &str| {
            Request::builder()
                .method("GET")
                .uri(format!("/attachments/{}", att.id))
                .header("authorization", format!("Bearer {tok}"))
                .body(Body::empty())
                .unwrap()
        };

        // Stranger → 403 on all three.
        let st = token(stranger, "customer");
        assert_eq!(
            status_of(router(deps.clone()), get_msgs(&st)).await,
            StatusCode::FORBIDDEN
        );
        assert_eq!(
            status_of(router(deps.clone()), mark(&st)).await,
            StatusCode::FORBIDDEN
        );
        assert_eq!(
            status_of(router(deps.clone()), get_att(&st)).await,
            StatusCode::FORBIDDEN
        );
        // No existence oracle: a non-participant hitting a NON-EXISTENT attachment id gets the
        // SAME 403 (not a 404), so 403-vs-404 can't be used to probe which attachments exist.
        let missing = Uuid::new_v4();
        let get_att_missing = Request::builder()
            .method("GET")
            .uri(format!("/attachments/{missing}"))
            .header("authorization", format!("Bearer {st}"))
            .body(Body::empty())
            .unwrap();
        assert_eq!(
            status_of(router(deps.clone()), get_att_missing).await,
            StatusCode::FORBIDDEN,
            "non-participant gets 403 for a non-existent attachment too (no existence oracle)"
        );

        // Participant (the customer) → allowed (200) for messages + mark-read.
        let ct = token(customer, "customer");
        assert_eq!(
            status_of(router(deps.clone()), get_msgs(&ct)).await,
            StatusCode::OK
        );
        assert_eq!(
            status_of(router(deps.clone()), mark(&ct)).await,
            StatusCode::OK
        );

        // Admin bypass on attachments.
        let at = token(Uuid::new_v4(), "admin");
        assert_eq!(
            status_of(router(deps.clone()), get_att(&at)).await,
            StatusCode::OK
        );

        // cleanup (cascades).
        let _ = sqlx::query("DELETE FROM chat.conversations WHERE id = $1")
            .bind(conv.id)
            .execute(&deps.db)
            .await;
    }

    #[tokio::test]
    async fn internal_status_accepts_valid_service_token() {
        let Some(deps) = real_deps().await else {
            eprintln!("SKIP: DATABASE_URL + TEST_REDIS_URL required for the internal status test");
            return;
        };
        let rid = Uuid::new_v4();
        let req = Request::builder()
            .method("PUT")
            .uri(format!("/internal/conversations/by-request/{rid}/status"))
            .header("authorization", format!("Bearer {}", svc_token()))
            .header("content-type", "application/json")
            .body(Body::from("{\"request_status\":\"completed\"}"))
            .unwrap();
        // Valid service token + reachable DB → 200 (idempotent; 0 rows updated is fine).
        assert_eq!(status_of(router(deps), req).await, StatusCode::OK);
    }
}
