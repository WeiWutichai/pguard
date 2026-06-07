import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/chat.dart';
import '../network/api_client.dart';
import '../network/sockets/chat_socket.dart';
import '../providers.dart';

part 'chat_controller.g.dart';

/// The real-time message list for one conversation. On build it loads history
/// (`GET /v1/conversations/{id}/messages`), marks the conversation read for the acting role
/// (`PUT .../read?role=`), and connects the chat WebSocket — whose pushed frames are folded in.
/// There is NO `Timer.periodic` polling: new messages arrive as server push.
///
/// Two invariants from the wire protocol:
///  - **Filter by conversation id.** One socket multiplexes ALL the user's conversations, so an
///    incoming frame for a different conversation is ignored.
///  - **Dedupe by message id.** The server echoes the sender's own message back, and history +
///    live can overlap, so every message id is admitted at most once.
///
/// Alignment is decided downstream by `sender_role == acting` (see [ChatMessage.isFromRole]),
/// never by sender id. Messages are kept oldest-first (natural append + autoscroll-to-bottom).
@riverpod
class ChatController extends _$ChatController {
  final Set<String> _seen = {};
  bool _disposed = false;
  ChatFeed? _feed;
  late String _conversationId;
  late ChatRole _acting;

  @override
  Future<List<ChatMessage>> build(String conversationId, ChatRole acting) async {
    _disposed = false; // reset every (re)build so a rebuilt notifier is never permanently muted
    _conversationId = conversationId;
    _acting = acting;
    _seen.clear();
    ref.onDispose(() => _disposed = true);

    final api = ref.read(pguardApiProvider);

    // History is newest-first on the wire → reverse to oldest-first for append + autoscroll.
    // Parsed defensively like the WS path (tryParse): one malformed row is dropped, not fatal.
    final data = await api.get('/conversations/$conversationId/messages');
    final raw = data is List ? data : const [];
    final history = raw
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.tryParse)
        .whereType<ChatMessage>()
        .toList()
        .reversed;
    // `_seen` is bounded by the screen-open lifetime (cleared here, disposed with the screen).
    final messages = <ChatMessage>[];
    for (final m in history) {
      if (_seen.add(m.id)) messages.add(m);
    }

    // Mark read for the acting role (best-effort — a failure must not break the screen).
    unawaited(_markRead(api));

    // NOTE: a message persisted in the tiny window between this history snapshot and the socket's
    // server-side subscription could be missed until reopen — acceptable for 1:1 low-volume booking
    // chat; dedupe-by-id makes any overlap safe.

    // Live feed: filter by conversation id + dedupe by message id as frames arrive.
    final feed = ref.read(chatFeedBuilderProvider)(() => api.validAccessToken());
    _feed = feed;
    final sub = feed.messages.listen(_onIncoming);
    ref.onDispose(() {
      sub.cancel();
      feed.close();
    });
    await feed.connect();

    return messages;
  }

  void _onIncoming(ChatMessage message) {
    if (_disposed) return;
    if (message.conversationId != _conversationId) return; // another conversation — ignore
    if (!_seen.add(message.id)) return; // echo / overlap — dedupe by id
    final current = state.valueOrNull ?? const <ChatMessage>[];
    state = AsyncData([...current, message]);
  }

  Future<void> _markRead(PguardApi api) async {
    try {
      // The embedded `?role=` is intentional (PguardApi.put takes no query map). The server uses
      // the JWT role for non-admins and ignores this param — harmless here since a user has exactly
      // one role, so the acting role always equals the token role.
      await api.put('/conversations/$_conversationId/read?role=${_acting.wire}');
    } catch (e) {
      // Best-effort (re-upserts next open); a debug breadcrumb (no PII) for a chronic failure.
      debugPrint('chat mark-read failed: $e');
    }
  }

  /// Send a text message over the WS. The input is cleared by the composer immediately; the
  /// bubble appears when the server echoes the persisted message back (deduped by id). A blank
  /// message is ignored. Read-only conversations hide the composer, and the server also rejects.
  void send(String text) {
    final body = text.trim();
    if (body.isEmpty || _feed == null) return;
    // If the socket is down (e.g. the documented gateway WS-proxy dependency) the frame is dropped
    // by ReconnectingWebSocket and the bubble only appears on the server echo — tracked limitation.
    _feed!.sendMessage(
      conversationId: _conversationId,
      content: body,
      type: ChatMessageType.text,
      senderRole: _acting,
    );
  }

  /// Send an already-uploaded attachment as an image/video message (the attachment id rides in
  /// `content`; the receiver resolves a fresh presigned URL via `GET /attachments/{id}`).
  void sendAttachment(Attachment attachment) {
    if (_feed == null) return;
    _feed!.sendMessage(
      conversationId: _conversationId,
      content: attachment.id,
      type: attachment.messageType,
      senderRole: _acting,
    );
  }
}
