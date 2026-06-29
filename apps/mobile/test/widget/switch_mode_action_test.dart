import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/auth/widgets/switch_mode_action.dart';

import '../support/fakes.dart';

/// A home stub carrying the switch action; tapping it must reach the mode picker WITHOUT logging
/// out (the session is untouched).
GoRouter _router() => GoRouter(
      initialLocation: '/home/guard',
      routes: [
        GoRoute(
          path: '/home/guard',
          builder: (_, __) => const Scaffold(
            body: Center(child: SwitchModeAction()),
          ),
        ),
        GoRoute(
            path: '/auth/role',
            builder: (_, __) => const Scaffold(body: Text('MODE PICKER'))),
      ],
    );

Future<ProviderContainer> _pump(WidgetTester tester, AuthUser user) async {
  final c = ProviderContainer(overrides: [
    appStoreProvider.overrideWithValue(InMemoryStore()),
    prefsStoreProvider.overrideWithValue(FakePrefsStore()),
  ]);
  addTearDown(c.dispose);
  c.read(sessionProvider.notifier).onLoggedIn(user);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(routerConfig: _router()),
  ));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('the switch action self-hides for a single-role account',
      (tester) async {
    await _pump(tester,
        const AuthUser(userId: 'u1', role: 'guard', roles: ['guard']));
    expect(find.byIcon(Icons.swap_horiz), findsNothing);
  });

  testWidgets(
      'a dual-role account shows the switch action; tapping it opens the picker (no logout)',
      (tester) async {
    final c = await _pump(
        tester,
        const AuthUser(
            userId: 'u1', role: 'guard', roles: ['guard', 'customer']));
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);

    await tester.tap(find.byIcon(Icons.swap_horiz));
    await tester.pumpAndSettle();

    expect(find.text('MODE PICKER'), findsOneWidget);
    // The session is intact — opening the picker is NOT a logout.
    expect(c.read(sessionProvider).status, SessionStatus.authenticated);
    expect(c.read(sessionProvider).user!.role, 'guard');
  });
}
