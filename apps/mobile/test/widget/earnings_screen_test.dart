import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/earnings_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> jobJson(
  String id,
  String status, {
  String address = 'หมู่บ้านลัดดารมย์',
  String baseFee = '230.00',
  int hours = 8,
  int guards = 2,
  String? commissionPercent,
  String scheduledAt = '2026-06-03T12:00:00Z',
}) =>
    {
      'id': id,
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': status,
      'address': address,
      // Noon UTC keeps the local calendar date stable across test-machine timezones.
      'scheduled_at': scheduledAt,
      'hours': hours,
      'guard_count': guards,
      'base_fee': baseFee,
      'tip': '500.00',
      if (commissionPercent != null) 'commission_percent': commissionPercent,
    };

// Pin "now" to the day after the jobs' fixed scheduled_at (2026-06-03T12:00Z) so the
// default Week window contains them — the windowed hero is otherwise time-relative.
final _now = DateTime.utc(2026, 6, 4, 12);

String _jwt() => fakeJwt({
      'sub': 'g1',
      'role': 'guard',
      'exp':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
    });

Future<void> pumpScreen(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = _jwt()),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      seededGuardSession(),
    ],
    child: MaterialApp(home: EarningsScreen(now: _now)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets(
      'hero totals completed jobs (per-guard share, tip excluded) + rows',
      (tester) async {
    // Earnings come from the ASSIGNED feed's completed jobs; the open-discovery feed
    // (/bookings/open) carries only `requested` jobs, so it returns nothing here.
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings'
          ? [
              jobJson('b1', 'completed'), // ฿230 × 8h = ฿1,840
              jobJson('b2', 'completed', address: 'คอนโด ไอดีโอ', hours: 5),
              jobJson('b3', 'accepted',
                  address: 'โรงงาน ปทุม'), // not yet earned
            ]
          : const <Map<String, dynamic>>[],
    );
    await pumpScreen(tester, api);

    // Default tab is Week; both jobs fall in the window (2026-06-03, "now" = 2026-06-04).
    expect(find.text('รายได้สัปดาห์นี้'), findsOneWidget);
    // ฿1,840 + ฿1,150 — per-guard share only: guard_count (2) and tip (฿500) excluded.
    expect(find.text('฿2,990'), findsOneWidget);
    expect(find.textContaining('ประมาณการ'), findsOneWidget);
    // The rows are the hero's own terms, so the heading names the selected window rather than
    // promising an all-time feed — a Day tab reading ฿0 above paid rows was the reported bug.
    expect(find.text('รายการในช่วงนี้'), findsOneWidget);

    // Per-job rows: place, "date · hours", mono amount; non-completed job absent.
    expect(find.text('หมู่บ้านลัดดารมย์'), findsOneWidget);
    expect(find.text('3 มิ.ย. · 8 ชม.'), findsOneWidget);
    expect(find.text('฿1,840'), findsOneWidget);
    expect(find.text('฿1,150'), findsOneWidget);
    expect(find.text('โรงงาน ปทุม'), findsNothing);
    // Three reads, each ONCE, no polling: /bookings (assigned feed) + /bookings/open (discovery) +
    // /payments/earnings (actual worked hours for base×actual pay). The earnings map is empty here
    // (the fake returns [] for it), so pay falls back to booked hours → the totals above are unchanged.
    expect(api.getCount, 3);
  });

  testWidgets(
      'commission is shown as gross → deduction → net, never a silent smaller number',
      (tester) async {
    // One ฿1,840 job at 10%: the guard takes home ฿1,656 — and must be able to SEE why.
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings'
          ? [jobJson('b1', 'completed', commissionPercent: '10.00')]
          : const <Map<String, dynamic>>[],
    );
    await pumpScreen(tester, api);

    // The hero prints the NET big — and so does the single row that makes it up (the hero and its
    // own terms must agree, which is why this is 2 and not 1).
    expect(find.text('฿1,656'), findsNWidgets(2));
    // …with the arithmetic that produced it right underneath.
    expect(find.text('รายได้ก่อนหัก'), findsOneWidget);
    expect(find.text('฿1,840.00'), findsOneWidget);
    expect(find.text('หักค่าคอมมิชชั่น'), findsOneWidget);
    expect(find.text('-฿184.00'), findsOneWidget);
    expect(find.text('รับสุทธิ'), findsOneWidget);
    expect(find.text('฿1,656.00'), findsOneWidget);
    expect(find.textContaining('หักค่าคอมมิชชั่น)'), findsOneWidget,
        reason: 'the method caption says the figure is net of commission');

    // The per-job row shows the same split: net, then "gross − commission".
    expect(find.text('฿1,840 − ฿184 ค่าคอม'), findsOneWidget);
  });

  testWidgets('the settle commission overrides the booking snapshot on screen',
      (tester) async {
    // Booked at 10%, actually settled at 20% (and 4 of the 8 hours worked): the screen must show
    // what was really taken — gross ฿920, commission ฿184, net ฿736.
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings') {
          return [jobJson('b1', 'completed', commissionPercent: '10.00')];
        }
        if (path == '/payments/earnings') {
          return [
            {
              'booking_id': 'b1',
              'actual_hours': '4.00',
              'commission_percent': '20.00',
            }
          ];
        }
        return const <Map<String, dynamic>>[];
      },
    );
    await pumpScreen(tester, api);

    expect(find.text('฿736'), findsNWidgets(2)); // hero + its one row
    expect(find.text('฿920 − ฿184 ค่าคอม'), findsOneWidget);
  });

  testWidgets('a 0% service shows no deduction line at all', (tester) async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings'
          ? [jobJson('b1', 'completed', commissionPercent: '0.00')]
          : const <Map<String, dynamic>>[],
    );
    await pumpScreen(tester, api);

    expect(find.text('฿1,840'),
        findsNWidgets(2)); // hero + its one row, gross == net
    expect(find.text('หักค่าคอมมิชชั่น'), findsNothing);
    expect(find.text('รายได้ก่อนหัก'), findsNothing);
  });

  testWidgets('surfaces the incompleteness caveat when the feed is at the cap',
      (tester) async {
    // A full page (100 rows) means the server may have dropped older jobs → the windowed
    // total can under-report, so the hero must say so rather than show a confident number.
    final full = [
      for (var i = 0; i < 100; i++) jobJson('b$i', 'completed'),
    ];
    final api = FakeApi(
      onGet: (path, _) async =>
          path == '/bookings' ? full : const <Map<String, dynamic>>[],
    );
    await pumpScreen(tester, api);

    expect(find.textContaining('ยอดอาจไม่ครบ'), findsOneWidget);
  });

  testWidgets('shows the empty state when nothing is completed yet',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => [jobJson('b1', 'accepted')]);
    await pumpScreen(tester, api);

    expect(find.textContaining('ยังไม่มีรายได้'), findsOneWidget);
    // The hero still renders the honest ฿0 total.
    expect(find.text('฿0'), findsOneWidget);
  });

  // The reported bug ("กราฟข้อมูลยังไม่ตรง"): the chart was hard-wired to 7 days with weekday labels
  // while the hero followed the Day/Week/Month tab, so on เดือน a 30-day hero sat above a 7-day
  // chart and on วัน a ฿0 hero sat above bars showing money. The chart must now follow the tab.
  group('the chart follows the selected tab', () {
    // "now" is Thursday 2026-06-04; the seven daily bars therefore end on พฤ.
    // One job yesterday (in every window) and one 20 days back (only in เดือน) — under the old
    // 7-day chart the เดือน bars could not show the second job the hero was counting.
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings'
          ? [
              jobJson('recent', 'completed'), // 2026-06-03 → ฿1,840
              jobJson('old', 'completed',
                  address: 'คอนโด ไอดีโอ',
                  scheduledAt: '2026-05-15T12:00:00Z'), // 20 days back → ฿1,840
            ]
          : const <Map<String, dynamic>>[],
    );

    testWidgets('สัปดาห์ — 7 daily bars, weekday labels, and the scale printed',
        (tester) async {
      await pumpScreen(tester, api);

      expect(find.text('รายได้ต่อวัน'), findsOneWidget);
      // Today's bar (Thursday) plus the six before it.
      for (final d in ['ศ', 'ส', 'อา', 'จ', 'อ', 'พ', 'พฤ']) {
        expect(find.text(d), findsOneWidget, reason: 'missing the $d bar');
      }
      // Bar heights normalise to the busiest bar, so that number has to be ON the chart —
      // without it a ฿1 day and a ฿10,000 day draw identically.
      expect(find.text('สูงสุด ฿1,840'), findsOneWidget);
      // The 20-day-old job is outside the week: hero and bars agree on ฿1,840 alone.
      expect(find.text('฿1,840'), findsNWidgets(2)); // hero + its single row
    });

    testWidgets('เดือน — 5 six-day blocks labelled by date, no weekday axis',
        (tester) async {
      await pumpScreen(tester, api);
      await tester.tap(find.text('เดือน'));
      await tester.pump();

      // The hero now counts BOTH jobs…
      expect(find.text('รายได้เดือนนี้'), findsOneWidget);
      expect(find.text('฿3,680'), findsOneWidget);
      // …and the chart is a 30-day decomposition, not the old 7-day one.
      expect(find.text('แท่งละ 6 วัน (เริ่มวันที่ใต้แท่ง)'), findsOneWidget);
      for (final d in ['6 พ.ค.', '12 พ.ค.', '18 พ.ค.', '24 พ.ค.', '30 พ.ค.']) {
        expect(find.text(d), findsOneWidget, reason: 'missing the $d block');
      }
      // The weekday axis belonged to the 7-day chart and must be gone with it.
      for (final d in ['ศ', 'ส', 'อา', 'จ', 'อ', 'พ', 'พฤ']) {
        expect(find.text(d), findsNothing,
            reason: 'weekday label "$d" is the 7-day chart leaking into เดือน');
      }
      // Both jobs are in the window, one per block → the busiest block is one job.
      expect(find.text('สูงสุด ฿1,840'), findsOneWidget);
      expect(find.text('คอนโด ไอดีโอ'), findsOneWidget);
    });

    testWidgets('วัน — no chart at all; the rows ARE the breakdown',
        (tester) async {
      await pumpScreen(tester, api);
      await tester.tap(find.text('วัน'));
      await tester.pump();

      // Nothing completed today: the honest ฿0 hero, and no bars to contradict it.
      expect(find.text('รายได้วันนี้'), findsOneWidget);
      expect(find.text('฿0'), findsOneWidget);
      expect(find.textContaining('สูงสุด'), findsNothing);
      expect(find.text('รายได้ต่อวัน'), findsNothing);
      expect(find.textContaining('แท่งละ'), findsNothing);
      expect(find.text('ยังไม่มีงานที่เสร็จในช่วงนี้'), findsOneWidget);
    });
  });

  testWidgets('shows PgErrorState on load failure', (tester) async {
    final api = FakeApi(onGet: (_, __) async => throw Exception('boom'));
    await pumpScreen(tester, api);

    expect(find.textContaining('โหลดรายได้ไม่สำเร็จ'), findsOneWidget);
    expect(find.textContaining('ลองอีกครั้ง'), findsOneWidget);
  });
}
