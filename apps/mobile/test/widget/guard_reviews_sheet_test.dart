import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/available_guard.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/widgets/guard_card.dart';
import 'package:pguard_mobile/features/booking/widgets/guard_reviews_sheet.dart';

import '../support/fakes.dart';

void main() {
  /// Pumps a single [GuardCard] whose "View reviews" affordance opens the reviews sheet, with the
  /// api faked to the supplied ratings handler. Thai default locale (no locale override).
  Future<void> pumpCardWithSheet(
    WidgetTester tester, {
    required AvailableGuard guard,
    required Future<dynamic> Function(String path, Map<String, dynamic>? query)
        onGet,
  }) {
    final api = FakeApi(onGet: onGet);
    return tester.pumpWidget(
      ProviderScope(
        overrides: [pguardApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => GuardCard(
                guard: guard,
                selected: false,
                onTap: () {},
                onViewReviews: () => showGuardReviewsSheet(
                    context: context, guardId: guard.guardId),
              ),
            ),
          ),
        ),
      ),
    );
  }

  const guard = AvailableGuard(
    guardId: 'g-aaaa',
    averageRating: '4.50',
    reviewCount: 2,
  );

  testWidgets(
      'tapping "View reviews" opens the sheet: parses the ratings response — aggregate + reviews newest-first',
      (tester) async {
    await pumpCardWithSheet(
      tester,
      guard: guard,
      onGet: (path, _) async {
        expect(path, '/guards/g-aaaa/ratings');
        return {
          'guard_id': 'g-aaaa',
          'average': '4.50', // decimal string on the wire
          'count': 2,
          'reviews': [
            {
              'id': 'r-old',
              'guard_id': 'g-aaaa',
              'overall_rating': 4,
              'review_text': 'Older review',
              'created_at': '2026-06-01T00:00:00Z',
            },
            {
              'id': 'r-new',
              'guard_id': 'g-aaaa',
              'overall_rating': 5,
              'review_text': 'Newer review',
              'created_at': '2026-06-10T00:00:00Z',
            },
          ],
        };
      },
    );

    await tester.tap(find.text('ดูรีวิว'));
    await tester.pumpAndSettle();

    // Aggregate header: numeric average (unique to the sheet) + the sheet's exact count line
    // ("จาก N รีวิว" — distinct from the card's "(N รีวิว)").
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('จาก 2 รีวิว'), findsOneWidget); // Thai default

    // Both comments render.
    expect(find.text('Newer review'), findsOneWidget);
    expect(find.text('Older review'), findsOneWidget);

    // Newest-first: the newer review's comment appears above the older one's.
    final newerY = tester.getTopLeft(find.text('Newer review')).dy;
    final olderY = tester.getTopLeft(find.text('Older review')).dy;
    expect(newerY, lessThan(olderY));
  });

  testWidgets('a guard with no visible reviews shows the friendly empty state',
      (tester) async {
    await pumpCardWithSheet(
      tester,
      guard: const AvailableGuard(
          guardId: 'g-empty', averageRating: null, reviewCount: 0),
      onGet: (_, __) async =>
          {'guard_id': 'g-empty', 'count': 0, 'reviews': <dynamic>[]},
    );

    await tester.tap(find.text('ดูรีวิว'));
    await tester.pumpAndSettle();

    // Friendly empty state (Thai default). The unique subtitle anchors the assertion to the
    // sheet (the card itself also shows a "ยังไม่มีรีวิว" no-rating label — with no documents
    // indicator here since this fixture's has_documents is unknown — hence the exact count of
    // two; the sheet's distinctive copy proves the empty state rendered).
    expect(find.textContaining('ยังไม่มีรีวิวจากลูกค้า'), findsOneWidget);
    expect(find.text('ยังไม่มีรีวิว'), findsNWidgets(2));
  });
}
