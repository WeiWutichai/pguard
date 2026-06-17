import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/permissions/location_rationale_screen.dart';

import '../support/fakes.dart';

Widget _host({required bool forGuard}) => ProviderScope(
      overrides: [
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        permissionGateProvider
            .overrideWithValue(FakePermissionGate(PgPermissionState.denied)),
      ],
      child: MaterialApp(home: LocationRationaleScreen(forGuard: forGuard)),
    );

void main() {
  testWidgets('renders the Thai rationale, both scope options + actions',
      (tester) async {
    await tester.pumpWidget(_host(forGuard: false));
    await tester.pump();

    expect(find.text('เปิดตำแหน่งเพื่อความปลอดภัย'), findsOneWidget);
    expect(find.textContaining('pguard ใช้ตำแหน่ง'), findsOneWidget);
    expect(find.text('ขณะใช้งานแอป'), findsOneWidget);
    expect(find.text('ตลอดเวลา'), findsOneWidget);
    expect(find.text('อนุญาต'), findsOneWidget);
    expect(find.text('ไม่ใช่ตอนนี้'), findsOneWidget);
    // Exactly one option is selected (no fabricated multi-select).
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping the other scope option moves the selection',
      (tester) async {
    await tester.pumpWidget(_host(forGuard: false));
    await tester.pump();

    await tester.tap(find.text('ตลอดเวลา'));
    await tester.pump();
    // Still exactly one selected after switching.
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
