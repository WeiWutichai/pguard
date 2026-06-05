import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/resend_policy.dart';

void main() {
  group('ResendPolicy', () {
    const policy = ResendPolicy(cooldown: Duration(seconds: 60));
    final sentAt = DateTime.utc(2026, 1, 1, 12, 0, 0);

    test('counts down whole seconds remaining', () {
      expect(policy.secondsRemaining(sentAt, sentAt), 60);
      expect(
        policy.secondsRemaining(
            sentAt, sentAt.add(const Duration(seconds: 18))),
        42,
      );
    });

    test('clamps to zero and allows resend after the cooldown', () {
      final after = sentAt.add(const Duration(seconds: 61));
      expect(policy.secondsRemaining(sentAt, after), 0);
      expect(policy.canResend(sentAt, after), isTrue);
      expect(policy.canResend(sentAt, sentAt), isFalse);
    });

    test('formats as m:ss', () {
      expect(policy.format(42), '0:42');
      expect(policy.format(5), '0:05');
      expect(policy.format(75), '1:15');
    });
  });
}
