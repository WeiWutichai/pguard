import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/auth_controller.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/auth/captcha_screen.dart';

import '../support/fakes.dart';

Future<void> pumpCaptcha(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ],
    child: const MaterialApp(home: CaptchaScreen()),
  ));
  await tester.pump(); // first frame
  await tester.pump(const Duration(milliseconds: 20)); // loadChallenge resolves
}

void main() {
  testWidgets('reloading the question clears the previous answer',
      (tester) async {
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
    );
    await pumpCaptcha(tester, api);

    // Answer the first question.
    await tester.enterText(find.byType(TextField), '18');
    await tester.pump();
    expect(find.text('18'), findsOneWidget);

    // Reload a fresh question — the stale answer must be cleared (the smoke-test bug).
    await tester.tap(find.text('โหลดคำถามใหม่'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('18'), findsNothing,
        reason: 'a new question makes the old answer meaningless — clear it');
    expect(served, 2, reason: 'reload fetched a new challenge');
  });

  testWidgets(
      'ISSUE 4: a failed send AUTO-refreshes the challenge and clears the stale answer',
      (tester) async {
    // The real trap: /otp/request fails (e.g. cooldown), the controller auto-refreshes the burned
    // captcha to a NEW question, but the OLD answer left in the field would then fail the NEXT
    // submit even though the user "answered correctly". The field must clear on challenge change.
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
        expect(path, '/otp/request');
        // Server rejects → the controller fetches a fresh challenge (keeping the error).
        throw const ApiException(
            message: 'กรุณารอสักครู่ก่อนขอ OTP ใหม่',
            code: 'OTP_COOLDOWN',
            statusCode: 400);
      },
    );
    final container = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ]);
    addTearDown(container.dispose);
    // A valid phone so sendOtp reaches /otp/request (not the early invalid-phone bail).
    container.read(authControllerProvider.notifier).setPhone('0812345678');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CaptchaScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20)); // ch1 loads

    await tester.enterText(find.byType(TextField), '18');
    await tester.pump();
    expect(find.text('18'), findsOneWidget);

    // Submit → /otp/request rejects → auto-refresh to ch2 → the listener clears the stale answer.
    await tester.tap(find.text('ยืนยันและส่ง OTP'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(served, 2,
        reason: 'the failed send auto-refreshed the burned challenge');
    expect(find.text('18'), findsNothing,
        reason:
            'the stale answer is cleared when the challenge auto-refreshes');
    // The new question is shown (proves the refresh landed) + the error is visible + localized.
    expect(find.text('2 + 2 = ?'), findsOneWidget);
    expect(find.text('กรุณารอสักครู่ก่อนขอรหัสใหม่'), findsOneWidget);
  });
}
