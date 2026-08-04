import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/models/geo.dart';
import 'package:pguard_mobile/features/home/guard_home_screen.dart';

Booking booking(
  String id, {
  required BookingStatus status,
  DateTime? scheduledAt,
  int? hours,
  int? guardCount,
  String? baseFee,
  double? lat,
  double? lng,
}) =>
    Booking(
      id: id,
      customerId: 'c1',
      status: status,
      scheduledAt: scheduledAt,
      hours: hours,
      guardCount: guardCount,
      baseFee: baseFee,
      lat: lat,
      lng: lng,
    );

void main() {
  final now = DateTime(2026, 6, 11, 9, 0);
  final today14 = DateTime(2026, 6, 11, 14, 0);
  final yesterday14 = DateTime(2026, 6, 10, 14, 0);

  final all = [
    // Completed today: 500 × 8h = ฿4,000 → counts (guard_count is the customer's crew size,
    // not a multiplier on one guard's pay).
    booking('b1',
        status: BookingStatus.completed,
        scheduledAt: today14,
        hours: 8,
        guardCount: 1,
        baseFee: '500.00'),
    // Still WORKING today (arrived): money not earned yet → excluded from today's earnings,
    // but it IS one of today's jobs.
    booking('b2',
        status: BookingStatus.arrived,
        scheduledAt: today14,
        hours: 2,
        guardCount: 2,
        baseFee: '500.00'),
    // An OPEN request from the discovery feed — no guard has taken it. Neither earnings nor
    // "jobs today": it is not this guard's job at all.
    booking('b3',
        status: BookingStatus.requested,
        scheduledAt: today14,
        hours: 8,
        guardCount: 1,
        baseFee: '500.00'),
    // Cancelled today → neither earned nor worked.
    booking('b4',
        status: BookingStatus.cancelled,
        scheduledAt: today14,
        hours: 8,
        guardCount: 1,
        baseFee: '500.00'),
    // Completed yesterday → not today's stats at all.
    booking('b5',
        status: BookingStatus.completed,
        scheduledAt: yesterday14,
        hours: 8,
        guardCount: 1,
        baseFee: '500.00'),
    // Unscheduled → never today's.
    booking('b6', status: BookingStatus.completed, hours: 8, baseFee: '500'),
  ];

  test('earningsTodaySatang counts only jobs COMPLETED today', () {
    // Only b1 (฿4,000). b2 is still being worked, b3 was never taken, b4 was cancelled, and
    // b5/b6 are not today. guard_count is NOT a multiplier — this guard is paid for themselves.
    expect(GuardHomeStats.earningsTodaySatang(all, now), 400000);
  });

  test('earningsTodaySatang prefers the hours ACTUALLY worked', () {
    // The reconciliation clamped b1 to 6h, so today's pay is 500 × 6 — the same number the
    // earnings screen shows. Before this the home card used booked hours and the two disagreed.
    expect(
      GuardHomeStats.earningsTodaySatang(all, now, actualHours: {'b1': 6}),
      300000,
    );
  });

  test('earningsTodaySatang is 0 for an empty list', () {
    expect(GuardHomeStats.earningsTodaySatang(const [], now), 0);
  });

  test('jobsToday counts only jobs this guard actually took', () {
    // b1 (completed) + b2 (arrived). NOT b3 — an unassigned open request, which used to make the
    // count climb whenever any customer booked — and not b4, which was cancelled.
    expect(GuardHomeStats.jobsToday(all, now), 2);
  });

  group('incomingDistanceLabel — honest guard→job distance', () {
    final pinned =
        booking('p', status: BookingStatus.requested, lat: 13.75, lng: 100.50);
    const guardAt = GeoPoint(13.70, 100.50); // ~5.5 km south of the pin

    test('null when the guard has no GPS fix (offline / no fix)', () {
      expect(
        GuardHomeStats.incomingDistanceLabel(null, pinned, isThai: true),
        isNull,
      );
    });

    test('null when the booking has no pinned coordinate', () {
      final noPin = booking('np', status: BookingStatus.requested);
      expect(
        GuardHomeStats.incomingDistanceLabel(guardAt, noPin, isThai: true),
        isNull,
      );
      // half-null (lat only) is also not a usable pin
      final halfPin =
          booking('hp', status: BookingStatus.requested, lat: 13.75);
      expect(
        GuardHomeStats.incomingDistanceLabel(guardAt, halfPin, isThai: true),
        isNull,
      );
    });

    test('both present → "distance · ~ETA" with the approximate-ETA tilde', () {
      final th =
          GuardHomeStats.incomingDistanceLabel(guardAt, pinned, isThai: true)!;
      expect(th, contains('·'));
      expect(th, contains('~'), reason: 'ETA must stay marked approximate');
      expect(th, contains('กม.'), reason: '~5.5 km renders in kilometres');
      expect(th, contains('นาที'));

      final en =
          GuardHomeStats.incomingDistanceLabel(guardAt, pinned, isThai: false)!;
      expect(en, contains('km'));
      expect(en, contains('~'));
      expect(en, contains('min'));
    });
  });
}
