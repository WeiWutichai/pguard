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

void main() {
  testWidgets('start → working panel shows the countdown + complete action',
      (tester) async {
    final api = FakeApi(
      onGet: (_, __) async => bookingJson('arrived'),
      onPut: (path, _) async {
        expect(path, '/bookings/b1/start');
        return bookingJson('arrived'); // start keeps status arrived
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        // An active booking now takes a presence GPS-streaming lease on mount — keep that off
        // platform channels (real permission_handler / WebSocket) with fakes.
        permissionGateProvider
            .overrideWithValue(FakePermissionGate(PgPermissionState.granted)),
        presenceFeedBuilderProvider
            .overrideWithValue((_) => FakePresenceFeed()),
        locationServiceProvider.overrideWithValue(FakeLocationService()),
      ],
      child: const MaterialApp(home: ActiveJobScreen(bookingId: 'b1')),
    ));
    // Resolve the initial load.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Arrived but not started → Start action; the working panel (ring + timeline) is not shown.
    // The "Start job" CTA is the PgPrimaryButton labelled เริ่มงาน — target it by widget so the
    // #123 status-timeline's own "เริ่มงาน / Working" STEP label doesn't make this ambiguous.
    final startBtn = find.widgetWithText(PgPrimaryButton, 'เริ่มงาน');
    expect(startBtn, findsOneWidget);
    expect(find.textContaining('ความคืบหน้า'), findsNothing);
    expect(find.text('หมู่บ้านลัดดารมย์ ซ.5'), findsOneWidget); // address shown

    // Tap "Start job" → records start time → working panel appears. The Start CTA lives in the
    // fixed bottom transition bar (not the scrollable list), so it is always on-screen regardless
    // of the #123 status timeline's added height — a plain tap reaches it.
    await tester.tap(startBtn);
    // The start is an async PUT and the controller then re-pulls its snapshot + progress reports;
    // pump enough frames for those async fetches to settle and the working panel to mount (the 1s
    // display ticker means we can't pumpAndSettle).
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // The #123 status timeline added height to the card above, so the working panel can sit below
    // the viewport in the lazy ListView (off-screen children aren't built). Scroll it up so the
    // countdown + timeline header are realised before asserting.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();

    // Working panel = the ring countdown ("เหลือ") + the per-hour timeline header.
    expect(find.text('เหลือ'), findsOneWidget);
    expect(find.textContaining('ความคืบหน้า'), findsOneWidget);
    expect(find.textContaining('จบงาน'), findsOneWidget); // end action
    expect(api.calls, contains('PUT /bookings/b1/start'));

    // Unmount to cancel the display ticker (no pending timers at teardown).
    await tester.pumpWidget(const SizedBox());
  });
}
