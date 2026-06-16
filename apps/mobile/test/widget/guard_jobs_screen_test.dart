import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/guard_jobs_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> _booking(String status, String address, String id) => {
      'id': id,
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': status,
      'address': address,
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'tip': '0',
    };

Future<void> _pump(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      // Locale defaults to Thai; the fake prefs store keeps the locale load hermetic.
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ],
    child: const MaterialApp(home: GuardJobsScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets(
      'opens on Active; tabs filter active/done; Pending empty when no open jobs',
      (tester) async {
    // Assigned feed (/bookings) = active + done; open-discovery feed (/bookings/open) empty here.
    final api = FakeApi(onGet: (path, _) async => path == '/bookings'
        ? [
            _booking('accepted', 'คอนโด ไอดีโอ', 'b-active'),
            _booking('completed', 'โรงงาน ปทุม', 'b-done'),
          ]
        : const <Map<String, dynamic>>[]);
    await _pump(tester, api);

    // Default tab = Active → the accepted job shows, the completed one does not.
    expect(find.text('คอนโด ไอดีโอ'), findsOneWidget);
    expect(find.text('โรงงาน ปทุม'), findsNothing);

    // Done tab (label carries a count: "เสร็จ 1").
    await tester.tap(find.textContaining('เสร็จ'));
    await tester.pumpAndSettle();
    expect(find.text('โรงงาน ปทุม'), findsOneWidget);
    expect(find.text('คอนโด ไอดีโอ'), findsNothing);

    // Pending tab — empty when the open-discovery feed returns nothing.
    await tester.tap(find.textContaining('รอตอบรับ'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีงานรอตอบรับ'), findsOneWidget);
  });

  testWidgets('open-discovery jobs (/bookings/open) appear in the Pending tab',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async => path == '/bookings/open'
        ? [_booking('requested', 'งานเปิดใหม่ ลาดพร้าว', 'b-open')]
        : const <Map<String, dynamic>>[]);
    await _pump(tester, api);

    await tester.tap(find.textContaining('รอตอบรับ'));
    await tester.pumpAndSettle();
    expect(find.text('งานเปิดใหม่ ลาดพร้าว'), findsOneWidget);
  });

  testWidgets('the job feeds are fetched once each (no polling)', (tester) async {
    final api = FakeApi(onGet: (path, _) async => path == '/bookings'
        ? [_booking('accepted', 'คอนโด ไอดีโอ', 'b-active')]
        : const <Map<String, dynamic>>[]);
    await _pump(tester, api);
    await tester.pump(const Duration(seconds: 2));

    // build fetches BOTH feeds (/bookings + /bookings/open) exactly once each — no timer re-fetch.
    expect(api.getCount, 2);
  });
}
