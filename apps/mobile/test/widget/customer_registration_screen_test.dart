import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/auth/registration/customer_registration_screen.dart';

import '../support/fakes.dart';

void main() {
  // Fakes so a valid submit doesn't hit real secure storage / network (it short-circuits with no
  // profile_token here — the controller-level submit is covered by the controller test).
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            appStoreProvider.overrideWithValue(InMemoryStore()),
            prefsStoreProvider.overrideWithValue(FakePrefsStore()),
            pguardApiProvider.overrideWithValue(
                FakeApi(onPost: (_, __) async => <String, dynamic>{})),
          ],
          child: const MaterialApp(home: CustomerRegistrationScreen()),
        ),
      );

  testWidgets('address is required and must meet a minimum length',
      (tester) async {
    await pump(tester);

    await tester.ensureVisible(find.text('สร้างบัญชี'));
    await tester.tap(find.text('สร้างบัญชี'));
    await tester.pump();
    expect(find.textContaining('กรุณากรอกที่อยู่'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('reg_address')), 'short');
    await tester.ensureVisible(find.text('สร้างบัญชี'));
    await tester.tap(find.text('สร้างบัญชี'));
    await tester.pump();
    expect(find.textContaining('ที่อยู่สั้นเกินไป'), findsOneWidget);
    // The live ✓ helper does not appear for an invalid address.
    expect(find.textContaining('✓ ที่อยู่ครบถ้วน'), findsNothing);
  });

  testWidgets('a valid address clears the errors and shows the live ✓ helper',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('reg_address')),
        '99/1 Sukhumvit Rd, Bangkok 10110');
    await tester.pump();
    // The design's live success helper appears once min length is met.
    expect(
        find.text('✓ ที่อยู่ครบถ้วน (อย่างน้อย 10 ตัวอักษร)'), findsOneWidget);

    await tester.ensureVisible(find.text('สร้างบัญชี'));
    await tester.tap(find.text('สร้างบัญชี'));
    await tester.pump();
    expect(find.textContaining('กรุณากรอกที่อยู่'), findsNothing);
    expect(find.textContaining('ที่อยู่สั้นเกินไป'), findsNothing);
  });
}
