import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/network/jwt.dart';

import '../support/fakes.dart';

void main() {
  group('Jwt', () {
    test('decodes role and subject claims', () {
      final token =
          fakeJwt({'sub': 'user-1', 'role': 'guard', 'exp': 9999999999});
      expect(Jwt.role(token), 'guard');
      expect(Jwt.subject(token), 'user-1');
    });

    test('returns null for malformed tokens', () {
      expect(Jwt.decodeClaims('not-a-jwt'), isNull);
      expect(Jwt.expiry('a.b'), isNull);
      expect(Jwt.role('garbage'), isNull);
    });

    test('isExpiredOrExpiring is true within the leeway window', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      // expires in 90s; with a 2-min leeway it should count as expiring.
      final soon = fakeJwt({
        'exp':
            now.add(const Duration(seconds: 90)).millisecondsSinceEpoch ~/ 1000
      });
      expect(
        Jwt.isExpiredOrExpiring(soon,
            leeway: const Duration(minutes: 2), now: now),
        isTrue,
      );
    });

    test('isExpiredOrExpiring is false when comfortably valid', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final later = fakeJwt({
        'exp': now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000
      });
      expect(
        Jwt.isExpiredOrExpiring(later,
            leeway: const Duration(minutes: 2), now: now),
        isFalse,
      );
    });

    test('treats a token with no exp as expired', () {
      final noExp = fakeJwt({'sub': 'x'});
      expect(Jwt.isExpiredOrExpiring(noExp, leeway: Duration.zero), isTrue);
    });
  });
}
