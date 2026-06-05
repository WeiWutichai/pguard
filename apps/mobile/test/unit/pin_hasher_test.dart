import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/pin_hasher.dart';

void main() {
  group('PinHasher', () {
    const hasher = PinHasher();

    test('hash is deterministic for the same pin+salt', () {
      const salt = 'abc';
      expect(hasher.hash('123456', salt), hasher.hash('123456', salt));
    });

    test('different salts yield different hashes (salt matters)', () {
      expect(hasher.hash('123456', 'saltA'),
          isNot(hasher.hash('123456', 'saltB')));
    });

    test('verify accepts the correct pin and rejects the wrong one', () {
      const salt = 'pepper';
      final hash = hasher.hash('246810', salt);
      expect(hasher.verify('246810', salt, hash), isTrue);
      expect(hasher.verify('000000', salt, hash), isFalse);
    });

    test('generateSalt produces a non-empty value', () {
      final salt = hasher.generateSalt(Random(7));
      expect(salt, isNotEmpty);
    });
  });
}
