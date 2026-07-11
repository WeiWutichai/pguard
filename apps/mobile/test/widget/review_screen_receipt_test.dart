import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/review_screen.dart';

import '../support/fakes.dart';

/// The post-review thank-you dialog's "ดูใบเสร็จ / View receipt" action. Regression for the
/// silent no-op: when the booking snapshot wasn't available the tap used to do NOTHING — it must
/// now await the fetch and, on failure, show the honest retry snackbar (same copy as the wallet
/// rows) instead of swallowing the tap.
void main() {
  Future<void> pumpReview(WidgetTester tester, FakeApi api) async {
    final router = GoRouter(
      initialLocation: '/booking/b1/review',
      routes: [
        GoRoute(
          path: '/booking/:id/review',
          builder: (_, s) => ReviewScreen(bookingId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/home/customer',
          builder: (_, __) => const Scaffold(body: Text('HOME')),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        // The review screen primes bookingStatusControllerProvider (a live feed) — fake it.
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tokenProvider) => FakeBookingFeed()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets(
      'thank-you dialog "View receipt": booking fetch failure shows the retry '
      'snackbar (was a silent no-op)', (tester) async {
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') {
          throw Exception('boom'); // the booking snapshot never loads
        }
        if (path == '/assignments/b1/review') {
          // Not rated yet → the form shows.
          throw const ApiException(message: 'not found', statusCode: 404);
        }
        return <Map<String, dynamic>>[]; // /payments
      },
      onPost: (_, __) async => {'success': true}, // the review submit succeeds
    );
    await pumpReview(tester, api);

    // Rate (tap the first overall star) and submit.
    await tester.tap(find.byIcon(Icons.star_outline_rounded).first);
    await tester.pump();
    await tester.tap(find.text('ส่งรีวิว'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The thank-you dialog offers the receipt.
    expect(find.text('ขอบคุณสำหรับการรีวิว'), findsOneWidget);
    await tester.tap(find.text('ดูใบเสร็จ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 300));

    // The failed snapshot surfaces the retry snackbar — and the flow still escapes to home
    // (never a dead-end).
    expect(find.text('โหลดใบเสร็จไม่สำเร็จ — ลองใหม่'), findsOneWidget,
        reason: 'the tap must never be a silent no-op');
    expect(find.text('ใบสรุปค่าบริการ'), findsNothing,
        reason: 'no sheet without a booking');
    expect(find.text('HOME'), findsOneWidget,
        reason: 'the thank-you flow still lands on home');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'thank-you dialog "View receipt": opens the receipt sheet when the '
      'snapshot loads', (tester) async {
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') {
          return {
            'id': 'b1',
            'customer_id': 'c1',
            'status': 'completed',
            'guard_id': 'g1',
            'hours': 2,
            'base_fee': '500.00',
          };
        }
        if (path == '/assignments/b1/review') {
          throw const ApiException(message: 'not found', statusCode: 404);
        }
        return <Map<String, dynamic>>[]; // /payments
      },
      onPost: (_, __) async => {'success': true},
    );
    await pumpReview(tester, api);

    await tester.tap(find.byIcon(Icons.star_outline_rounded).first);
    await tester.pump();
    await tester.tap(find.text('ส่งรีวิว'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.text('ดูใบเสร็จ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ใบสรุปค่าบริการ'), findsOneWidget,
        reason: 'the receipt sheet opens with the booking snapshot');

    await tester.pumpWidget(const SizedBox());
  });
}
