import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/guard_map_screen.dart';
import 'package:pguard_mobile/features/booking/live_status_screen.dart';

import '../support/fakes.dart';

void main() {
  testWidgets(
      'live-status screen renders the snapshot then updates from a WS push',
      (tester) async {
    final feed = FakeBookingFeed();
    final store = InMemoryStore()..access = 'token';
    final api = FakeApi(
        onGet: (path, _) async => {
              'id': 'b1',
              'customer_id': 'c1',
              'status': 'accepted',
              'guard_id': null
            });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(store),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tokenProvider) => feed),
      ],
      child: const MaterialApp(home: LiveStatusScreen(bookingId: 'b1')),
    ));

    // Resolve the initial REST snapshot.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.textContaining('Guard assigned'),
        findsOneWidget); // status = accepted

    // A WebSocket push advances the on-screen status — no polling, no rebuild trigger but the
    // pushed frame.
    feed.emit(BookingStatusEvent(
        bookingId: 'b1',
        status: BookingStatus.arrived,
        occurredAt: DateTime.utc(2026)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.textContaining('Arrived'), findsOneWidget);

    // Exactly one booking GET — proves the screen is push-driven, not polling. (The chat
    // unread badge adds at most ONE conversations fetch — also not polled.)
    expect(api.calls.where((c) => c == 'GET /bookings/b1').length, 1);
    expect(api.calls.where((c) => c.startsWith('GET /conversations')).length,
        lessThanOrEqualTo(1));
  });

  testWidgets(
      'guard assigned → track-guard tile navigates to the live-map screen',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') {
        return {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'en_route',
          'guard_id': 'g1',
          'address': 'หมู่บ้านลัดดารมย์ ซ.5',
        };
      }
      if (path == '/guards/g1/location') {
        return {
          'guard_id': 'g1',
          'lat': 13.7563,
          'lng': 100.5018,
          'recorded_at': '2026-06-10T10:30:45Z',
          'is_online': true,
          'is_live': true,
        };
      }
      return <Map<String, dynamic>>[]; // conversations (unread badge)
    });

    final router = GoRouter(
      initialLocation: '/booking/b1/live',
      routes: [
        GoRoute(
          path: '/booking/:id/live',
          builder: (_, s) =>
              LiveStatusScreen(bookingId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/booking/:id/map',
          builder: (_, s) =>
              GuardMapScreen(bookingId: s.pathParameters['id']!),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tp) => FakeBookingFeed()),
        locationServiceProvider.overrideWithValue(FakeLocationService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The entry tile is visible because a guard is assigned and the job is active
    // (default locale is Thai; the label toggles with the locale controller).
    final tile = find.text('ดูตำแหน่งเจ้าหน้าที่');
    expect(tile, findsOneWidget);

    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(GuardMapScreen), findsOneWidget,
        reason: 'tapping the tile pushes /booking/b1/map');
    expect(find.byIcon(Icons.shield), findsOneWidget,
        reason: 'the map rendered the guard marker');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no guard assigned → no track-guard tile', (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') {
        return {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'requested',
          'guard_id': null,
        };
      }
      return <Map<String, dynamic>>[];
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tp) => FakeBookingFeed()),
      ],
      child: const MaterialApp(home: LiveStatusScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('ดูตำแหน่งเจ้าหน้าที่'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
