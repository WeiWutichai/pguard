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
    // A tall surface so the multi-step content (5 doc tiles) + the active step's button are
    // on-screen (the default 800×600 clips the Next button just past the fold).
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

  testWidgets('multi-step: advances personal → documents → bank, rejects a too-short account',
      (tester) async {
    await pump(tester);

    // Step 1 (personal) is shown first.
    expect(find.text('เพศ / Gender'), findsOneWidget);

    // Next → documents (the doc list is tall — scroll the control into view first).
    await tester.ensureVisible(find.text('ถัดไป / Next'));
    await tester.tap(find.text('ถัดไป / Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ID card'), findsOneWidget);

    // Next → bank (the continue button becomes Submit).
    await tester.ensureVisible(find.text('ถัดไป / Next'));
    await tester.tap(find.text('ถัดไป / Next'));
    await tester.pumpAndSettle();
    expect(find.text('บันทึกและส่ง / Submit'), findsOneWidget);

    // A too-short account number is rejected client-side (no submit).
    await tester.enterText(find.byKey(const Key('reg_account_number')), '123');
    await tester.ensureVisible(find.text('บันทึกและส่ง / Submit'));
    await tester.tap(find.text('บันทึกและส่ง / Submit'));
    await tester.pump();
    expect(find.textContaining('Account must be'), findsOneWidget);
  });

  testWidgets('document step picks an image via the (real) picker seam', (tester) async {
    await pump(tester);
    // Advance to the documents step.
    await tester.tap(find.text('ถัดไป / Next'));
    await tester.pumpAndSettle();

    // Tap the first doc's "Pick" → choose gallery from the sheet.
    await tester.tap(find.text('เลือก / Pick').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลือกจากคลัง / Choose from gallery'));
    await tester.pumpAndSettle();

    // The picker seam was invoked (production wires the real image_picker) and the tile updates.
    expect(picker.picks, contains(DocSource.gallery));
    expect(find.text('เลือกแล้ว / Selected'), findsOneWidget);
  });
}
