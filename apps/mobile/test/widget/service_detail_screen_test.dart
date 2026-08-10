import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/controllers/booking_flow_controller.dart';
import 'package:pguard_mobile/core/models/service_catalog.dart';
import 'package:pguard_mobile/features/booking/service_detail_screen.dart';

// base_fee ฿250/hr × min 6h = ฿1,500 starting figure (exact via Money, no float).
const _service = ServiceOption(
  id: 'svc-2',
  nameTh: 'คอนโด',
  nameEn: 'Condo',
  baseFeeSatang: 25000,
  minHours: 6,
  description: 'ดูแลพื้นที่ส่วนกลางคอนโด',
);

GoRouter _router() => GoRouter(
      initialLocation: '/book/detail',
      routes: [
        GoRoute(
          path: '/book/detail',
          builder: (_, __) => const ServiceDetailScreen(service: _service),
        ),
        GoRoute(
          path: '/book/form',
          builder: (_, __) => const Scaffold(
              body: Text('FORM', textDirection: TextDirection.ltr)),
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(routerConfig: _router()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the static included guarantees', (tester) async {
    await _pump(tester, ProviderContainer());

    // The three platform-wide "included" rows (titles + subtitles), hardcoded for every package.
    expect(find.text('ตรวจรอบรายชั่วโมง + รูปยืนยัน'), findsOneWidget);
    expect(find.text('เช็คอินพร้อม GPS ทุกชั่วโมง'), findsOneWidget);
    expect(find.text('ติดตามตำแหน่งแบบเรียลไทม์'), findsOneWidget);
    expect(find.text('แชต & โทรในแอป'), findsOneWidget);
  });

  testWidgets('shows the description (from notes) and the base × min pricing',
      (tester) async {
    await _pump(tester, ProviderContainer());

    // Description from the catalog `notes`, surfaced in the hero.
    expect(find.text('ดูแลพื้นที่ส่วนกลางคอนโด'), findsOneWidget);

    // Pricing rows: base rate + min-hours.
    expect(find.text('฿250 /ชม.'), findsOneWidget);
    expect(find.text('6 ชม.'), findsOneWidget);

    // เริ่มต้น = (฿250 × 6) + 7% VAT = ฿1,605. Catalog rates are VAT-EXCLUSIVE, so the figure a
    // customer reads as "the price" must be the VAT-INCLUSIVE one they are actually charged — with
    // the tax on its own row above it, never folded in silently.
    expect(find.text('฿105'), findsOneWidget); // VAT row: ฿1,500 × 7%
    expect(find.text('฿1,605'), findsOneWidget);
    expect(find.textContaining('฿250 × 6 ชม. + VAT 7%'), findsOneWidget);
    expect(find.textContaining('ยอดจริงคำนวณตามเวลาทำงานจริง'), findsOneWidget);
  });

  testWidgets(
      'choosing the package commits selectService and navigates to the form',
      (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await _pump(tester, c);

    // Nothing selected in the shared booking flow yet.
    expect(c.read(bookingFlowControllerProvider).service, isNull);

    await tester.tap(find.text('เลือกแพ็กเกจนี้'));
    await tester.pumpAndSettle();

    // The chosen service is now committed to the booking flow (carrying its min-hours floor —
    // the form's start/end time model computes the actual hours and enforces this minimum), and
    // we advanced to the booking form.
    final state = c.read(bookingFlowControllerProvider);
    expect(state.service?.id, 'svc-2');
    expect(state.minHours,
        6); // the service's min_hours, enforced on the form + server
    expect(find.text('FORM'), findsOneWidget);
  });
}
