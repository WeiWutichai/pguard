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

    // Each catalog category is shown (bilingual title).
    expect(find.textContaining('หมู่บ้าน · Village'), findsOneWidget);
    expect(find.textContaining('คอนโด · Condo'), findsOneWidget);
    expect(find.textContaining('โรงงาน · Factory'), findsOneWidget);

    // Indicative ฿/hr estimates from the catalog are rendered…
    expect(find.textContaining('฿230'), findsOneWidget); // village
    expect(find.textContaining('฿250'), findsOneWidget); // condo
    // …and the custom "Other" service shows no fixed price.
    expect(find.text('ตามจริง'), findsOneWidget);
  });
}
