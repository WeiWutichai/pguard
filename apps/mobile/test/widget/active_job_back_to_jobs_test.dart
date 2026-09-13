import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/active_job_screen.dart';
import 'package:pguard_mobile/features/guard/guard_jobs_screen.dart';
import 'package:pguard_mobile/features/home/guard_home_screen.dart';

import '../support/fakes.dart';

const _activeId = 'b1';

/// An open, unassigned job the guard could take right now — exactly what "กลับไปรับงานใหม่"
/// promises. Served from `/bookings/open` (guard_id null → [GuardJobsController.incoming]).
const _openJobAddress = 'งานเปิดใหม่ ลาดพร้าว';

Map<String, dynamic> _booking(
  String status, {
  String id = _activeId,
  String? guardId = 'g1',
  String address = 'หมู่บ้านลัดดารมย์ ซ.5',
}) =>
    {
      'id': id,
      'customer_id': 'c1',
      'guard_id': guardId,
      'status': status,
      'address': address,
      'scheduled_at': '2026-06-05T14:00:00Z',
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'tip': '0',
      'paid_at': '2026-06-05T10:30:00Z',
      'created_at': '2026-06-05T10:00:00Z',
      'updated_at': '2026-06-05T10:00:00Z',
    };

/// The active-job snapshot is [status]; the open feed always carries one takeable job.
FakeApi _api(String status, {void Function()? onBookingsFetch}) => FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings') {
          onBookingsFetch?.call();
          return [_booking(status)];
        }
        if (path == '/bookings/open') {
          return [
            _booking('requested',
                id: 'b-open', guardId: null, address: _openJobAddress),
          ];
        }
        if (path == '/bookings/$_activeId') return _booking(status);
        return const <Map<String, dynamic>>[];
      },
    );

