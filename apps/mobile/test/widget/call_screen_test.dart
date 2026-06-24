import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/controllers/call_controller.dart';
import 'package:pguard_mobile/core/models/call.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/call/call_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> callJson(String id, {String callType = 'audio'}) => {
      'id': id,
      'caller_id': 'a',
      'callee_id': 'b',
      'booking_id': 'bk',
      'call_type': callType,
      'status': 'initiated',
      'started_at': '2026-06-05T10:00:00Z',
      'created_at': '2026-06-05T10:00:00Z',
      'updated_at': '2026-06-05T10:00:00Z',
    };

/// STUN-only ICE config — enough for the controller's `GET /calls/ice` during call setup.
Map<String, dynamic> iceJson() => {
      'ice_servers': [
        {
          'urls': ['stun:stun.l.google.com:19302']
        },
      ],
      'ttl_secs': 3600,
    };

({ProviderContainer c, FakeApi api}) harness() {
  final api = FakeApi(
    onPost: (_, __) async => callJson('call1'),
    // Call setup GETs both the call (`/calls/{id}`) and the served ICE list (`/calls/ice`).
    onGet: (path, __) async =>
        path == '/calls/ice' ? iceJson() : callJson('call1'),
    onPut: (_, __) async => {'success': true},
  );
  final c = ProviderContainer(overrides: [
    pguardApiProvider.overrideWithValue(api),
    appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    callEngineFactoryProvider.overrideWithValue(FakeCallEngine.new),
    callSignalFeedBuilderProvider.overrideWithValue((_) => FakeCallSignalFeed()),
  ]);
  // The caller disposes EXPLICITLY at the end of the test body (not via addTearDown) so the
  // keepAlive controller's one-shot connect-timeout is cancelled inside the FakeAsync zone,
  // before the framework's pending-timer assertion runs.
  return (c: c, api: api);
}

// A minimal router: /call is PUSHED on top of /home so the screen's `context.pop()` works.
GoRouter router(String? incoming) => GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (ctx, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ctx.push(
                    incoming != null ? '/call?incoming=$incoming' : '/call'),
                child: const Text('GO'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/call',
          builder: (ctx, state) => CallScreen(
              incomingCallId: state.uri.queryParameters['incoming']),
        ),
      ],
    );

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('incoming: shows accept + reject; accept → PUT /accept', (tester) async {
    final h = harness();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: h.c,
      child: MaterialApp.router(routerConfig: router('call1')),
    ));
    await tester.tap(find.text('GO'));
    await settle(tester);

    expect(find.textContaining('สายเรียกเข้า'), findsOneWidget);
    expect(find.byIcon(Icons.call), findsOneWidget, reason: 'accept');
    expect(find.byIcon(Icons.call_end), findsOneWidget, reason: 'reject');

    // Finish the route push transition first: the accept button sits at the design's right-edge
    // position and is off-screen mid-slide (tap() would miss it).
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.call)); // accept (does not pop)
    await settle(tester);
    expect(h.api.calls, contains('PUT /calls/call1/accept'));

    await tester.pumpWidget(const SizedBox());
    h.c.dispose(); // cancels the controller's connect-timeout within the test body
  });

  testWidgets('incoming: reject → PUT /reject and pops back', (tester) async {
    final h = harness();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: h.c,
      child: MaterialApp.router(routerConfig: router('call1')),
    ));
    await tester.tap(find.text('GO'));
    await settle(tester);
    expect(find.textContaining('สายเรียกเข้า'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.call_end)); // reject → pop
    await settle(tester);

    expect(h.api.calls, contains('PUT /calls/call1/reject'));
    expect(find.text('GO'), findsOneWidget, reason: 'popped back to home');

    await tester.pumpWidget(const SizedBox());
    h.c.dispose(); // cancels the controller's connect-timeout within the test body
  });

  testWidgets('incoming → reject → dispose resets the singleton (no framework assertion); a fresh call renders',
      (tester) async {
    // The reject pops the screen; its dispose() defers `CallController.reset()` to a microtask
    // (resetting the keepAlive singleton synchronously in dispose would `markNeedsBuild during
    // dispose`). This asserts that path raises NO framework error AND that the singleton is clean
    // afterwards — a NEW call started on the same container renders fresh from idle.
    final h = harness();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: h.c,
      child: MaterialApp.router(routerConfig: router('call1')),
    ));
    await tester.tap(find.text('GO'));
    await settle(tester);
    expect(find.textContaining('สายเรียกเข้า'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.call_end)); // reject → ended → auto-pop
    await settle(tester);
    // Let the auto-pop transition finish so the screen is fully unmounted + disposed; dispose()
    // then schedules `Future.microtask(reset)`. A final settle turns the event loop so the deferred
    // reset fires before we assert.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'the deferred reset on dispose raises no framework assertion');
    expect(find.text('GO'), findsOneWidget, reason: 'popped back to home');
    // The singleton was returned to idle by the deferred reset (not stuck in `ended`).
    expect(h.c.read(callControllerProvider).phase, CallPhase.idle);

    // A SUBSEQUENT call renders fresh on the same (reset) singleton: start an outgoing call, push
    // the screen again, and confirm the ringing UI shows (not a stale call-ended summary).
    await h.c
        .read(callControllerProvider.notifier)
        .startOutgoing(bookingId: 'bk2', type: CallType.audio);
    await tester.tap(find.text('GO'));
    await settle(tester);
    expect(find.textContaining('กำลังเรียก'), findsOneWidget,
        reason: 'the next call renders fresh from dialing');

    await tester.pumpWidget(const SizedBox());
    h.c.dispose(); // cancels the controller's connect-timeout within the test body
  });

  testWidgets('outgoing: a started call shows the ringing UI + a cancel control',
      (tester) async {
    final h = harness();
    // Start the call, then show the screen — it reflects the dialing state.
    await h.c
        .read(callControllerProvider.notifier)
        .startOutgoing(bookingId: 'bk1', type: CallType.audio);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: h.c,
      child: MaterialApp.router(routerConfig: router(null)),
    ));
    await tester.tap(find.text('GO'));
    await settle(tester);

    expect(find.textContaining('กำลังเรียก'), findsOneWidget);
    expect(find.byIcon(Icons.call_end), findsOneWidget, reason: 'cancel');

    await tester.pumpWidget(const SizedBox());
    h.c.dispose(); // cancels the controller's connect-timeout within the test body
  });
}
