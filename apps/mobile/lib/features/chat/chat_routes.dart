import '../../core/models/chat.dart';

/// Location builders for the chat routes (single source of truth for the path shapes the router
/// in `lib/routing/app_router.dart` parses). The acting role + read-only flag travel as query
/// params so the routes survive a deep link without relying on `extra`; the counterpart name is
/// passed as `extra` (optional, header only).
class ChatRoutes {
  const ChatRoutes._();

  /// The conversation list for an acting role.
  static String list(ChatRole acting) => '/chat?role=${acting.wire}';

  /// A single conversation. `readonly` is encoded `1`/`0`. [bookingId] (the linked
  /// `request_id`) + [callable] power the in-thread call action; both are optional so a deep
  /// link / chat-list open (no booking context) still works — the call action simply hides.
  static String conversation(
    String conversationId, {
    required ChatRole acting,
    required bool readOnly,
    String? bookingId,
    bool callable = false,
  }) {
    final params = <String, String>{
      'role': acting.wire,
      'readonly': readOnly ? '1' : '0',
      if (bookingId != null) 'booking': bookingId,
      if (callable) 'callable': '1',
    };
    final query =
        params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return '/chat/c/$conversationId?$query';
  }
}
