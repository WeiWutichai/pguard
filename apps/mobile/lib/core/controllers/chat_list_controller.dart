import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/chat.dart';
import '../providers.dart';

part 'chat_list_controller.g.dart';

/// The conversation list for the caller's ACTING role, from `GET /v1/conversations?role={acting}`
/// (N+1-free — one call resolves the counterpart name/avatar, last message, unread count + the
/// booking status). The acting role is passed by the entry point (guard dashboard → guard,
/// customer → customer), NEVER inferred from the user id. Pull-to-refresh re-fetches; no polling.
@riverpod
class ChatListController extends _$ChatListController {
  @override
  Future<List<Conversation>> build(ChatRole acting) async {
    final data = await ref
        .read(pguardApiProvider)
        .get('/conversations', query: {'role': acting.wire});
    final raw = data is List ? data : const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Conversation.fromJson)
        .toList();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
