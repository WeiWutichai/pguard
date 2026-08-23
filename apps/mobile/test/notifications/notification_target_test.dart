import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';
import 'package:pguard_mobile/core/models/notification.dart';
import 'package:pguard_mobile/features/notifications/notification_target.dart';

AppNotification notif(String type, Map<String, dynamic> payload) =>
    AppNotification.fromJson({
      'id': 'n1',
      'user_id': 'u1',
      'title': 't',
      'body': 'b',
      'notification_type': type,
      'is_read': false,
      'sent_at': '2026-06-06T11:55:00Z',
      'read_at': null,
      'payload': payload,
    });

const guard = AuthUser(userId: 'g1', role: 'guard');
const customer = AuthUser(userId: 'c1', role: 'customer');

void main() {
  group('payload parsing', () {
    test('extracts the reference ids', () {
      final n = notif('chat_message', {
        'conversation_id': 'conv-9',
        'booking_id': 'bk-1',
      });
      expect(n.conversationId, 'conv-9');
      expect(n.bookingId, 'bk-1');
      expect(n.callId, isNull);
    });

    test('missing/empty payload is null-safe', () {
      expect(notif('system', const {}).bookingId, isNull);
      expect(notif('system', {'booking_id': ''}).bookingId, isNull);
    });
  });

  group('notificationTarget', () {
    test('chat → the conversation, acting role per the user', () {
      final n = notif('chat_message', {'conversation_id': 'conv-9'});
      expect(notificationTarget(n, user: guard),
          '/chat/c/conv-9?role=guard&readonly=0');
      expect(notificationTarget(n, user: customer),
          '/chat/c/conv-9?role=customer&readonly=0');
    });

    test('booking → guard active screen / customer live screen', () {
      final n = notif('guard_en_route', {'booking_id': 'bk-7'});
      expect(notificationTarget(n, user: guard), '/guard/active/bk-7');
      expect(notificationTarget(n, user: customer), '/booking/bk-7/live');
    });

    test('every booking type with a booking_id resolves', () {
      for (final t in [
        'booking_created',
        'guard_assigned',
        'guard_en_route',
        'guard_arrived',
        'booking_completed',
        'booking_cancelled',
      ]) {
        expect(
            notificationTarget(notif(t, {'booking_id': 'bk-1'}),
                user: customer),
            isNotNull,
            reason: t);
      }
    });

    test('system + call_id → the incoming-call screen', () {
      final n = notif('system', {'call_id': 'call-3', 'type': 'incoming_call'});
      expect(notificationTarget(n, user: customer), '/call?incoming=call-3');
    });

    // N1 — the `system` catch-all used to return null for every non-call kind (a dead tap). Each is
    // now routed to its most sensible detail via the payload's `event_type`.
    group('system subtypes are no longer dead taps', () {
      test('rating.submitted → the guard\'s ratings list', () {
        final n = notif('system', {
          'event_type': 'pguard.events.rating.submitted',
          'rating_id': 'r1',
          'booking_id': 'bk-1',
        });
        expect(notificationTarget(n, user: guard), '/guard/ratings');
      });

      test('payment.refund_processed → the booking summary/receipt', () {
        final n = notif('system', {
          'event_type': 'pguard.events.payment.refund_processed',
          'booking_id': 'bk-2',
          'payment_id': 'p1',
        });
        expect(notificationTarget(n, user: customer), '/booking/bk-2/summary');
      });

      test('payment.completed → guard active / customer live', () {
        final n = notif('system', {
          'event_type': 'pguard.events.payment.completed',
          'booking_id': 'bk-3',
        });
        expect(notificationTarget(n, user: guard), '/guard/active/bk-3');
        expect(notificationTarget(n, user: customer), '/booking/bk-3/live');
      });

      test('completion_requested → guard active / customer live', () {
        final n = notif('system', {
          'event_type': 'pguard.events.booking.completion_requested',
          'booking_id': 'bk-4',
        });
        expect(notificationTarget(n, user: guard), '/guard/active/bk-4');
        expect(notificationTarget(n, user: customer), '/booking/bk-4/live');
      });

      test('declined → the customer live-status screen', () {
        final n = notif('system', {
          'event_type': 'pguard.events.booking.declined',
          'booking_id': 'bk-5',
        });
        expect(notificationTarget(n, user: customer), '/booking/bk-5/live');
      });
    });

    test('no usable reference id → null (still markable read, no nav)', () {
      expect(notificationTarget(notif('chat_message', const {}), user: guard),
          isNull);
      expect(
          notificationTarget(notif('guard_assigned', const {}), user: customer),
          isNull);
      // A `system` notice with neither a call_id NOR a routable event_type has no screen to open.
      expect(
          notificationTarget(notif('system', {'payment_id': 'p1'}),
              user: guard),
          isNull);
      // A booking-scoped system kind whose payload is missing the booking_id can't route either.
      expect(
          notificationTarget(
              notif('system', {'event_type': 'pguard.events.booking.declined'}),
              user: customer),
          isNull);
    });
  });
}
