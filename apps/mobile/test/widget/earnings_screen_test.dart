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
}) =>
    {
      'id': id,
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': status,
      'address': address,
      // Noon UTC keeps the local calendar date stable across test-machine timezones.
      'scheduled_at': '2026-06-03T12:00:00Z',
      'hours': hours,
      'guard_count': guards,
      'base_fee': baseFee,
      'tip': '500.00',
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

  testWidgets('shows PgErrorState on load failure', (tester) async {
    final api = FakeApi(onGet: (_, __) async => throw Exception('boom'));
    await pumpScreen(tester, api);

    expect(find.textContaining('โหลดรายได้ไม่สำเร็จ'), findsOneWidget);
    expect(find.textContaining('ลองอีกครั้ง'), findsOneWidget);
  });
}
