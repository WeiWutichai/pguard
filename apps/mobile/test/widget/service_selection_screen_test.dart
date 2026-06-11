import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/features/booking/service_selection_screen.dart';

void main() {
  testWidgets('renders a card per service with its indicative price',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: ServiceSelectionScreen()),
    ));
    await tester.pump();

    // Each catalog category is shown (bilingual title; the design's "Other" card carries
    // its parenthetical).
    expect(find.textContaining('หมู่บ้าน · Village'), findsOneWidget);
    expect(find.textContaining('คอนโด · Condo'), findsOneWidget);
    expect(find.textContaining('โรงงาน · Factory'), findsOneWidget);
    expect(find.textContaining('อื่นๆ (ระบุเอง)'), findsOneWidget);

    // Indicative ฿/hr estimates exactly as designed ("฿230/ชม." — no "เริ่ม" prefix)…
    expect(find.text('฿230/ชม.'), findsOneWidget); // village
    expect(find.text('฿250/ชม.'), findsOneWidget); // condo
    expect(find.text('฿280/ชม.'), findsOneWidget); // factory
    // …and the custom "Other" service shows NO price at all.
    expect(find.text('ตามจริง'), findsNothing);
    expect(find.textContaining('เริ่ม ฿'), findsNothing);
  });
}
