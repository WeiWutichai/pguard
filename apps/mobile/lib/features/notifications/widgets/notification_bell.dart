import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/locale_controller.dart';
import '../../../core/controllers/notification_controller.dart';

/// The dashboard bell + unread-count badge. Watches [unreadCountProvider]; tapping opens the
/// notification centre and, on return, re-fetches the count (focus-refresh — NOT polling).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.color = Colors.white});

  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final count = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    return IconButton(
      tooltip: isThai ? 'การแจ้งเตือน' : 'Notifications',
      onPressed: () async {
        await context.push('/notifications');
        ref.invalidate(unreadCountProvider);
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.notifications_none, color: color, size: 22),
          if (count > 0)
            Positioned(right: -5, top: -4, child: _Badge(count: count)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 9 ? '9+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: PgTokens.colorDanger,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
