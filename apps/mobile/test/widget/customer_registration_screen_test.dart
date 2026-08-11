import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/auth/registration/customer_registration_screen.dart';

import '../support/fakes.dart';

/// The customer profile form. Both `full_name` and `address` are REQUIRED — an anonymous signup is
/// what left the admin approval queue showing a bare id ("#5680b50f") with no way to identify the
/// applicant, so the assertions here are as much about what does NOT happen (no
/// `POST /profile/customer`) as about what does.
GoRouter _router() => GoRouter(
      initialLocation: '/auth/register/customer',
      routes: [
        GoRoute(
            path: '/auth/register/customer',
            builder: (_, __) => const CustomerRegistrationScreen()),
        GoRoute(
            path: '/auth/pending',
            builder: (_, __) => const Scaffold(body: Text('PENDING'))),
      ],
    );

const String _validAddress = '99/1 Sukhumvit Rd, Bangkok 10110';

/// A store carrying the single-use `profile_token` the submit presents as its Bearer — without it
/// the controller short-circuits before the API and a "valid submit" would prove nothing.
InMemoryStore _readyStore() => InMemoryStore()..profileToken = 'ptok';

/// The fake API plus the payloads it was POSTed — the shared [FakeApi] logs paths and bearers but
/// not bodies, and one test needs to prove the name actually reached the wire.
class _Harness {
  _Harness(this.api, this.bodies);

  final FakeApi api;
  final Map<String, Object?> bodies;

  List<String> get calls => api.calls;
}

Future<_Harness> _pump(WidgetTester tester) async {
  final bodies = <String, Object?>{};
  final api = FakeApi(onPost: (path, data) async {
    bodies[path] = data;
    return <String, dynamic>{};
  });
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appStoreProvider.overrideWithValue(_readyStore()),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      pguardApiProvider.overrideWithValue(api),
    ],
    child: MaterialApp.router(routerConfig: _router()),
  ));
  await tester.pumpAndSettle();
  return _Harness(api, bodies);
}

Future<void> _tapCreate(WidgetTester tester) async {
  await tester.ensureVisible(find.text('สร้างบัญชี'));
  await tester.tap(find.text('สร้างบัญชี'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('address is required and must meet a minimum length',
      (tester) async {
    await _pump(tester);

    await _tapCreate(tester);
    expect(find.textContaining('กรุณากรอกที่อยู่'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('reg_address')), 'short');
    await _tapCreate(tester);
    expect(find.textContaining('ที่อยู่สั้นเกินไป'), findsOneWidget);
    // The live ✓ helper does not appear for an invalid address.
    expect(find.textContaining('✓ ที่อยู่ครบถ้วน'), findsNothing);
  });

  testWidgets('a valid address clears the errors and shows the live ✓ helper',
      (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('reg_address')), _validAddress);
    await tester.pump();
    // The design's live success helper appears once min length is met.
    expect(
        find.text('✓ ที่อยู่ครบถ้วน (อย่างน้อย 10 ตัวอักษร)'), findsOneWidget);

    await _tapCreate(tester);
    expect(find.textContaining('กรุณากรอกที่อยู่'), findsNothing);
    expect(find.textContaining('ที่อยู่สั้นเกินไป'), findsNothing);
  });

  testWidgets('a blank name blocks the submit — the API is never called',
      (tester) async {
    final h = await _pump(tester);
    // Everything else valid, so the ONLY thing that can block the submit is the missing name.
    await tester.enterText(find.byKey(const Key('reg_address')), _validAddress);
    await _tapCreate(tester);

    expect(find.textContaining('กรุณากรอกชื่อ-นามสกุล'), findsOneWidget);
    expect(h.calls, isEmpty);
    expect(find.text('PENDING'), findsNothing);
  });

  testWidgets('a whitespace-only name is still blank — the API is never called',
      (tester) async {
    final h = await _pump(tester);
    await tester.enterText(find.byKey(const Key('reg_address')), _validAddress);
    await tester.enterText(find.byKey(const Key('reg_full_name')), '   ');
    await _tapCreate(tester);

    expect(find.textContaining('กรุณากรอกชื่อ-นามสกุล'), findsOneWidget);
    expect(h.calls, isEmpty);
  });

  testWidgets('a name that is not a real name is rejected', (tester) async {
    final h = await _pump(tester);
    await tester.enterText(find.byKey(const Key('reg_address')), _validAddress);

    // Too short.
    await tester.enterText(find.byKey(const Key('reg_full_name')), 'ก');
    await _tapCreate(tester);
    expect(find.textContaining('กรุณากรอกชื่อจริง'), findsOneWidget);

    // Long enough, but no letters in it.
    await tester.enterText(find.byKey(const Key('reg_full_name')), '12345');
    await _tapCreate(tester);
    expect(find.textContaining('กรุณากรอกชื่อจริง'), findsOneWidget);

    expect(h.calls, isEmpty);
  });

  testWidgets('a valid name shows the live ✓ helper and submits',
      (tester) async {
    final h = await _pump(tester);
    await tester.enterText(find.byKey(const Key('reg_address')), _validAddress);
    await tester.enterText(find.byKey(const Key('reg_full_name')), 'พลอย ใจดี');
    await tester.pump();
    expect(find.text('✓ ชื่อครบถ้วน'), findsOneWidget);

    await _tapCreate(tester);

    expect(h.calls, contains('POST /profile/customer'));
    // The name reaches the wire — the whole point of making it required.
    expect(
        h.bodies['/profile/customer'], containsPair('full_name', 'พลอย ใจดี'));
    expect(find.text('PENDING'), findsOneWidget);
  });

  testWidgets('the name field is no longer labelled optional', (tester) async {
    await _pump(tester);
    // The "(ไม่บังคับ)" suffix belongs to company/email/phone only — 3 fields, not 4.
    expect(find.textContaining('(ไม่บังคับ)'), findsNWidgets(3));
  });
}
