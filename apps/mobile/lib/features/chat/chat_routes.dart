import '../../core/models/chat.dart';

/// Location builders for the chat routes (single source of truth for the path shapes the router
/// in `lib/routing/app_router.dart` parses). The acting role + read-only flag travel as query
/// params so the routes survive a deep link without relying on `extra`; the counterpart name is
/// passed as `extra` (optional, header only).
class ChatRoutes {
  const ChatRoutes._();

  /// The conversation list for an acting role.
  static String list(ChatRole acting) => '/chat?role=${acting.wire}';

  /// A single conversation. `readonly` is encoded `1`/`0`.
  static String conversation(
    String conversationId, {
    required ChatRole acting,
    required bool readOnly,
  }) =>
      '/chat/c/$conversationId?role=${acting.wire}&readonly=${readOnly ? 1 : 0}';
}
