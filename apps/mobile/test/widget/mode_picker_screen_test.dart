import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/controllers/registration_controller.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/auth/registration/role_selection_screen.dart';

import '../support/fakes.dart';

/// A router with the mode picker + stub destinations so we can assert where a tap navigates.
GoRouter _router() => GoRouter(
      initialLocation: '/auth/role',
      routes: [
        GoRoute(
            path: '/auth/role',
            builder: (_, __) => const RoleSelectionScreen()),
        GoRoute(
            path: '/home/guard',
            builder: (_, __) => const Scaffold(body: Text('GUARD HOME'))),
        GoRoute(
            path: '/home/customer',
            builder: (_, __) => const Scaffold(body: Text('CUSTOMER HOME'))),
        GoRoute(
            path: '/auth/register/guard',
            builder: (_, __) => const Scaffold(body: Text('GUARD FORM'))),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  required FakeApi api,
  required AuthUser user,
  InMemoryStore? store,
}) async {
  final c = ProviderContainer(overrides: [
    pguardApiProvider.overrideWithValue(api),
    appStoreProvider.overrideWithValue(store ?? InMemoryStore()),
    prefsStoreProvider.overrideWithValue(FakePrefsStore()),
  ]);
  addTearDown(c.dispose);
  c.read(sessionProvider.notifier).onLoggedIn(user);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(routerConfig: _router()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'AUTHENTICATED dual-role → mode picker: shows both roles + the current/ready badges',
      (tester) async {
    await _pump(
      tester,
      api: FakeApi(onPost: (_, __) async => <String, dynamic>{}),
      user: const AuthUser(
          userId: 'u1', role: 'customer', roles: ['customer', 'guard']),
    );
    expect(find.text('เลือกโหมด'), findsOneWidget);
    expect(find.text('เจ้าหน้าที่ รปภ.'), findsOneWidget);
    expect(find.text('จ้าง รปภ'), findsOneWidget);
    // The active role is badged "ปัจจุบัน"; the other enrolled role "พร้อมใช้".
    expect(find.text('ปัจจุบัน'), findsOneWidget);
    expect(find.text('พร้อมใช้'), findsOneWidget);
  });

  testWidgets('tapping the ENROLLED other role switches + routes to its home',
      (tester) async {
    final store = InMemoryStore();
    await _pump(
      tester,
      store: store,
      api: FakeApi(onPost: (path, _) async {
        expect(path, '/auth/switch-role');
        return {
          'access_token':
              fakeJwt({'sub': 'u1', 'role': 'guard', 'exp': 9999999999}),
          'refresh_token': 'r-new',
          'expires_in': 3600,
        };
      }),
      user: const AuthUser(
          userId: 'u1', role: 'customer', roles: ['customer', 'guard']),
    );

    await tester.tap(find.text('เจ้าหน้าที่ รปภ.'));
    await tester.pumpAndSettle();

    // Switched (no logout) → routed to the guard home.
    expect(find.text('GUARD HOME'), findsOneWidget);
    expect(store.refresh, 'r-new');
  });

  testWidgets(
      'tapping a NOT-enrolled role starts the add-role flow → that role profile form',
      (tester) async {
    final store = InMemoryStore();
    await _pump(
      tester,
      store: store,
      api: FakeApi(onPost: (path, _) async {
        expect(path, '/auth/roles');
        return {'user_id': 'u1', 'profile_token': 'ptok-guard'};
      }),
      // Single-role customer → guard is NOT enrolled (the "+ add" path).
      user: const AuthUser(userId: 'u1', role: 'customer', roles: ['customer']),
    );

    await tester.tap(find.text('เจ้าหน้าที่ รปภ.'));
    await tester.pumpAndSettle();

    // The profile_token was captured and the guard profile form opened.
    expect(store.profileToken, 'ptok-guard');
    expect(find.text('GUARD FORM'), findsOneWidget);
  });

  testWidgets('the close button returns to the CURRENT role home (no logout)',
      (tester) async {
    await _pump(
      tester,
      api: FakeApi(onPost: (_, __) async => <String, dynamic>{}),
      user: const AuthUser(
          userId: 'u1', role: 'customer', roles: ['customer', 'guard']),
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('CUSTOMER HOME'), findsOneWidget);
  });

  testWidgets('UNauthenticated → the original onboarding chooser (single-role path intact)',
      (tester) async {
    final c = ProviderContainer(overrides: [
      pguardApiProvider
          .overrideWithValue(FakeApi(onPost: (_, __) async => <String, dynamic>{})),
      appStoreProvider.overrideWithValue(InMemoryStore()),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ]);
    addTearDown(c.dispose);
    // No login → session is unauthenticated; the screen must show the registration chooser.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: RoleSelectionScreen()),
    ));
    await tester.pumpAndSettle();
    // Original onboarding copy ("คุณคือใคร?"), NOT the mode picker ("เลือกโหมด").
    expect(find.text('คุณคือใคร?'), findsOneWidget);
    expect(find.text('เลือกโหมด'), findsNothing);
    // The registration controller is the driver here (no switch controller involvement).
    expect(c.read(registrationControllerProvider).role, isNull);
  });
}
