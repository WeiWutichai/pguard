import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/chat.dart';
import '../network/api_client.dart';
import '../network/sockets/chat_socket.dart';
import '../providers.dart';
import 'chat_list_controller.dart';

part 'chat_controller.g.dart';

/// Whether the conversation is CLOSED (read-only) according to the SERVER — the chat screen's
/// SELF-VERIFIED signal, independent of the navigation-time `readOnly` flag (which goes stale
/// when the booking completes while the thread is open, and is hardcoded `false` on the
/// push-notification entry — see `notification_target.dart`).
///
/// Resolution reuses the existing conversations-list fetch (`GET /v1/conversations?role=` already
/// returns `request_status` per row — no new endpoint): the list is awaited and this conversation's
/// [Conversation.isReadOnly] is the answer. Unknown conversation / fetch failure → `false` (fall
/// back to the navigation flag; the server still rejects writes, this gate is UX only).
///
/// [markClosed] flips it to `true` the moment a live send is rejected with `code == "read_only"`
/// (see [ChatController]) — and is STICKY: a closed booking never reopens, so a slower/stale list
/// fetch resolving after the flip must not undo it.
@riverpod
class ChatServerClosed extends _$ChatServerClosed {
  bool _closedByServer = false;

  @override
  Future<bool> build(String conversationId, ChatRole acting) async {
    final conversations =
        await ref.watch(chatListControllerProvider(acting).future);
    for (final conversation in conversations) {
      if (conversation.id == conversationId) {
        return _closedByServer || conversation.isReadOnly;
      }
    }
    return _closedByServer;
  }

  /// The server refused a send because the conversation is closed — latch read-only NOW (don't
  /// wait for a list re-fetch). Sticky across rebuilds via [_closedByServer].
  void markClosed() {
    _closedByServer = true;
    state = const AsyncData(true);
  }
}

