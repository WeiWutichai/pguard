import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/controllers/tracking_controller.dart';
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
}
