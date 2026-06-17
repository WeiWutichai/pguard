import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/rating.dart';

void main() {
  // Locks the "never fabricate a rating" contract the live-map profile block depends on: the
  // numeric average is shown ONLY when there are real reviews AND a parseable average.
  group('GuardRatings.hasRatings', () {
    GuardRatings r({Object? average, int count = 0}) => GuardRatings.fromJson({
          'guard_id': 'g1',
          'average': average,
          'count': count,
          'reviews': const [],
        });

    test('count 0 → no rating, even if an average string is present', () {
      expect(r(average: '0', count: 0).hasRatings, isFalse);
      expect(r(average: '4.9', count: 0).hasRatings, isFalse);
    });

    test('absent/garbage average → no rating (never default to a number)', () {
      expect(r(average: null, count: 5).hasRatings, isFalse);
      expect(r(average: 'n/a', count: 5).hasRatings, isFalse);
    });

    test('a genuine zero average WITH reviews is honest (shown, not fabricated)',
        () {
      final g = r(average: '0', count: 3);
      expect(g.hasRatings, isTrue);
      expect(g.averageValue, 0.0);
    });

    test('a real average with reviews is shown', () {
      final g = r(average: '4.50', count: 12);
      expect(g.hasRatings, isTrue);
      expect(g.averageValue, 4.5);
    });
  });
}
