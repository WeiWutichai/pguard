import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/payment_screen.dart';

import '../support/fakes.dart';

/// The customer must be able to CANCEL from the payment screen while still unpaid + pre-arrival —
/// the guard accepted but they haven't transferred yet (reported "กดยกเลิกไม่ได้ … กรณียังไม่ได้
/// โอนเงิน"). The only exit used to be the back button.
Map<String, dynamic> bookingJson(String status, {String? paidAt}) => {
      'id': 'b1',
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': status,
      'base_fee': '500.00',
      'hours': 2,
      'guard_count': 1,
      if (paidAt != null) 'paid_at': paidAt,
    };

Future<void> pumpPayment(WidgetTester tester, FakeApi api) async {
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
  testWidgets(
      'accepted + UNPAID: the Cancel booking button opens the cancel flow',
      (tester) async {
    final api = FakeApi(
        onGet: (path, _) async => path == '/bookings/b1'
            ? bookingJson('accepted')
            : const <dynamic>[]);
    await pumpPayment(tester, api);

    final cancel = find.text('ยกเลิกการจอง');
    expect(cancel, findsOneWidget,
        reason: 'unpaid + accepted must offer a cancel');

    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('CANCEL FLOW'), findsOneWidget);
  });

  testWidgets('already PAID: no Cancel booking button (past the payment stage)',
      (tester) async {
    final api = FakeApi(
        onGet: (path, _) async => path == '/bookings/b1'
            ? bookingJson('accepted', paidAt: '2026-08-01T10:00:00Z')
            : const <dynamic>[]);
    await pumpPayment(tester, api);
    expect(find.text('ยกเลิกการจอง'), findsNothing);
  });
}
