import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/locale_controller.dart';
import '../../../core/controllers/relative_time.dart';
import '../../../core/models/notification.dart';
import '../../booking/widgets/cancel_reason.dart';

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
    // and keep the server strings for `system` (reviews / calls / payments etc. we don't model).
    // The exception is the CANCELLATION kinds, whose body is not a constant: they read the payload
    // (`target_role`, `cancellation_reason`/`_note`) and fall back to the server body — see
    // [_cancelledCopy] / [_cancelBody].
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
      return _cancelledCopy(n, thai);
    case NotificationType.chatMessage:
      return thai
          ? const _NotifCopy('ข้อความใหม่', 'คุณมีข้อความใหม่')
          : const _NotifCopy('New message', 'You have a new message');
    case NotificationType.system:
      // Several server kinds (declined / completion-requested / payment / review / call) are all
      // `system` on the wire with pre-rendered THAI title+body, so they never followed the language
      // toggle. Localize them here by the payload's `event_type`; a truly-unknown kind keeps the
      // server copy.
      return _systemCopy(n, thai);
  }
}

/// A cancelled/declined notification's reason, ready to read: the localized label for the stable
/// `cancellation_reason` CODE the event carries, with the free-text `cancellation_note` in
/// parentheses when the canceller left one. Null when the notification carries no reason (a
/// pre-migration booking, or a kind that has none) — callers then fall back to plain copy.
///
/// Deliberately built from the CODE rather than the server's sentence: the payload is
/// locale-independent, so an English reader gets English here instead of the service's Thai.
String? _reasonPhrase(AppNotification n, bool thai) {
  final code = n.payload['cancellation_reason'];
  final label = PgCancelReason.labelFor(code is String ? code : null, thai);
  if (label.isEmpty) return null;
  final raw = n.payload['cancellation_note'];
  final note = raw is String ? raw.trim() : '';
  return note.isEmpty ? label : '$label ($note)';
}

/// Body copy for a cancellation-shaped notification. Prefers OUR localized sentence carrying the
/// payload's reason; with no structured reason it falls back to the SERVER's own body in Thai
/// mode (that is the notification service's own rendering — the richest thing available, reason
/// included when it interpolated one), and only then to the plain [head] + [tail].
String _cancelBody(AppNotification n, bool thai,
    {required String head, String? tail}) {
  final reason = _reasonPhrase(n, thai);
  if (reason == null) {
    final server = n.body.trim();
    if (thai && server.isNotEmpty) return server;
    return [head, if (tail != null) tail].join(' ');
  }
  final withReason =
      thai ? '$head — เหตุผล: $reason' : '$head — reason: $reason';
  return [withReason, if (tail != null) tail].join(' ');
}

/// `booking_cancelled` copy. The server body for this type is NOT a constant — it names WHO
/// cancelled (the guard reads "ลูกค้ายกเลิกงานแล้ว", the customer "งานของคุณถูกยกเลิกแล้ว") and now
/// carries the reason the booking service interpolates; the old const `_NotifCopy` threw all of
/// that away and always said "งานถูกยกเลิกแล้ว". Rebuild it from the payload instead: `target_role`
/// picks the side, `cancellation_reason` supplies the why.
_NotifCopy _cancelledCopy(AppNotification n, bool thai) {
  final guardSide = n.payload['target_role'] == 'guard';
  final head = guardSide
      ? (thai ? 'ลูกค้ายกเลิกงานแล้ว' : 'The customer cancelled the job')
      : (thai ? 'งานของคุณถูกยกเลิกแล้ว' : 'Your booking was cancelled');
  return _NotifCopy(
    thai ? 'งานถูกยกเลิก' : 'Booking cancelled',
    _cancelBody(n, thai, head: head),
  );
}

_NotifCopy _systemCopy(AppNotification n, bool thai) {
  final event = n.payload['event_type'] as String?;
  switch (event) {
    case 'pguard.events.booking.declined':
      // `declined` is TERMINAL — the booking never re-enters discovery, so
      // "กำลังค้นหาเจ้าหน้าที่ใหม่ให้คุณ" / "Finding you another guard" promised a search that never
      // happens. The notification service already stopped claiming it (see
      // `services/notification/src/domain/mapping.rs` BOOKING_DECLINED); this client copy was
      // still lying over the top of it. Say what is true — the job ended, a paid booking is
      // refunded in full — and carry the GUARD's reason through to the customer.
      return _NotifCopy(
        thai ? 'เจ้าหน้าที่ยกเลิกงาน' : 'Guard cancelled the job',
        _cancelBody(
          n,
          thai,
          head:
              thai ? 'เจ้าหน้าที่ยกเลิกงานนี้' : 'The guard cancelled this job',
          tail: thai
              ? 'หากชำระเงินแล้วระบบจะคืนเงินให้เต็มจำนวน กรุณาจองใหม่อีกครั้ง'
              : 'Any payment is refunded in full — please book again.',
        ),
      );
    case 'pguard.events.booking.completion_requested':
      return thai
          ? const _NotifCopy(
              'เจ้าหน้าที่ขอปิดงาน', 'เจ้าหน้าที่ขอปิดงาน — โปรดตรวจสอบ')
          : const _NotifCopy('Completion requested',
              'The guard asked to close the job — please review');
    case 'pguard.events.payment.completed':
      final guardSide = n.payload['target_role'] == 'guard';
      if (guardSide) {
        return thai
            ? const _NotifCopy('ลูกค้าชำระเงินแล้ว', 'ลูกค้าชำระเงินแล้ว')
            : const _NotifCopy('Customer paid', 'The customer has paid');
      }
      return thai
          ? const _NotifCopy('ชำระเงินสำเร็จ', 'ชำระเงินสำเร็จ')
          : const _NotifCopy('Payment successful', 'Payment completed');
    case 'pguard.events.rating.submitted':
      return thai
          ? const _NotifCopy('มีรีวิวใหม่', 'คุณได้รับคะแนนรีวิวใหม่')
          : const _NotifCopy('New review', 'You received a new review');
    case 'pguard.events.calling.initiated':
      return thai
          ? const _NotifCopy('สายเรียกเข้า', 'คุณมีสายเรียกเข้า แตะเพื่อรับสาย')
          : const _NotifCopy(
              'Incoming call', 'You have an incoming call — tap to answer');
    case 'pguard.events.calling.ended':
      return thai
          ? const _NotifCopy('สายที่ไม่ได้รับ', 'สายเรียกเข้าถูกยกเลิก')
          : const _NotifCopy('Missed call', 'The call was cancelled');
    default:
      return _NotifCopy(n.title, n.body); // truly unknown → server copy
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
