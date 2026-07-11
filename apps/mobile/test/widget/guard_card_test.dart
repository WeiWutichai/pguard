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

  testWidgets('shows the guard REAL NAME when discovery provides display_name',
      (tester) async {
    await pumpCard(
      tester,
      const AvailableGuard(
        guardId: 'guard-aaaa-1111',
        displayName: 'สมชาย มั่นคง',
        averageRating: '4.90',
        reviewCount: 188,
      ),
    );

    // Real name rendered as the title — NOT the id handle.
    expect(find.text('สมชาย มั่นคง'), findsOneWidget);
    expect(find.textContaining('เจ้าหน้าที่ #'), findsNothing);
  });

  testWidgets('falls back to the id handle when there is no display_name',
      (tester) async {
    await pumpCard(
      tester,
      const AvailableGuard(
        guardId: 'guard-bbbb-2222',
        averageRating: null,
        reviewCount: 0,
      ),
    );

    // No name → the "เจ้าหน้าที่ #XXXX" id-derived handle (Thai-default locale).
    expect(find.textContaining('เจ้าหน้าที่ #'), findsOneWidget);
  });

  testWidgets('renders the guard PHOTO when an avatar_url is provided',
      (tester) async {
    await pumpCard(
      tester,
      const AvailableGuard(
        guardId: 'guard-cccc-3333',
        displayName: 'อนันต์ ศรีสุข',
        avatarUrl: 'https://cdn.example/guard-cccc.jpg',
        averageRating: '4.50',
        reviewCount: 12,
      ),
    );

    // The avatar is a network image (the photo) — present when avatar_url is set.
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.image, isA<NetworkImage>());
    expect(
        (img.image as NetworkImage).url, 'https://cdn.example/guard-cccc.jpg');
  });

  testWidgets('shows the initials monogram (no Image) when there is no photo',
      (tester) async {
    await pumpCard(
      tester,
      const AvailableGuard(
        guardId: 'guard-dddd-4444',
        displayName: 'บุญมี',
        averageRating: null,
        reviewCount: 0,
      ),
    );

    // No photo → no network image; the first GRAPHEME of the name is the monogram. "บุญมี" begins
    // with the cluster "บุ" (บ + the below-vowel ◌ุ), so the monogram is "บุ" not a broken "บ".
    expect(find.byType(Image), findsNothing);
    expect(find.text('บุ'), findsOneWidget);
  });

  testWidgets('shows "มีเอกสาร" when the guard has documents on file',
      (tester) async {
    await pumpCard(
      tester,
      const AvailableGuard(
        guardId: 'guard-aaaa-1111',
        averageRating: '4.90',
        reviewCount: 188,
        hasDocuments: true,
      ),
    );

    expect(find.textContaining('มีเอกสาร'), findsOneWidget);
    expect(find.textContaining('ไม่มีเอกสาร'), findsNothing);
  });

  testWidgets(
      'shows "ไม่มีเอกสาร" when the guard has no documents (honest absence)',
      (tester) async {
    await pumpCard(
      tester,
      const AvailableGuard(
        guardId: 'guard-bbbb-2222',
        averageRating: null,
        reviewCount: 0,
        hasDocuments: false,
      ),
    );

    expect(find.textContaining('ไม่มีเอกสาร'), findsOneWidget);
  });

  testWidgets(
      'renders NO documents indicator when the backend omitted has_documents (unknown)',
      (tester) async {
    await pumpCard(
      tester,
      const AvailableGuard(
        guardId: 'guard-cccc-3333',
        averageRating: null,
        reviewCount: 0,
        // hasDocuments omitted → null (older backend) → say nothing, never a false claim.
      ),
    );

    expect(find.textContaining('เอกสาร'), findsNothing);
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
