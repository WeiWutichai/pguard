import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/cancellation_screen.dart';
import 'package:pguard_mobile/features/booking/live_status_screen.dart';
import 'package:pguard_mobile/features/booking/widgets/reason_tile.dart';

import '../support/fakes.dart';

/// base_fee 500 × 3h × 1 guard + tip 295 = ฿1,795 — the design's exact banner amount.
Map<String, dynamic> bookingJson(String status) => {
      'id': 'b1',
      'customer_id': 'c1',
      'guard_id': null,
      'status': status,
      'address': 'หมู่บ้านลัดดารมย์',
      'hours': 3,
      'base_fee': '500.00',
      'guard_count': 1,
      'tip': '295',
      // PAID — the refund copy is now gated on isPaid (an unpaid cancel promises no refund).
      'paid_at': '2026-07-21T10:00:00Z',
    };

GoRouter buildRouter() => GoRouter(
      initialLocation: '/booking/b1/live',
      routes: [
        GoRoute(
          path: '/booking/:id/live',
          builder: (_, s) =>
              LiveStatusScreen(bookingId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/booking/:id/cancel',
          builder: (_, s) => CancellationScreen(
            bookingId: s.pathParameters['id']!,
            args: s.extra is CancellationArgs
                ? s.extra as CancellationArgs
                : null,
          ),
        ),
      ],
    );

Future<void> pumpFlow(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tp) => FakeBookingFeed()),
    ],
    child: MaterialApp.router(routerConfig: buildRouter()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

FakeApi apiWith({Future<dynamic> Function(String, Object?)? onPut}) => FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? bookingJson('accepted')
          : <Map<String, dynamic>>[], // conversations (chat unread badge)
      onPut: onPut,
    );

void main() {
  testWidgets(
      'live-status cancel button opens the cancellation screen with the four '
      'reasons (first pre-selected) and the dynamic refund amount',
      (tester) async {
    final api = apiWith();
    await pumpFlow(tester, api);

    // Pre-arrival (accepted) → the ghost cancel affordance is present.
    // Default locale is Thai, so the UI renders the Thai-only strings.
    await tester.tap(find.text('ยกเลิกและค้นหาใหม่'));
    await tester.pumpAndSettle();

    expect(find.byType(CancellationScreen), findsOneWidget);
    expect(find.text('ยกเลิกการจอง'), findsOneWidget);
    // Subtitle: short id + the address passed via extra.
    expect(find.textContaining('BK-'), findsOneWidget);
    expect(find.textContaining('หมู่บ้านลัดดารมย์'), findsOneWidget);
    expect(find.text('เลือกเหตุผลในการยกเลิก'), findsOneWidget);

    // 4 reason tiles, "เปลี่ยนแผน" pre-selected.
    expect(find.byType(PgReasonTile), findsNWidgets(4));
    expect(
        tester
            .widget<PgReasonTile>(
                find.widgetWithText(PgReasonTile, 'เปลี่ยนแผน'))
            .selected,
        isTrue);
    expect(
        tester
            .widget<PgReasonTile>(find.widgetWithText(PgReasonTile, 'อื่นๆ'))
            .selected,
        isFalse);

    // Refund banner with the dynamic total (500×3×1 + 295 = ฿1,795).
    expect(find.textContaining('คืนเงินเต็มจำนวน ฿1,795'), findsOneWidget);

    // Selecting another reason moves the radio.
    await tester.tap(find.text('ไม่ต้องการแล้ว'));
    await tester.pump();
    expect(
        tester
            .widget<PgReasonTile>(
                find.widgetWithText(PgReasonTile, 'ไม่ต้องการแล้ว'))
            .selected,
        isTrue);
  });

  testWidgets(
      'confirm sheet → "ใช่ ยกเลิกงาน" PUTs /bookings/b1/cancel and pops back '
      'to live status with a SnackBar', (tester) async {
    final api = apiWith(onPut: (path, data) async {
      expect(path, '/bookings/b1/cancel');
      expect(data, isNull, reason: 'contract endpoint takes no body');
      return bookingJson('cancelled');
    });
    await pumpFlow(tester, api);

    await tester.tap(find.text('ยกเลิกและค้นหาใหม่'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยันยกเลิกงาน'));
    await tester.pumpAndSettle();

    // STATE 2 sheet content.
    expect(find.text('ยกเลิกงานนี้?'), findsOneWidget);
    expect(find.textContaining('ระบบจะคืนเงิน ฿1,795'), findsOneWidget);

    await tester.tap(find.text('ใช่ ยกเลิกงาน'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('PUT /bookings/b1/cancel'));
    expect(find.byType(CancellationScreen), findsNothing,
        reason: 'popped back to live status');
    expect(find.byType(LiveStatusScreen), findsOneWidget);
    expect(find.text('ยกเลิกการจองแล้ว'), findsOneWidget);
  });

  testWidgets('"เก็บงานไว้" dismisses the sheet without a PUT', (tester) async {
    final api = apiWith();
    await pumpFlow(tester, api);

    await tester.tap(find.text('ยกเลิกและค้นหาใหม่'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยันยกเลิกงาน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เก็บงานไว้'));
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => c.startsWith('PUT')), isEmpty);
    expect(find.byType(CancellationScreen), findsOneWidget,
        reason: 'still on the reason screen');
  });

  testWidgets('post-arrival there is no cancel affordance', (tester) async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? (bookingJson('arrived')..['guard_id'] = 'g1')
          : <Map<String, dynamic>>[],
    );
    await pumpFlow(tester, api);

    expect(find.text('ยกเลิกและค้นหาใหม่'), findsNothing,
        reason: 'contract allows cancel only requested/accepted/en_route');
  });
}
