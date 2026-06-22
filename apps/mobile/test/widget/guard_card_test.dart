import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/available_guard.dart';
import 'package:pguard_mobile/features/booking/widgets/guard_card.dart';

void main() {
  // No locale override → the LocaleController default (Thai) drives rendering,
  // so the card's rating line renders its Thai-only strings.
  Future<void> pumpCard(
    WidgetTester tester,
    AvailableGuard guard, {
    VoidCallback? onTap,
    VoidCallback? onViewReviews,
  }) {
    return tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: GuardCard(
            guard: guard,
            selected: false,
            onTap: onTap ?? () {},
            onViewReviews: onViewReviews ?? () {},
          ),
        ),
      ),
    ));
  }

  testWidgets('shows the rating average and review count', (tester) async {
    await pumpCard(
      tester,
      const AvailableGuard(
        guardId: 'guard-aaaa-1111',
        yearsOfExperience: 6,
        averageRating: '4.90',
        reviewCount: 188,
      ),
    );

    // Rating average rendered to one decimal + the review count.
    expect(find.textContaining('4.9'), findsOneWidget);
    expect(find.textContaining('188'), findsOneWidget);
    expect(find.textContaining('6 ปี'), findsOneWidget); // experience
  });

  testWidgets('shows an empty-rating label when there are no reviews',
      (tester) async {
    await pumpCard(
      tester,
      const AvailableGuard(
        guardId: 'guard-bbbb-2222',
        averageRating: null,
        reviewCount: 0,
      ),
    );

    expect(find.textContaining('ยังไม่มีรีวิว'), findsOneWidget);
  });

  testWidgets(
      'the "ดูรีวิว" affordance fires onViewReviews and does NOT radio-select the card',
      (tester) async {
    var selected = 0;
    var viewed = 0;
    await pumpCard(
      tester,
      const AvailableGuard(
        guardId: 'guard-cccc-3333',
        averageRating: '4.20',
        reviewCount: 9,
      ),
      onTap: () => selected++,
      onViewReviews: () => viewed++,
    );

    // The distinct view-reviews affordance is present (Thai-default locale).
    expect(find.text('ดูรีวิว'), findsOneWidget);

    await tester.tap(find.text('ดูรีวิว'));
    await tester.pump();

    // Opens reviews WITHOUT selecting the guard (first-come radio untouched).
    expect(viewed, 1);
    expect(selected, 0);
  });
}