/// The server's send-REJECTION frames for one conversation, as a watchable stream — lets the
/// screen `ref.listen` for the error snackbar without hand-managing a StreamSubscription.
/// Depends on the NOTIFIER instance (not its message-list state) so ordinary message updates
/// never resubscribe; keeping this provider watched also keeps the controller (and its socket)
/// alive.
@riverpod
Stream<ChatWsError> chatSendErrors(
        ChatSendErrorsRef ref, String conversationId, ChatRole acting) =>
    ref
        .watch(chatControllerProvider(conversationId, acting).notifier)
        .sendErrors;

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

  /// Re-broadcast of the feed's server-rejection frames (see [chatSendErrors]). Notifier-scoped
  /// and intentionally never closed: `build()` re-runs on the SAME notifier instance (a rebuild's
  /// `onDispose` must not kill it), and a listener-less broadcast controller holds no resources.
  final StreamController<ChatWsError> _errors =
      StreamController<ChatWsError>.broadcast();

  /// Server rejections of this user's sends (read-only conversation, participant gate, …) —
  /// consumed by the screen via [chatSendErrors] for the snackbar; the `read_only` flip of
  /// [ChatServerClosed] already happened in [_onSendError] by the time an event lands here.
  Stream<ChatWsError> get sendErrors => _errors.stream;

  @override
  Future<List<ChatMessage>> build(
      String conversationId, ChatRole acting) async {
    _disposed =
        false; // reset every (re)build so a rebuilt notifier is never permanently muted
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
    final feed =
        ref.read(chatFeedBuilderProvider)(() => api.validAccessToken());
    _feed = feed;
    final sub = feed.messages.listen(_onIncoming);
    // Rejected sends come back as ERROR frames on the same socket — surface them (snackbar via
    // [chatSendErrors]) and flip the read-only signal on `code == read_only` instead of letting
    // the frame vanish silently.
    final errSub = feed.errors.listen(_onSendError);
    // Recover messages MISSED during a WS gap. The hub forwards only LIVE frames and replays no
    // history on (re)connect, so a message the counterpart sent while the socket was down reaches
    // an OPEN thread never — it would surface only on reopen (deep-review). On each RECONNECT edge
    // re-pull the history page and fold in anything unseen (the `_seen` id-dedupe already makes the
    // overlap safe), mirroring BookingStatusController's reconnect re-pull. Baseline `true` so the
    // initial connect below — whose history we JUST fetched — is not treated as a reconnect.
    var wasConnected = true;
    final connSub = feed.connectionChanges.listen((connected) {
      final reconnected = connected && !wasConnected;
      wasConnected = connected;
      if (reconnected) unawaited(_repullOnReconnect(api));
    });
    ref.onDispose(() {
      sub.cancel();
      errSub.cancel();
      connSub.cancel();
      feed.close();
      // Mark read on LEAVE too. The open-time mark_read (above) captured `read_at` BEFORE any live
      // message arrived, so a message received WHILE the thread was open would re-surface as unread
      // when the list re-pulls on back-out. This advances `read_at` past everything seen this
      // session. Fire-and-forget with the captured `api` (the notifier is disposing).
      unawaited(_markRead(api));
    });
    await feed.connect();

    return messages;
  }

  /// Re-pull the history page after a reconnect and fold in any messages persisted while the socket
  /// was down (deduped by id — an overlap with what we already have is admitted at most once).
  /// Best-effort: a failed re-pull leaves the current list; a later live frame or a reopen recovers.
  Future<void> _repullOnReconnect(PguardApi api) async {
    if (_disposed) return;
    try {
      final data = await api.get('/conversations/$_conversationId/messages');
      if (_disposed) return;
      final raw = data is List ? data : const [];
      // Newest-first on the wire → oldest-first for natural append (same parse as [build]).
      final fresh = raw
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.tryParse)
          .whereType<ChatMessage>()
          .toList()
          .reversed;
      final additions = <ChatMessage>[];
      for (final m in fresh) {
        if (_seen.add(m.id)) additions.add(m);
      }
      if (additions.isEmpty) return;
      final current = state.valueOrNull ?? const <ChatMessage>[];
      state = AsyncData([...current, ...additions]);
      // The thread is foregrounded → keep `read_at` current so the recovered messages don't
      // resurface as unread on leave.
      unawaited(_markRead(api));
    } catch (_) {
      // Best-effort — the socket is back, so any newer message still arrives live.
    }
  }

  void _onIncoming(ChatMessage message) {
    if (_disposed) return;
    // another conversation — ignore
    if (message.conversationId != _conversationId) return;
    if (!_seen.add(message.id)) return; // echo / overlap — dedupe by id
    final current = state.valueOrNull ?? const <ChatMessage>[];
    state = AsyncData([...current, message]);
    // The thread is FOREGROUNDED, so the user is seeing this message → keep `read_at` current so the
    // unread badge doesn't reappear on leave. Best-effort; low-volume 1:1 chat so no throttle needed.
    unawaited(_markRead(ref.read(pguardApiProvider)));
  }

  void _onSendError(ChatWsError error) {
    if (_disposed) return;
    // The booking closed while the thread was open (the server is authoritative): latch the
    // self-verified read-only signal so the composer locks reactively — BEFORE re-broadcasting,
    // so the screen's snackbar handler already sees the locked state.
    if (error.isReadOnly) {
      ref
          .read(chatServerClosedProvider(_conversationId, _acting).notifier)
          .markClosed();
    }
    if (!_errors.isClosed) _errors.add(error);
  }

  Future<void> _markRead(PguardApi api) async {
    try {
      // The embedded `?role=` is intentional (PguardApi.put takes no query map). The server uses
      // the JWT role for non-admins and ignores this param — harmless here since a user has exactly
      // one role, so the acting role always equals the token role.
      await api
          .put('/conversations/$_conversationId/read?role=${_acting.wire}');
    } catch (e) {
      // Best-effort (re-upserts next open); a debug breadcrumb (no PII) for a chronic failure.
      debugPrint('chat mark-read failed: $e');
    }
  }

  /// Send a text message over the WS. The bubble appears when the server echoes the persisted
  /// message back (deduped by id). Returns `true` when the frame reached a live socket — the
  /// composer clears only then. Returns `false` for a BLANK message (nothing to send) OR when the
  /// socket is down and the frame was dropped: the caller keeps the user's text and surfaces a
  /// "couldn't send" hint instead of silently destroying it (deep-review — a dropped frame used to
  /// vanish from both the composer and the thread with no error). Read-only conversations hide the
  /// composer, and the server also rejects.
  bool send(String text) {
    final body = text.trim();
    if (body.isEmpty) return false;
    final feed = _feed;
    if (feed == null) return false;
    return feed.sendMessage(
      conversationId: _conversationId,
      content: body,
      type: ChatMessageType.text,
      senderRole: _acting,
    );
  }

  /// Send an already-uploaded attachment as an image/video message (the attachment id rides in
  /// `content`; the receiver resolves a fresh presigned URL via `GET /attachments/{id}`). Returns
  /// `false` when the socket was down and the frame was dropped (the attachment itself is already
  /// persisted server-side; only the chat message frame was lost) so the caller can surface it.
  bool sendAttachment(Attachment attachment) {
    final feed = _feed;
    if (feed == null) return false;
    return feed.sendMessage(
      conversationId: _conversationId,
      content: attachment.id,
      type: attachment.messageType,
      senderRole: _acting,
    );
  }
}
