import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/earnings.dart';
import 'package:pguard_mobile/core/models/booking.dart';

Booking booking({
  String id = 'b1',
  BookingStatus status = BookingStatus.completed,
  String? baseFee = '230.00',
  int? hours = 8,
  int? guardCount = 1,
  String? tip,
}) =>
    Booking(
      id: id,
      customerId: 'c1',
      status: status,
      baseFee: baseFee,
      hours: hours,
      guardCount: guardCount,
      tip: tip,
    );

void main() {
  group('GuardEarnings.jobEarningsSatang', () {
    test('is base_fee × hours (the design row: ฿230/h × 8h = ฿1,840)', () {
      expect(GuardEarnings.jobEarningsSatang(booking()), 184000);
    });

    test('guard_count does NOT multiply the per-guard share', () {
      expect(
        GuardEarnings.jobEarningsSatang(booking(guardCount: 3)),
        184000,
      );
    });

    test('tip is EXCLUDED (no per-guard tip split exists in v2)', () {
      expect(
        GuardEarnings.jobEarningsSatang(booking(tip: '500.00')),
        184000,
      );
    });

    test('missing hours/base_fee degrade to 0, never throw', () {
      expect(GuardEarnings.jobEarningsSatang(booking(hours: null)), 0);
      expect(GuardEarnings.jobEarningsSatang(booking(baseFee: null)), 0);
    });
  });

  group('GuardEarnings totals', () {
    final jobs = [
      booking(id: 'b1'), // completed, ฿1,840
      booking(id: 'b2', hours: 5), // completed, ฿1,150
      booking(id: 'b3', status: BookingStatus.accepted), // not yet earned
      booking(id: 'b4', status: BookingStatus.cancelled), // never earns
    ];

    test('completedJobs keeps only completed, order preserved', () {
      expect(
        GuardEarnings.completedJobs(jobs).map((b) => b.id),
        ['b1', 'b2'],
      );
    });

    test('totalEarningsSatang sums completed jobs only', () {
      expect(GuardEarnings.totalEarningsSatang(jobs), 184000 + 115000);
    });

    test('empty list totals 0', () {
      expect(GuardEarnings.totalEarningsSatang(const []), 0);
    });
  });
}
