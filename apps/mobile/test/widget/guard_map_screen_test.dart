import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/location/routing_service.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/guard_map_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson({
  String? guardId,
  String status = 'en_route',
  double? lat,
  double? lng,
}) =>
    {
      'id': 'b1',
      'customer_id': 'c1',
      'guard_id': guardId,
      'status': status,
      'address': 'หมู่บ้านลัดดารมย์ ซ.5',
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    };

Map<String, dynamic> locationJson({bool live = true}) => {
      'guard_id': 'g1',
      'lat': 13.7563,
      'lng': 100.5018,
      'accuracy': 8.0,
      'heading': 90.0,
      'recorded_at': '2026-06-10T10:30:45Z',
      'is_online': live,
      'is_live': live,
    };

Map<String, dynamic> publicJson({String? fullName = 'ณัฐพล วงศ์ดี', int? years = 7}) =>
    {
      'user_id': 'g1',
      if (fullName != null) 'full_name': fullName,
      if (years != null) 'years_of_experience': years,
    };

Map<String, dynamic> ratingsJson({String? average = '4.9', int count = 12}) => {
      'guard_id': 'g1',
      'average': average,
      'count': count,
      'reviews': <Map<String, dynamic>>[],
    };

/// A 4-point road route (so the customer map draws a multi-point road line, not the straight
/// 2-point fallback), 6 km road distance.
RouteResult routeResult() => RouteResult.fromOsrm({
      'routes': [
        {
          'distance': 6000.0,
          'duration': 600.0,
          'geometry': {
            'coordinates': [
              [100.5018, 13.7563],
              [100.5400, 13.7700],
              [100.5800, 13.7850],
              [100.6000, 13.8000],
            ],
          },
        },
      ],
    })!;

Widget host({
  required FakeApi api,
  FakeBookingFeed? feed,
  FakeLocationService? loc,
  Map<String, String> prefs = const {},
  RouteResult? route,
}) {
  return ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      prefsStoreProvider
          .overrideWithValue(FakePrefsStore()..values.addAll(prefs)),
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tp) => feed ?? FakeBookingFeed()),
      locationServiceProvider.overrideWithValue(loc ?? FakeLocationService()),
      // Real OSRM routing is reused on the customer side (matches the guard nav) — fake it so the
      // map watches the shared guardRouteProvider without any network. `null` (default) → the
      // straight-line fallback every existing assertion expects; a RouteResult → the real road path.
      routingServiceProvider
          .overrideWithValue(FakeRoutingService(result: route)),
    ],
    child: const MaterialApp(home: GuardMapScreen(bookingId: 'b1')),
  );
}

Future<void> settle(WidgetTester tester) async {
  // Three pumps: deliver the (broadcast-stream) event, run the scheduled provider rebuild
  // (async build), then render the dirty widget. A fourth covers the guardRoute future resolving
  // (the FakeRoutingService is async) so the real-route polyline lands before assertions.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 20));
}

/// The number of points in the (single) road/route polyline drawn on the map, or 0 when there is
/// none — distinguishes the multi-point real route from the straight 2-point fallback.
int polylinePointCount(WidgetTester tester) {
  final layers = tester.widgetList<PolylineLayer>(find.byType(PolylineLayer));
  if (layers.isEmpty) return 0;
  return layers.first.polylines.first.points.length;
}

