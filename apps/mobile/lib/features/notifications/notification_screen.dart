import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/notification_controller.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/models/notification.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pg_skeleton.dart';
import '../../widgets/pguard_header.dart';
import 'notification_target.dart';
import 'widgets/notification_tile.dart';

/// The notification centre: the caller's notifications with mark-read (tap) + mark-all-read.
/// Pull-to-refresh re-fetches; there is NO polling. UI per `Mobile - Guard App.html`.
class NotificationScreen extends ConsumerStatefulWidget {
  const NotificationScreen({super.key});

  @override
  ConsumerState<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen> {
  // Fire the open-time badge-clear exactly once (post first loaded-with-unread build).
  bool _autoMarked = false;

  // The rows that were unread WHEN THE CENTRE OPENED. Opening clears the bell badge (a server
  // read-all flips every row's `is_read`), but these rows stay visually highlighted until the user
  // taps each one — so the highlight isn't erased wholesale the instant the screen appears. Ids are
  // removed on individual tap (see [_open]).
  final Set<String> _highlightUntilTapped = {};

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(notificationControllerProvider);
    final ctrl = ref.read(notificationControllerProvider.notifier);
    final list = async.valueOrNull;
    final hasUnread = list?.any((n) => !n.isRead) ?? false;

    // OPENING the centre = seeing everything → clear the bell BADGE (the reported "read them all but
    // the number stays"; users expect opening the list to be enough). We still fire the server
    // read-all so the unread-count drops to 0, BUT first snapshot which rows were unread so their
    // ROW highlight survives the read-all and only clears on an individual tap. Fire once, post-frame
    // (never mutate during build).
    if (hasUnread && !_autoMarked && list != null) {
      _autoMarked = true;
      _highlightUntilTapped.addAll([
        for (final n in list)
          if (!n.isRead) n.id
      ]);
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.markAllRead());
    }

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'การแจ้งเตือน' : 'Notifications',
        showBack: true,
        trailing: hasUnread
            ? TextButton(
                onPressed: ctrl.markAllRead,
                child: Text(
                  isThai ? 'อ่านทั้งหมด' : 'Mark all read',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              )
            : null,
      ),
      // Stale-while-revalidate (perf-review #1): render the LAST-KNOWN notifications (`list`, already
      // `valueOrNull`) so a re-entry never blanks; a skeleton list on a genuine first load (not a
      // full-screen spinner); the error state only with no data.
      body: SafeArea(
        child: list == null
            ? (async.hasError
                ? PgErrorState(
                    title: isThai
                        ? 'โหลดการแจ้งเตือนไม่สำเร็จ'
                        : 'Could not load notifications',
                    message: async.error is ApiException
                        ? (async.error as ApiException).message
                        : null,
                    onRetry: ctrl.refresh,
                  )
                : const Padding(
                    padding: EdgeInsets.all(PgTokens.space4),
                    child: PgSkeletonList(count: 6, itemHeight: 72),
                  ))
            : RefreshIndicator(
                onRefresh: ctrl.refresh,
                child: list.isEmpty
                    ? _EmptyBody(isThai: isThai)
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final n = list[i];
                          // Every tile is tappable: mark read (no-op if already read) THEN open the
                          // notification's target screen, if any (booking / chat / call).
                          // `forceUnread` keeps a row highlighted after the open-time badge-clear
                          // read-all, until this row is individually tapped (see [_open]).
                          return NotificationTile(
                            notification: n,
                            forceUnread: _highlightUntilTapped.contains(n.id),
                            onTap: () => _open(context, ref, n),
                          );
                        },
                      ),
              ),
      ),
    );
  }

  /// Mark the notification read (optimistic, no-op if already read) and navigate to its target
  /// screen, if it resolves to one. Read-first so the badge/dot clears even when there is no
  /// destination (e.g. a payment/rating notice). Tapping a row also drops its open-time highlight
  /// so the unread paint clears for THIS row only (the rest stay highlighted until tapped).
  Future<void> _open(
      BuildContext context, WidgetRef ref, AppNotification n) async {
    if (_highlightUntilTapped.remove(n.id)) setState(() {});
    if (!n.isRead) {
      // Fire-and-forget the server write; the optimistic update + count refresh happen inside.
      unawaited(
          ref.read(notificationControllerProvider.notifier).markRead(n.id));
    }
    final user = ref.read(sessionProvider).user;
    final target = notificationTarget(n, user: user);
    if (target != null && context.mounted) context.push(target);
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return ListView(
      // ListView so pull-to-refresh still works on the empty state.
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.notifications_off_outlined,
            size: 48, color: PgTokens.colorTextFaint),
        const SizedBox(height: PgTokens.space3),
        Center(
          child: Text(
            isThai ? 'ยังไม่มีการแจ้งเตือน' : 'No notifications yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: PgTokens.colorText),
          ),
        ),
        const SizedBox(height: PgTokens.space2),
        Center(
          child: Text(
            isThai
                ? 'เราจะแจ้งเมื่อมีงานหรือข่าวสารใหม่'
                : 'We\'ll let you know when something happens',
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
          ),
        ),
      ],
    );
  }
}
