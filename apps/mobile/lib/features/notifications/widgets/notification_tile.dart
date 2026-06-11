import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/locale_controller.dart';
import '../../../core/controllers/relative_time.dart';
import '../../../core/models/notification.dart';

/// One notification row: type-coloured icon tile, title + body, relative time, and an unread
/// highlight + dot. The relative time follows the language toggle (locale-aware).
class NotificationTile extends ConsumerWidget {
  const NotificationTile({super.key, required this.notification, this.onTap});

  final AppNotification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thai = ref.watch(localeControllerProvider) == AppLocale.th;
    final now = DateTime.now();
    final rel = thai
        ? RelativeTime.th(notification.sentAt, now: now)
        : RelativeTime.en(notification.sentAt, now: now);
    final style = _styleFor(notification.type);
    final unread = !notification.isRead;

    return Material(
      color: unread ? PgTokens.colorGreen50 : PgTokens.colorSurface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          // Design `.notif`: padding 14px 20px (20 = space4+space1; no 20px token).
          padding: const EdgeInsets.symmetric(
              horizontal: PgTokens.space4 + PgTokens.space1, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: PgTokens.colorBorder)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(PgTokens.radiusLg),
                ),
                child: Icon(style.icon, color: style.color, size: 18),
              ),
              const SizedBox(width: 13), // design `.notif` gap: 13px
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Design `.nt`: one 13.5px run, '<bold title> · body' —
                    // unread is conveyed by the row tint + dot only.
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: notification.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (notification.body.isNotEmpty)
                            TextSpan(text: ' · ${notification.body}'),
                        ],
                      ),
                      style: const TextStyle(
                          fontSize: 13.5, color: PgTokens.colorText),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      rel,
                      style: const TextStyle(
                          fontSize: 11, color: PgTokens.colorTextFaint),
                    ),
                  ],
                ),
              ),
              if (unread)
                Container(
                  margin: const EdgeInsets.only(left: PgTokens.space2, top: 6),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: PgTokens.colorPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotifStyle {
  const _NotifStyle(this.icon, this.color);
  final IconData icon;
  final Color color;
}

/// Type → icon + colour (icons live in the widget layer, not the model).
_NotifStyle _styleFor(NotificationType type) {
  switch (type) {
    case NotificationType.bookingCreated:
      return const _NotifStyle(Icons.event_available_outlined, PgTokens.colorSuccess);
    case NotificationType.guardAssigned:
      return const _NotifStyle(Icons.verified_user_outlined, PgTokens.colorPrimary);
    case NotificationType.guardEnRoute:
      return const _NotifStyle(Icons.directions_car_outlined, PgTokens.colorInfo);
    case NotificationType.guardArrived:
      return const _NotifStyle(Icons.location_on_outlined, PgTokens.colorSuccess);
    case NotificationType.bookingCompleted:
      return const _NotifStyle(Icons.task_alt, PgTokens.colorSuccess);
    case NotificationType.bookingCancelled:
      return const _NotifStyle(Icons.cancel_outlined, PgTokens.colorDanger);
    case NotificationType.chatMessage:
      return const _NotifStyle(Icons.chat_bubble_outline, PgTokens.colorInfo);
    case NotificationType.system:
      return const _NotifStyle(Icons.notifications_none, PgTokens.colorTextMuted);
  }
}
