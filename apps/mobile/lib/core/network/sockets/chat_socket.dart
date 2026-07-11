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

  Future<void> connect();

  /// Send a message frame. `conversationId` travels IN the frame (it is NEVER in the URL — the
  /// contract rule). For media, `content` carries the attachment id and [type] is image/video.
  void sendMessage({
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
/// BACKEND DEPENDENCY (documented, mirrors `booking_status_socket.dart`): the api-gateway does
/// not yet proxy the `/v1/ws/chat` upgrade. This client codes against the agreed contract so the
/// screen works unchanged the moment a WS-aware ingress lands. NO polling: messages are push.
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
  Future<void> connect() => _ws.connect();

  @override
  void sendMessage({
    required String conversationId,
    String? content,
    required ChatMessageType type,
    required ChatRole senderRole,
  }) {
    _ws.send({
      'conversation_id': conversationId,
      if (content != null) 'content': content,
      'message_type': type.wire,
      'sender_role': senderRole.wire,
    });
  }

  @override
  Future<void> close() => _ws.close();
}
