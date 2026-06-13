import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/media/document_picker.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/auth/registration/guard_registration_screen.dart';

import '../support/fakes.dart';

void main() {
  late FakeDocumentPicker picker;

  Future<void> pump(WidgetTester tester) {
    // A tall surface so the step content (5 doc rows) is on-screen alongside the fixed footer CTA.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    picker = FakeDocumentPicker();
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentPickerProvider.overrideWithValue(picker),
          appStoreProvider.overrideWithValue(InMemoryStore()),
          prefsStoreProvider.overrideWithValue(FakePrefsStore()),
          pguardApiProvider.overrideWithValue(
              FakeApi(onPost: (_, __) async => <String, dynamic>{})),
        ],
        child: const MaterialApp(home: GuardRegistrationScreen()),
      ),
    );
  }

  testWidgets(
      'multi-step: personal → documents → bank → review, rejects a too-short account',
      (tester) async {
    await pump(tester);

    // Step 1 (personal) is shown first with the design head.
    expect(find.text('ขั้นที่ 1 จาก 4'), findsOneWidget);
    expect(find.text('เพศ'), findsOneWidget);

    // Next → documents (footer CTA carries the captured-doc count).
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
    expect(find.textContaining('บัตรประชาชน'), findsOneWidget);
    expect(find.text('ถัดไป (0/5)'), findsOneWidget);

    // Next → bank (payout account).
    await tester.tap(find.text('ถัดไป (0/5)'));
    await tester.pumpAndSettle();
    expect(find.text('บัญชีรับเงิน'), findsOneWidget);

    // A too-short account number blocks advancing to the review step.
    await tester.enterText(find.byKey(const Key('reg_account_number')), '123');
    await tester.tap(find.text('ถัดไป'));
    await tester.pump();
    expect(find.textContaining('เลขบัญชี'), findsOneWidget);
    expect(find.text('ตรวจทานข้อมูล'), findsNothing);

    // A valid account advances to the review step with the design submit CTA.
    await tester.enterText(
        find.byKey(const Key('reg_account_number')), '1234567890');
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
    expect(find.text('ตรวจทานข้อมูล'), findsOneWidget);
    expect(find.text('ส่งใบสมัคร'), findsOneWidget);
    // The review row shows only the MASKED account number, never the full digits.
    expect(find.textContaining('7890'), findsOneWidget);
    expect(find.textContaining('1234567890'), findsNothing);
  });

  testWidgets('document step picks an image via the (real) picker seam',
      (tester) async {
    await pump(tester);
    // Advance to the documents step.
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();

    // Tap the first doc row's "Upload" → choose gallery from the sheet.
    await tester.tap(find.text('อัปโหลด').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลือกจากคลัง'));
    await tester.pumpAndSettle();

    // The picker seam was invoked (production wires the real image_picker), the row flips to the
    // captured state, and the footer CTA count updates.
    expect(picker.picks, contains(DocSource.gallery));
    expect(find.text('เลือกแล้ว'), findsOneWidget);
    expect(find.text('ถัดไป (1/5)'), findsOneWidget);
  });
}
