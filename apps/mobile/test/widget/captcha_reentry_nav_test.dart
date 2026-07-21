import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/controllers/auth_controller.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/auth/captcha_screen.dart';

import '../support/fakes.dart';

/// Reproduces the REAL navigation shape of the "ไม่ได้รับรหัส? ขอใหม่" path with go_router
/// (push('/auth/captcha') → push('/auth/otp') → go('/auth/captcha')) to pin down whether the
/// CaptchaScreen is REMOUNTED (initState → loadChallenge re-runs) or REUSED (stale burned
/// challenge stays rendered). The production router uses the same sibling GoRoute layout.
void main() {
  testWidgets(
      'ขอใหม่ leg: go(/auth/captcha) from /auth/otp re-fetches a challenge '
      '(the burned one must not stay submittable)', (tester) async {
    var served = 0;
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/otp/challenge');
        served++;
        return {
          'challenge_id': 'ch$served',
          'question': served == 1 ? '11 + 7 = ?' : '2 + 2 = ?',
          'expires_in': 180,
        };
      },
      onPost: (path, _) async {
        // sendOtp succeeds → the server BURNS ch1 (GETDEL) and the flow advances to OTP.
        expect(path, '/otp/request');
        return {'message': 'ok', 'expires_in': 300};
      },
    );
    final container = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ]);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).setPhone('0812345678');

    // Same sibling layout as app_router.dart (captcha + otp as flat GoRoutes).
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
            path: '/start',
            builder: (_, __) => const Scaffold(body: Text('start'))),
        GoRoute(
            path: '/auth/captcha', builder: (_, __) => const CaptchaScreen()),
        GoRoute(
            path: '/auth/otp',
            builder: (_, __) => Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => context.go('/auth/captcha'),
                      child: const Text('ขอใหม่'),
                    ),
                  ),
                )),
      ],
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();

    // Enter captcha the way phone_entry does: push.
    router.push('/auth/captcha');
    await tester.pumpAndSettle();
    expect(served, 1, reason: 'first mount loads ch1');
    expect(find.text('11 + 7 = ?'), findsOneWidget);

    // Solve + submit → advances (push /auth/otp), ch1 is now burned server-side.
    await tester.enterText(find.byType(TextField), '18');
    await container.read(authControllerProvider.notifier).sendOtp('18');
    router.push('/auth/otp');
    await tester.pumpAndSettle();
    expect(find.text('ขอใหม่'), findsOneWidget);

    // The real resend leg: go('/auth/captcha').
    await tester.tap(find.text('ขอใหม่'));
    await tester.pumpAndSettle();

    // THE PROBE: did re-entry fetch a fresh challenge, or is burned ch1 still submittable?
    expect(served, 2,
        reason: 'RE-ENTRY MUST RE-FETCH — if this fails, the CaptchaScreen was '
            'reused without initState and the burned ch1 is still rendered');
    expect(find.text('2 + 2 = ?'), findsOneWidget,
        reason: 'the fresh question must be the one rendered');
  });
}
