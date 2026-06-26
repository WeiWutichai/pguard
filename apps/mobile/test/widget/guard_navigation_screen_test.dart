import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:pguard_mobile/core/location/routing_service.dart';
import 'package:pguard_mobile/core/models/geo.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/guard_navigation_screen.dart';

import '../support/fakes.dart';

/// A 4-point road route (so the map polyline is multi-point, not the straight 2-point fallback),
/// 6 km / 10 min driving.
RouteResult _route() => RouteResult.fromOsrm({
      'routes': [
        {
          'distance': 6000.0,
          'duration': 600.0,
          'geometry': {
            'coordinates': [
              [100.5001, 13.7600],
              [100.5005, 13.7560],
              [100.5003, 13.7520],
              [100.5001, 13.7501],
            ],
          },
        },
      ],
    })!;

Map<String, dynamic> _bookingJson(String status) => {
      'id': 'b1',
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': status,
      'address': 'หมู่บ้านลัดดารมย์ ซ.5',
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'lat': 13.7501,
      'lng': 100.5001,
      'tip': '0',
      'created_at': '2026-06-16T00:00:00Z',
      'updated_at': '2026-06-16T00:00:00Z',
    };

Future<void> _pump(
  WidgetTester tester,
  FakeApi api,
  GeoPoint? self, {
  RouteResult? route,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      guardSelfLocationProvider.overrideWith((ref) => Stream.value(self)),
      // null route → the straight-line fallback path; a RouteResult → the real road polyline.
      routingServiceProvider
          .overrideWithValue(FakeRoutingService(result: route)),
    ],
    child: const MaterialApp(home: GuardNavigationScreen(bookingId: 'b1')),
  ));
  await _settle(tester);
}

/// The number of points in the (single) polyline drawn on the map, or 0 when there is none.
int _polylinePointCount(WidgetTester tester) {
  final layers = tester.widgetList<PolylineLayer>(find.byType(PolylineLayer));
  if (layers.isEmpty) return 0;
  return layers.first.polylines.first.points.length;
}

/// flutter_map's TileLayer keeps requesting network tiles, so `pumpAndSettle` never settles and
/// times out under full-suite load (a flake). Pump a bounded set of frames instead — enough to
/// resolve the booking/location futures + render, without waiting on tiles.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets(
      'FALLBACK: no route → straight-line distance·ETA with the ~ + a 2-point line',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => _bookingJson('en_route'));
    // ~1.1 km north of the destination; FakeRoutingService returns null (OSRM down/offline).
    await _pump(tester, api, const GeoPoint(13.7600, 100.5001)); // route: null

    // The fallback ETA keeps the tilde to mark it approximate.
    expect(find.textContaining('~'), findsOneWidget);
    expect(find.textContaining('นาที'), findsOneWidget);
    expect(find.textContaining('หมู่บ้านลัดดารมย์'), findsOneWidget);
    expect(find.text('ถึงจุดนัดแล้ว — เริ่มงาน'), findsOneWidget);
    // The drawn line is the straight 2-point segment, not a multi-point road route.
    expect(_polylinePointCount(tester), 2);
  });

  testWidgets(
      'REAL route: multi-point road polyline + road distance·ETA with NO ~',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => _bookingJson('en_route'));
    await _pump(tester, api, const GeoPoint(13.7600, 100.5001),
        route: _route());

    // Real routed ETA → no tilde anywhere on the sheet.
    expect(find.textContaining('~'), findsNothing);
    expect(find.textContaining('นาที'), findsOneWidget);
    // The map draws the full 4-point road geometry, not the 2-point straight line.
    expect(_polylinePointCount(tester), 4);
  });

  testWidgets('mode selector switches the ETA (car → walk) keeping the geometry',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => _bookingJson('en_route'));
    await _pump(tester, api, const GeoPoint(13.7600, 100.5001),
        route: _route());

    // Default car ETA: 600 s → 10 นาที.
    expect(find.textContaining('10 นาที'), findsOneWidget);
    final before = _polylinePointCount(tester);

    // Switch to เดิน (walk): 6000 m / 1.39 ≈ 72 นาที — a different, longer ETA.
    await tester.tap(find.text('เดิน'));
    await _settle(tester);

    expect(find.textContaining('10 นาที'), findsNothing);
    expect(find.textContaining('72 นาที'), findsOneWidget);
    // The geometry is unchanged — only the ETA label flips.
    expect(_polylinePointCount(tester), before);
  });

  testWidgets(
      'the sheet ▲ recenters the map: re-frames the whole route after panning away',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => _bookingJson('en_route'));
    await _pump(tester, api, const GeoPoint(13.7600, 100.5001),
        route: _route());

    // The ▲ tile is now a tappable recenter button with the brand recenter Semantics/Tooltip.
    final recenter = find.byTooltip('จัดกึ่งกลางเส้นทาง');
    expect(recenter, findsOneWidget,
        reason: 'the ▲ tile carries the recenter tooltip');

    final controller =
        tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    final framed = controller.camera.center;

    // The guard pans + zooms far off the route.
    controller.move(const LatLng(15.0, 102.0), 8);
    await _settle(tester);
    expect(controller.camera.center.latitude, isNot(closeTo(framed.latitude, 0.1)),
        reason: 'precondition: the camera moved off the route');

    // Tapping ▲ bumps the recenter token → PgMap re-fits the camera back onto the route.
    await tester.tap(recenter);
    await _settle(tester);

    expect(controller.camera.center.latitude, closeTo(framed.latitude, 0.05),
        reason: 'the ▲ tap re-frames the route (guard + dest + road polyline)');
    expect(controller.camera.center.longitude, closeTo(framed.longitude, 0.05));
  });

  testWidgets('degrades to address-only when there is no GPS fix (no distance)',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => _bookingJson('en_route'));
    await _pump(tester, api, null); // no self position

    expect(find.textContaining('นาที'), findsNothing); // no fabricated ETA
    expect(find.text('ถึงจุดนัดแล้ว — เริ่มงาน'), findsOneWidget);
    expect(find.textContaining('หมู่บ้านลัดดารมย์'), findsOneWidget);
  });

  testWidgets('the combined CTA marks arrived then starts the job',
      (tester) async {
    final api = FakeApi(
      onGet: (_, __) async => _bookingJson('en_route'),
      onPut: (path, _) async {
        if (path == '/bookings/b1/arrived') return _bookingJson('arrived');
        if (path == '/bookings/b1/start') return _bookingJson('arrived');
        throw StateError('unexpected PUT $path');
      },
    );
    final router = GoRouter(initialLocation: '/start', routes: [
      GoRoute(
        path: '/start',
        builder: (context, __) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => context.push('/nav'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/nav',
        builder: (_, __) => const GuardNavigationScreen(bookingId: 'b1'),
      ),
    ]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        guardSelfLocationProvider
            .overrideWith((ref) => Stream.value(const GeoPoint(13.76, 100.50))),
        routingServiceProvider
            .overrideWithValue(FakeRoutingService()), // no network in tests
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await _settle(tester);

    await tester.tap(find.text('go'));
    await _settle(tester);
    await tester.tap(find.text('ถึงจุดนัดแล้ว — เริ่มงาน'));
    await _settle(tester);

    expect(api.calls, contains('PUT /bookings/b1/arrived'));
    expect(api.calls, contains('PUT /bookings/b1/start'));
    // Returned to the previous screen after arrive+start.
    expect(find.text('go'), findsOneWidget);
  });
}
