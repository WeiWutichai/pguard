import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/guard_map_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson({String? guardId, String status = 'en_route'}) =>
    {
      'id': 'b1',
      'customer_id': 'c1',
      'guard_id': guardId,
      'status': status,
      'address': 'หมู่บ้านลัดดารมย์ ซ.5',
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

Widget host({
  required FakeApi api,
  FakeBookingFeed? feed,
  FakeLocationService? loc,
  Map<String, String> prefs = const {},
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
    ],
    child: const MaterialApp(home: GuardMapScreen(bookingId: 'b1')),
  );
}

Future<void> settle(WidgetTester tester) async {
  // Three pumps: deliver the (broadcast-stream) event, run the scheduled provider rebuild
  // (async build), then render the dirty widget.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets(
      'renders the guard marker, reference marker, en-route status chip and '
      'live freshness from one snapshot', (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      if (path == '/guards/g1/location') return locationJson();
      fail('unexpected GET $path');
    });

    await tester.pumpWidget(host(api: api));
    await settle(tester);

    expect(find.byIcon(Icons.shield), findsOneWidget, reason: 'guard marker');
    expect(find.text('คุณ'), findsOneWidget, reason: 'reference marker label');
    expect(find.text('กำลังเดินทาง'), findsOneWidget, reason: 'status chip');
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
    expect(find.text('กำลังเดินทาง'), findsOneWidget);

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

    expect(find.text('On the way'), findsOneWidget);
    expect(find.text('Live position'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.textContaining('from you'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
