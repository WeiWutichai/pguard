import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/chat.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../providers.dart';

part 'chat_launcher.g.dart';

/// Resolves the conversation to open for a booking, from an entry-point screen.
///
/// `POST /conversations` is NOT idempotent (the backend always inserts), so we must FIND first
/// and only create on a miss: look the booking up in the caller's conversation list (matched by
/// `request_id`); if absent, create it with the booking-derived participants. Returns the
/// conversation id to navigate to. Decoupled from Dio so it is unit-testable against a fake api.
///
/// Residual race (accepted): two TRULY-concurrent callers for the same booking could both miss the
/// find and both create. In practice the entry buttons debounce via their own busy flag, so this
/// needs two independent entry points firing at once. A single-flight by `request_id` here, or a
/// server-side `unique(request_id)` + treat-409-as-find, would close it fully.
class ChatLauncher {
  const ChatLauncher(this._api);

  final PguardApi _api;

  Future<String> resolveConversationId({
    required String requestId,
    required ChatRole acting,
    required List<ParticipantInput> participants,
    String? requestStatus,
  }) async {
    // 1) Find an existing conversation for this booking in the acting role's list.
    final data = await _api.get('/conversations', query: {'role': acting.wire});
    final raw = data is List ? data : const [];
    for (final item in raw.whereType<Map<String, dynamic>>()) {
      final conv = Conversation.fromJson(item);
      if (conv.requestId == requestId) return conv.id;
    }

    // 2) None found → create (only now, since POST is not idempotent).
    final created = await _api.post('/conversations', data: {
      'request_id': requestId,
      if (requestStatus != null) 'request_status': requestStatus,
      'participants': participants.map((p) => p.toJson()).toList(),
    });
    if (created is Map<String, dynamic> && created['id'] is String) {
      return created['id'] as String;
    }
    throw const ApiException(message: 'Could not open the conversation');
  }
}

/// Production [ChatLauncher] bound to the app's REST client.
@Riverpod(keepAlive: true)
ChatLauncher chatLauncher(ChatLauncherRef ref) =>
    ChatLauncher(ref.watch(pguardApiProvider));
