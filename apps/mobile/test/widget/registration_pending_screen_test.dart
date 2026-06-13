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
        (label: 'เพศ', value: 'male'),
        (label: 'เลขบัญชี', value: '••••7890'),
      ],
    );
    prefs.values[kRegSummaryKey] = jsonEncode(summary.toJson());

    await pump(tester, prefs);

    // No green PGuardHeader anymore (hi-fi has no top bar) — the role-specific hero head is
    // the screen's title, so the old 'Pending approval' header subtitle is gone by design.
    expect(find.textContaining('Pending approval'), findsNothing);
    // Per-role design copy + the role badge pill. Default locale is Thai (no override), so the
    // single-language render shows the Thai halves.
    expect(find.text('กำลังตรวจสอบใบสมัคร'), findsOneWidget);
    expect(find.text('เจ้าหน้าที่ รปภ.'), findsOneWidget);
    expect(find.text('ตรวจสอบสถานะ'), findsOneWidget);
    // The summary rows are no longer rendered — the masked value must not appear anywhere.
    expect(find.text('••••7890'), findsNothing);
    expect(find.text('male'), findsNothing);
  });

  testWidgets('customer: per-role copy + amber badge', (tester) async {
    final prefs = FakePrefsStore();
    const summary = RegistrationSummary(
      role: RegistrationRole.customer,
      lines: [(label: 'ที่อยู่', value: '99/1 Sukhumvit Rd')],
    );
    prefs.values[kRegSummaryKey] = jsonEncode(summary.toJson());

    await pump(tester, prefs);

    expect(find.text('เกือบเสร็จแล้ว!'), findsOneWidget);
    expect(find.text('ลูกค้าจ้างงาน'), findsOneWidget);
    expect(find.text('ตรวจสอบสถานะ'), findsOneWidget);
  });
}
