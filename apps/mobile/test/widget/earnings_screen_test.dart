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

Future<void> pumpScreen(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ],
    child: const MaterialApp(home: EarningsScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets(
      'hero totals completed jobs (per-guard share, tip excluded) + rows',
      (tester) async {
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/bookings');
        return [
          jobJson('b1', 'completed'), // ฿230 × 8h = ฿1,840
          jobJson('b2', 'completed', address: 'คอนโด ไอดีโอ', hours: 5),
          jobJson('b3', 'accepted', address: 'โรงงาน ปทุม'), // not yet earned
        ];
      },
    );
    await pumpScreen(tester, api);

    expect(find.text('รวมรายได้ / Total earnings'), findsOneWidget);
    // ฿1,840 + ฿1,150 — per-guard share only: guard_count (2) and tip (฿500) excluded.
    expect(find.text('฿2,990'), findsOneWidget);
    expect(find.textContaining('ประมาณการ'), findsOneWidget);
    expect(find.text('รายการล่าสุด / Recent'), findsOneWidget);

    // Per-job rows: place, "date · hours", mono amount; non-completed job absent.
    expect(find.text('หมู่บ้านลัดดารมย์'), findsOneWidget);
    expect(find.text('3 มิ.ย. · 8 ชม.'), findsOneWidget);
    expect(find.text('฿1,840'), findsOneWidget);
    expect(find.text('฿1,150'), findsOneWidget);
    expect(find.text('โรงงาน ปทุม'), findsNothing);
    // One fetch — no polling.
    expect(api.getCount, 1);
  });

  testWidgets('shows the empty state when nothing is completed yet',
      (tester) async {
    final api =
        FakeApi(onGet: (_, __) async => [jobJson('b1', 'accepted')]);
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
