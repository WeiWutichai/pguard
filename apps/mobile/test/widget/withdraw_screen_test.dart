import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/widgets/cancel_reason.dart';
import 'package:pguard_mobile/features/booking/widgets/reason_tile.dart';
import 'package:pguard_mobile/features/guard/active_job_screen.dart';
import 'package:pguard_mobile/features/guard/withdraw_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson(String status) => {
      'id': 'b1',
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': status,
      'address': 'โรงงาน ปทุม',
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'tip': '0',
    };

GoRouter buildRouter() => GoRouter(
      initialLocation: '/guard/active/b1',
      routes: [
        GoRoute(
          path: '/guard/active/:id',
          builder: (_, s) =>
              ActiveJobScreen(bookingId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/guard/active/:id/withdraw',
          builder: (_, s) => WithdrawScreen(bookingId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/home/guard',
          builder: (_, __) => const Scaffold(body: Text('GUARD HOME STUB')),
        ),
      ],
    );

Future<void> pumpFlow(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      // Locale defaults to Thai; the fake prefs store keeps locale load hermetic
      // (no platform channel) — the screen renders single-language Thai copy.
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      // The active booking takes a presence GPS-streaming lease on mount — keep that off
      // platform channels (real permission_handler / WebSocket) with fakes.
      permissionGateProvider
          .overrideWithValue(FakePermissionGate(PgPermissionState.granted)),
      presenceFeedBuilderProvider.overrideWithValue((_) => FakePresenceFeed()),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
      // The active-job screen (and now the withdraw PUT) go through the booking-status
      // controller — keep its feed off a real WebSocket.
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tp) => FakeBookingFeed()),
    ],
    child: MaterialApp.router(routerConfig: buildRouter()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets(
      'active-job Withdraw navigates to the withdraw screen (no AlertDialog): '
      'warning banner + 3 reasons + notes-optional submit', (tester) async {
    final api = FakeApi(onGet: (_, __) async => bookingJson('accepted'));
    await pumpFlow(tester, api);

    await tester.tap(find.text('ปฏิเสธงาน'));
    await tester.pumpAndSettle();

    expect(find.byType(WithdrawScreen), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('ขอถอนจากงาน'), findsOneWidget);
    expect(find.textContaining('โรงงาน ปทุม'), findsOneWidget); // subtitle
    // EXACT escalation copy from the design.
    expect(
        find.textContaining(
            'การถอนงานเป็นกรณีพิเศษ จะถูกส่งให้แอดมินตรวจสอบ และอาจมีผลต่อคะแนนของคุณ'),
        findsOneWidget);

    // 4 reasons (the 3 design options + "อื่นๆ"), "เหตุฉุกเฉินส่วนตัว" pre-selected.
    expect(find.byType(PgReasonTile), findsNWidgets(4));
    expect(
        tester
            .widget<PgReasonTile>(
                find.widgetWithText(PgReasonTile, 'เหตุฉุกเฉินส่วนตัว'))
            .selected,
        isTrue);
    expect(find.text('ป่วย'), findsOneWidget);
    expect(find.text('เดินทางไปไม่ได้'), findsOneWidget);
    expect(find.text('อื่นๆ'), findsOneWidget);

    // Notes are optional for the three concrete reasons: a reason is always pre-selected, so
    // Submit is enabled from the start — even before any admin note is typed.
    final submit = find.widgetWithText(ElevatedButton, 'ส่งคำขอถอนงาน');
    expect(tester.widget<ElevatedButton>(submit).onPressed, isNotNull);

    // Typing a note keeps Submit enabled (the note now FLOWS to the API as `note`).
    await tester.enterText(find.byType(TextField), 'รถเสียกลางทาง');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(submit).onPressed, isNotNull);
  });

  testWidgets(
      'submit PUTs /bookings/b1/decline WITH the guard reason code + note and '
      'returns to the guard dashboard', (tester) async {
    Object? sentBody;
    final api = FakeApi(
      onGet: (_, __) async => bookingJson('accepted'),
      onPut: (path, data) async {
        expect(path, '/bookings/b1/decline');
        sentBody = data;
        return bookingJson('declined');
      },
    );
    await pumpFlow(tester, api);

    await tester.tap(find.text('ปฏิเสธงาน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ป่วย'));
    await tester.enterText(find.byType(TextField), ' มีไข้สูง ');
    await tester.pump();
    await tester.tap(find.text('ส่งคำขอถอนงาน'));
    await tester.pumpAndSettle();

    // A confirm dialog gates the REAL decline (the customer is notified) — no PUT until confirmed.
    expect(find.text('ยืนยันถอนตัวจากงานนี้?'), findsOneWidget);
    expect(api.calls.where((c) => c.startsWith('PUT')), isEmpty);
    expect(find.textContaining('ลูกค้าจะได้รับแจ้ง'), findsOneWidget);
    await tester.tap(find.text('ถอนตัว'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('PUT /bookings/b1/decline'));
    // THE fix: the guard's reason CODE + trimmed note actually reach the server.
    expect(sentBody, {'reason': PgCancelReason.sick, 'note': 'มีไข้สูง'});
    expect(find.text('GUARD HOME STUB'), findsOneWidget);
    expect(find.text('ส่งคำขอถอนงานแล้ว'), findsOneWidget);
  });

  testWidgets(
      '"อื่นๆ" with a BLANK note blocks submit: no confirm dialog, NO PUT, and '
      'an inline message — then filling the note lets it through', (tester) async {
    Object? sentBody;
    final api = FakeApi(
      onGet: (_, __) async => bookingJson('accepted'),
      onPut: (path, data) async {
        sentBody = data;
        return bookingJson('declined');
      },
    );
    await pumpFlow(tester, api);

    await tester.tap(find.text('ปฏิเสธงาน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('อื่นๆ'));
    await tester.pump();
    // Whitespace only — blank after trim, exactly like the server's check.
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    await tester.tap(find.text('ส่งคำขอถอนงาน'));
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => c.startsWith('PUT')), isEmpty,
        reason: 'other + blank note must never reach the API');
    expect(find.text('ยืนยันถอนตัวจากงานนี้?'), findsNothing,
        reason: 'blocked BEFORE the destructive confirm dialog');
    expect(find.text(PgCancelReason.noteMissingMessage(true)), findsOneWidget);

    // Typing clears the complaint; the withdrawal then goes through carrying the note.
    await tester.enterText(find.byType(TextField), 'ติดธุระด่วน');
    await tester.pump();
    expect(find.text(PgCancelReason.noteMissingMessage(true)), findsNothing);
    await tester.tap(find.text('ส่งคำขอถอนงาน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ถอนตัว'));
    await tester.pumpAndSettle();

    expect(sentBody, {'reason': PgCancelReason.other, 'note': 'ติดธุระด่วน'});
  });
}
