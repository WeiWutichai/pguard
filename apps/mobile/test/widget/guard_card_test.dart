import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/available_guard.dart';
import 'package:pguard_mobile/features/booking/widgets/guard_card.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, AvailableGuard guard) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GuardCard(guard: guard, selected: false, onTap: () {}),
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
}
