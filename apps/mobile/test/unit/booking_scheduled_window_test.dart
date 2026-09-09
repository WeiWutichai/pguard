import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking.dart';

/// QA #25 — the client mirror of the booking service's booked-window boundary.
///
/// The customer may not extend the original job: past `scheduled_at + hours` the server refuses
/// the "ให้ทำต่อ" reject with 409 `JOB_WINDOW_CLOSED`, and the guard's screen auto-closes the job
/// rather than leaving them on site unpaid. Both screens key off [Booking.isPastScheduledWindow],
/// so its boundary must match the server's exactly — STRICT `>`, no grace.
void main() {
  final t0 = DateTime.utc(2026, 6, 10, 9);

  Booking booking({DateTime? scheduledAt, int? hours}) => Booking(
        id: 'b1',
        customerId: 'c1',
        status: BookingStatus.pendingCompletion,
        scheduledAt: scheduledAt,
        hours: hours,
      );

  group('Booking.scheduledEndAt', () {
    test('is scheduledAt + hours', () {
      expect(
        booking(scheduledAt: t0, hours: 4).scheduledEndAt,
        DateTime.utc(2026, 6, 10, 13),
      );
    });

    test('is null when the window cannot be computed', () {
      // A snapshot from a backend predating either field, or a nonsense duration.
      expect(booking(scheduledAt: null, hours: 4).scheduledEndAt, isNull);
      expect(booking(scheduledAt: t0, hours: null).scheduledEndAt, isNull);
      expect(booking(scheduledAt: t0, hours: 0).scheduledEndAt, isNull);
    });
  });

  group('Booking.isPastScheduledWindow', () {
    final b = booking(scheduledAt: t0, hours: 4);
    final end = DateTime.utc(2026, 6, 10, 13);

    test('is open through the window and AT its end', () {
      expect(b.isPastScheduledWindow(t0), isFalse);
      expect(
          b.isPastScheduledWindow(t0.add(const Duration(hours: 2))), isFalse);
      expect(
        b.isPastScheduledWindow(end.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      // EXACTLY at the end → still open (strict `>`, matching `is_expired` server-side).
      expect(b.isPastScheduledWindow(end), isFalse);
    });

    test('is closed one second past the end and stays closed', () {
      expect(
        b.isPastScheduledWindow(end.add(const Duration(seconds: 1))),
        isTrue,
      );
      // Inside the server's 30-min auto-complete grace: that grace is the customer's window to
      // APPROVE, never to send the guard back out — so it is CLOSED here too.
      expect(b.isPastScheduledWindow(end.add(const Duration(minutes: 30))),
          isTrue);
      expect(b.isPastScheduledWindow(end.add(const Duration(days: 1))), isTrue);
    });

    test('an uncomputable window reads as OPEN, never as closed', () {
      // Fail-open by design: wrongly HIDING "ให้ทำต่อ" strands a customer with no way to ask for
      // the time they paid for, while wrongly offering it just surfaces the server's typed,
      // localized 409.
      final unknown = booking(scheduledAt: null, hours: null);
      expect(unknown.isPastScheduledWindow(end.add(const Duration(days: 7))),
          isFalse);
    });

    test('compares in UTC regardless of the caller\'s timezone', () {
      // Device clocks arrive local; the window is server time. A local-time `now` that is the
      // same instant must give the same answer.
      final localNow = end.add(const Duration(seconds: 1)).toLocal();
      expect(b.isPastScheduledWindow(localNow), isTrue);
    });
  });
}
