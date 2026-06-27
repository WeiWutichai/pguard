import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/active_job_screen.dart';
import 'package:pguard_mobile/features/guard/guard_jobs_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> _booking(String status) => {
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

/// #121 regression: after a guard completes a job, the "กลับไปรับงานใหม่ / Take new jobs" CTA must
///   (a) land on the "งานของฉัน / My Jobs" list,
///   (b) over a POPPABLE stack (so the header back button is not frozen — the bug that forced an
///       app restart), and
///   (c) after re-fetching the jobs list (so the completed job is fresh — leaves "กำลังทำ").
void main() {
  testWidgets(
      '"Take new jobs" lands on My Jobs over a poppable stack and re-fetches the list',
      (tester) async {
    var bookingsFetches = 0;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings') {
          bookingsFetches++;
          return const <Map<String, dynamic>>[];
        }
        if (path == '/bookings/open') return const <Map<String, dynamic>>[];
        if (path == '/bookings/b1/progress-reports') {
          return const <Map<String, dynamic>>[];
        }
        // The active-job screen's snapshot read — booking is already completed.
        return _booking('completed');
      },
    );

    final router = GoRouter(
      initialLocation: '/guard/active/b1',
      routes: [
        // Stub home + jobs probes; the active screen is the real one under test.
        GoRoute(
          path: '/home/guard',
          builder: (_, __) => const Scaffold(body: Text('HOME')),
        ),
        // The REAL jobs screen — it watches guardJobsControllerProvider, so landing on it after the
        // invalidate proves the list is (re)fetched fresh.
        GoRoute(
          path: '/guard/jobs',
          builder: (_, __) => const GuardJobsScreen(),
        ),
        GoRoute(
          path: '/guard/active/:id',
          builder: (_, state) =>
              ActiveJobScreen(bookingId: state.pathParameters['id']!),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        // Completed jobs don't stream, but keep platform channels off regardless.
        permissionGateProvider
            .overrideWithValue(FakePermissionGate(PgPermissionState.granted)),
        presenceFeedBuilderProvider.overrideWithValue((_) => FakePresenceFeed()),
        locationServiceProvider.overrideWithValue(FakeLocationService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The completed (done) stage shows "งานเสร็จสมบูรณ์" + the "Take new jobs" CTA.
    expect(find.text('งานเสร็จสมบูรณ์'), findsOneWidget);
    final cta = find.text('กลับไปรับงานใหม่');
    expect(cta, findsOneWidget);

    // The guard jobs list was fetched once during this session (no extra refetch yet).
    final fetchesBeforeTap = bookingsFetches;

    // Tap "Take new jobs".
    await tester.tap(cta);
    await tester.pumpAndSettle();

    // (a) We land on My Jobs (the real GuardJobsScreen — its Thai title proves it mounted)...
    expect(find.text('งานของฉัน'), findsOneWidget);

    // (c) ...and the jobs list was (re)fetched — the GuardJobsScreen watches guardJobsController
    // provider, which the CTA invalidated, so it pulls a fresh /bookings. A just-completed job
    // therefore partitions into Done instead of lingering in the Active ("กำลังทำ") tab.
    expect(bookingsFetches, greaterThan(fetchesBeforeTap));

    // (b) The back stack is poppable (My Jobs sits ON TOP of /home/guard) — NOT a dead root. This is
    // the freeze fix: a bare context.go('/guard/jobs') would have left a single un-poppable page.
    expect(router.canPop(), isTrue);

    // Popping returns to the guard home, proving back is not frozen.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });
}
