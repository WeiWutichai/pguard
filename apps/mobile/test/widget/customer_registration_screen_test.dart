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

  testWidgets('address is required and must meet a minimum length', (tester) async {
    await pump(tester);

    await tester.tap(find.text('บันทึกและส่ง / Submit'));
    await tester.pump();
    expect(find.textContaining('Address is required'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).last, 'short');
    await tester.tap(find.text('บันทึกและส่ง / Submit'));
    await tester.pump();
    expect(find.textContaining('too short'), findsOneWidget);
  });

  testWidgets('a valid address clears the validation errors', (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byType(TextFormField).last, '99/1 Sukhumvit Rd, Bangkok 10110');
    await tester.tap(find.text('บันทึกและส่ง / Submit'));
    await tester.pump();
    expect(find.textContaining('Address is required'), findsNothing);
    expect(find.textContaining('too short'), findsNothing);
  });
}
