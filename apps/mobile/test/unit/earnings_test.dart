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
  DateTime? scheduledAt,
}) =>
    Booking(
      id: id,
      customerId: 'c1',
      status: status,
      baseFee: baseFee,
      hours: hours,
      guardCount: guardCount,
      tip: tip,
      scheduledAt: scheduledAt,
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

    test(
        'actual_hours (reconciled) OVERRIDES booked hours — pays for hours worked',
        () {
      // Booked 8h but worked only 2h → ฿230 × 2 = ฿460, not the ฿1,840 booked estimate. This is the
      // fix for "รปภ ได้เต็ม แต่ลูกค้าโดนคืนเงิน": pay tracks the customer's reconciled net.
      expect(
        GuardEarnings.jobEarningsSatang(booking(),
            actualHours: const {'b1': 2.0}),
        46000,
      );
    });

    test('fractional actual_hours rounds to the nearest satang', () {
      // ฿230 × 2.5h = ฿575.00 = 57500 satang.
      expect(
        GuardEarnings.jobEarningsSatang(booking(),
            actualHours: const {'b1': 2.5}),
        57500,
      );
    });

    test('a booking absent from the map falls back to booked hours', () {
      expect(
        GuardEarnings.jobEarningsSatang(booking(),
            actualHours: const {'other': 2.0}),
        184000,
      );
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

  group('GuardEarnings windowed', () {
    final now = DateTime.utc(2026, 6, 17, 12);
    // ฿230 × 8h = ฿1,840 = 184000 satang per completed job below.
    final jobs = [
      booking(id: 'today', scheduledAt: now.subtract(const Duration(hours: 2))),
      booking(id: 'd3', scheduledAt: now.subtract(const Duration(days: 3))),
      booking(id: 'd20', scheduledAt: now.subtract(const Duration(days: 20))),
      booking(id: 'd40', scheduledAt: now.subtract(const Duration(days: 40))),
      // Completed but undated → never counted in a window.
      booking(id: 'nodate', scheduledAt: null),
      // In-window but not completed → never earns.
      booking(
          id: 'open',
          status: BookingStatus.accepted,
          scheduledAt: now.subtract(const Duration(hours: 1))),
    ];

    test('day window keeps only the last 24h of completed jobs', () {
      expect(GuardEarnings.sumInWindow(jobs, now, EarningsWindow.day), 184000);
    });

    test('week window keeps the last 7 days', () {
      // today + d3 (d20/d40 are older; nodate/open excluded).
      expect(GuardEarnings.sumInWindow(jobs, now, EarningsWindow.week),
          184000 * 2);
    });

    test('month window keeps the last 30 days', () {
      // today + d3 + d20 (d40 falls outside 30 days).
      expect(GuardEarnings.sumInWindow(jobs, now, EarningsWindow.month),
          184000 * 3);
    });

    test('a future-CALENDAR-DAY job is excluded from the window', () {
      final withFuture = [
        ...jobs,
        booking(id: 'future', scheduledAt: now.add(const Duration(days: 1))),
      ];
      expect(GuardEarnings.sumInWindow(withFuture, now, EarningsWindow.day),
          184000);
    });

    test('a completed job scheduled LATER TODAY is counted (bug: ฿0 today)',
        () {
      // now = 12:00 June 17; a job booked for 14:00 TODAY that is already completed must count
      // in today's total (the old rolling window wrongly excluded it via a future-time guard).
      final laterToday = [
        booking(id: 'later', scheduledAt: now.add(const Duration(hours: 2))),
      ];
      expect(GuardEarnings.sumInWindow(laterToday, now, EarningsWindow.day),
          184000);
      expect(GuardEarnings.sumInWindow(laterToday, now, EarningsWindow.week),
          184000);
    });

    test('growth is null when the prior window earned nothing', () {
      // Only a job today; the prior week (−14d…−7d) is empty → no baseline.
      final onlyNow = [
        booking(scheduledAt: now.subtract(const Duration(hours: 1)))
      ];
      expect(GuardEarnings.growth(onlyNow, now, EarningsWindow.week), isNull);
    });

    test('growth compares current vs prior window of equal length', () {
      // Current week: two jobs (368000). Prior week (−14d…−7d): one job (184000).
      final series = [
        booking(id: 'c1', scheduledAt: now.subtract(const Duration(days: 1))),
        booking(id: 'c2', scheduledAt: now.subtract(const Duration(days: 2))),
        booking(id: 'p1', scheduledAt: now.subtract(const Duration(days: 9))),
      ];
      expect(GuardEarnings.growth(series, now, EarningsWindow.week), 1.0);
    });

    test('dailySeries buckets by local date, oldest-first, today last', () {
      final s = GuardEarnings.dailySeries(jobs, now);
      expect(s.length, 7);
      expect(s.last, 184000); // today
      expect(s[7 - 1 - 3], 184000); // 3 days ago
      // Days with no completed job stay 0.
      expect(s[0], 0);
      expect(s.fold<int>(0, (a, b) => a + b), 184000 * 2);
    });

    test('dailySeries on empty input is all zeros', () {
      expect(GuardEarnings.dailySeries(const [], now), List<int>.filled(7, 0));
    });

    test('dailySeries excludes a future-dated job', () {
      final withFuture = [
        booking(scheduledAt: now.add(const Duration(days: 1))),
      ];
      expect(
          GuardEarnings.dailySeries(withFuture, now), List<int>.filled(7, 0));
    });

    test('seriesDates is oldest-first, today last, length days', () {
      final d = GuardEarnings.seriesDates(now, days: 7);
      expect(d.length, 7);
      final today = now.toLocal();
      expect(d.last.year, today.year);
      expect(d.last.month, today.month);
      expect(d.last.day, today.day);
      // Strictly ascending, one calendar day apart.
      for (var i = 1; i < d.length; i++) {
        expect(d[i].difference(d[i - 1]).inDays, 1);
      }
    });

    test('feedMayBeTruncated flips at the row cap', () {
      List<Booking> n(int count) =>
          List.generate(count, (i) => booking(id: 'b$i'));
      expect(GuardEarnings.feedMayBeTruncated(n(99)), isFalse);
      expect(GuardEarnings.feedMayBeTruncated(n(GuardEarnings.feedRowCap)),
          isTrue);
    });
  });
}
