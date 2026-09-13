import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/ratings/guard_ratings_screen.dart';
import 'package:pguard_mobile/widgets/star_rating.dart';

import '../support/fakes.dart';

/// The SECOND "กราฟยังไม่ตรง" screen the tester reported ("มีหน้านี้อีกหน้านึงครับที่กราฟยังไม่ตรง").
///
/// Here the bars are per-category averages sitting under a big headline average, so they read as a
/// breakdown of it — but they are a different quantity over a different set, in two independent
/// ways (see [GuardRatingsScreen]): the headline is the server's mean of already-ROUNDED whole-star
/// overalls across ALL visible reviews, while the bars are unrounded per-category means over the
/// returned page only, and only over reviews that filled the optional categories in.
///
/// The model side of that is locked in `test/unit/rating_test.dart`; these tests lock what the
/// SCREEN does about it, which is the part the guard actually sees.
Map<String, dynamic> _review(
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
      'comment': 'ตรงเวลาดีมาก',
    };

FakeApi _api({
  required String average,
  required int count,
  required List<Map<String, dynamic>> reviews,
}) =>
    FakeApi(
      onGet: (path, _) async => path == '/guards/g1/ratings'
          ? {
              'guard_id': 'g1',
              'average': average,
              'count': count,
              'reviews': reviews,
            }
          : const <String, dynamic>{},
    );

Future<void> _pump(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      seededGuardSession(),
    ],
    child: const MaterialApp(home: GuardRatingsScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('the bars name the sample they are averaged over, not the hero',
      (tester) async {
    // Three reviews back, but only two scored any category — so the bars speak for 2, not 3.
    await _pump(
      tester,
      _api(average: '4.00', count: 3, reviews: [
        _review('a', punctuality: 5, professionalism: 4),
        _review('b', appearance: 3, communication: 4),
        _review('c'), // overall only — contributes to no bar
      ]),
    );

    expect(
      find.text('เฉลี่ยรายหมวด · จาก 2 รีวิวที่ให้คะแนนรายหมวด'),
      findsOneWidget,
      reason: 'without this caption the bars read as a breakdown of the '
          'headline, which is a different number over a different set',
    );
    // The page returned everything the aggregate counted, so no truncation warning.
    expect(find.textContaining('แถบอาจไม่ครบ'), findsNothing);
  });

  testWidgets('warns when the aggregate counts more reviews than came back',
      (tester) async {
    // 120 visible reviews, one page of 2 returned → the bars cover a subset of the headline.
    await _pump(
      tester,
      _api(average: '4.50', count: 120, reviews: [
        _review('a', punctuality: 5),
        _review('b', punctuality: 4),
      ]),
    );

    expect(
        find.text('แสดงรีวิวล่าสุด 2 จาก 120 · แถบอาจไม่ครบ'), findsOneWidget,
        reason: 'the bars are computed from the returned page only');
  });

  testWidgets('the headline stars are the FRACTIONAL average, not round()',
      (tester) async {
    // 4.5 used to draw as FIVE full stars next to a printed "4.5" — the screen contradicting its
    // own number, a second, smaller way this page disagreed with itself.
    await _pump(
      tester,
      // Both reviews scored punctuality 5, so the BAR reads 5.0 while the headline reads 4.5 —
      // keeping the two numbers textually distinct here, and incidentally showing once more that
      // the bars are not the headline's own arithmetic.
      _api(average: '4.50', count: 2, reviews: [
        _review('a', overall: 5, punctuality: 5),
        _review('b', overall: 4, punctuality: 5),
      ]),
    );

    expect(find.text('4.5'), findsOneWidget, reason: 'the hero average');
    expect(find.text('5.0'), findsOneWidget, reason: 'the punctuality bar');
    final stars =
        tester.widget<StarRatingAverage>(find.byType(StarRatingAverage).first);
    expect(stars.value, 4.5);

    // Four full + one HALF: the half-star is the whole point, and `round()` would have made it a
    // fifth full star.
    final icons = tester
        .widgetList<Icon>(find.descendant(
            of: find.byType(StarRatingAverage).first,
            matching: find.byType(Icon)))
        .map((i) => i.icon)
        .toList();
    expect(icons.where((i) => i == Icons.star_rounded).length, 4);
    expect(icons.where((i) => i == Icons.star_half_rounded).length, 1);
  });

  testWidgets('no caption when nobody scored a category (there are no bars)',
      (tester) async {
    await _pump(
      tester,
      _api(average: '4.00', count: 2, reviews: [_review('a'), _review('b')]),
    );

    expect(find.textContaining('เฉลี่ยรายหมวด'), findsNothing);
    // …and no fake 0.0 bars invented to fill the space.
    expect(find.text('ตรงต่อเวลา'), findsNothing);
  });
}
