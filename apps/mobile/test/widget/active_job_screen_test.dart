import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/active_job_screen.dart';
import 'package:pguard_mobile/widgets/primary_button.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson(String status) => {
      'id': 'b1',
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': status,
      'address': 'หมู่บ้านลัดดารมย์ ซ.5',
      'scheduled_at': '2026-06-05T14:00:00Z',
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
}
