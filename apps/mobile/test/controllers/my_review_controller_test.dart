import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/my_review_controller.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
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

  test('a 404 (not rated yet) resolves to null — the gate offers the form', () async {
    final api = FakeApi(onGet: (path, _) async {
      expect(path, '/assignments/b1/review');
      throw const ApiException(message: 'not found', statusCode: 404);
    });
    final review = await container(api).read(myReviewProvider('b1').future);
    expect(review, isNull);
  });

  test('an existing review parses → the gate shows the "rated" state', () async {
    final api = FakeApi(onGet: (path, _) async {
      expect(path, '/assignments/b1/review');
      return {
        'id': 'rev9',
        'guard_id': 'g1',
        'overall_rating': 4,
        'punctuality': 5,
        'created_at': '2026-07-03T11:33:57Z',
      };
    });
    final review = await container(api).read(myReviewProvider('b1').future);
    expect(review, isNotNull);
    expect(review!.overallRating, 4);
    expect(review.guardId, 'g1');
  });

  test('a non-404 error propagates (not silently treated as "not rated")', () async {
    final api = FakeApi(onGet: (_, __) async =>
        throw const ApiException(message: 'boom', statusCode: 500));
    await expectLater(
      container(api).read(myReviewProvider('b1').future),
      throwsA(isA<ApiException>()),
    );
  });
}
