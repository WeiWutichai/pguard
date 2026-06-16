import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/guard_ratings_controller.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  ProviderContainer container(FakeApi api) {
    final c = ProviderContainer(
      overrides: [pguardApiProvider.overrideWithValue(api)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
      'fetches + parses ratings: avg/count/reviews + per-category averages DERIVED from reviews',
      () async {
    final api = FakeApi(onGet: (path, _) async {
      expect(path, '/guards/g1/ratings');
      return {
        'guard_id': 'g1',
        'average': '4.50', // decimal string on the wire
        'count': 2,
        'reviews': [
          {
            'id': 'r1',
            'guard_id': 'g1',
            'overall_rating': 5,
            'punctuality': 5,
            'professionalism': 4,
            'created_at': '2026-06-01T00:00:00Z',
          },
          {
            'id': 'r2',
            'guard_id': 'g1',
            'overall_rating': 4,
            'punctuality': 5,
            'created_at': '2026-06-02T00:00:00Z',
          },
        ],
      };
    });
    final r = await container(api).read(guardRatingsProvider('g1').future);

    expect(r.averageValue, 4.5);
    expect(r.count, 2);
    expect(r.reviews.length, 2);
    expect(r.hasRatings, isTrue);
    // Category averages are computed from the returned reviews, non-null values only.
    expect(r.categoryAverage((x) => x.punctuality), 5.0); // (5 + 5) / 2
    expect(r.categoryAverage((x) => x.professionalism), 4.0); // only r1 rated it
    expect(r.categoryAverage((x) => x.communication), isNull); // none rated it
  });

  test('no visible reviews → hasRatings false (never a fake 0.0)', () async {
    final api = FakeApi(
        onGet: (_, __) async =>
            {'guard_id': 'g1', 'count': 0, 'reviews': <dynamic>[]});
    final r = await container(api).read(guardRatingsProvider('g1').future);

    expect(r.count, 0);
    expect(r.averageValue, isNull);
    expect(r.hasRatings, isFalse);
  });
}
