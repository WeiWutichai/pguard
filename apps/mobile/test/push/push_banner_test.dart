import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/push/push_banner.dart';

void main() {
  group('pushBanner (foreground in-app banner copy)', () {
    test('incoming_call → call banner (bilingual)', () {
      final data = {'type': 'incoming_call', 'call_id': 'c1'};
      expect(pushBanner(data, isThai: true), 'สายเรียกเข้า');
      expect(pushBanner(data, isThai: false), 'Incoming call');
    });

    test('chat push (no type, classified by event_type)', () {
      final data = {
        'event_type': 'pguard.events.chat.message_sent',
        'conversation_id': 'conv-1',
      };
      expect(pushBanner(data, isThai: true), 'ข้อความใหม่');
      expect(pushBanner(data, isThai: false), 'New message');
    });

    test('booking-status push (no type, booking.* event_type)', () {
      for (final ev in [
        'pguard.events.booking.job_accepted',
        'pguard.events.booking.guard_en_route',
        'pguard.events.booking.arrived',
        'pguard.events.booking.completed',
        'pguard.events.booking.cancelled',
      ]) {
        expect(pushBanner({'event_type': ev, 'booking_id': 'b1'}, isThai: false),
            'Booking update',
            reason: ev);
      }
      expect(
          pushBanner({'event_type': 'pguard.events.booking.arrived'},
              isThai: true),
          'อัปเดตงานของคุณ');
    });

    test('new_job is NOT bannered here (handled by the registration controller)',
        () {
      expect(pushBanner({'type': 'new_job', 'booking_id': 'b1'}, isThai: true),
          isNull);
    });

    test('unknown / payload-less push → null', () {
      expect(pushBanner(const {}, isThai: true), isNull);
      expect(pushBanner({'event_type': 'pguard.events.user.compromised'},
          isThai: false), isNull);
    });
  });
}