void main() {
  testWidgets(
      'renders the guard marker, reference marker, en-route status chip and '
      'live freshness from one snapshot', (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      if (path == '/guards/g1/location') return locationJson();
      if (path == '/guards/g1/public') return publicJson();
      if (path == '/guards/g1/ratings') return ratingsJson();
      // The info panel's chat entry overlays an unread badge (one conversations fetch).
      if (path == '/conversations') return <Map<String, dynamic>>[];
      fail('unexpected GET $path');
    });

    await tester.pumpWidget(host(api: api));
    await settle(tester);

    expect(find.byIcon(Icons.shield), findsOneWidget, reason: 'guard marker');
    expect(find.text('คุณ'), findsOneWidget, reason: 'reference marker label');
    // The profile block shows the real name + honest rating (no fake photo/ETA).
    expect(find.text('ณัฐพล วงศ์ดี'), findsOneWidget, reason: 'guard name');
    expect(find.textContaining('4.9'), findsOneWidget, reason: 'rating average');
    // En-route uses the design's customer-directed tracking copy, not the lifecycle label.
    expect(find.text('กำลังเดินทางมาหาคุณ'), findsOneWidget,
        reason: 'status chip');
    expect(find.text('ตำแหน่งสด'), findsOneWidget, reason: 'is_live freshness');
    expect(find.textContaining('ความแม่นยำ'), findsOneWidget);
    expect(find.textContaining('ห่างจากคุณ'), findsOneWidget,
        reason: 'distance from reference');
    expect(find.text('หมู่บ้านลัดดารมย์ ซ.5'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a WS status push updates the chip and re-pulls the snapshot',
      (tester) async {
    final feed = FakeBookingFeed();
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      return locationJson();
    });

    await tester.pumpWidget(host(api: api, feed: feed));
    await settle(tester);
    expect(find.text('กำลังเดินทางมาหาคุณ'), findsOneWidget);

    feed.emit(BookingStatusEvent(
        bookingId: 'b1',
        status: BookingStatus.arrived,
        occurredAt: DateTime.utc(2026)));
    await settle(tester);

    expect(find.text('ถึงจุดนัดหมาย'), findsOneWidget,
        reason: 'arrived chip after the push');
    expect(
        api.calls.where((c) => c == 'GET /guards/g1/location').length, 2,
        reason: 'event-driven snapshot refresh — exactly one per push');
    expect(api.calls.where((c) => c == 'GET /bookings/b1').length, 1,
        reason: 'the booking REST is never polled');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no guard assigned → searching overlay, no marker',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') {
        return bookingJson(guardId: null, status: 'requested');
      }
      // The info panel's chat entry overlays an unread badge (one conversations fetch).
      if (path == '/conversations') return <Map<String, dynamic>>[];
      fail('unexpected GET $path');
    });

    await tester.pumpWidget(host(api: api));
    await settle(tester);

    expect(find.byIcon(Icons.shield), findsNothing);
    // Exact overlay text (the status chip also says 'กำลังค้นหาเจ้าหน้าที่' for `requested`).
    expect(find.text('กำลังค้นหาเจ้าหน้าที่…'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('404 (no fix yet) → no-signal overlay instead of an error',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      throw const ApiException(message: 'not found', statusCode: 404);
    });

    await tester.pumpWidget(host(api: api));
    await settle(tester);

    expect(find.textContaining('ยังไม่มีสัญญาณตำแหน่ง'), findsOneWidget);
    expect(find.byIcon(Icons.shield), findsNothing);
    expect(find.text('ไม่มีตำแหน่งสด'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stale fix shows last-seen instead of LIVE', (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      return locationJson(live: false);
    });

    await tester.pumpWidget(host(api: api));
    await settle(tester);

    expect(find.text('ตำแหน่งสด'), findsNothing);
    expect(find.textContaining('อัปเดตล่าสุด'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('EN locale renders the English strings', (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      return locationJson();
    });

    await tester
        .pumpWidget(host(api: api, prefs: const {'pg_locale': 'en'}));
    await settle(tester);

    expect(find.text('On the way to you'), findsOneWidget);
    expect(find.text('Live position'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.textContaining('from you'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'no profile name → generic role label + person avatar (never a fake name)',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      if (path == '/guards/g1/location') return locationJson();
      if (path == '/guards/g1/public') {
        return publicJson(fullName: null, years: null);
      }
      if (path == '/guards/g1/ratings') return ratingsJson();
      if (path == '/conversations') return <Map<String, dynamic>>[];
      fail('unexpected GET $path');
    });

    await tester.pumpWidget(host(api: api));
    await settle(tester);

    expect(find.text('เจ้าหน้าที่รักษาความปลอดภัย'), findsOneWidget,
        reason: 'generic role label — never a fabricated name');
    expect(find.byIcon(Icons.person), findsOneWidget,
        reason: 'avatar placeholder (not a fake photo, not the brand shield)');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no visible reviews → "ยังไม่มีรีวิว" (never a fake 0.0)',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      if (path == '/guards/g1/location') return locationJson();
      if (path == '/guards/g1/public') return publicJson();
      if (path == '/guards/g1/ratings') {
        return ratingsJson(average: null, count: 0);
      }
      if (path == '/conversations') return <Map<String, dynamic>>[];
      fail('unexpected GET $path');
    });

    await tester.pumpWidget(host(api: api));
    await settle(tester);

    expect(find.text('ยังไม่มีรีวิว'), findsOneWidget);
    expect(find.textContaining('0.0'), findsNothing,
        reason: 'never fabricate a 0.0 rating');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'booking with a pinned coordinate → "ปลายทาง" marker + distance from the '
      'destination, and NEVER a fabricated ETA in minutes', (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') {
        return bookingJson(guardId: 'g1', lat: 13.80, lng: 100.60);
      }
      if (path == '/guards/g1/location') return locationJson();
      if (path == '/guards/g1/public') return publicJson();
      if (path == '/guards/g1/ratings') return ratingsJson();
      if (path == '/conversations') return <Map<String, dynamic>>[];
      fail('unexpected GET $path');
    });

    await tester.pumpWidget(host(api: api));
    await settle(tester);

    expect(find.text('ปลายทาง'), findsOneWidget,
        reason: 'the marker labels the booking pin as the destination');
    expect(find.text('คุณ'), findsNothing,
        reason: 'the device-fix label is not used when a pin exists');
    expect(find.textContaining('ห่างจากจุดหมายประมาณ'), findsOneWidget,
        reason: 'straight-line fallback → approximate "ประมาณ" wording');
    expect(find.textContaining('นาที'), findsNothing,
        reason: 'no routing service → distance only, never a fake ETA');
    // No route → the straight 2-point fallback segment is drawn.
    expect(polylinePointCount(tester), 2,
        reason: 'fallback: the straight guard→destination segment');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'REAL route: the customer map draws the multi-point road line + the road '
      'distance with NO "ประมาณ" (matches the guard nav)', (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') {
        return bookingJson(guardId: 'g1', lat: 13.80, lng: 100.60);
      }
      if (path == '/guards/g1/location') return locationJson();
      if (path == '/guards/g1/public') return publicJson();
      if (path == '/guards/g1/ratings') return ratingsJson();
      if (path == '/conversations') return <Map<String, dynamic>>[];
      fail('unexpected GET $path');
    });

    await tester.pumpWidget(host(api: api, route: routeResult()));
    await settle(tester);

    // The map draws the full 4-point OSRM road geometry, not the 2-point straight line — the
    // guard pin then animates along this real road line as its position updates.
    expect(polylinePointCount(tester), 4,
        reason: 'real road polyline reused from the shared guardRouteProvider');
    // The road distance (6 km) is exact → no "ประมาณ" hedge, and the routed wording is used.
    expect(find.textContaining('ระยะตามถนน'), findsOneWidget,
        reason: 'routed → real road distance label');
    expect(find.textContaining('ประมาณ'), findsNothing,
        reason: 'a routed distance is exact — no approximate cue');
    expect(find.textContaining('6.0 กม.'), findsOneWidget,
        reason: 'the OSRM road distance, not the straight-line haversine');

    await tester.pumpWidget(const SizedBox());
  });
}
