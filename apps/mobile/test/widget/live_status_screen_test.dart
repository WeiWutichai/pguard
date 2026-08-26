import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/guard_discovery_screen.dart';
import 'package:pguard_mobile/features/booking/guard_map_screen.dart';
import 'package:pguard_mobile/features/booking/job_completion_summary_screen.dart';
import 'package:pguard_mobile/features/booking/live_status_screen.dart';
import 'package:pguard_mobile/widgets/booking_status_pill.dart';
import 'package:pguard_mobile/widgets/booking_status_timeline.dart';

import '../support/fakes.dart';

/// A valid access JWT whose `sub` becomes the acting user id the session resolves (#87 pay-gate
/// ownership is `viewerUserId == booking.customerId`).
String _jwt(String sub, {String role = 'customer'}) => fakeJwt({
      'sub': sub,
      'role': role,
      'exp':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
    });

/// A router rooting the live screen at `/booking/b1/live`, plus the two destinations the C1
/// guard-withdrew redirect builds (`/home/customer` → `/book/guards`). `/home/customer` is a bare
/// placeholder so the test doesn't drag in the dashboard's providers.
GoRouter _c1Router() => GoRouter(
      initialLocation: '/booking/b1/live',
      routes: [
        GoRoute(
          path: '/booking/:id/live',
          builder: (_, s) =>
              LiveStatusScreen(bookingId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/home/customer',
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/book/guards',
          builder: (_, __) => const GuardDiscoveryScreen(),
        ),
      ],
    );

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
        // Real OSRM routing is now reused by the inline live-map preview — fake it so no test hits
        // the network (default null route → the straight-line fallback the preview degrades to).
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
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
      'guard assigned → inline live-map preview expands to the full live-map screen',
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
          builder: (_, s) => GuardMapScreen(bookingId: s.pathParameters['id']!),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        // Real OSRM routing is now reused by the inline live-map preview — fake it so no test hits
        // the network (default null route → the straight-line fallback the preview degrades to).
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
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

    // The inline live-map preview is embedded because a guard is assigned and the job is active;
    // it carries the fullscreen expand affordance.
    final expand = find.byIcon(Icons.fullscreen);
    expect(expand, findsOneWidget);

    await tester.tap(expand);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(GuardMapScreen), findsOneWidget,
        reason: 'tapping the expand affordance pushes /booking/b1/map');
    // The pushed full map renders the guard's (current-position) marker (the inline preview
    // underneath also shows one, so at least one is on screen). A2: the marker is a dot now, not a
    // shield — assert on the marker widget itself.
    expect(find.byType(GuardMapGuardMarker), findsWidgets,
        reason: 'the full map rendered the guard marker');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no guard assigned → no inline live-map preview', (tester) async {
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
        // Real OSRM routing is now reused by the inline live-map preview — fake it so no test hits
        // the network (default null route → the straight-line fallback the preview degrades to).
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tp) => FakeBookingFeed()),
      ],
      child: const MaterialApp(home: LiveStatusScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byIcon(Icons.fullscreen), findsNothing);

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
        // Real OSRM routing is now reused by the inline live-map preview — fake it so no test hits
        // the network (default null route → the straight-line fallback the preview degrades to).
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
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

    // The #123 status timeline added height above; the approve CTA can sit below the fold, so
    // bring it into view before tapping (the screen is scrollable).
    await tester.ensureVisible(approve);
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // It PUT the approve action and landed on the completion summary.
    expect(putBody, {'action': 'approve'});
    expect(
        api.calls
            .where((c) => c == 'PUT /bookings/b1/review-completion')
            .length,
        1);
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
        // Real OSRM routing is now reused by the inline live-map preview — fake it so no test hits
        // the network (default null route → the straight-line fallback the preview degrades to).
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tp) => FakeBookingFeed()),
        locationServiceProvider.overrideWithValue(FakeLocationService()),
      ],
      child: const MaterialApp(home: LiveStatusScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The completion-review panel + the inline live-map both render while pending_completion
    // (guard assigned, not terminal). Tap the "keep working" CTA — the inline map needs a
    // (fake) location service for its controller's device-fix fallback. The inline map adds
    // height, so scroll the CTA into view before tapping.
    final keepWorking = find.text('ให้ทำต่อ');
    await tester.ensureVisible(keepWorking);
    await tester.pump();
    await tester.tap(keepWorking);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // It PUT the reject action; the booking folds back to `arrived` (panel gone) and a
    // confirmation snackbar appears.
    expect(putBody, {'action': 'reject'});
    expect(find.text('รอยืนยันจบงาน'), findsNothing);
    expect(find.text('แจ้งให้เจ้าหน้าที่ทำงานต่อแล้ว'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Details action opens the booking-details sheet (no longer a no-op)',
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
        // Real OSRM routing is now reused by the inline live-map preview — fake it so no test hits
        // the network (default null route → the straight-line fallback the preview degrades to).
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tp) => FakeBookingFeed()),
      ],
      child: const MaterialApp(home: LiveStatusScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The #123 status timeline added height above; the Details CTA can sit below the fold, so
    // bring it into view before tapping (the screen is scrollable).
    final detailsBtn = find.text('ดูรายละเอียด');
    await tester.ensureVisible(detailsBtn);
    await tester.pumpAndSettle();
    await tester.tap(detailsBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The bottom sheet opened with the booking details (the title + detail rows are sheet-only;
    // the address also shows in the guard card above, so assert on the sheet-unique labels).
    expect(find.text('รายละเอียดการจอง'), findsOneWidget);
    expect(find.text('จำนวนชั่วโมง'), findsOneWidget);
    // The composed address is now split into clean rows; the first line is the 'ที่อยู่' row.
    expect(find.text('ที่อยู่'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      '#127/#129 details sheet: emphasised status pill + the work-status timeline',
      (tester) async {
    // A pending_completion booking: the guard requested completion and the job awaits the customer.
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') {
        return {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'pending_completion',
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
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tp) => FakeBookingFeed()),
      ],
      child: const MaterialApp(home: LiveStatusScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final detailsBtn = find.text('ดูรายละเอียด');
    await tester.ensureVisible(detailsBtn);
    await tester.pumpAndSettle();
    await tester.tap(detailsBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // #127: the status row carries an emphasised COLOURED pill (not flat text) for the
    // awaiting-confirmation state — assert the pill widget is present in the open sheet.
    expect(find.byType(BookingStatusPill), findsOneWidget);

    // #129: the shared work-status timeline now renders INSIDE the details sheet (the same widget
    // the main live/active screens use), under the "สถานะการทำงาน" heading.
    expect(find.byType(BookingStatusTimeline), findsWidgets);
    // The sheet's own "Job progress" heading (the customer screen above also has one, so the sheet
    // adds a second occurrence).
    expect(find.text('สถานะการทำงาน'), findsWidgets);
    // The timeline's step labels render in the sheet (e.g. the first + last steps).
    expect(find.text('เริ่มรับงาน'), findsWidgets);
    expect(find.text('เสร็จงาน'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('#87 OWNER (customer) sees the Pay banner when accepted + unpaid',
      (tester) async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? {
              'id': 'b1',
              'customer_id': 'c1',
              'status': 'accepted',
              'guard_id': 'g1',
            }
          : const <Map<String, dynamic>>[],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        // Real OSRM routing is now reused by the inline live-map preview — fake it so no test hits
        // the network (default null route → the straight-line fallback the preview degrades to).
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
        // The acting user IS the booking owner (sub == customer_id 'c1'). A refresh token (+ no
        // PIN) makes the session resolve `authenticated` so sessionProvider.user is populated.
        appStoreProvider.overrideWithValue(InMemoryStore()
          ..refresh = 'r'
          ..access = _jwt('c1')),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tp) => FakeBookingFeed()),
      ],
      child: const MaterialApp(home: LiveStatusScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The customer sees the prominent Pay CTA + banner (default locale = Thai).
    expect(find.text('ชำระเงิน'), findsOneWidget,
        reason: 'the owner customer sees the Pay button');
    expect(find.text('เจ้าหน้าที่รับงานแล้ว — ชำระเงินเพื่อเริ่มงาน'),
        findsOneWidget);
    // The read-only non-owner notice is NOT shown to the owner.
    expect(find.text('รอลูกค้าชำระเงิน'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('#97 completed: OWNER (customer) sees the Rate-the-guard CTA',
      (tester) async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? {
              'id': 'b1',
              'customer_id': 'c1',
              'status': 'completed',
              'guard_id': 'g1',
              'hours': 2,
              'base_fee': '500.00',
            }
          : const <Map<String, dynamic>>[],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        // Real OSRM routing is now reused by the inline live-map preview — fake it so no test hits
        // the network (default null route → the straight-line fallback the preview degrades to).
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
        // Acting user IS the owner (sub == customer_id 'c1').
        appStoreProvider.overrideWithValue(InMemoryStore()
          ..refresh = 'r'
          ..access = _jwt('c1')),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tp) => FakeBookingFeed()),
      ],
      child: const MaterialApp(home: LiveStatusScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The customer keeps the rating CTA on a completed job — and NOW also gets the receipt as a
    // secondary action beside it (the rating-only state dead-ended the owner away from their
    // settled bill).
    expect(find.text('ให้คะแนนเจ้าหน้าที่'), findsOneWidget,
        reason: 'the customer (owner) rates the guard');
    expect(find.text('ดูใบสรุปค่าบริการ'), findsOneWidget,
        reason: 'the owner gets a receipt path alongside the rating CTA');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'completed + already RATED: owner sees the passive Rated state AND keeps '
      'the receipt button', (tester) async {
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') {
          return {
            'id': 'b1',
            'customer_id': 'c1',
            'status': 'completed',
            'guard_id': 'g1',
            'hours': 2,
            'base_fee': '500.00',
          };
        }
        if (path == '/assignments/b1/review') {
          // The customer already reviewed this booking.
          return {
            'id': 'rv1',
            'guard_id': 'g1',
            'overall_rating': 5,
            'created_at': '2026-06-10T10:00:00Z',
          };
        }
        return const <Map<String, dynamic>>[];
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
        appStoreProvider.overrideWithValue(InMemoryStore()
          ..refresh = 'r'
          ..access = _jwt('c1')),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tp) => FakeBookingFeed()),
      ],
      child: const MaterialApp(home: LiveStatusScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    // One more frame: the already-rated gate (GET /assignments/{id}/review) resolves a hop
    // after the completed actions row first builds.
    await tester.pump(const Duration(milliseconds: 20));

    // The passive "Rated" state replaces the rating CTA — but the receipt stays reachable
    // (previously the rated state was the ONLY action, hiding the receipt entirely).
    expect(find.text('ให้คะแนนแล้ว'), findsOneWidget);
    expect(find.text('ให้คะแนนเจ้าหน้าที่'), findsNothing);
    expect(find.text('ดูใบสรุปค่าบริการ'), findsOneWidget,
        reason: 'the receipt survives rating');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      '#97 completed: NON-owner (guard) sees a receipt, NEVER a rating CTA',
      (tester) async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? {
              'id': 'b1',
              'customer_id': 'c1',
              'status': 'completed',
              'guard_id': 'g1',
              'hours': 2,
              'base_fee': '500.00',
            }
          : const <Map<String, dynamic>>[],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        // Real OSRM routing is now reused by the inline live-map preview — fake it so no test hits
        // the network (default null route → the straight-line fallback the preview degrades to).
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
        // Acting user is the GUARD (sub 'g1') — NOT the booking owner 'c1'.
        appStoreProvider.overrideWithValue(InMemoryStore()
          ..refresh = 'r'
          ..access = _jwt('g1', role: 'guard')),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tp) => FakeBookingFeed()),
      ],
      child: const MaterialApp(home: LiveStatusScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The guard must NEVER see a rating CTA for their own job (#97), and never the customer's
    // receipt either — that document totals the customer's bill (tip + the whole crew) and settles
    // against a payment row the guard cannot read. Their own pay is on the earnings screen.
    expect(find.text('ให้คะแนนเจ้าหน้าที่'), findsNothing,
        reason: 'a guard must never see a rating CTA (#97)');
    expect(find.text('ดูใบสรุปค่าบริการ'), findsNothing,
        reason: "the receipt is the customer's document");
    expect(find.text('ดูรายได้ของฉัน'), findsOneWidget,
        reason: 'the guard gets their own earnings instead');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      '#87 NON-owner (guard) sees the await notice and NEVER the Pay button',
      (tester) async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? {
              'id': 'b1',
              'customer_id': 'c1',
              'status': 'accepted',
              'guard_id': 'g1',
            }
          : const <Map<String, dynamic>>[],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        // Real OSRM routing is now reused by the inline live-map preview — fake it so no test hits
        // the network (default null route → the straight-line fallback the preview degrades to).
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
        // The acting user is the GUARD (sub 'g1', role guard) — NOT the booking owner 'c1'.
        appStoreProvider.overrideWithValue(InMemoryStore()
          ..refresh = 'r'
          ..access = _jwt('g1', role: 'guard')),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tp) => FakeBookingFeed()),
      ],
      child: const MaterialApp(home: LiveStatusScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The guard NEVER sees a pay button/banner here — only the read-only await notice.
    expect(find.text('รอลูกค้าชำระเงิน'), findsOneWidget,
        reason: 'a non-owner viewer sees the read-only await-payment notice');
    expect(find.text('ชำระเงิน'), findsNothing,
        reason: 'a guard must NEVER see the Pay button (#87)');
    expect(find.text('เจ้าหน้าที่รับงานแล้ว — ชำระเงินเพื่อเริ่มงาน'),
        findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'E: a declined frame (guard withdrew) prompts a choice; "find a new guard" '
      're-searches', (tester) async {
    final feed = FakeBookingFeed();
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') {
        // A guard had accepted (guard_id null keeps the inline live-map out of this test — the
        // prompt depends only on the status transition).
        return {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'accepted',
          'guard_id': null,
        };
      }
      // The discovery screen's initState loads available guards once.
      return <Map<String, dynamic>>[];
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider.overrideWithValue((id, tp) => feed),
      ],
      child: MaterialApp.router(routerConfig: _c1Router()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(LiveStatusScreen), findsOneWidget);
    expect(find.byType(GuardDiscoveryScreen), findsNothing);

    // The guard withdraws after accepting → the booking goes `declined` over the WS → a CHOICE dialog
    // appears (no silent redirect).
    feed.emit(BookingStatusEvent(
        bookingId: 'b1',
        status: BookingStatus.declined,
        occurredAt: DateTime.utc(2026)));
    await tester
        .pump(); // fold the event → the listener fires + schedules the post-frame prompt
    await tester.pump(); // post-frame → showDialog
    await tester.pump(const Duration(milliseconds: 300)); // dialog transition
    expect(find.text('รปภ. ยกเลิกงาน'), findsOneWidget,
        reason: 'the guard-withdrew choice dialog, not a silent redirect');
    expect(find.byType(GuardDiscoveryScreen), findsNothing);

    // Choose "find a new guard" → re-search: go(/home) + push(/book/guards) → discovery builds +
    // loads guards. Pump generously (past the ~300ms route transition); avoid pumpAndSettle (the
    // discovery "searching" dots animate forever until guards resolve).
    await tester.tap(find.text('ค้นหา Guard ใหม่'));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(GuardDiscoveryScreen), findsOneWidget,
        reason: 'a guard withdrawal + "find a new guard" routes to re-search');
    expect(find.byType(LiveStatusScreen), findsNothing,
        reason: 'the dead live screen is left behind');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'E: a declined frame → "cancel job" calls cancel-after-decline and stays '
      'on the terminal cancelled screen (no re-search)', (tester) async {
    final feed = FakeBookingFeed();
    var putPath = '';
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') {
          return {
            'id': 'b1',
            'customer_id': 'c1',
            'status': 'accepted',
            'guard_id': null,
          };
        }
        return <Map<String, dynamic>>[];
      },
      onPut: (path, _) async {
        putPath = path;
        // The server transitions declined → cancelled and returns the updated booking.
        return {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'cancelled',
          'guard_id': null,
        };
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider.overrideWithValue((id, tp) => feed),
      ],
      child: MaterialApp.router(routerConfig: _c1Router()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    feed.emit(BookingStatusEvent(
        bookingId: 'b1',
        status: BookingStatus.declined,
        occurredAt: DateTime.utc(2026)));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('รปภ. ยกเลิกงาน'), findsOneWidget);

    // Choose "cancel job" → PUT /bookings/b1/cancel-after-decline; the booking becomes cancelled and
    // the customer STAYS on the (now terminal) live screen — no re-search, no re-prompt.
    await tester.tap(find.text('ยกเลิกงาน'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(putPath, '/bookings/b1/cancel-after-decline');
    expect(find.byType(GuardDiscoveryScreen), findsNothing,
        reason: 'cancelling after a decline is terminal — no re-search');
    expect(find.byType(LiveStatusScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      "C1: a cancelled frame (the customer's OWN cancel) stays terminal — no "
      'redirect', (tester) async {
    final feed = FakeBookingFeed();
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') {
        return {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'accepted',
          'guard_id': null,
        };
      }
      return <Map<String, dynamic>>[];
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        routingServiceProvider.overrideWithValue(FakeRoutingService()),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider.overrideWithValue((id, tp) => feed),
      ],
      child: MaterialApp.router(routerConfig: _c1Router()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The customer cancels their own booking pre-arrival → the booking goes `cancelled`.
    feed.emit(BookingStatusEvent(
        bookingId: 'b1',
        status: BookingStatus.cancelled,
        occurredAt: DateTime.utc(2026)));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // No re-search — a self-cancel is a terminal dead-end (the refund banner), so the customer
    // stays put on the live screen (distinct from a guard `declined` withdrawal).
    expect(find.byType(GuardDiscoveryScreen), findsNothing,
        reason: "the customer's own cancel must NOT trigger re-search");
    expect(find.byType(LiveStatusScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
