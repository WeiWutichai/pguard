import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/controllers/guard_jobs_controller.dart';
import 'package:pguard_mobile/core/controllers/tracking_controller.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/network/sockets/presence_socket.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/widgets/online_card.dart';

import '../support/fakes.dart';

/// Fake tracking controller: starts offline, and `toggle()` is a no-op so the test never opens a
/// real presence feed / GPS stream (we only care about the permission-rationale wiring).
class _FakeTracking extends TrackingController {
  @override
  TrackingState build() => const TrackingState();
  @override
  Future<void> toggle() async {}
}

/// Fake tracking controller fixed ONLINE+connected, for the #123 busy-state test (the busy badge
/// only shows while online).
class _OnlineTracking extends TrackingController {
  @override
  TrackingState build() =>
      const TrackingState(online: true, link: PresenceLink.online);
  @override
  Future<void> toggle() async {}
}

/// Fake guard-jobs controller returning a fixed list, so the busy-state test can hand the
/// [OnlineCard] an active (or empty) jobs feed without any network.
class _FakeJobs extends GuardJobsController {
  _FakeJobs(this._jobs);
  final List<Booking> _jobs;
  @override
  Future<List<Booking>> build() async => _jobs;
}

Booking _job(BookingStatus status) =>
    Booking(id: 'b', customerId: 'c', status: status, guardId: 'g');

void main() {
  testWidgets(
      'guard online-toggle (location not granted) routes to the rationale '
      'with forGuard=true', (tester) async {
    Object? capturedExtra;
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: OnlineCard())),
      GoRoute(
        path: '/permissions/location',
        builder: (_, state) {
          capturedExtra = state.extra;
          return const Scaffold(body: Center(child: Text('RATIONALE')));
        },
      ),
    ]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        permissionGateProvider
            .overrideWithValue(FakePermissionGate(PgPermissionState.denied)),
        trackingControllerProvider.overrideWith(() => _FakeTracking()),
        // OnlineCard now also watches the jobs feed (busy state) — keep it off the network.
        guardJobsControllerProvider.overrideWith(() => _FakeJobs(const [])),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('RATIONALE'), findsOneWidget,
        reason: 'going online while ungranted shows the rationale (not orphaned)');
    expect(capturedExtra, true,
        reason: 'the guard path passes extra:true → rationale defaults to "Always"');
  });

  testWidgets(
      '#123 online WITH an active job shows the distinct busy "On a job" state, '
      'not the plain online label', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        permissionGateProvider
            .overrideWithValue(FakePermissionGate(PgPermissionState.granted)),
        trackingControllerProvider.overrideWith(() => _OnlineTracking()),
        guardJobsControllerProvider
            .overrideWith(() => _FakeJobs([_job(BookingStatus.arrived)])),
      ],
      child: const MaterialApp(
        // Force Thai so the assertion is unambiguous.
        home: Scaffold(body: OnlineCard()),
      ),
    ));
    // The GPS line spins (online, no fix yet), so pumpAndSettle would never settle — a couple of
    // pumps is enough for the jobs FutureProvider to resolve and the busy state to render.
    await tester.pump();
    await tester.pump();

    expect(find.text('กำลังดำเนินงานอยู่'), findsWidgets,
        reason: 'busy guard sees the "On a job" busy label, distinct from online');
    expect(find.text('พร้อมรับงาน'), findsNothing,
        reason: 'the normal online label must NOT show while on a job');
  });

  testWidgets(
      '#123 online with NO active job keeps the normal "พร้อมรับงาน" online state',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        permissionGateProvider
            .overrideWithValue(FakePermissionGate(PgPermissionState.granted)),
        trackingControllerProvider.overrideWith(() => _OnlineTracking()),
        guardJobsControllerProvider.overrideWith(() => _FakeJobs(const [])),
      ],
      child: const MaterialApp(home: Scaffold(body: OnlineCard())),
    ));
    // Spinner online without a fix → pump a couple of frames rather than pumpAndSettle.
    await tester.pump();
    await tester.pump();

    expect(find.text('พร้อมรับงาน'), findsOneWidget);
    expect(find.text('กำลังดำเนินงานอยู่'), findsNothing);
  });
}
