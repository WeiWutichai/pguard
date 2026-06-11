import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/registration.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/auth/registration/registration_pending_screen.dart';

import '../support/fakes.dart';

void main() {
  Future<void> pump(WidgetTester tester, FakePrefsStore prefs) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsStoreProvider.overrideWithValue(prefs),
          appStoreProvider.overrideWithValue(InMemoryStore()),
          pguardApiProvider
              .overrideWithValue(FakeApi(onPost: (_, __) async => null)),
        ],
        child: const MaterialApp(home: RegistrationPendingScreen()),
      ),
    );
    await tester.pumpAndSettle(); // let the post-frame prefs load complete
  }

  testWidgets(
      'guard: role hero + badge + check-status; the persisted summary is NOT rendered',
      (tester) async {
    final prefs = FakePrefsStore();
    // Cold-start path: the masked summary is read from prefs — it backs the role detection only
    // (the design's pending screen shows no summary list; bank already masked, never full).
    const summary = RegistrationSummary(
      role: RegistrationRole.guard,
      lines: [
        (label: 'เพศ / Gender', value: 'male'),
        (label: 'เลขบัญชี / Account', value: '••••7890'),
      ],
    );
    prefs.values[kRegSummaryKey] = jsonEncode(summary.toJson());

    await pump(tester, prefs);

    expect(find.textContaining('Pending approval'), findsOneWidget);
    // Per-role design copy + the role badge pill.
    expect(find.text('กำลังตรวจสอบใบสมัคร / Application under review'),
        findsOneWidget);
    expect(find.text('เจ้าหน้าที่ รปภ. / Security Guard'), findsOneWidget);
    expect(find.text('ตรวจสอบสถานะ / Check status'), findsOneWidget);
    // The summary rows are no longer rendered — the masked value must not appear anywhere.
    expect(find.text('••••7890'), findsNothing);
    expect(find.text('male'), findsNothing);
  });

  testWidgets('customer: per-role copy + amber badge', (tester) async {
    final prefs = FakePrefsStore();
    const summary = RegistrationSummary(
      role: RegistrationRole.customer,
      lines: [(label: 'ที่อยู่ / Address', value: '99/1 Sukhumvit Rd')],
    );
    prefs.values[kRegSummaryKey] = jsonEncode(summary.toJson());

    await pump(tester, prefs);

    expect(find.text('เกือบเสร็จแล้ว! / Almost there!'), findsOneWidget);
    expect(find.text('ลูกค้าจ้างงาน / Hirer'), findsOneWidget);
    expect(find.text('ตรวจสอบสถานะ / Check status'), findsOneWidget);
  });
}
