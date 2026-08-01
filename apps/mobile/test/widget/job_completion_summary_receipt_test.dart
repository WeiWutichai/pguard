import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/job_completion_summary_screen.dart';

import '../support/fakes.dart';

/// The job-completion summary IS the receipt, but tapping "Rate" pushReplaces it off the stack, so a
/// customer had no way back to their settled bill (the reported "หลังจบงานไม่มีปุ่มดูใบเสร็จ"). The
/// summary now carries a "ดูใบเสร็จ / View receipt" action that opens the receipt sheet directly.
void main() {
  Future<void> pumpSummary(WidgetTester tester, FakeApi api) async {
    final router = GoRouter(
      initialLocation: '/booking/b1/summary',
      routes: [
        GoRoute(
          path: '/booking/:id/summary',
          builder: (_, s) =>
              JobCompletionSummaryScreen(bookingId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/booking/:id/review',
          builder: (_, __) => const Scaffold(body: Text('REVIEW')),
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

  testWidgets(
      'summary shows a "View receipt" action that opens the receipt sheet',
      (tester) async {
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') {
          return {
            'id': 'b1',
            'customer_id': 'c1',
            'status': 'completed',
            'guard_id': 'g1',
            'base_fee': '230.00',
            'hours': 8,
            'guard_count': 1,
          };
        }
        return <Map<String,
            dynamic>>[]; // /payments — settle not propagated → booking-derived
      },
    );
    await pumpSummary(tester, api);

    // The receipt action exists on the summary itself (alongside "Rate the guard").
    expect(find.text('ดูใบเสร็จ'), findsOneWidget);
    expect(find.text('ให้คะแนนเจ้าหน้าที่'), findsOneWidget);

    // Tapping it opens the shared receipt sheet — without leaving the summary / needing the rating.
    await tester.tap(find.text('ดูใบเสร็จ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('ใบสรุปค่าบริการ'), findsOneWidget,
        reason: 'the receipt sheet opens straight from the summary');

    await tester.pumpWidget(const SizedBox());
  });
}
