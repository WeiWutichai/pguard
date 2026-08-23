import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/active_job_screen.dart';
import 'package:pguard_mobile/widgets/primary_button.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson(String status, {String? scheduledAt}) => {
      'id': 'b1',
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': status,
      'address': 'หมู่บ้านลัดดารมย์ ซ.5',
      // Default is well in the past so the G3 start-window gate is OPEN for the existing tests;
      // pass a future `scheduledAt` to exercise the too-early gate.
      'scheduled_at': scheduledAt ?? '2026-06-05T14:00:00Z',
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'tip': '0',
      'created_at': '2026-06-05T10:00:00Z',
      'updated_at': '2026-06-05T10:00:00Z',
    };

/// An hour-1 progress report (the START check-in) anchored [ago] before now, so the working panel
/// hydrates mid-shift (clock shows remaining time, no time-up auto-complete).
Map<String, dynamic> startCheckInReport({Duration ago = Duration.zero}) => {
      'hour_number': 1,
      'created_at': DateTime.now().toUtc().subtract(ago).toIso8601String(),
    };

List<Override> _baseOverrides(FakeApi api) => [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      // An active booking takes a presence GPS-streaming lease on mount — keep that off platform
      // channels (real permission_handler / WebSocket) with fakes.
      permissionGateProvider
          .overrideWithValue(FakePermissionGate(PgPermissionState.granted)),
      presenceFeedBuilderProvider.overrideWithValue((_) => FakePresenceFeed()),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
    ];

