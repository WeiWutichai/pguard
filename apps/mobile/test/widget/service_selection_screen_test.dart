import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/services_controller.dart';
import 'package:pguard_mobile/core/models/service_catalog.dart';
import 'package:pguard_mobile/features/booking/service_selection_screen.dart';

const _catalog = [
  ServiceOption(
    id: 'svc-1',
    nameTh: 'หมู่บ้าน',
    nameEn: 'Village',
    baseFeeSatang: 23000, // ฿230/hr
    minHours: 4,
  ),
  ServiceOption(
    id: 'svc-2',
    nameTh: 'คอนโด',
    nameEn: 'Condo',
    baseFeeSatang: 25000, // ฿250/hr
    minHours: 6,
  ),
  // A free-quote service (base_fee 0 → no price chip).
  ServiceOption(
    id: 'svc-3',
    nameTh: 'อื่นๆ',
    nameEn: 'Other',
    baseFeeSatang: 0,
    minHours: 1,
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required Override servicesOverride,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [servicesOverride],
    child: const MaterialApp(home: ServiceSelectionScreen()),
  ));
}

void main() {
  testWidgets('shows a spinner while the catalog is loading', (tester) async {
    final completer = Completer<List<ServiceOption>>();
    await _pump(tester,
        servicesOverride:
            servicesProvider.overrideWith((ref) => completer.future));
    await tester.pump(); // resolve the FutureProvider's loading frame

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(_catalog);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('renders a card per fetched service with its ฿/hr + min-hours',
      (tester) async {
    await _pump(tester,
        servicesOverride:
            servicesProvider.overrideWith((ref) async => _catalog));
    await tester.pumpAndSettle();

    // Each fetched service is shown (single-language Thai by default).
    expect(find.textContaining('หมู่บ้าน'), findsOneWidget);
    expect(find.textContaining('คอนโด'), findsOneWidget);
    expect(find.textContaining('อื่นๆ'), findsOneWidget);

    // Indicative ฿/hr from the catalog base_fee…
    expect(find.text('฿230/ชม.'), findsOneWidget);
    expect(find.text('฿250/ชม.'), findsOneWidget);

    // …min-hours line per card…
    expect(find.text('ขั้นต่ำ 4 ชม.'), findsOneWidget);
    expect(find.text('ขั้นต่ำ 6 ชม.'), findsOneWidget);
    expect(find.text('ขั้นต่ำ 1 ชม.'), findsOneWidget);

    // …and a free-quote service (base_fee 0) shows NO price chip.
    expect(find.text('฿0/ชม.'), findsNothing);
  });

  testWidgets('error state offers a retry that re-fetches the catalog',
      (tester) async {
    var attempt = 0;
    await _pump(tester,
        servicesOverride: servicesProvider.overrideWith((ref) async {
      attempt++;
      if (attempt == 1) throw Exception('network');
      return _catalog;
    }));
    await tester.pumpAndSettle();

    expect(find.textContaining('โหลดรายการบริการไม่สำเร็จ'), findsOneWidget);

    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();

    expect(find.textContaining('โหลดรายการบริการไม่สำเร็จ'), findsNothing);
    expect(find.textContaining('คอนโด'), findsOneWidget);
  });

  testWidgets('empty catalog shows the empty state', (tester) async {
    await _pump(tester,
        servicesOverride:
            servicesProvider.overrideWith((ref) async => const []));
    await tester.pumpAndSettle();

    expect(find.textContaining('ยังไม่มีบริการ'), findsOneWidget);
  });
}
