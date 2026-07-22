import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/biometric_service.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/features/auth/pin_lock_screen.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

/// A returning user with a session + PIN → the lock screen is the cold-start gate. Seed a
/// refresh+access+PIN so `Session._load` classifies the start as `locked`.
InMemoryStore lockedStore({required bool biometricEnabled}) => InMemoryStore()
  ..refresh = 'r'
  ..access = fakeJwt({'sub': 'u1', 'role': 'customer'})
  ..pinHash = 'h'
  ..pinSalt = 's'
  ..biometricEnabled = biometricEnabled;

Future<({ProviderContainer container, FakeBiometricAuthenticator auth})>
    pumpLock(
  WidgetTester tester, {
  required bool biometricEnabled,
  bool available = true,
  bool authResult = true,
}) async {
  final store = lockedStore(biometricEnabled: biometricEnabled);
  final auth = FakeBiometricAuthenticator(
    deviceSupported: available,
    canCheck: available,
    authResult: authResult,
  );
  final container = ProviderContainer(overrides: [
    appStoreProvider.overrideWithValue(store),
    prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    biometricServiceProvider.overrideWithValue(
        BiometricService(store: store, authenticator: auth)),
  ]);
  addTearDown(container.dispose);
  // Build + keep the Session provider alive so its startup _load() (a chain of async storage
  // reads) actually runs and classifies the cold start as `locked`.
  container.listen(sessionProvider, (_, __) {});
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: PinLockScreen()),
  ));
  // Settle both Session._load and the screen's biometric microtasks (each pump flushes the
  // microtask queue; there are no animations to chase).
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 5));
  }
  return (container: container, auth: auth);
}

void main() {
  testWidgets(
      'opted in + available: shows the biometric key, auto-prompts once, and '
      'unlocks on success', (tester) async {
    final h = await pumpLock(tester, biometricEnabled: true);

    expect(find.byIcon(Icons.fingerprint), findsOneWidget);
    expect(find.text('กรอก PIN หรือใช้ไบโอเมตริก'), findsOneWidget);
    expect(h.auth.authCalls, 1); // auto-prompt fired exactly once
    expect(
        h.container.read(sessionProvider).status, SessionStatus.authenticated);
  });

  testWidgets('not opted in: no biometric key and no auto-prompt',
      (tester) async {
    final h = await pumpLock(tester, biometricEnabled: false);

    expect(find.byIcon(Icons.fingerprint), findsNothing);
    expect(find.text('กรอก PIN เพื่อเข้าสู่ระบบ'), findsOneWidget);
    expect(h.auth.authCalls, 0);
    expect(h.container.read(sessionProvider).status, SessionStatus.locked);
  });

  testWidgets('opted in but unavailable: no biometric key, stays locked',
      (tester) async {
    final h =
        await pumpLock(tester, biometricEnabled: true, available: false);

    expect(find.byIcon(Icons.fingerprint), findsNothing);
    expect(h.auth.authCalls, 0);
    expect(h.container.read(sessionProvider).status, SessionStatus.locked);
  });

  testWidgets('failed auto-prompt leaves the user on the PIN keypad',
      (tester) async {
    final h = await pumpLock(tester,
        biometricEnabled: true, authResult: false);

    expect(h.auth.authCalls, 1);
    // The key is still offered for a manual retry; the gate is not cleared.
    expect(find.byIcon(Icons.fingerprint), findsOneWidget);
    expect(h.container.read(sessionProvider).status, SessionStatus.locked);
  });
}
