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

    test(
        'a genuine zero average WITH reviews is honest (shown, not fabricated)',
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

  // The per-category bars are NOT the headline's breakdown, and the screen has to be able to say
  // what they actually cover: the headline is the server's AVG over EVERY visible review (of an
  // already whole-star `overall_rating`), the bars are unrounded means over the returned PAGE.
  group('GuardRatings — the bars\' own sample', () {
    Map<String, dynamic> review(
      String id, {
      int overall = 4,
      int? punctuality,
      int? professionalism,
      int? communication,
      int? appearance,
    }) =>
        {
          'id': id,
          'guard_id': 'g1',
          'overall_rating': overall,
          'punctuality': punctuality,
          'professionalism': professionalism,
          'communication': communication,
          'appearance': appearance,
          'created_at': '2026-06-01T12:00:00Z',
        };

    GuardRatings r(
            {Object? average = '4.00',
            required int count,
            required List<Map<String, dynamic>> reviews}) =>
        GuardRatings.fromJson({
          'guard_id': 'g1',
          'average': average,
          'count': count,
          'reviews': reviews,
        });

    test('categorySampleSize counts only reviews that scored a category', () {
      final g = r(count: 3, reviews: [
        review('a', punctuality: 5),
        review('b', appearance: 3, communication: 4),
        review('c'), // overall only — contributes to no bar
      ]);
      expect(g.categorySampleSize, 2);
    });

    test('categorySampleSize is 0 when nobody scored a category', () {
      expect(
          r(count: 2, reviews: [review('a'), review('b')]).categorySampleSize,
          0);
    });

    test('isPartialSample flips when the aggregate outruns the returned page',
        () {
      expect(r(count: 2, reviews: [review('a'), review('b')]).isPartialSample,
          isFalse);
      // 120 visible reviews, one page of 100 back → the bars cover a subset of the headline.
      expect(r(count: 120, reviews: [review('a')]).isPartialSample, isTrue);
    });

    test(
        'the bars and the headline are genuinely different numbers (5/4/4/4 → "4.0" over 4.25)',
        () {
      // The customer's form submits the category mean ROUNDED to a whole star, so the server's
      // overall is 4 while the categories plainly average 4.25. Nothing here is wrong — the two
      // are different quantities, which is exactly why the bars need their own caption.
      final g = r(average: '4.00', count: 1, reviews: [
        review('a',
            overall: 4,
            punctuality: 5,
            professionalism: 4,
            communication: 4,
            appearance: 4),
      ]);
      expect(g.averageValue, 4.0);
      expect(g.categoryAverage((x) => x.punctuality), 5.0);
      final bars = [
        g.categoryAverage((x) => x.punctuality)!,
        g.categoryAverage((x) => x.professionalism)!,
        g.categoryAverage((x) => x.communication)!,
        g.categoryAverage((x) => x.appearance)!,
      ];
      expect(bars.reduce((a, b) => a + b) / bars.length, 4.25);
    });

    test('a category nobody scored is omitted, never a fake 0.0', () {
      final g = r(count: 1, reviews: [review('a', punctuality: 5)]);
      expect(g.categoryAverage((x) => x.punctuality), 5.0);
      expect(g.categoryAverage((x) => x.appearance), isNull);
    });
  });
}
