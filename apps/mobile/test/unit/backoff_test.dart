import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/network/sockets/backoff.dart';

void main() {
  group('BackoffPolicy', () {
    const policy = BackoffPolicy(
      initial: Duration(seconds: 1),
      max: Duration(seconds: 60),
      factor: 2.0,
    );

    test('grows exponentially from the initial delay', () {
      expect(policy.delayFor(0), const Duration(seconds: 1));
      expect(policy.delayFor(1), const Duration(seconds: 2));
      expect(policy.delayFor(2), const Duration(seconds: 4));
      expect(policy.delayFor(3), const Duration(seconds: 8));
    });

    test('clamps to the 60s cap', () {
      expect(policy.delayFor(10), const Duration(seconds: 60));
      expect(policy.delayFor(100), const Duration(seconds: 60));
    });

    test('treats negative attempts as the first attempt', () {
      expect(policy.delayFor(-5), const Duration(seconds: 1));
    });
  });
}
