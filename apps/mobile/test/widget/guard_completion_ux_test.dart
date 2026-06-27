import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/active_job_screen.dart';

import '../support/fakes.dart';

/// Guard job-completion UX (#97 / #98 / #99). The guard's active-job screen consolidates the
/// primary action (check-in → end) in ONE bottom bar, never shows a rating CTA, and gives a
/// non-dead-end completed view with a receipt + a path back to take new jobs.

List<Override> _trackingFakes() => [
      permissionGateProvider
          .overrideWithValue(FakePermissionGate(PgPermissionState.granted)),
      presenceFeedBuilderProvider.overrideWithValue((_) => FakePresenceFeed()),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
    ];

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
      'paid_at': '2026-06-05T10:30:00Z',
      'created_at': '2026-06-05T10:00:00Z',
      'updated_at': '2026-06-05T10:00:00Z',
    };

/// Pump the active-job screen inside a GoRouter so `context.go('/guard/jobs')` resolves.
Future<void> pumpActiveJob(
  WidgetTester tester, {
  required FakeApi api,
}) async {
  final router = GoRouter(
    initialLocation: '/guard/active/b1',
    routes: [
      GoRoute(
        path: '/guard/active/:id',
        builder: (_, s) => ActiveJobScreen(bookingId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/guard/jobs',
        builder: (_, __) => const Scaffold(body: Text('JOBS LIST')),
      ),
      // _backToJobs resets the stack to the guard home then pushes /guard/jobs (so 'back' from the
      // jobs list returns home instead of being frozen) — the home route must exist for go() to land.
      GoRoute(
        path: '/home/guard',
        builder: (_, __) => const Scaffold(body: Text('GUARD HOME')),
      ),
      GoRoute(
        path: '/booking/:id/live',
        builder: (_, __) => const Scaffold(body: Text('LIVE')),
      ),
    ],
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      ..._trackingFakes(),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets(
      '#98 working stage: the primary action (check-in + End) lives in ONE bottom bar',
      (tester) async {
    // Arrived, not yet started, no reports → JobStage.start. Tapping "Start job" stamps startedAt
    // = now with no completed slots, so slot 0 is immediately due → the check-in CTA is primary
    // with "End" as the secondary, BOTH in the bottom bar (the consolidation).
    final api = FakeApi(onPut: (path, _) async {
      return bookingJson('arrived'); // start keeps status arrived
    }, onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson('arrived');
      return const <Map<String, dynamic>>[];
    });

    await pumpActiveJob(tester, api: api);

    // Pre-start: the Start CTA (one place), no working panel yet.
    expect(find.text('เริ่มงาน'), findsOneWidget);
    expect(find.textContaining('ความคืบหน้า'), findsNothing);

    await tester.tap(find.text('เริ่มงาน'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The consolidated bottom bar: the due check-in CTA (slot 0 = "เช็คอินเริ่มงาน") is primary,
    // and "จบงาน" (End) is the secondary — both in the bottom action area. The working panel
    // shows the read-only progress (countdown + timeline), no separate in-panel check-in button.
    expect(find.text('เช็คอินเริ่มงาน'), findsOneWidget);
    expect(find.text('จบงาน'), findsOneWidget);
    // The #123 status timeline grew the card above, so the working panel's progress header can sit
    // below the lazy ListView fold (off-screen children aren't built) — scroll it up first.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    expect(find.textContaining('ความคืบหน้า'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      '#97/#99 done stage: neutral completion + receipt + take-new-jobs, NO rating CTA',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson('completed');
      return const <Map<String, dynamic>>[];
    });

    await pumpActiveJob(tester, api: api);

    // Neutral completion state — NOT a rating CTA (rating is customer-only, #97).
    expect(find.text('งานเสร็จสมบูรณ์'), findsOneWidget);
    expect(find.textContaining('ให้คะแนน'), findsNothing,
        reason: 'a guard must NEVER see a rating CTA for their own job (#97)');

    // Not a dead-end (#99a): a clear path back to take new jobs, plus the receipt (#99c).
    expect(find.text('กลับไปรับงานใหม่'), findsOneWidget);
    expect(find.text('ดูใบสรุปค่าบริการ'), findsOneWidget);

    // Tapping "take new jobs" navigates to the jobs list (no dead-end).
    await tester.tap(find.text('กลับไปรับงานใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('JOBS LIST'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('#99c done stage: View receipt opens the booking-derived receipt sheet',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson('completed');
      return const <Map<String, dynamic>>[];
    });

    await pumpActiveJob(tester, api: api);

    await tester.tap(find.text('ดูใบสรุปค่าบริการ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The receipt sheet opened with the cost breakdown derived from the booking.
    expect(find.text('ใบสรุปค่าบริการ'), findsWidgets); // sheet title
    expect(find.text('ค่าบริการ (ตามจอง)'), findsOneWidget);
    // Booking-derived note flags that the settled bill is on the customer side.
    expect(
        find.textContaining('ยอดสุทธิเป็นยอดประมาณจากการจอง'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      '#99a awaiting stage: guard can return to their jobs (not stuck)',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson('pending_completion');
      return const <Map<String, dynamic>>[];
    });

    await pumpActiveJob(tester, api: api);

    // Awaiting the customer — but the guard is NOT stuck: a clear, enabled primary returns them to
    // their jobs. (The actual `context.go('/guard/jobs')` wiring is covered by the done-stage test;
    // pending_completion holds a GPS lease, whose dispose-time release trips a test-only "modify a
    // provider during build" assertion on synchronous navigation, so here we assert the affordance
    // is present + live rather than driving the unmount.)
    expect(find.text('รอลูกค้าตรวจสอบการจบงาน'), findsOneWidget);
    final back = find.text('กลับไปหน้างานของฉัน');
    expect(back, findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.ancestor(of: back, matching: find.byType(ElevatedButton)),
    );
    expect(button.onPressed, isNotNull,
        reason: 'the "back to my jobs" CTA is live (no dead-end)');

    await tester.pumpWidget(const SizedBox());
  });
}
