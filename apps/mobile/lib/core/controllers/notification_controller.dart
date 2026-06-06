import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/notification.dart';
import '../providers.dart';

part 'notification_controller.g.dart';

/// The notification list, from `GET /v1/notifications` (the caller's notifications, newest
/// first). Mark-read is OPTIMISTIC with rollback on failure. Pull-to-refresh re-fetches.
/// No polling — the badge ([UnreadCount]) refreshes on dashboard focus, not on a timer.
@riverpod
class NotificationController extends _$NotificationController {
  @override
  Future<List<AppNotification>> build() async {
    final data = await ref.read(pguardApiProvider).get('/notifications');
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(AppNotification.fromJson)
        .toList();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// `PUT /v1/notifications/{id}/read` — optimistic; rolls back the list on failure.
  Future<void> markRead(String id) async {
    final list = state.valueOrNull;
    if (list == null) return;
    final idx = list.indexWhere((n) => n.id == id);
    if (idx < 0 || list[idx].isRead) return;

    final original = list;
    final optimistic = [...list];
    optimistic[idx] =
        list[idx].copyWith(isRead: true, readAt: DateTime.now().toUtc());
    state = AsyncData(optimistic);

    try {
      await ref.read(pguardApiProvider).put('/notifications/$id/read');
    } catch (_) {
      state = AsyncData(original); // rollback
    }
  }

  /// `PUT /v1/notifications/read-all` — optimistic; rolls back the list on failure.
  Future<void> markAllRead() async {
    final list = state.valueOrNull;
    if (list == null || list.every((n) => n.isRead)) return;

    final original = list;
    final now = DateTime.now().toUtc();
    state = AsyncData([
      for (final n in list)
        n.isRead ? n : n.copyWith(isRead: true, readAt: now),
    ]);

    try {
      await ref.read(pguardApiProvider).put('/notifications/read-all');
    } catch (_) {
      state = AsyncData(original); // rollback
    }
  }
}

/// The unread-notification count for the dashboard bell badge, from
/// `GET /v1/notifications/unread-count` → `{ count }`. A separate, lightweight provider (the
/// list may not be loaded on the dashboard). Refreshed on dashboard focus / after the user
/// returns from the notification screen — never on a `Timer.periodic`.
@riverpod
class UnreadCount extends _$UnreadCount {
  @override
  Future<int> build() async {
    final data =
        await ref.read(pguardApiProvider).get('/notifications/unread-count');
    if (data is Map<String, dynamic>) {
      return (data['count'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }
}
