import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/permissions/location_denied_screen.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('renders the deny banner; "Open Settings" delegates to the gate',
      (tester) async {
    final gate = FakePermissionGate(PgPermissionState.permanentlyDenied);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        permissionGateProvider.overrideWithValue(gate),
      ],
      child: const MaterialApp(home: LocationDeniedScreen()),
    ));
    await tester.pump();

    expect(find.text('ต้องเปิดสิทธิ์ตำแหน่ง'), findsOneWidget);
    expect(find.textContaining('สิทธิ์ตำแหน่งถูกปิดอยู่'), findsOneWidget);

    await tester.tap(find.text('เปิดในตั้งค่า'));
    await tester.pump();
    expect(gate.openSettingsCount, 1);

    await tester.pumpWidget(const SizedBox());
  });
}
