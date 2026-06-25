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

    test('parses a progress_reported check-in as a refresh-only nudge', () {
      // A guard check-in rides the booking_status frame with the sentinel status — it must parse
      // as a refresh nudge (no lifecycle status) so the live screen re-pulls progress reports
      // WITHOUT changing the booking's status.
      final e = BookingStatusEvent.tryParse({
        'type': 'booking_status',
        'booking_id': 'b1',
        'status': 'progress_reported',
        'occurred_at': '2026-06-25T10:00:00Z',
        'guard_id': 'g1',
      });
      expect(e, isNotNull);
      expect(e!.isRefresh, isTrue);
      expect(e.status, isNull, reason: 'a check-in carries NO lifecycle status');
      expect(e.bookingId, 'b1');
      expect(e.guardId, 'g1');
    });

    test('rejects a truly unknown status (forward-compat) but not the nudge', () {
      expect(
        BookingStatusEvent.tryParse({
          'type': 'booking_status',
          'booking_id': 'b1',
          'status': 'something_new',
        }),
        isNull,
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

    test('a refresh-only nudge keeps status but returns a fresh instance', () {
      // A guard check-in nudge (status == null) must NOT rewind the booking's lifecycle status —
      // it stays `arrived` — yet still produce a NEW instance so re-emitting it notifies the
      // progress-reports controller to re-pull (the check-in photo + advancing countdown).
      const booking = Booking(
        id: 'b1',
        customerId: 'c1',
        guardId: 'g1',
        status: BookingStatus.arrived,
        hours: 3,
      );
      final next = booking.applyEvent(BookingStatusEvent(
        bookingId: 'b1',
        status: null,
        occurredAt: DateTime.utc(2026),
        isRefresh: true,
      ));
      expect(next.status, BookingStatus.arrived,
          reason: 'a check-in is not a status change');
      expect(next.guardId, 'g1');
      expect(next.hours, 3);
      expect(identical(next, booking), isFalse,
          reason: 'a fresh instance must notify watchers to re-pull');
    });
  });
}
