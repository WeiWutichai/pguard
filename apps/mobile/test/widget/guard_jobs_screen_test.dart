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
      'opens on Active; tabs filter active/done; Pending is empty (no v2 discovery)',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      expect(path, '/bookings');
      return [
        _booking('accepted', 'คอนโด ไอดีโอ', 'b-active'),
        _booking('completed', 'โรงงาน ปทุม', 'b-done'),
      ];
    });
    await _pump(tester, api);

    // Default tab = Active → the accepted job shows, the completed one does not.
    expect(find.text('คอนโด ไอดีโอ'), findsOneWidget);
    expect(find.text('โรงงาน ปทุม'), findsNothing);

    // Done tab (label carries a count: "เสร็จ 1").
    await tester.tap(find.textContaining('เสร็จ'));
    await tester.pumpAndSettle();
    expect(find.text('โรงงาน ปทุม'), findsOneWidget);
    expect(find.text('คอนโด ไอดีโอ'), findsNothing);

    // Pending tab — structurally empty in v2 (no open-job discovery feed).
    await tester.tap(find.text('รอตอบรับ'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีงานรอตอบรับ'), findsOneWidget);
  });

  testWidgets('GET /bookings is fetched exactly once (no polling)', (tester) async {
    final api = FakeApi(onGet: (_, __) async => [
          _booking('accepted', 'คอนโด ไอดีโอ', 'b-active'),
        ]);
    await _pump(tester, api);
    await tester.pump(const Duration(seconds: 2));

    expect(api.getCount, 1);
  });
}
