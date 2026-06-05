import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking.dart';

void main() {
  group('BookingStatus parsing', () {
    test('parses wire values and ignores unknowns', () {
      expect(BookingStatus.tryParse('en_route'), BookingStatus.enRoute);
      expect(BookingStatus.tryParse('pending_completion'),
          BookingStatus.pendingCompletion);
      expect(BookingStatus.tryParse('weird'), isNull);
      expect(BookingStatus.tryParse(null), isNull);
    });
  });

  group('BookingStatusEvent.tryParse', () {
    test('parses a well-formed booking_status frame', () {
      final e = BookingStatusEvent.tryParse({
        'type': 'booking_status',
        'booking_id': 'b1',
        'status': 'arrived',
        'occurred_at': '2026-06-05T10:00:00Z',
        'guard_id': 'g1',
      });
      expect(e, isNotNull);
      expect(e!.status, BookingStatus.arrived);
      expect(e.bookingId, 'b1');
      expect(e.guardId, 'g1');
    });

    test('rejects non booking_status frames and bad payloads', () {
      expect(BookingStatusEvent.tryParse({'type': 'ping'}), isNull);
      expect(
        BookingStatusEvent.tryParse(
            {'type': 'booking_status', 'status': 'arrived'}),
        isNull, // missing booking_id
      );
    });
  });

  group('BookingLifecycle', () {
    test('orders the happy-path steps', () {
      expect(BookingLifecycle.stepIndex(BookingStatus.accepted), 0);
      expect(BookingLifecycle.stepIndex(BookingStatus.enRoute), 1);
      expect(BookingLifecycle.stepIndex(BookingStatus.arrived), 2);
      expect(BookingLifecycle.stepIndex(BookingStatus.pendingCompletion), 3);
      expect(BookingLifecycle.stepIndex(BookingStatus.completed), 4);
      expect(BookingLifecycle.stepIndex(BookingStatus.requested), -1);
    });

    test('classifies terminal and negative-terminal states', () {
      expect(BookingLifecycle.isTerminal(BookingStatus.completed), isTrue);
      expect(BookingLifecycle.isTerminal(BookingStatus.declined), isTrue);
      expect(BookingLifecycle.isTerminal(BookingStatus.cancelled), isTrue);
      expect(BookingLifecycle.isTerminal(BookingStatus.arrived), isFalse);
      expect(
          BookingLifecycle.isNegativeTerminal(BookingStatus.cancelled), isTrue);
      expect(BookingLifecycle.isNegativeTerminal(BookingStatus.completed),
          isFalse);
    });

    test('provides bilingual labels for every status', () {
      for (final s in BookingStatus.values) {
        expect(BookingLifecycle.labelTh(s), isNotEmpty);
        expect(BookingLifecycle.labelEn(s), isNotEmpty);
      }
    });
  });

  group('Booking.applyEvent', () {
    test('advances status and fills a newly-known guard id', () {
      const booking = Booking(
        id: 'b1',
        customerId: 'c1',
        status: BookingStatus.accepted,
      );
      final next = booking.applyEvent(BookingStatusEvent(
        bookingId: 'b1',
        status: BookingStatus.enRoute,
        occurredAt: DateTime.utc(2026),
        guardId: 'g9',
      ));
      expect(next.status, BookingStatus.enRoute);
      expect(next.guardId, 'g9');
      expect(next.id, 'b1');
    });
  });
}
