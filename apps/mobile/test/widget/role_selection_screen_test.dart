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

    expect(find.textContaining('ลูกค้า'), findsOneWidget);
    expect(find.textContaining('เจ้าหน้าที่ รปภ.'), findsOneWidget);
    // The guard card flags that approval is required (it can't log in until approved).
    expect(find.textContaining('ต้องผ่านการอนุมัติ'), findsOneWidget);
  });
}
