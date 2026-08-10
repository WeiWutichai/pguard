import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/controllers/services_controller.dart';
import 'package:pguard_mobile/core/models/service_catalog.dart';
import 'package:pguard_mobile/features/booking/service_detail_screen.dart';
import 'package:pguard_mobile/features/booking/service_selection_screen.dart';

const _catalog = [
  ServiceOption(
    id: 'svc-1',
    nameTh: 'หมู่บ้าน',
    nameEn: 'Village',
    baseFeeSatang: 23000, // ฿230/hr
    minHours: 4,
    description: 'เหมาะกับหมู่บ้านจัดสรร',
  ),
  ServiceOption(
    id: 'svc-2',
    nameTh: 'คอนโด',
    nameEn: 'Condo',
    baseFeeSatang: 25000, // ฿250/hr
    minHours: 6,
  ),
  // A free-quote service (base_fee 0 → no price line).
  ServiceOption(
    id: 'svc-3',
    nameTh: 'อื่นๆ',
    nameEn: 'Other',
    baseFeeSatang: 0,
    minHours: 1,
  ),
];

/// A router that wires the two-screen package picker (selection → detail) plus a form stub, so a
/// test can verify "ดูรายละเอียด" pushes the detail screen with the selected ServiceOption.
GoRouter _router() => GoRouter(
      initialLocation: '/book',
      routes: [
        GoRoute(
            path: '/book', builder: (_, __) => const ServiceSelectionScreen()),
        GoRoute(
          path: '/book/detail',
          builder: (_, s) =>
              ServiceDetailScreen(service: s.extra as ServiceOption),
        ),
        GoRoute(
          path: '/book/form',
          builder: (_, __) => const Scaffold(
              body: Text('FORM', textDirection: TextDirection.ltr)),
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  required Override servicesOverride,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [servicesOverride],
    child: MaterialApp.router(routerConfig: _router()),
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

  testWidgets(
      'renders a radio card per fetched service with its ฿/hr, min-hours, '
      'and (when present) description', (tester) async {
    await _pump(tester,
        servicesOverride:
            servicesProvider.overrideWith((ref) async => _catalog));
    await tester.pumpAndSettle();

    // Each fetched service NAME is shown (exact, single-language Thai by default — `textContaining`
    // would also match the description, which embeds "หมู่บ้าน").
    expect(find.text('หมู่บ้าน'), findsOneWidget);
    expect(find.text('คอนโด'), findsOneWidget);
    expect(find.text('อื่นๆ'), findsOneWidget);

    // The description (from `notes`) renders for the service that has one, not for the others.
    expect(find.text('เหมาะกับหมู่บ้านจัดสรร'), findsOneWidget);

    // Indicative "฿/hr" from the catalog base_fee…
    expect(find.text('฿230 /ชม.'), findsOneWidget);
    expect(find.text('฿250 /ชม.'), findsOneWidget);

    // …min-hours line per card…
    expect(find.text('ขั้นต่ำ 4 ชม.'), findsOneWidget);
    expect(find.text('ขั้นต่ำ 6 ชม.'), findsOneWidget);
    expect(find.text('ขั้นต่ำ 1 ชม.'), findsOneWidget);

    // …and a free-quote service (base_fee 0) shows NO price line.
    expect(find.text('฿0 /ชม.'), findsNothing);

    // The rates above are VAT-EXCLUSIVE, so the picker says so ONCE, above the prices it
    // qualifies — the customer meets the 7% while comparing packages, not at checkout.
    expect(find.textContaining('ราคาต่อชั่วโมงยังไม่รวมภาษีมูลค่าเพิ่ม 7%'),
        findsOneWidget);
  });

  testWidgets(
      'the View-details CTA is disabled until a package is selected, then '
      'navigates to the detail screen', (tester) async {
    await _pump(tester,
        servicesOverride:
            servicesProvider.overrideWith((ref) async => _catalog));
    await tester.pumpAndSettle();

    // CTA present but disabled (no selection yet) — tapping it does nothing.
    final cta = find.widgetWithText(ElevatedButton, 'ดูรายละเอียด');
    expect(cta, findsOneWidget);
    expect(tester.widget<ElevatedButton>(cta).onPressed, isNull);

    await tester.tap(cta);
    await tester.pumpAndSettle();
    // Still on the selection screen (no navigation).
    expect(find.text('FORM'), findsNothing);
    expect(find.text('หมู่บ้าน'), findsOneWidget);

    // Select a package (radio-select — does NOT navigate yet).
    await tester.tap(find.text('คอนโด'));
    await tester.pumpAndSettle();
    expect(find.text('FORM'), findsNothing); // selecting alone never navigates

    // Now the CTA is enabled and opens the detail screen for the selected package.
    expect(tester.widget<ElevatedButton>(cta).onPressed, isNotNull);
    await tester.tap(cta);
    await tester.pumpAndSettle();

    // The detail screen's title is the selected service name, and its hero shows it too.
    expect(find.text('คอนโด'), findsWidgets);
    expect(find.text('เลือกแพ็กเกจนี้'), findsOneWidget);
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
