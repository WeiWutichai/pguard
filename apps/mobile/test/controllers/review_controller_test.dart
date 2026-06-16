import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/review_controller.dart';
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

  test(
      'submit posts overall + non-null categories + trimmed text → submitted; no guard_id on the wire',
      () async {
    Object? body;
    final api = FakeApi(onPost: (path, data) async {
      expect(path, '/assignments/a1/review');
      body = data;
      return {'id': 'rev1'};
    });
    final c = container(api);
    final outcome =
        await c.read(reviewControllerProvider.notifier).submit(
              assignmentId: 'a1',
              overallRating: 5,
              punctuality: 4,
              professionalism: null, // omitted category dropped from the body
              communication: 3,
              appearance: null,
              reviewText: '  ดีมาก  ', // trimmed
            );

    expect(outcome, ReviewOutcome.submitted);
    final map = body! as Map<String, dynamic>;
    expect(map['overall_rating'], 5);
    expect(map['punctuality'], 4);
    expect(map['communication'], 3);
    expect(map.containsKey('professionalism'), isFalse);
    expect(map.containsKey('appearance'), isFalse);
    expect(map['review_text'], 'ดีมาก'); // surrounding whitespace stripped
    // The reviewed guard is derived server-side from the assignment — never trust the client.
    expect(map.containsKey('guard_id'), isFalse);
    // No lingering error/busy after success.
    expect(c.read(reviewControllerProvider).busy, isFalse);
    expect(c.read(reviewControllerProvider).error, isNull);
  });

  test('whitespace-only review text is omitted (no empty review_text on the wire)',
      () async {
    Object? body;
    final api = FakeApi(onPost: (_, data) async {
      body = data;
      return {'id': 'rev2'};
    });
    final outcome =
        await container(api).read(reviewControllerProvider.notifier).submit(
              assignmentId: 'a1',
              overallRating: 4,
              reviewText: '   ',
            );

    expect(outcome, ReviewOutcome.submitted);
    final map = body! as Map<String, dynamic>;
    expect(map['overall_rating'], 4);
    expect(map.containsKey('review_text'), isFalse);
  });

  test('409 → alreadyReviewed, surfaced as a normal end state (no error message)',
      () async {
    final api = FakeApi(onPost: (_, __) async {
      throw const ApiException(
          message: 'already reviewed', code: 'CONFLICT', statusCode: 409);
    });
    final c = container(api);
    final outcome =
        await c.read(reviewControllerProvider.notifier).submit(
              assignmentId: 'a1',
              overallRating: 5,
            );

    expect(outcome, ReviewOutcome.alreadyReviewed);
    expect(c.read(reviewControllerProvider).error, isNull); // not an error
    expect(c.read(reviewControllerProvider).busy, isFalse);
  });

  test('non-409 ApiException → error with the server message surfaced', () async {
    final api = FakeApi(onPost: (_, __) async {
      throw const ApiException(
          message: 'booking not completed',
          code: 'CONFLICT',
          statusCode: 422);
    });
    final c = container(api);
    final outcome =
        await c.read(reviewControllerProvider.notifier).submit(
              assignmentId: 'a1',
              overallRating: 5,
            );

    expect(outcome, ReviewOutcome.error);
    expect(c.read(reviewControllerProvider).error, 'booking not completed');
    expect(c.read(reviewControllerProvider).busy, isFalse);
  });

  test('re-entrancy latch: a second submit while the first is in flight is rejected',
      () async {
    var posts = 0;
    final gate = Completer<void>();
    final api = FakeApi(onPost: (_, __) async {
      posts++;
      await gate.future; // hold the first call open
      return {'id': 'rev3'};
    });
    final c = container(api);
    final notifier = c.read(reviewControllerProvider.notifier);

    final first = notifier.submit(assignmentId: 'a1', overallRating: 5);
    // busy is set synchronously before the await, so the second call sees the latch.
    final second = await notifier.submit(assignmentId: 'a1', overallRating: 4);
    expect(second, ReviewOutcome.error);

    gate.complete();
    expect(await first, ReviewOutcome.submitted);
    expect(posts, 1); // the second submit never reached the network
  });
}