void main() {
  testWidgets(
      'BUG2: arrived-but-not-checked-in shows the START check-in CTA, NOT the working panel',
      (tester) async {
    // Arrived, no reports → the timer must NOT be running: stageOf → JobStage.start, whose ONE CTA
    // is "เช็คอินเริ่มงาน" (start + capture photo). The working panel (ring + progress) is hidden.
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? bookingJson('arrived')
          : const <Map<String, dynamic>>[],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: _baseOverrides(api),
      child: const MaterialApp(home: ActiveJobScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The start-check-in CTA (not the old bare "เริ่มงาน"), and NO working panel / countdown.
    expect(find.widgetWithText(PgPrimaryButton, 'เช็คอินเริ่มงาน'),
        findsOneWidget);
    expect(find.text('เริ่มงาน'), findsNothing);
    expect(find.textContaining('ความคืบหน้า'), findsNothing);
    expect(find.text('เหลือ'), findsNothing); // no countdown ring yet
    expect(find.text('หมู่บ้านลัดดารมย์ ซ.5'), findsOneWidget); // address shown
  });

  testWidgets(
      'BUG2: tapping "เช็คอินเริ่มงาน" stamps start (PUT /start) then opens the check-in sheet',
      (tester) async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? bookingJson('arrived')
          : const <Map<String, dynamic>>[],
      onPut: (path, _) async {
        expect(path, '/bookings/b1/start');
        return bookingJson('arrived'); // start keeps status arrived
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ..._baseOverrides(api),
        photoCaptureServiceProvider
            .overrideWithValue(FakePhotoCaptureService()),
        checkInServiceProvider.overrideWithValue(FakeCheckInService()),
      ],
      child: const MaterialApp(home: ActiveJobScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.widgetWithText(PgPrimaryButton, 'เช็คอินเริ่มงาน'));
    // start() PUT + the modal check-in sheet opening are async.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    // start() was fired first (the backend needs work_started_at before an hour-1 check-in), and
    // the check-in sheet is now open (its submit button is on screen).
    expect(api.calls, contains('PUT /bookings/b1/start'));
    expect(find.text('ส่งรายงานรอบนี้'), findsOneWidget);

    // Close the sheet + unmount cleanly.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'BUG2: once the START check-in is filed, the working panel shows the countdown + End',
      (tester) async {
    // The server check-in trail carries the hour-1 (start) report → build() marks slot 0 done and
    // anchors startedAt → stageOf → JobStage.working. Anchored 5 min ago so the 8h shift is
    // mid-flight (clock shows "เหลือ", no time-up auto-complete).
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') return bookingJson('arrived');
        if (path == '/bookings/b1/progress-reports') {
          return [startCheckInReport(ago: const Duration(minutes: 5))];
        }
        return const <Map<String, dynamic>>[];
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: _baseOverrides(api),
      child: const MaterialApp(home: ActiveJobScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The #123 status timeline grows the card above, so the working panel can sit below the lazy
    // ListView fold — scroll it up before asserting.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();

    // Working panel = the ring countdown ("เหลือ") + the per-hour progress header + End action.
    expect(find.text('เหลือ'), findsOneWidget);
    expect(find.textContaining('ความคืบหน้า'), findsOneWidget);
    expect(find.textContaining('จบงาน'), findsOneWidget);
    // The start CTA is gone (we are past it).
    expect(find.text('เช็คอินเริ่มงาน'), findsNothing);

    // Unmount to cancel the 1s display ticker (no pending timers at teardown).
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'ISSUE3: en_route (pre-arrival) offers a Withdraw button so the guard can back out',
      (tester) async {
    // status=en_route → JobStage.arrived bar: primary confirms arrival (no coords → "ถึงแล้ว"),
    // secondary is the pre-arrival withdraw (a paid booking is refunded server-side). Once ARRIVED
    // (start/working) the withdraw is gone.
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? bookingJson('en_route')
          : const <Map<String, dynamic>>[],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: _baseOverrides(api),
      child: const MaterialApp(home: ActiveJobScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('ถึงแล้ว'), findsOneWidget); // arrival primary
    expect(find.text('ปฏิเสธงาน'), findsOneWidget,
        reason: 'the guard can withdraw before arriving');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'G3: arrived BEFORE the scheduled window → start CTA is disabled with a '
      '"ยังไม่ถึงเวลาเริ่มงาน" notice', (tester) async {
    // Arrived early (advance booking), scheduled 2h out. The start window opens at
    // scheduled − 15min, so the "เช็คอินเริ่มงาน" CTA must be DISABLED and the guard told why —
    // the server would otherwise reject the start with START_TOO_EARLY.
    final future =
        DateTime.now().toUtc().add(const Duration(hours: 2)).toIso8601String();
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? bookingJson('arrived', scheduledAt: future)
          : const <Map<String, dynamic>>[],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: _baseOverrides(api),
      child: const MaterialApp(home: ActiveJobScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('ยังไม่ถึงเวลาเริ่มงาน'), findsOneWidget);
    final btn = tester.widget<PgPrimaryButton>(
        find.widgetWithText(PgPrimaryButton, 'เช็คอินเริ่มงาน'));
    expect(btn.onPressed, isNull,
        reason:
            'the start CTA stays disabled until the scheduled window opens');

    await tester.pumpWidget(const SizedBox()); // cancel the 1s display ticker
  });

  testWidgets(
      'G1: past the booked end + 30-min grace, the check-in window is CLOSED — '
      'shows "หมดเวลาเช็คอินแล้ว" and NO check-in CTA (End stays)',
      (tester) async {
    // Working (arrived + the start check-in filed), but the start was 9h ago on an 8h shift → the
    // window (end + 30min = 8h30m) has closed. The bottom bar must NOT offer a check-in CTA — a
    // late file only 409s CHECK_IN_WINDOW_CLOSED — but the truthful note + End remain.
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') return bookingJson('arrived');
        if (path == '/bookings/b1/progress-reports') {
          return [startCheckInReport(ago: const Duration(hours: 9))];
        }
        return const <Map<String, dynamic>>[];
      },
    );
    await tester.pumpWidget(ProviderScope(
      overrides: _baseOverrides(api),
      child: const MaterialApp(home: ActiveJobScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The closed-window note + End, and NO due check-in CTA (neither start nor hourly).
    expect(find.text('หมดเวลาเช็คอินแล้ว'), findsOneWidget);
    expect(find.textContaining('เช็คอินชั่วโมง'), findsNothing);
    expect(find.text('เช็คอินเริ่มงาน'), findsNothing);
    expect(find.widgetWithText(PgPrimaryButton, 'จบงาน'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // cancel the 1s display tickers
  });
}
