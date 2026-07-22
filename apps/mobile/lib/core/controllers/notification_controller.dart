import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/notification.dart';
import '../providers.dart';
import 'session_controller.dart';

part 'notification_controller.g.dart';

/// The notification list, from `GET /v1/notifications` (the caller's notifications, newest
/// first). Mark-read is OPTIMISTIC with rollback on failure. Pull-to-refresh re-fetches.
/// No polling — the badge ([UnreadCount]) refreshes on dashboard focus, not on a timer.
@riverpod
class NotificationController extends _$NotificationController {
  // True once this (autoDispose) controller is gone, so a rollback from an in-flight request
  // after the screen unmounts doesn't write to disposed state.
  bool _disposed = false;

  @override
  Future<List<AppNotification>> build() async {
    ref.onDispose(() => _disposed = true);
    // Scope to the ACTIVE role so a dual-role account in customer mode doesn't see the guard's
    // new-job items (whose tap 403s on another customer's booking) — the backend keeps role-agnostic
    // rows visible either way (deep-review). Omit when no session (defensive).
    final role = ref.read(sessionProvider).user?.role;
    final data = await ref
        .read(pguardApiProvider)
        .get('/notifications', query: role != null ? {'role': role} : null);
    final raw = data is List ? data : const [];
    return raw
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
      // The server count is now lower → refresh the bell badge source so it clears (the list and
      // the count are separate providers/endpoints; the optimistic list update alone never touches
      // the badge). Skip when disposed — the read survives, but there's no live count to refresh.
      if (!_disposed) ref.invalidate(unreadCountProvider);
    } catch (_) {
      if (!_disposed) state = AsyncData(original); // rollback
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
      // Read-all is scoped to the active role too, so customer mode never silently clears the
      // guard-role notifications (and vice-versa). Role in the path (put takes no query param).
      final role = ref.read(sessionProvider).user?.role;
      await ref
          .read(pguardApiProvider)
          .put('/notifications/read-all${role != null ? '?role=$role' : ''}');
      // clear the bell badge (→ 0)
      if (!_disposed) ref.invalidate(unreadCountProvider);
    } catch (_) {
      if (!_disposed) state = AsyncData(original); // rollback
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
    final role = ref.read(sessionProvider).user?.role;
    final data = await ref.read(pguardApiProvider).get(
        '/notifications/unread-count',
        query: role != null ? {'role': role} : null);
    if (data is Map<String, dynamic>) {
      return (data['count'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }
}
