import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
