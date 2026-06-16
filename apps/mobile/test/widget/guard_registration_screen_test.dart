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

  /// Fill the now-required step-0 fields (name, gender, DOB, experience, workplace) so the flow can
  /// advance. DOB confirms the picker's default selected date via "OK" (en MaterialLocalizations).
  Future<void> fillPersonal(WidgetTester tester,
      {String name = 'สมชาย ใจดี'}) async {
    await tester.enterText(find.byKey(const Key('reg_full_name')), name);
    await tester.tap(find.text('ชาย')); // gender = male
    await tester.pump();
    await tester.tap(find.byKey(const Key('reg_dob')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('reg_experience')), '5');
    await tester.enterText(
        find.byKey(const Key('reg_workplace')), 'ABC Security');
  }

  /// Select a bank from the dropdown (now required on the bank step).
  Future<void> selectBank(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ธนาคารกสิกรไทย').last);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'multi-step happy path: personal → documents → bank (matching name) → review',
      (tester) async {
    await pump(tester);
    expect(find.text('ขั้นที่ 1 จาก 4'), findsOneWidget);

    await fillPersonal(tester);
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
    expect(find.textContaining('บัตรประชาชน'), findsOneWidget);
    expect(find.text('ถัดไป (0/5)'), findsOneWidget);

    // No documents attached → no expiry needed; advance to bank.
    await tester.tap(find.text('ถัดไป (0/5)'));
    await tester.pumpAndSettle();
    expect(find.text('บัญชีรับเงิน'), findsOneWidget);

    // Account name must match the registered full name; a selected bank + valid account number +
    // matching name advances to the review step.
    await selectBank(tester);
    await tester.enterText(
        find.byKey(const Key('reg_account_number')), '1234567890');
    await tester.enterText(
        find.byKey(const Key('reg_account_name')), 'สมชาย ใจดี');
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
    expect(find.text('ตรวจทานข้อมูล'), findsOneWidget);
    expect(find.text('ส่งใบสมัคร'), findsOneWidget);
    // The review row shows only the MASKED account number, never the full digits.
    expect(find.textContaining('7890'), findsOneWidget);
    expect(find.textContaining('1234567890'), findsNothing);
  });

  testWidgets('step 0 blocks until every required personal field is filled',
      (tester) async {
    await pump(tester);
    // Tapping Next with an empty form stays on step 1 with a prompt.
    await tester.tap(find.text('ถัดไป'));
    await tester.pump();
    expect(find.text('ขั้นที่ 1 จาก 4'), findsOneWidget);
    expect(find.textContaining('ชื่อ-นามสกุล'), findsWidgets); // error snackbar/label

    // Filling everything advances to the document step.
    await fillPersonal(tester);
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
    expect(find.textContaining('บัตรประชาชน'), findsOneWidget);
  });

  testWidgets('an attached document with no expiry blocks step 1', (tester) async {
    await pump(tester);
    await fillPersonal(tester);
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();

    // Attach the first document (no expiry yet).
    await tester.tap(find.text('อัปโหลด').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลือกจากคลัง'));
    await tester.pumpAndSettle();
    expect(find.text('เลือกแล้ว'), findsOneWidget);
    expect(find.text('ต้องระบุวันหมดอายุ'), findsOneWidget); // required prompt

    // Next is blocked while the attached doc has no expiry — stays on the document step.
    await tester.tap(find.text('ถัดไป (1/5)'));
    await tester.pumpAndSettle();
    expect(find.text('ถัดไป (1/5)'), findsOneWidget); // still on docs
    expect(find.text('บัญชีรับเงิน'), findsNothing);

    // Setting the expiry clears the requirement (picker confirms its future default via "OK"):
    // the red required prompt is replaced by the chosen date, so the gate would now pass (the
    // step-advance itself is the same path the happy-path test covers).
    await tester.tap(find.text('ต้องระบุวันหมดอายุ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('ต้องระบุวันหมดอายุ'), findsNothing);
    expect(find.textContaining('หมดอายุ'), findsWidgets); // the chosen date now shows
  });

  testWidgets('bank step rejects an account name that does not match the registrant',
      (tester) async {
    await pump(tester);
    await fillPersonal(tester, name: 'สมชาย ใจดี');
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ถัดไป (0/5)'));
    await tester.pumpAndSettle();
    await selectBank(tester);

    // Valid account number but a DIFFERENT holder name → blocked, stays on bank.
    await tester.enterText(
        find.byKey(const Key('reg_account_number')), '1234567890');
    await tester.enterText(
        find.byKey(const Key('reg_account_name')), 'สมหญิง อื่น');
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ต้องตรงกับชื่อ'), findsOneWidget); // mismatch error
    expect(find.text('ตรวจทานข้อมูล'), findsNothing);

    // Correcting the name to match (case/space-insensitive) advances.
    await tester.enterText(
        find.byKey(const Key('reg_account_name')), '  สมชาย   ใจดี ');
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
    expect(find.text('ตรวจทานข้อมูล'), findsOneWidget);
  });

  testWidgets('document step picks an image via the (real) picker seam',
      (tester) async {
    await pump(tester);
    await fillPersonal(tester);
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
