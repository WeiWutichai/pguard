import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/pin_policy.dart';

void main() {
  group('PinPolicy', () {
    const policy = PinPolicy();
    final now = DateTime.utc(2026, 1, 1, 12, 0, 0);

    test('validates a 6-digit numeric PIN', () {
      expect(policy.isValidFormat('123456'), isTrue);
      expect(policy.isValidFormat('12345'), isFalse); // too short
      expect(policy.isValidFormat('12345a'), isFalse); // non-digit
      expect(policy.isValidFormat('1234567'), isFalse); // too long
    });

    test('locks for 60s on the 5th wrong attempt', () {
      final d = policy.afterWrongAttempt(4, now); // -> 5th
      expect(d.newAttempts, 5);
      expect(d.locked, isTrue);
      expect(d.shouldWipe, isFalse);
      final remaining = policy.remainingLockout(d.lockUntilMs, now);
      expect(remaining, const Duration(seconds: 60));
    });

    test('does not lock on non-multiple attempts', () {
      final d = policy.afterWrongAttempt(0, now); // -> 1st
      expect(d.locked, isFalse);
      expect(d.attemptsRemaining, 9);
    });

    test('wipes on the 10th cumulative wrong attempt', () {
      final d = policy.afterWrongAttempt(9, now); // -> 10th
      expect(d.shouldWipe, isTrue);
      expect(d.newAttempts, 10);
    });

    test('remainingLockout is null once the deadline passes', () {
      final past =
          now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch;
      expect(policy.remainingLockout(past, now), isNull);
      expect(policy.remainingLockout(null, now), isNull);
    });
  });
}
