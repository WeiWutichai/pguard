import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/review_screen.dart';
import 'package:pguard_mobile/widgets/star_rating.dart';

import '../support/fakes.dart';

/// The overall ★ is the AUTO-COMPUTED average of the per-category ministars (not a separate tap),
/// and the submit CTA is gated on EVERY category being rated.
void main() {
  Future<void> pumpReview(WidgetTester tester, FakeApi api) async {
    final router = GoRouter(
      initialLocation: '/booking/b1/review',
      routes: [
        GoRoute(
          path: '/booking/:id/review',
          builder: (_, s) => ReviewScreen(bookingId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/home/customer',
          builder: (_, __) => const Scaffold(body: Text('HOME')),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tokenProvider) => FakeBookingFeed()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  /// The four category inputs are the tappable StarRatingInputs; the overall is a read-only
  /// StarRatingAverage. Set category [i] (0..3) to [score] (1..5) by tapping its score-th star.
  Future<void> rateCategory(WidgetTester tester, int i, int score) async {
    final input = find.byType(StarRatingInput).at(i);
    final stars =
        find.descendant(of: input, matching: find.byType(InkResponse));
    await tester.tap(stars.at(score - 1));
    await tester.pump();
  }

  testWidgets(
      'submit is disabled until ALL categories are rated, then sends the average as overall',
      (tester) async {
    Map<String, dynamic>? posted;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/assignments/b1/review') {
          throw const ApiException(message: 'not found', statusCode: 404);
        }
        return const <dynamic>[];
      },
      onPost: (path, data) async {
        posted = data as Map<String, dynamic>;
        return {'success': true};
      },
    );
    await pumpReview(tester, api);

    // The overall is a read-only average display — NOT a tappable StarRatingInput. Only the 4
    // categories are tappable.
    expect(find.byType(StarRatingAverage), findsOneWidget);
    expect(find.byType(StarRatingInput), findsNWidgets(4));

    // Submit stays disabled until every category is rated.
    ElevatedButton submitBtn() => tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'ส่งรีวิว'));
    await rateCategory(tester, 0, 5);
    await rateCategory(tester, 1, 4);
    await rateCategory(tester, 2, 4);
    expect(submitBtn().onPressed, isNull,
        reason: '3 of 4 rated → still disabled');

    await rateCategory(tester, 3, 3); // 5,4,4,3 → avg 4.0
    expect(submitBtn().onPressed, isNotNull, reason: 'all rated → enabled');

    await tester.tap(find.text('ส่งรีวิว'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // overall = round((5+4+4+3)/4) = round(4.0) = 4; the categories ride along.
    expect(posted?['overall_rating'], 4);
    expect(posted?['punctuality'], 5);
    expect(posted?['professionalism'], 4);
    expect(posted?['communication'], 4);
    expect(posted?['appearance'], 3);
  });

  testWidgets('overall rounds the average to the nearest whole star (4.75 → 5)',
      (tester) async {
    Map<String, dynamic>? posted;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/assignments/b1/review') {
          throw const ApiException(message: 'not found', statusCode: 404);
        }
        return const <dynamic>[];
      },
      onPost: (path, data) async {
        posted = data as Map<String, dynamic>;
        return {'success': true};
      },
    );
    await pumpReview(tester, api);

    // 5,5,5,4 → avg 4.75 → rounds to 5.
    await rateCategory(tester, 0, 5);
    await rateCategory(tester, 1, 5);
    await rateCategory(tester, 2, 5);
    await rateCategory(tester, 3, 4);
    await tester.tap(find.text('ส่งรีวิว'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(posted?['overall_rating'], 5);
  });
}
