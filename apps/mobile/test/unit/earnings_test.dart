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
  String? commissionPercent,
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
      commissionPercent: commissionPercent,
    );

void main() {
  group(
      'GuardEarnings.hoursLabel (actual payable hours, booked-estimate annotated)',
      () {
    test('no reconcile → the plain booked figure', () {
      expect(
          GuardEarnings.hoursLabel(booking(hours: 8), isThai: true), '8 ชม.');
      expect(
          GuardEarnings.hoursLabel(booking(hours: 8), isThai: false), '8 hrs');
    });

    test(
        'reconciled BELOW the booked hours → actual with the booked estimate in parens',
        () {
      expect(
          GuardEarnings.hoursLabel(booking(hours: 8),
              actualHours: {'b1': 5.5}, isThai: true),
          '5.5 ชม. (จอง 8)');
      expect(
          GuardEarnings.hoursLabel(booking(hours: 8),
              actualHours: {'b1': 5.5}, isThai: false),
          '5.5 hrs (booked 8)');
    });

    test(
        'reconciled EQUAL to the booked hours → plain (no redundant annotation)',
        () {
      expect(
          GuardEarnings.hoursLabel(booking(hours: 8),
              actualHours: {'b1': 8.0}, isThai: true),
          '8 ชม.');
    });

    test('the label matches the amount: base × the SAME hours the row prints',
        () {
      final b = booking(hours: 8); // ฿230/h
      // 5.5h reconciled → label "5.5" and pay 230×5.5 = ฿1,265 (both off actual hours).
      expect(
          GuardEarnings.hoursLabel(b, actualHours: {'b1': 5.5}, isThai: true),
          '5.5 ชม. (จอง 8)');
      expect(
          GuardEarnings.jobEarningsSatang(b, actualHours: {'b1': 5.5}), 126500);
    });
  });

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

  group('commission — gross, deduction, net', () {
    test('a 0%/absent commission leaves the gross untouched', () {
      final pay = GuardEarnings.jobPay(booking());
      expect(pay.grossSatang, 184000);
      expect(pay.commissionSatang, 0);
      expect(pay.netSatang, 184000);
      expect(pay.hasCommission, isFalse,
          reason: 'no deduction line when nothing is deducted');
    });

    test("the booking's SNAPSHOT percent is deducted from the guard's pay", () {
      // ฿230 × 8h = ฿1,840 gross; 10% = ฿184 commission; ฿1,656 net.
      final pay = GuardEarnings.jobPay(booking(commissionPercent: '10.00'));
      expect(pay.grossSatang, 184000);
      expect(pay.commissionSatang, 18400);
      expect(pay.netSatang, 165600);
      expect(pay.hasCommission, isTrue);
      // The three figures must always reconcile — a net that isn't gross − commission is exactly
      // the silent smaller number a payout screen must never show.
      expect(pay.netSatang, pay.grossSatang - pay.commissionSatang);
    });

    test('jobEarningsSatang IS the net (every guard screen shows take-home)',
        () {
      expect(
        GuardEarnings.jobEarningsSatang(booking(commissionPercent: '12.50')),
        184000 - 23000,
      );
    });

    test('commission applies to the RECONCILED hours, not the booked ones', () {
      // Worked 2h of an 8h booking: gross ฿460, 10% = ฿46, net ฿414.
      final pay = GuardEarnings.jobPay(
        booking(commissionPercent: '10.00'),
        actualHours: const {'b1': 2.0},
      );
      expect(pay.grossSatang, 46000);
      expect(pay.commissionSatang, 4600);
      expect(pay.netSatang, 41400);
    });

    test("the settle's percent OVERRIDES the booking snapshot", () {
      // The booking was snapshotted at 10% but the settle actually applied 20%: show what was
      // actually taken, not what was quoted.
      final pay = GuardEarnings.jobPay(
        booking(commissionPercent: '10.00'),
        commissionPercent: const {'b1': 2000},
      );
      expect(pay.commissionSatang, 36800); // 20% of ฿1,840
      expect(pay.netSatang, 184000 - 36800);
    });

    test('a booking absent from the settle map keeps its own snapshot', () {
      final pay = GuardEarnings.jobPay(
        booking(commissionPercent: '10.00'),
        commissionPercent: const {'other': 2000},
      );
      expect(pay.commissionSatang, 18400);
    });

    test('totals and windows carry gross, commission AND net together', () {
      final now = DateTime.utc(2026, 6, 17, 12);
      final jobs = [
        booking(
            id: 'a',
            commissionPercent: '10.00',
            scheduledAt: now.subtract(const Duration(hours: 2))),
        booking(
            id: 'b',
            hours: 5,
            commissionPercent: '10.00',
            scheduledAt: now.subtract(const Duration(days: 2))),
      ];
      // ฿1,840 + ฿1,150 = ฿2,990 gross; 10% = ฿299; ฿2,691 net.
      final total = GuardEarnings.totalPay(jobs);
      expect(total.grossSatang, 299000);
      expect(total.commissionSatang, 29900);
      expect(total.netSatang, 269100);

      final window = GuardEarnings.payInWindow(jobs, now, EarningsWindow.week);
      expect(window.grossSatang, 299000);
      expect(window.commissionSatang, 29900);
      // The windowed sum the hero prints is the NET.
      expect(GuardEarnings.sumInWindow(jobs, now, EarningsWindow.week), 269100);
      // …and the bars add up to it.
      expect(
        GuardEarnings.seriesFor(jobs, now, EarningsWindow.week).totalSatang,
        269100,
      );
      // Growth compares take-home with take-home (no prior window here → no baseline).
      expect(GuardEarnings.growth(jobs, now, EarningsWindow.week), isNull);
    });
  });

  group('GuardEarningsRow (GET /payments/earnings)', () {
    test('parses hours + commission from decimal strings', () {
      final row = GuardEarningsRow.tryParse(const {
        'booking_id': 'b1',
        'actual_hours': '2.50',
        'commission_percent': '12.50',
      })!;
      expect(row.bookingId, 'b1');
      expect(row.actualHours, 2.5);
      expect(row.commissionPercentHundredths, 1250);
    });

    test('tolerates numbers on the wire and null fields', () {
      final row = GuardEarningsRow.tryParse(const {
        'booking_id': 'b1',
        'actual_hours': 3,
        'commission_percent': null,
      })!;
      expect(row.actualHours, 3.0);
      expect(row.commissionPercentHundredths, isNull,
          reason: 'null → fall back to the booking snapshot, not to 0%');
    });

    test('a row without a booking id is dropped', () {
      expect(GuardEarningsRow.tryParse(const {'actual_hours': '2'}), isNull);
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

    test('jobsInWindow returns exactly the rows the window total is made of',
        () {
      // The rows under the hero must add up to it. They used to be all-time, so the Day tab
      // showed ฿0 above a list of paid jobs and the screen contradicted itself.
      for (final w in EarningsWindow.values) {
        final rows = GuardEarnings.jobsInWindow(jobs, now, w);
        final rowSum =
            rows.fold(0, (a, b) => a + GuardEarnings.jobEarningsSatang(b));
        expect(rowSum, GuardEarnings.sumInWindow(jobs, now, w),
            reason: 'rows must sum to the hero for $w');
      }
    });

    test('jobsInWindow excludes undated and unfinished jobs, newest first', () {
      final rows = GuardEarnings.jobsInWindow(jobs, now, EarningsWindow.month);
      expect(rows.map((b) => b.id), ['today', 'd3', 'd20']);
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

    test('seriesFor(week) buckets by local date, oldest-first, today last', () {
      final s = GuardEarnings.seriesFor(jobs, now, EarningsWindow.week);
      expect(s.buckets.length, 7);
      expect(s.bucketDays, 1);
      expect(s.buckets.last.netSatang, 184000); // today
      expect(s.buckets[7 - 1 - 3].netSatang, 184000); // 3 days ago
      // Days with no completed job stay 0.
      expect(s.buckets.first.netSatang, 0);
      expect(s.totalSatang, 184000 * 2);
      expect(s.maxSatang, 184000);
    });

    test('seriesFor on empty input is all-zero buckets, not an empty chart',
        () {
      for (final w in EarningsWindow.values) {
        final s = GuardEarnings.seriesFor(const [], now, w);
        expect(s.buckets.length, GuardEarnings.windowDays(w) ~/ s.bucketDays);
        expect(s.buckets.every((b) => b.netSatang == 0), isTrue);
        expect(s.totalSatang, 0);
        expect(s.maxSatang, 0);
        expect(s.isEmpty, isTrue, reason: 'every bar is a true zero');
      }
    });

    test('seriesFor excludes a future-dated job', () {
      final withFuture = [
        booking(scheduledAt: now.add(const Duration(days: 1))),
      ];
      for (final w in EarningsWindow.values) {
        expect(GuardEarnings.seriesFor(withFuture, now, w).totalSatang, 0);
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

  // The reported bug: the chart was hard-wired to 7 days while the hero followed the Day/Week/Month
  // tab, so on เดือน the bars contradicted the number directly above them (and on วัน they showed
  // money the hero deliberately excluded). Everything here exists to make that unrepeatable.
  group('GuardEarnings.seriesFor — the bars decompose the hero', () {
    final now = DateTime.utc(2026, 6, 17, 12);

    // A completed job on EVERY one of the last 45 days, each at a DIFFERENT rate (฿1, ฿2, …), so an
    // off-by-one in any bucket boundary moves a total instead of hiding behind identical amounts.
    // Noon UTC keeps each local calendar date stable across test-machine timezones.
    final spread = [
      for (var d = 0; d < 45; d++)
        booking(
          id: 'd$d',
          baseFee: '${d + 1}.00',
          hours: 1,
          scheduledAt: now.subtract(Duration(days: d)),
        ),
    ];

    test('THE INVARIANT: the bars sum to the hero, on every tab', () {
      for (final w in EarningsWindow.values) {
        expect(
          GuardEarnings.seriesFor(spread, now, w).totalSatang,
          GuardEarnings.payInWindow(spread, now, w).netSatang,
          reason: 'chart ≠ hero on $w — that disagreement IS the bug',
        );
      }
    });

    test(
        'the invariant survives the settle overrides (actual hours + commission)',
        () {
      // Reconciled to half the booked hour at 12.5% commission — the bars must follow the hero
      // through BOTH overrides, since they are what makes the hero's number move.
      final actual = {for (var d = 0; d < 45; d++) 'd$d': 0.5};
      final pct = {for (var d = 0; d < 45; d++) 'd$d': 1250};
      for (final w in EarningsWindow.values) {
        expect(
          GuardEarnings.seriesFor(spread, now, w,
                  actualHours: actual, commissionPercent: pct)
              .totalSatang,
          GuardEarnings.payInWindow(spread, now, w,
                  actualHours: actual, commissionPercent: pct)
              .netSatang,
          reason: 'chart ≠ hero on $w after reconcile',
        );
      }
    });

    test('วัน = 1 bucket · สัปดาห์ = 7 daily bars · เดือน = 5 six-day blocks',
        () {
      final day = GuardEarnings.seriesFor(spread, now, EarningsWindow.day);
      final week = GuardEarnings.seriesFor(spread, now, EarningsWindow.week);
      final month = GuardEarnings.seriesFor(spread, now, EarningsWindow.month);

      expect(day.buckets.length, 1);
      expect(week.buckets.length, 7);
      expect(week.bucketDays, 1);
      expect(month.buckets.length, 5);
      expect(month.bucketDays, 6);
      // 30 daily bars on a phone is ~11px each; a single bar is not a chart at all. The Day tab's
      // breakdown is the per-job rows below it instead, so the screen draws no bars there.
      expect(day.isChartable, isFalse);
      expect(week.isChartable, isTrue);
      expect(month.isChartable, isTrue);
    });

    test('every window is covered exactly — buckets × bucketDays == windowDays',
        () {
      for (final w in EarningsWindow.values) {
        final s = GuardEarnings.seriesFor(spread, now, w);
        expect(s.buckets.length * s.bucketDays, GuardEarnings.windowDays(w));
        for (final b in s.buckets) {
          expect(b.end.difference(b.start).inDays + 1, s.bucketDays,
              reason: 'a bar must span exactly bucketDays calendar days');
          expect(b.isSingleDay, s.bucketDays == 1);
        }
      }
    });

    test('buckets are contiguous, oldest-first, and the last one holds today',
        () {
      final local = now.toLocal();
      final today = DateTime(local.year, local.month, local.day);
      for (final w in EarningsWindow.values) {
        final s = GuardEarnings.seriesFor(spread, now, w);
        expect(s.buckets.last.end, today);
        expect(
          s.buckets.first.start,
          DateTime(today.year, today.month,
              today.day - (GuardEarnings.windowDays(w) - 1)),
          reason: 'the oldest bar must start where payInWindow starts',
        );
        for (var i = 1; i < s.buckets.length; i++) {
          final prev = s.buckets[i - 1].end;
          expect(
              s.buckets[i].start, DateTime(prev.year, prev.month, prev.day + 1),
              reason: 'no gap and no overlap between bar ${i - 1} and bar $i');
        }
      }
    });

    test(
        'a job on the window\'s oldest day is IN (and in the OLDEST bar); one day earlier is OUT',
        () {
      for (final w in EarningsWindow.values) {
        final days = GuardEarnings.windowDays(w);
        final onEdge = [
          booking(
              id: 'edge', scheduledAt: now.subtract(Duration(days: days - 1)))
        ];
        final justOutside = [
          booking(id: 'out', scheduledAt: now.subtract(Duration(days: days)))
        ];
        final s = GuardEarnings.seriesFor(onEdge, now, w);
        expect(s.totalSatang, 184000, reason: '$w: the boundary day counts');
        expect(s.buckets.first.netSatang, 184000,
            reason: '$w: and it belongs to the oldest bar');
        expect(GuardEarnings.seriesFor(justOutside, now, w).totalSatang, 0,
            reason: '$w: one day before the window earns nothing here');
      }
    });

    test('each เดือน bar holds exactly its own six days', () {
      // One ฿1,840 job on each of the 30 days in the window → every block must read 6 × ฿1,840.
      final everyDay = [
        for (var d = 0; d < 30; d++)
          booking(id: 'x$d', scheduledAt: now.subtract(Duration(days: d))),
      ];
      final s = GuardEarnings.seriesFor(everyDay, now, EarningsWindow.month);
      expect(s.buckets.map((b) => b.netSatang).toList(),
          List<int>.filled(5, 184000 * 6));
      expect(s.maxSatang, 184000 * 6);
      expect(
          s.totalSatang,
          GuardEarnings.payInWindow(everyDay, now, EarningsWindow.month)
              .netSatang);
    });

    test('undated and not-yet-completed jobs never occupy a bar', () {
      final noise = [
        booking(id: 'nodate', scheduledAt: null),
        booking(id: 'open', status: BookingStatus.accepted, scheduledAt: now),
      ];
      for (final w in EarningsWindow.values) {
        final s = GuardEarnings.seriesFor(noise, now, w);
        expect(s.totalSatang, 0);
        expect(s.isEmpty, isTrue);
      }
    });

    test('maxSatang is the busiest BAR (the scale the heights normalise to)',
        () {
      // Two ฿1,840 jobs on one day, one on another → the tall bar is ฿3,680, not ฿1,840.
      final jobs = [
        booking(id: 'a', scheduledAt: now.subtract(const Duration(days: 1))),
        booking(id: 'b', scheduledAt: now.subtract(const Duration(days: 1))),
        booking(id: 'c', scheduledAt: now.subtract(const Duration(days: 2))),
      ];
      final s = GuardEarnings.seriesFor(jobs, now, EarningsWindow.week);
      expect(s.maxSatang, 368000);
      expect(s.isEmpty, isFalse);
    });
  });
}
