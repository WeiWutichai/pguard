import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/auth/otp_screen.dart';

import '../support/fakes.dart';

/// The OTP screen auto-submits on the 6th digit and has no submit button — so it MUST show a
/// spinner while the code is being checked, otherwise an in-flight verify is indistinguishable
/// from the "ค้าง" hang QA reported (staging 2026-07-14).
void main() {
  Future<void> pumpOtp(WidgetTester tester, FakeApi api) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      ],
      child: const MaterialApp(home: OtpScreen()),
    ));
    await tester.pump();
  }

  testWidgets(
      'entering 6 digits fires POST /otp/verify once and shows a spinner while it runs',
      (tester) async {
    final gate = Completer<dynamic>();
    var verifyCalls = 0;
    final api = FakeApi(onPost: (path, data) {
      if (path == '/otp/verify') {
        verifyCalls++;
        return gate.future; // hold the verify in-flight
      }
      return Future.value(<String, dynamic>{});
    });
    await pumpOtp(tester, api);

    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();

    expect(verifyCalls, 1, reason: 'auto-submit dispatched the verify');
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'an in-flight verify must look like progress, not a hang');

    // Unwind cleanly with a rejection so no navigation (which needs a router) is attempted.
    gate.completeError(const ApiException(
        message: 'รหัสไม่ถูกต้อง', code: 'BAD_REQUEST', statusCode: 400));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'spinner clears once verify resolves');
    expect(verifyCalls, 1, reason: 'no duplicate submit');
  });

  testWidgets(
      'verify of a phone that ALREADY has an account navigates to /login/pin '
      '(the returning path must NOT rely on the session redirect, which keeps /auth/otp)',
      (tester) async {
    // Regression for the "กรอก OTP แล้วค้าง" hang: once the controller-listener fix made the verify
    // actually fire, a RETURNING user (existing account) verified successfully, the screen flipped the
    // session to `returning`, then did a bare `return` trusting the router to redirect to PIN-login.
    // But `sessionRedirect(returning, '/auth/otp')` returns null (STAY) — so the user was stranded on
    // the OTP screen with no error and no forward progress. The screen must navigate EXPLICITLY.
    final api = FakeApi(onPost: (path, data) async {
      if (path == '/otp/verify') {
        return <String, dynamic>{'phone_verified_token': 'tok'};
      }
      if (path == '/auth/phone-status') {
        return <String, dynamic>{'account_exists': true};
      }
      return <String, dynamic>{};
    });

    final router = GoRouter(
      initialLocation: '/auth/otp',
      routes: [
        GoRoute(path: '/auth/otp', builder: (_, __) => const OtpScreen()),
        GoRoute(
          path: '/login/pin',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('PIN LOGIN'))),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pumpAndSettle();

    expect(find.text('PIN LOGIN'), findsOneWidget,
        reason:
            'an existing-account verify must LAND on PIN-login, not hang on /auth/otp');
    expect(find.byType(OtpScreen), findsNothing,
        reason: 'the OTP screen must be left behind');
    expect(api.calls,
        containsAll(<String>['POST /otp/verify', 'POST /auth/phone-status']));
  });
}
