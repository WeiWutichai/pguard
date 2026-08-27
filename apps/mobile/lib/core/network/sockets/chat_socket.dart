import '../../config/app_config.dart';
import '../../models/chat.dart';
import 'ws_client.dart';

/// The real-time chat feed the [ChatController] depends on. An interface so the controller is
/// unit-testable against a fake (no real WebSocket); [ChatSocket] is the production implementation.
abstract class ChatFeed {
  /// Persisted messages arriving over the socket — both the counterpart's messages AND the
  /// echo of this client's own sends (so the controller must DEDUPE by message id).
  Stream<ChatMessage> get messages;

  /// Server ERROR frames — the reply to a REJECTED send (read-only conversation, participant
  /// gate, malformed frame). Split out of [messages] (which drops non-message frames) so a
  /// refused send is surfaced to the user instead of vanishing silently.
  Stream<ChatWsError> get errors;

  /// Connection liveness edges (`true` on open, `false` on drop). The hub replays no history on
  /// (re)connect, so the [ChatController] re-pulls the message page on each reconnect edge to
  /// recover frames missed while the socket was down.
  Stream<bool> get connectionChanges;

  Future<void> connect();

  /// Send a message frame. `conversationId` travels IN the frame (it is NEVER in the URL — the
  /// contract rule). For media, `content` carries the attachment id and [type] is image/video.
  ///
  /// Returns `true` when the frame reached a live socket, `false` when the socket was down and the
  /// frame was dropped — the caller keeps the user's text instead of silently destroying it.
  bool sendMessage({
    required String conversationId,
    String? content,
    required ChatMessageType type,
    required ChatRole senderRole,
  });

  Future<void> close();
}

/// Typed chat subscription over [ReconnectingWebSocket] (Bearer-on-upgrade, auto-reconnect).
///
/// Protocol (per `contracts/asyncapi/chat-ws.yaml` + the merged chat backend, `services/chat`):
///  - Connect to `{wsBaseUrl}/ws/chat` — **`conversation_id` is NOT in the URL**.
///  - **No subscribe frame is sent.** The server prefetches the user's participant conversations
///    on open and auto-forwards their broadcasts; and it PERSISTS every inbound frame, so a bare
///    `{conversation_id}` "subscribe" frame would create an empty message. `conversation_id`
///    instead rides on each real send frame.
///  - One socket multiplexes ALL the user's conversations (the server fans out every authorized
///    room over it). The [ChatController] therefore filters incoming by `conversation_id` and
///    dedupes by message id (the server echoes the sender's own message back to them).
///
/// BACKEND: the api-gateway NOW proxies the `/v1/ws/chat` upgrade (`crate::wsproxy`, registered in
/// `services/api-gateway/src/main.rs` and mapped `Upstream::Chat -> /ws/chat` in
/// `WS_PROXY_ROUTES`), exactly like `/v1/ws/track` (presence) and `/v1/ws/bookings/{id}`. The chat
/// service persists each frame + broadcasts it to the conversation's `chat:{id}` Redis channel for
/// cross-replica fan-out, so a message from one participant reaches the other IN REALTIME while both
/// have the conversation open. NO polling: messages are push. (The chat-list unread badge, which is
/// a REST fetch and only live while a conversation screen holds the socket, is bumped separately by
/// the FCM chat push in `push_registration_controller._handle`.)
class ChatSocket implements ChatFeed {
  ChatSocket({
    required Future<String?> Function() tokenProvider,
    WsChannelFactory? factory,
  }) : _ws = factory != null
            ? ReconnectingWebSocket(
                url: _url, tokenProvider: tokenProvider, factory: factory)
            : ReconnectingWebSocket(url: _url, tokenProvider: tokenProvider);

  final ReconnectingWebSocket _ws;

  static Uri get _url => Uri.parse('${AppConfig.wsBaseUrl}/ws/chat');

  /// Decoded message frames; error/heartbeat/non-message frames are filtered out by [ChatMessage.tryParse].
  @override
  Stream<ChatMessage> get messages => _ws.messages
      .map(ChatMessage.tryParse)
      .where((m) => m != null)
      .cast<ChatMessage>();

  /// Decoded server error frames (`{"type":"error",…}`) — the frames [messages] drops. A rejected
  /// send (e.g. the booking completed while the thread was open → `code: "read_only"`) reaches
  /// the controller here instead of disappearing.
  @override
  Stream<ChatWsError> get errors => _ws.messages
      .map(ChatWsError.tryParse)
      .where((e) => e != null)
      .cast<ChatWsError>();

  @override
  Stream<bool> get connectionChanges => _ws.connectionChanges;

  @override
  Future<void> connect() => _ws.connect();

  @override
  bool sendMessage({
    required String conversationId,
    String? content,
    required ChatMessageType type,
    required ChatRole senderRole,
  }) {
    return _ws.send({
      'conversation_id': conversationId,
      if (content != null) 'content': content,
      'message_type': type.wire,
      'sender_role': senderRole.wire,
    });
  }

  @override
  Future<void> close() => _ws.close();
}