/// Pump the guard's REAL screens behind a real router: the active-job screen under test, the real
/// My Jobs list at `/guard/jobs`, and (by default) the real dashboard at `/home/guard`. Both
/// destinations must be real, because the bug is not "no navigation happened" — it is that the two
/// destinations LOOK like each other to a stub while looking completely different to the guard.
///
/// [home] exists only to substitute a stub dashboard: mounting the real one in the same frame the
/// active-job screen unmounts trips a PRE-EXISTING Riverpod assert on the streaming stages — see
/// the AWAITING test below.
Future<GoRouter> _pump(
  WidgetTester tester, {
  required FakeApi api,
  Widget Function()? home,
}) async {
  final router = GoRouter(
    initialLocation: '/guard/active/$_activeId',
    routes: [
      GoRoute(
        path: '/home/guard',
        builder: (_, __) => home?.call() ?? const GuardHomeScreen(),
      ),
      GoRoute(
        path: '/guard/jobs',
        builder: (_, state) => GuardJobsScreen(
          initialTab:
              GuardJobsScreen.tabFromQuery(state.uri.queryParameters['tab']),
        ),
      ),
      GoRoute(
        path: '/guard/active/:id',
        builder: (_, s) => ActiveJobScreen(bookingId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/earnings', builder: (_, __) => const SizedBox()),
      GoRoute(path: '/profile', builder: (_, __) => const SizedBox()),
    ],
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      // The jobs controller scopes the assigned feed to the SESSION user id ('g1' here).
      seededGuardSession(),
      // Keep the duty/GPS chrome off platform channels.
      permissionGateProvider
          .overrideWithValue(FakePermissionGate(PgPermissionState.granted)),
      presenceFeedBuilderProvider.overrideWithValue((_) => FakePresenceFeed()),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  return router;
}

void main() {
  // The tester's report: "ตอนกดกลับไปรับงานใหม่ มันไม่ได้กลับไปที่หน้าพร้อมรับงาน แต่ไปที่หน้างานที่กำลังทำ".
  // The CTA was wired to the AWAITING stage's helper, which pushes the My Jobs list — and My Jobs
  // opens on its "กำลังทำ / Active" tab, which by definition cannot hold the job that just finished.
  // So the guard landed on an empty กำลังทำ list while the jobs they could actually take sat
  // unread on the un-selected "รอตอบรับ" tab.
  testWidgets(
      'DONE: "กลับไปรับงานใหม่" lands on the พร้อมรับงาน dashboard with takeable jobs — NOT on My Jobs',
      (tester) async {
    var bookingsFetches = 0;
    final api = _api('completed', onBookingsFetch: () => bookingsFetches++);
    final router = await _pump(tester, api: api);

    // The completed (done) stage: the success banner + the CTA under test.
    expect(find.text('งานเสร็จสมบูรณ์'), findsOneWidget);
    final cta = find.text('กลับไปรับงานใหม่');
    expect(cta, findsOneWidget);

    final fetchesBeforeTap = bookingsFetches;
    await tester.tap(cta);
    await tester.pumpAndSettle();

    // (a) NOT the My Jobs list — this is the assertion that fails before the fix. (Matching on the
    // empty-state TEXT would not do: the dashboard's own "งานที่กำลังทำ" section has the identical
    // "ยังไม่มีงานที่กำลังทำ" empty state, so only the screen type tells the two apart.)
    expect(find.byType(GuardJobsScreen), findsNothing,
        reason: '"take NEW jobs" must not open the My Jobs list, whose default '
            'tab is กำลังทำ and cannot contain a job that just ended');

    // (b) The ready-for-work dashboard instead, carrying the open-job pool the CTA promised —
    // with its actionable รับงาน button, so the guard can take the next job right there.
    expect(find.byType(GuardHomeScreen), findsOneWidget);
    expect(find.text(_openJobAddress), findsOneWidget,
        reason: 'the guard must be able to SEE a job they can take');
    expect(find.text('รับงาน'), findsOneWidget);

    // (c) The dead job is off the stack: nothing to pop, so no back gesture (header chevron or
    // Android system back) can walk the guard into a completed job's screen again.
    expect(router.canPop(), isFalse);
    expect(find.byType(ActiveJobScreen), findsNothing);

    // (d) The jobs list was re-fetched, so the dashboard is not rendering the pre-completion cache.
    expect(bookingsFetches, greaterThan(fetchesBeforeTap));
  });

  // The CANCELLED terminal already pointed at the pool; lock it, so the two identically-labelled
  // "กลับไปรับงานใหม่" CTAs can never drift apart again.
  testWidgets('CANCELLED: "กลับไปรับงานใหม่" also lands on the dashboard pool',
      (tester) async {
    final router = await _pump(tester, api: _api('cancelled'));

    // Two matches by design: the header's status subtitle and the terminal banner.
    expect(find.text('งานนี้ถูกยกเลิกแล้ว'), findsWidgets);
    await tester.tap(find.text('กลับไปรับงานใหม่'));
    await tester.pumpAndSettle();

    expect(find.byType(GuardHomeScreen), findsOneWidget);
    expect(find.byType(GuardJobsScreen), findsNothing);
    expect(find.text(_openJobAddress), findsOneWidget);
    expect(router.canPop(), isFalse);
  });

  // The THIRD bar, AWAITING ("กลับไปหน้างานของฉัน"), is deliberately UNCHANGED: pending_completion
  // is NOT terminal — the job is still the guard's and really does sit in My Jobs' กำลังทำ tab
  // (guard_jobs_screen_test locks that partition) — so that label's destination was already right.
  // Its navigation + #121 poppable stack stay covered by guard_completion_ux_test's
  // "#99a awaiting stage". It is not re-tested here because exercising it needs a live GPS
  // streaming lease, whose release from `_ActiveJobScreenState.dispose` trips a PRE-EXISTING
  // Riverpod "modify a provider while the widget tree was building" assert (reproduced against an
  // unmodified tree; debug-only, and untouched by this fix) — reported as its own defect rather
  // than worked around with a weakened assertion here.

  // Same symptom, different entry point: the bottom-nav "งาน" badge counts รอตอบรับ offers, so
  // tapping it must open THAT tab instead of dropping the guard on the default (empty) กำลังทำ tab.
  testWidgets('the nav "งาน" badge opens the tab it counts (รอตอบรับ)',
      (tester) async {
    // No assigned jobs at all — only the one open offer the badge is counting.
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/open') {
        return [
          _booking('requested',
              id: 'b-open', guardId: null, address: _openJobAddress),
        ];
      }
      return const <Map<String, dynamic>>[];
    });
    final router = await _pump(tester, api: api);
    router.go('/home/guard');
    await tester.pumpAndSettle();

    await tester.tap(find.text('งาน').last);
    await tester.pumpAndSettle();

    expect(find.byType(GuardJobsScreen), findsOneWidget);
    expect(find.text(_openJobAddress), findsOneWidget,
        reason: 'a count badge must lead to the jobs it counts, not to an '
            'empty กำลังทำ tab one tab away');
  });
}
