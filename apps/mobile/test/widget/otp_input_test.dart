import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/widgets/otp_input.dart';

/// The OTP screen has NO submit button by design — `onCompleted` is the ONLY submit trigger, so
/// these guarantees are load-bearing (staging 2026-07-14: a code that never reached full length
/// stranded the user with no error and nothing to tap).
void main() {
  Future<void> pump(WidgetTester tester,
      {required ValueChanged<String> onCompleted}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: OtpInput(onCompleted: onCompleted)),
    ));
    await tester.pump();
  }

  testWidgets('onCompleted fires exactly when the 6th digit lands',
      (tester) async {
    final completed = <String>[];
    await pump(tester, onCompleted: completed.add);

    await tester.enterText(find.byType(TextField), '12345');
    await tester.pump();
    expect(completed, isEmpty, reason: '5 digits is not a full code');

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    expect(completed, ['123456']);
  });

  testWidgets('a whole-code paste / autofill in one event still completes',
      (tester) async {
    // Real IME/SMS-autofill inserts the full string in a single onChanged — the `>=` guard must
    // catch it even though the length jumped straight to full without passing through each value.
    final completed = <String>[];
    await pump(tester, onCompleted: completed.add);

    await tester.enterText(find.byType(TextField), '246810');
    await tester.pump();
    expect(completed, ['246810']);
  });

  testWidgets(
      'the keyboard action key submits a full code (invisible manual fallback)',
      (tester) async {
    final completed = <String>[];
    await pump(tester, onCompleted: completed.add);

    await tester.enterText(find.byType(TextField), '654321');
    completed
        .clear(); // ignore the onChanged completion; assert the action-key path in isolation
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(completed, ['654321'],
        reason: 'Done/✓ rescues a full-but-unsent code');
  });
}
