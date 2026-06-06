import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/notification_controller.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pguard_header.dart';
import 'widgets/notification_tile.dart';

/// The notification centre: the caller's notifications with mark-read (tap) + mark-all-read.
/// Pull-to-refresh re-fetches; there is NO polling. UI per `Mobile - Guard App.html`.
class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationControllerProvider);
    final ctrl = ref.read(notificationControllerProvider.notifier);
    final hasUnread =
        async.valueOrNull?.any((n) => !n.isRead) ?? false;

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: 'การแจ้งเตือน',
        subtitle: 'Notifications',
        showBack: true,
        trailing: hasUnread
            ? TextButton(
                onPressed: ctrl.markAllRead,
                child: const Text(
                  'อ่านทั้งหมด',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorBody(
            message: e is ApiException
                ? e.message
                : 'โหลดการแจ้งเตือนไม่สำเร็จ / Could not load notifications',
            onRetry: ctrl.refresh,
          ),
          data: (list) => RefreshIndicator(
            onRefresh: ctrl.refresh,
            child: list.isEmpty
                ? const _EmptyBody()
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final n = list[i];
                      return NotificationTile(
                        notification: n,
                        onTap: n.isRead ? null : () => ctrl.markRead(n.id),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      // ListView so pull-to-refresh still works on the empty state.
      children: const [
        SizedBox(height: 120),
        Icon(Icons.notifications_off_outlined,
            size: 48, color: PgTokens.colorTextFaint),
        SizedBox(height: PgTokens.space3),
        Center(
          child: Text(
            'ยังไม่มีการแจ้งเตือน\nNo notifications yet',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: PgTokens.colorText),
          ),
        ),
        SizedBox(height: PgTokens.space2),
        Center(
          child: Text(
            'เราจะแจ้งเมื่อมีงานหรือข่าวสารใหม่\nWe\'ll let you know when something happens',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
          ),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PgTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 40, color: PgTokens.colorTextMuted),
            const SizedBox(height: PgTokens.space3),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: PgTokens.colorTextMuted)),
            const SizedBox(height: PgTokens.space3),
            TextButton(
                onPressed: onRetry,
                child: const Text('ลองใหม่ / Retry')),
          ],
        ),
      ),
    );
  }
}
