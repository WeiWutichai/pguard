import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/auth/registration/role_selection_screen.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('renders a card for each role (customer + guard)',
      (tester) async {
    // Fakes so a future test that taps a role (→ register()) stays off real storage/network.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appStoreProvider.overrideWithValue(InMemoryStore()),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        pguardApiProvider.overrideWithValue(
            FakeApi(onPost: (_, __) async => <String, dynamic>{})),
      ],
      child: const MaterialApp(home: RoleSelectionScreen()),
    ));
    await tester.pump();

    expect(find.textContaining('จ้าง รปภ'), findsOneWidget);
    expect(find.textContaining('เจ้าหน้าที่ รปภ.'), findsOneWidget);
    // Per the role-chooser design the cards describe the role's purpose (guard self-access vs
    // hiring a guard); approval is surfaced later on the pending screen.
    expect(find.textContaining('สำหรับเจ้าหน้าที่เพื่อเข้าใช้งานระบบ'),
        findsOneWidget);
    expect(find.textContaining('จ้างเจ้าหน้าที่รักษาความปลอดภัยระดับมืออาชีพ'),
        findsOneWidget);
    // Guard is presented FIRST (above the hire card), matching the design order.
    expect(
      tester.getTopLeft(find.text('เจ้าหน้าที่ รปภ.')).dy,
      lessThan(tester.getTopLeft(find.text('จ้าง รปภ')).dy),
    );
  });
}
