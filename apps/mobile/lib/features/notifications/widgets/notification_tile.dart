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
    // Localize the copy by TYPE so it follows the language toggle. The notification service sends
    // server-rendered title/body that aren't all localized (e.g. `booking_created` arrives as the
    // English "New job nearby" even in Thai mode) — for the known types we render our own locale copy
    // and keep the server strings only for `system` (reviews / calls / payments etc. we don't model).
    final copy = _copyFor(notification, thai);

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
                            text: copy.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (copy.body.isNotEmpty)
                            TextSpan(text: ' · ${copy.body}'),
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

class _NotifCopy {
  const _NotifCopy(this.title, this.body);
  final String title;
  final String body;
}

/// Locale-aware title + body by TYPE. For the modelled types we render our own copy (so a
/// server-side English string never leaks into Thai mode); `system` — reviews/calls/payments and
/// any forward-compat kind we don't model — keeps the server-rendered strings.
_NotifCopy _copyFor(AppNotification n, bool thai) {
  switch (n.type) {
    case NotificationType.bookingCreated:
      return thai
          ? const _NotifCopy('งานใหม่ใกล้คุณ', 'มีงานใหม่ใกล้คุณ แตะเพื่อดู')
          : const _NotifCopy(
              'New job nearby', 'A new job is available near you');
    case NotificationType.guardAssigned:
      return thai
          ? const _NotifCopy('รับงานแล้ว', 'เจ้าหน้าที่รับงานของคุณแล้ว')
          : const _NotifCopy('Guard assigned', 'A guard accepted your booking');
    case NotificationType.guardEnRoute:
      return thai
          ? const _NotifCopy('กำลังเดินทาง', 'เจ้าหน้าที่กำลังเดินทางไปหาคุณ')
          : const _NotifCopy('On the way', 'Your guard is on the way');
    case NotificationType.guardArrived:
      return thai
          ? const _NotifCopy('ถึงจุดนัดแล้ว', 'เจ้าหน้าที่ถึงจุดนัดหมายแล้ว')
          : const _NotifCopy('Arrived', 'Your guard has arrived');
    case NotificationType.bookingCompleted:
      return thai
          ? const _NotifCopy('งานเสร็จสมบูรณ์', 'งานของคุณเสร็จสมบูรณ์แล้ว')
          : const _NotifCopy('Job completed', 'Your job is complete');
    case NotificationType.bookingCancelled:
      return thai
          ? const _NotifCopy('งานถูกยกเลิก', 'งานถูกยกเลิกแล้ว')
          : const _NotifCopy('Booking cancelled', 'The booking was cancelled');
    case NotificationType.chatMessage:
      return thai
          ? const _NotifCopy('ข้อความใหม่', 'คุณมีข้อความใหม่')
          : const _NotifCopy('New message', 'You have a new message');
    case NotificationType.system:
      // Not modelled → trust the server copy (already localized for these).
      return _NotifCopy(n.title, n.body);
  }
}

/// Type → icon + colour (icons live in the widget layer, not the model).
_NotifStyle _styleFor(NotificationType type) {
  switch (type) {
    case NotificationType.bookingCreated:
      return const _NotifStyle(
          Icons.event_available_outlined, PgTokens.colorSuccess);
    case NotificationType.guardAssigned:
      return const _NotifStyle(
          Icons.verified_user_outlined, PgTokens.colorPrimary);
    case NotificationType.guardEnRoute:
      return const _NotifStyle(
          Icons.directions_car_outlined, PgTokens.colorInfo);
    case NotificationType.guardArrived:
      return const _NotifStyle(
          Icons.location_on_outlined, PgTokens.colorSuccess);
    case NotificationType.bookingCompleted:
      return const _NotifStyle(Icons.task_alt, PgTokens.colorSuccess);
    case NotificationType.bookingCancelled:
      return const _NotifStyle(Icons.cancel_outlined, PgTokens.colorDanger);
    case NotificationType.chatMessage:
      return const _NotifStyle(Icons.chat_bubble_outline, PgTokens.colorInfo);
    case NotificationType.system:
      return const _NotifStyle(
          Icons.notifications_none, PgTokens.colorTextMuted);
  }
}
