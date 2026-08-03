import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/auth/registration/role_selection_screen.dart';
import 'package:pguard_mobile/features/legal/terms_screen.dart';

import '../support/fakes.dart';

/// The terms gate: registration must be BLOCKED until the three consents are accepted.
///
/// The requirement is "ถ้าไม่ยอมรับให้ค้างหน้านั้นไว้ไม่ให้ผ่าน" — so the assertions here are about
/// what does NOT happen (no `POST /auth/register`, no profile form) as much as what does.
GoRouter _router() => GoRouter(
      initialLocation: '/auth/role',
      routes: [
        GoRoute(
            path: '/auth/role',
            builder: (_, __) => const RoleSelectionScreen()),
        GoRoute(
            path: '/auth/terms',
            builder: (_, s) =>
                TermsScreen(readOnly: s.uri.queryParameters['read'] == '1')),
        GoRoute(
            path: '/auth/register/customer',
            builder: (_, __) => const Scaffold(body: Text('CUSTOMER FORM'))),
        GoRoute(
            path: '/auth/register/guard',
            builder: (_, __) => const Scaffold(body: Text('GUARD FORM'))),
      ],
    );

/// A stand-in document — the real asset is exercised by `terms_asset_test.dart`; here the point is
/// the GATE, and real asset I/O does not resolve under the widget-test fake clock.
const String _fakeDoc =
    'ข้อกำหนดและเงื่อนไขการใช้บริการ PGUARD\n1. บทนำ\nทดสอบ';

/// A store carrying a completed OTP+PIN onboarding, so `register()` would fire if it were reached.
InMemoryStore _readyStore() => InMemoryStore()
  ..phone = '0812345678'
  ..phoneVerifiedToken = 'pvt-token'
  ..onboardingPin = '123456';

Future<FakeApi> _pump(WidgetTester tester) async {
  final api = FakeApi(
    onPost: (_, __) async => <String, dynamic>{'profile_token': 'ptok'},
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(_readyStore()),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      termsDocumentProvider.overrideWith((ref) async => _fakeDoc),
    ],
    child: MaterialApp.router(routerConfig: _router()),
  ));
  await tester.pumpAndSettle();
  return api;
}

Future<void> _tapCustomerRole(WidgetTester tester) async {
  await tester.tap(find.textContaining('จ้าง รปภ'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'picking a role opens the terms FIRST — nothing is registered yet',
      (tester) async {
    final api = await _pump(tester);
    await _tapCustomerRole(tester);

    expect(find.text('ข้อกำหนดการใช้บริการ'), findsOneWidget);
    // The gate ran BEFORE the account call — the whole point of pre-registration consent.
    expect(api.calls, isEmpty);
    expect(find.text('CUSTOMER FORM'), findsNothing);
  });

  testWidgets('accepting is impossible until ALL THREE consents are ticked',
      (tester) async {
    final api = await _pump(tester);
    await _tapCustomerRole(tester);

    Finder button() =>
        find.widgetWithText(ElevatedButton, 'ยอมรับและดำเนินการต่อ');
    expect(tester.widget<ElevatedButton>(button()).onPressed, isNull);
    expect(
        find.text('ต้องยอมรับครบทุกข้อจึงจะสมัครสมาชิกต่อได้'), findsOneWidget);

    // Two of three is still not consent (PDPA wants the sensitive-data one on its own).
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(button()).onPressed, isNull);

    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(button()).onPressed, isNotNull);
    expect(api.calls,
        isEmpty); // still nothing registered — accept hasn't been tapped
  });

  testWidgets('accepting all three lets the registration through to the form',
      (tester) async {
    final api = await _pump(tester);
    await _tapCustomerRole(tester);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(Checkbox).at(i));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยอมรับและดำเนินการต่อ'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('POST /auth/register'));
    expect(find.text('CUSTOMER FORM'), findsOneWidget);
  });

  testWidgets(
      'backing out of the terms registers NOTHING and stays on the chooser',
      (tester) async {
    final api = await _pump(tester);
    await _tapCustomerRole(tester);
    expect(find.text('ข้อกำหนดการใช้บริการ'), findsOneWidget);

    // The only exits are "accept" or back — back must not create an account. Driven through the
    // system back gesture (the hardware/edge-swipe path), which is what a user reaching for "no"
    // actually presses.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(api.calls, isEmpty);
    expect(find.text('CUSTOMER FORM'), findsNothing);
    expect(find.textContaining('จ้าง รปภ'), findsOneWidget);
  });

  testWidgets('a document that fails to load offers NOTHING to accept',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appStoreProvider.overrideWithValue(InMemoryStore()),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        // A packaging failure must not present an accept button over an empty page.
        termsDocumentProvider.overrideWith((ref) async => ''),
      ],
      child: const MaterialApp(home: TermsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('โหลดเอกสารไม่สำเร็จ กรุณาลองใหม่'), findsOneWidget);
    expect(find.text('ยอมรับและดำเนินการต่อ'), findsNothing);
  });

  testWidgets('read-only mode shows the document with nothing to accept',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appStoreProvider.overrideWithValue(InMemoryStore()),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        termsDocumentProvider.overrideWith((ref) async => _fakeDoc),
      ],
      child: const MaterialApp(home: TermsScreen(readOnly: true)),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('ยอมรับและดำเนินการต่อ'), findsNothing);
    expect(find.textContaining('PGUARD'), findsWidgets);
  });
}
