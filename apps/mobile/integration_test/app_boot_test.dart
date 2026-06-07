// Patrol smoke: the app boots and (with no stored session) lands on the phone-entry screen.
//
// This is the smallest runnable e2e — it needs an emulator/simulator but NOT the backend. It
// proves the Patrol harness + app wiring are intact. Run:
//   cd apps/mobile && dart run patrol_cli test -t integration_test/app_boot_test.dart
//
// NOTE: requires the native platform projects to exist first — this app is pure-Dart at this phase
// (`flutter create --platforms=android,ios .` to scaffold them). See tests/e2e/mobile/README.md.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:pguard_mobile/main.dart' as app;

void main() {
  patrolTest('boots to the phone-entry screen', ($) async {
    app.main();
    await $.pumpAndSettle();

    // The router redirect (app_router.dart): no session → /auth/phone. The phone field renders,
    // with the bilingual "เบอร์โทรศัพท์ / Phone" label.
    expect(find.byType(TextField), findsWidgets);
    expect(find.textContaining('Phone'), findsWidgets);
  });
}
