import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/payment_screen.dart';

import '../support/fakes.dart';

/// The PRE-PAY screen must quote the VAT-INCLUSIVE amount the customer is actually charged, with
/// the 7% shown as its own line. Catalog rates are VAT-exclusive, so a screen that headlined the
/// subtotal would quote ฿1,000 and then take ฿1,070.
Map<String, dynamic> _bookingJson({String tip = '0'}) => {
      'id': 'b1',
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': 'accepted',
      'base_fee': '500.00',
      'hours': 2,
      'guard_count': 1,
      'tip': tip,
    };

Future<void> _pump(WidgetTester tester, FakeApi api) async {
  final router = GoRouter(
    initialLocation: '/booking/b1/pay',
    routes: [
      GoRoute(
        path: '/booking/:id/pay',
        builder: (_, s) => PaymentScreen(bookingId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/booking/:id/cancel',
        builder: (_, __) => const Scaffold(body: Text('CANCEL FLOW')),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tokenProvider) => FakeBookingFeed()),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('the summary itemises subtotal, VAT 7% and the charged total',
      (tester) async {
    // ฿500 × 2 hr × 1 guard = ฿1,000.00 subtotal; VAT ฿70.00; charged ฿1,070.00.
    final api = FakeApi(
        onGet: (path, _) async =>
            path == '/bookings/b1' ? _bookingJson() : const <dynamic>[]);
    await _pump(tester, api);

    expect(find.text('รวมเป็นเงิน'), findsOneWidget);
    expect(find.text('฿1,000.00'), findsOneWidget);
    expect(find.text('ภาษีมูลค่าเพิ่ม 7%'), findsOneWidget,
        reason: 'VAT is its own line, never folded into the total');
    expect(find.text('฿70.00'), findsOneWidget);

    // The headline total and the pay CTA both quote the VAT-INCLUSIVE figure.
    expect(find.text('ยอดชำระ (ประมาณ)'), findsOneWidget);
    expect(find.text('฿1,070.00'), findsOneWidget);
    expect(find.text('ชำระเงิน ฿1,070'), findsOneWidget);
    expect(find.textContaining('รวมภาษีมูลค่าเพิ่ม 7% แล้ว'), findsOneWidget);
  });

  testWidgets('a tip is taxed with the rest of the bill', (tester) async {
    // ฿1,000.00 + ฿100.00 tip = ฿1,100.00 subtotal; VAT ฿77.00; charged ฿1,177.00.
    final api = FakeApi(
        onGet: (path, _) async => path == '/bookings/b1'
            ? _bookingJson(tip: '100.00')
            : const <dynamic>[]);
    await _pump(tester, api);

    expect(find.text('฿1,100.00'), findsOneWidget);
    expect(find.text('฿77.00'), findsOneWidget);
    expect(find.text('฿1,177.00'), findsOneWidget);
  });
}
