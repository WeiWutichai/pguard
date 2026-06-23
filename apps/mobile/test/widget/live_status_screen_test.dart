import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/guard_map_screen.dart';
import 'package:pguard_mobile/features/booking/job_completion_summary_screen.dart';
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

  testWidgets(
      'pending_completion → approve calls review-completion {approve} and routes to summary',
      (tester) async {
    Object? putBody;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') {
          return {
            'id': 'b1',
            'customer_id': 'c1',
            'status': 'pending_completion',
            'guard_id': 'g1',
            'hours': 2,
            'base_fee': '500.00',
          };
        }
        if (path == '/payments') {
          return <Map<String, dynamic>>[
            {
              'id': 'p1',
              'booking_id': 'b1',
              'customer_id': 'c1',
              'amount': '1000.00',
              'final_amount': '500.00',
              'refund_amount': '500.00',
              'actual_hours': '1',
              'refund_status': 'pending',
              'status': 'completed',
            }
          ];
        }
        return <Map<String, dynamic>>[]; // conversations / progress-reports
      },
      onPut: (path, data) async {
        putBody = data;
        return {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'completed',
          'guard_id': 'g1',
          'hours': 2,
          'base_fee': '500.00',
        };
      },
    );

    final router = GoRouter(
      initialLocation: '/booking/b1/live',
      routes: [
        GoRoute(
          path: '/booking/:id/live',
          builder: (_, s) =>
              LiveStatusScreen(bookingId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/booking/:id/summary',
          builder: (_, s) =>
              JobCompletionSummaryScreen(bookingId: s.pathParameters['id']!),
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
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The completion-review panel is shown (default locale = Thai).
    expect(find.text('รอยืนยันจบงาน'), findsOneWidget);
    final approve = find.text('ยืนยันจบงาน');
    expect(approve, findsOneWidget);
    expect(find.text('ให้ทำต่อ'), findsOneWidget);

    await tester.tap(approve);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // It PUT the approve action and landed on the completion summary.
    expect(putBody, {'action': 'approve'});
    expect(api.calls.where((c) => c == 'PUT /bookings/b1/review-completion').length, 1);
    expect(find.byType(JobCompletionSummaryScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'pending_completion → reject calls review-completion {reject} and stays',
      (tester) async {
    Object? putBody;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') {
          return {
            'id': 'b1',
            'customer_id': 'c1',
            'status': 'pending_completion',
            'guard_id': 'g1',
            'hours': 2,
          };
        }
        return <Map<String, dynamic>>[];
      },
      onPut: (path, data) async {
        putBody = data;
        return {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'arrived',
          'guard_id': 'g1',
          'hours': 2,
        };
      },
    );

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

    await tester.tap(find.text('ให้ทำต่อ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // It PUT the reject action; the booking folds back to `arrived` (panel gone) and a
    // confirmation snackbar appears.
    expect(putBody, {'action': 'reject'});
    expect(find.text('รอยืนยันจบงาน'), findsNothing);
    expect(find.text('แจ้งให้เจ้าหน้าที่ทำงานต่อแล้ว'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Details action opens the booking-details sheet (no longer a no-op)',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') {
        return {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'arrived',
          'guard_id': 'g1',
          'address': 'หมู่บ้านลัดดารมย์',
          'hours': 3,
          'base_fee': '500.00',
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

    await tester.tap(find.text('ดูรายละเอียด'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The bottom sheet opened with the booking details (the title + detail rows are sheet-only;
    // the address also shows in the guard card above, so assert on the sheet-unique labels).
    expect(find.text('รายละเอียดการจอง'), findsOneWidget);
    expect(find.text('จำนวนชั่วโมง'), findsOneWidget);
    expect(find.text('สถานที่'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
