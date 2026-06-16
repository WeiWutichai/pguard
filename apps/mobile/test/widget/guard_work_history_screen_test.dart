import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/guard_work_history_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> _b(String status, String address, String id, String at) =>
    {
      'id': id,
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': status,
      'address': address,
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'scheduled_at': at,
      'tip': '0',
    };

Future<void> _pump(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ],
    child: const MaterialApp(home: GuardWorkHistoryScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets(
      'Completed tab (default, newest first); Cancelled shows cancelled+declined; active excluded',
      (tester) async {
    // History reads the ASSIGNED feed (/bookings); the open-discovery feed (/bookings/open)
    // never carries completed/cancelled jobs, so it returns nothing here.
    final api = FakeApi(onGet: (path, _) async => path == '/bookings'
        ? [
            _b('completed', 'งานเก่า', 'c-old', '2026-06-01T07:00:00Z'),
            _b('completed', 'งานใหม่', 'c-new', '2026-06-10T07:00:00Z'),
            _b('cancelled', 'ลูกค้ายกเลิกงาน', 'x1', '2026-06-05T07:00:00Z'),
            _b('declined', 'ถอนตัวเอง', 'x2', '2026-06-06T07:00:00Z'),
            _b('accepted', 'งานที่กำลังรับ', 'a1', '2026-06-09T07:00:00Z'),
          ]
        : const <Map<String, dynamic>>[]);
    await _pump(tester, api);

    // Completed tab is the default: both completed jobs show; cancelled/declined/active do not.
    expect(find.text('งานใหม่'), findsOneWidget);
    expect(find.text('งานเก่า'), findsOneWidget);
    expect(find.text('ลูกค้ายกเลิกงาน'), findsNothing);
    expect(find.text('งานที่กำลังรับ'), findsNothing);

    // Newest first.
    expect(
      tester.getTopLeft(find.text('งานใหม่')).dy,
      lessThan(tester.getTopLeft(find.text('งานเก่า')).dy),
    );

    // Cancelled tab — the label "ยกเลิก 2" is the only ยกเลิก text while on the Completed tab.
    await tester.tap(find.textContaining('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(find.text('ลูกค้ายกเลิกงาน'), findsOneWidget);
    expect(find.text('ถอนตัวเอง'), findsOneWidget); // declined included
    expect(find.text('งานใหม่'), findsNothing);
  });

  testWidgets('the job feeds are fetched once each (no polling)', (tester) async {
    final api = FakeApi(onGet: (path, _) async => path == '/bookings'
        ? [_b('completed', 'งานเสร็จ', 'c1', '2026-06-10T07:00:00Z')]
        : const <Map<String, dynamic>>[]);
    await _pump(tester, api);
    await tester.pump(const Duration(seconds: 2));

    // build fetches BOTH feeds (/bookings + /bookings/open) exactly once each — no timer re-fetch.
    expect(api.getCount, 2);
  });
}
