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
      GoRoute(
        path: '/earnings',
        builder: (_, __) => const Scaffold(body: Text('EARNINGS')),
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
      'BUG1/BUG2 arrived-not-checked-in: the ONE CTA is the start check-in; End is unreachable',
      (tester) async {
    // Arrived, no reports → JobStage.start. The ONE CTA is "เช็คอินเริ่มงาน" (start + photo); the
    // old bare "เริ่มงาน" is gone, there is no working panel, and — the BUG1 gate — "จบงาน" (End) is
    // NOT reachable, because the only complete() callers live inside working-gated widgets.
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson('arrived');
      return const <Map<String, dynamic>>[];
    });

    await pumpActiveJob(tester, api: api);

    expect(find.text('เริ่มงาน'), findsNothing);
    expect(find.text('เช็คอินเริ่มงาน'), findsOneWidget);
    expect(find.textContaining('ความคืบหน้า'), findsNothing);
    expect(find.textContaining('จบงาน'), findsNothing,
        reason:
            'BUG1: End must be unreachable until the start check-in is filed');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      '#98 working stage: after the start check-in, End is the consolidated bottom action',
      (tester) async {
    // The hour-1 (start) report hydrates slot 0 → JobStage.working. Anchored 5 min ago so the 8h
    // shift is mid-flight (no hourly check-in due yet) → "จบงาน" is the primary End in the ONE
    // bottom bar, and the panel is read-only progress (no separate in-panel check-in button).
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson('arrived');
      if (path == '/bookings/b1/progress-reports') {
        return [
          {
            'hour_number': 1,
            'created_at': DateTime.now()
                .toUtc()
                .subtract(const Duration(minutes: 5))
                .toIso8601String(),
          }
        ];
      }
      return const <Map<String, dynamic>>[];
    });

    await pumpActiveJob(tester, api: api);

    // The consolidated End action (no in-panel check-in button; the panel is read-only progress).
    expect(find.text('จบงาน'), findsOneWidget);
    // The #123 status timeline grew the card above, so the working panel's progress header can sit
    // below the lazy ListView fold (off-screen children aren't built) — scroll it up first.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    expect(find.textContaining('ความคืบหน้า'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      '#97/#99 done stage: neutral completion + own earnings + take-new-jobs, NO rating CTA',
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

    // Not a dead-end (#99a): a clear path back to take new jobs, plus this guard's own pay. NOT
    // the receipt — that is the customer's document (it totals the customer's bill, tip and whole
    // crew included, and settles against a payment row a guard cannot read).
    expect(find.text('กลับไปรับงานใหม่'), findsOneWidget);
    expect(find.text('ดูใบสรุปค่าบริการ'), findsNothing);
    expect(find.text('ดูรายได้ของฉัน'), findsOneWidget);

    // Tapping "take new jobs" navigates to the jobs list (no dead-end).
    await tester.tap(find.text('กลับไปรับงานใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('JOBS LIST'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('#99c done stage: the guard is sent to their OWN earnings',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson('completed');
      return const <Map<String, dynamic>>[];
    });

    await pumpActiveJob(tester, api: api);

    await tester.tap(find.text('ดูรายได้ของฉัน'));
    await tester.pumpAndSettle();

    expect(find.text('EARNINGS'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      '#126 awaiting stage: a PROMINENT status card makes "waiting on the customer" clear',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson('pending_completion');
      return const <Map<String, dynamic>>[];
    });

    await pumpActiveJob(tester, api: api);

    // The emphasised card leads the screen with a bold, unambiguous headline: the guard is BLOCKED
    // on the CUSTOMER's confirmation, not stuck. (#126)
    expect(find.text('รอลูกค้ายืนยันการจบงาน'), findsOneWidget);
    // A status badge icon (hourglass) reinforces the meaning at a glance.
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    // The reassurance line tells the guard they can pick up other jobs in the meantime.
    expect(find.textContaining('รับงานอื่นต่อได้'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('#99a awaiting stage: guard can return to their jobs (not stuck)',
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
