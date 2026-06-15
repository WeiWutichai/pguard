import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/controllers/biometric_service.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/auth/biometric_enroll_screen.dart';

import '../support/fakes.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: '/auth/biometric',
      routes: [
        GoRoute(
            path: '/auth/biometric',
            builder: (_, __) => const BiometricEnrollScreen()),
        GoRoute(
            path: '/auth/role',
            builder: (_, __) => const Scaffold(body: Text('ROLE STUB'))),
      ],
    );

Future<({InMemoryStore store, FakeBiometricAuthenticator auth})> pumpScreen(
  WidgetTester tester, {
  bool available = true,
  bool authResult = true,
}) async {
  final store = InMemoryStore();
  final auth = FakeBiometricAuthenticator(
    deviceSupported: available,
    canCheck: available,
    authResult: authResult,
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appStoreProvider.overrideWithValue(store),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      biometricServiceProvider.overrideWithValue(
          BiometricService(store: store, authenticator: auth)),
    ],
    child: MaterialApp.router(routerConfig: buildRouter()),
  ));
  await tester.pumpAndSettle();
  return (store: store, auth: auth);
}

void main() {
  testWidgets('renders the enrol prompt with Enable + Skip', (tester) async {
    await pumpScreen(tester);
    expect(find.text('เปิดใช้ Face ID?'), findsOneWidget);
    expect(find.text('เปิดใช้ Face ID'), findsOneWidget); // enable CTA
    expect(find.text('ข้ามไปก่อน'), findsOneWidget); // skip
  });

  testWidgets('Enable persists the opt-in and continues to role-select',
      (tester) async {
    final h = await pumpScreen(tester, authResult: true);
    await tester.tap(find.text('เปิดใช้ Face ID'));
    await tester.pumpAndSettle();

    expect(h.auth.authCalls, 1);
    expect(h.store.biometricEnabled, isTrue);
    expect(find.text('ROLE STUB'), findsOneWidget);
  });

  testWidgets('a cancelled prompt does NOT opt in and keeps the user on screen',
      (tester) async {
    final h = await pumpScreen(tester, authResult: false);
    await tester.tap(find.text('เปิดใช้ Face ID'));
    await tester.pumpAndSettle();

    expect(h.store.biometricEnabled, isFalse);
    expect(find.text('ROLE STUB'), findsNothing);
    expect(find.text('เปิดใช้ Face ID?'), findsOneWidget); // still here
  });

  testWidgets('Skip continues without opting in', (tester) async {
    final h = await pumpScreen(tester);
    await tester.tap(find.text('ข้ามไปก่อน'));
    await tester.pumpAndSettle();

    expect(h.auth.authCalls, 0);
    expect(h.store.biometricEnabled, isFalse);
    expect(find.text('ROLE STUB'), findsOneWidget);
  });

  testWidgets('forwards straight to role-select when biometrics unavailable',
      (tester) async {
    await pumpScreen(tester, available: false);
    // initState's availability check skips the dead screen.
    expect(find.text('ROLE STUB'), findsOneWidget);
    expect(find.text('เปิดใช้ Face ID?'), findsNothing);
  });
}
