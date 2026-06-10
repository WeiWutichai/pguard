// Chat domain models — mirror `contracts/openapi/chat.yaml` + `contracts/asyncapi/chat-ws.yaml`.
// PURE (no Flutter / no IO) so alignment, read-only, dedupe-key and parsing are unit-testable.
//
// v2 wire rules baked in:
//  - Alignment is decided by `sender_role` vs the caller's ACTING role — NEVER by `sender_id`
//    (the same user is the guard in one conversation and the customer in another). See
//    [ChatMessage.isFromRole].
//  - Read-only is derived from the booking's `request_status` (`completed`/`cancelled`); the
//    server also rejects writes, so the client gate is UX only. See [ChatReadOnly].

/// The role the caller is acting AS in a conversation (drives bubble side + read receipts).
/// Passed in by the entry point (guard dashboard → [guard]; customer → [customer]) — never
/// inferred from the user id.
enum ChatRole {
  guard('guard'),
  customer('customer');

  const ChatRole(this.wire);

  final String wire;

  static ChatRole? tryParse(String? value) {
    for (final r in ChatRole.values) {
      if (r.wire == value) return r;
    }
    return null;
  }
}

/// The kind of a chat message. `image`/`video` reference an uploaded attachment (the attachment
/// id travels in `content`; the presigned URL is resolved separately via `GET /attachments/{id}`).
enum ChatMessageType {
  text('text'),
  image('image'),
  video('video'),
  system('system');

  const ChatMessageType(this.wire);

  final String wire;

  bool get isMedia => this == ChatMessageType.image || this == ChatMessageType.video;

  /// Parse a wire value; unknown/absent → [text] (forward-compatible).
  static ChatMessageType parse(String? value) {
    for (final t in ChatMessageType.values) {
      if (t.wire == value) return t;
    }
    return ChatMessageType.text;
  }
}

/// Read-only decision for a conversation, from the linked booking's `request_status`. A
/// `completed`/`cancelled` booking disables sending (composer hidden). PURE + unit-testable.
class ChatReadOnly {
  const ChatReadOnly._();

  static bool fromStatus(String? requestStatus) =>
      requestStatus == 'completed' || requestStatus == 'cancelled';
}

/// One chat message — the shape of both `GET /conversations/{id}/messages` rows AND the WS
/// `OutgoingChatMessage` broadcast/echo frame (identical fields).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.createdAt,
    this.senderRole,
    this.content,
  });

  final String id;
  final String conversationId;
  final String senderId;

  /// `guard` | `customer` (or null for `system`) — the ONLY alignment signal (never sender_id).
  final String? senderRole;
  final String? content;
  final ChatMessageType type;
  final DateTime createdAt;

  /// `true` when this message was sent in the caller's acting role → render on the RIGHT (me).
  /// Alignment by role, NEVER by sender_id (rule: a user can be guard here, customer elsewhere).
  bool isFromRole(ChatRole acting) => senderRole == acting.wire;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        senderId: (json['sender_id'] as String?) ?? '',
        senderRole: json['sender_role'] as String?,
        content: json['content'] as String?,
        type: ChatMessageType.parse(json['message_type'] as String?),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
      );

  /// Parse a decoded WS frame into a message, or `null` if it is not a message (e.g. a
  /// `{ "type":"error", ... }` frame, or a malformed/heartbeat frame). Lets the socket layer
  /// `.where((m) => m != null)` so only real messages reach the controller.
  static ChatMessage? tryParse(Map<String, dynamic> json) {
    if (json['type'] == 'error') return null; // server error frame — not a message
    if (json['id'] is! String || json['conversation_id'] is! String) return null;
    return ChatMessage.fromJson(json);
  }
}

/// An enriched conversation row from `GET /conversations?role=` (N+1-free). The counterpart is
/// the participant whose role differs from the acting role (already resolved server-side).
class Conversation {
  const Conversation({
    required this.id,
    required this.requestId,
    required this.createdAt,
    required this.unreadCount,
    this.participantId,
    this.participantName,
    this.participantAvatar,
    this.lastMessage,
    this.lastMessageAt,
    this.requestStatus,
  });

  final String id;
  final String requestId;
  final DateTime createdAt;
  final int unreadCount;
  final String? participantId;
  final String? participantName;
  final String? participantAvatar;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? requestStatus;

  bool get hasUnread => unreadCount > 0;

  /// The conversation is read-only when its booking is `completed`/`cancelled`.
  bool get isReadOnly => ChatReadOnly.fromStatus(requestStatus);

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        requestId: json['request_id'] as String,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
        participantId: json['participant_id'] as String?,
        participantName: json['participant_name'] as String?,
        participantAvatar: json['participant_avatar'] as String?,
        lastMessage: json['last_message'] as String?,
        lastMessageAt: json['last_message_at'] != null
            ? DateTime.tryParse(json['last_message_at'] as String)?.toUtc()
            : null,
        requestStatus: json['request_status'] as String?,
      );
}

/// Total unread messages across [conversations], optionally narrowed to one booking's
/// conversation(s) via [requestId]. PURE — drives the entry-point unread badges.
int unreadTotal(Iterable<Conversation> conversations, {String? requestId}) =>
    conversations
        .where((c) => requestId == null || c.requestId == requestId)
        .fold(0, (sum, c) => sum + c.unreadCount);

/// A participant for `POST /conversations` — booking-derived role + optional display data
/// supplied inline by the creator (v2 forbids the cross-schema JOIN v1 used to resolve names).
class ParticipantInput {
  const ParticipantInput({
    required this.userId,
    required this.role,
    this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final ChatRole role;
  final String? displayName;
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'role': role.wire,
        if (displayName != null) 'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };
}

/// An uploaded attachment from `POST /attachments` / `GET /attachments/{id}` — the presigned
/// `fileUrl` is short-lived (TTL 1h), regenerated on each GET (so we resolve it on view).
class Attachment {
  const Attachment({
    required this.id,
    required this.chatId,
    required this.fileUrl,
    required this.mimeType,
    this.fileSize,
  });

  final String id;
  final String chatId;
  final String fileUrl;
  final String mimeType;
  final int? fileSize;

  /// The message type to send for this attachment (`image`/`video` from the MIME family).
  ChatMessageType get messageType =>
      mimeType.startsWith('video/') ? ChatMessageType.video : ChatMessageType.image;

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String,
        chatId: (json['chat_id'] as String?) ?? '',
        fileUrl: (json['file_url'] as String?) ?? '',
        mimeType: (json['mime_type'] as String?) ?? 'application/octet-stream',
        fileSize: (json['file_size'] as num?)?.toInt(),
      );
}
