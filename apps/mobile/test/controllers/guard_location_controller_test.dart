import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/guard_location_controller.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/models/geo.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson({
  String? guardId,
  String status = 'accepted',
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

Map<String, dynamic> locationJson(double lat) => {
      'guard_id': 'g1',
      'lat': lat,
      'lng': 100.5018,
      'accuracy': 8.0,
      'recorded_at': '2026-06-10T10:30:45Z',
      'is_online': true,
      'is_live': true,
    };

Map<String, dynamic> publicJson() => {
      'user_id': 'g1',
      'full_name': 'ณัฐพล วงศ์ดี',
      'years_of_experience': 7,
    };

Map<String, dynamic> ratingsJson({String? average = '4.9', int count = 12}) => {
      'guard_id': 'g1',
      'average': average,
      'count': count,
      'reviews': <Map<String, dynamic>>[],
    };

({
  ProviderContainer c,
  FakeBookingFeed feed,
  FakeApi api,
  FakeLocationService loc,
}) make({
  required Future<dynamic> Function(String path, Map<String, dynamic>? query)
      onGet,
}) {
  final feed = FakeBookingFeed();
  final loc = FakeLocationService();
  final api = FakeApi(onGet: onGet);
  final c = ProviderContainer(overrides: [
    pguardApiProvider.overrideWithValue(api),
    appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    bookingStatusFeedBuilderProvider.overrideWithValue((id, tp) => feed),
    locationServiceProvider.overrideWithValue(loc),
  ]);
  addTearDown(c.dispose);
  return (c: c, feed: feed, api: api, loc: loc);
}

int locationGets(FakeApi api) =>
    api.calls.where((c) => c == 'GET /guards/g1/location').length;

void main() {
  test(
      'one snapshot per trigger: build fetches once, each WS status push '
      'refetches once — and the booking REST is never re-pulled (NO polling)',
      () async {
    var lat = 13.70;
    final t = make(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      if (path == '/guards/g1/location') return locationJson(lat += 0.01);
      if (path == '/guards/g1/public') return publicJson();
      if (path == '/guards/g1/ratings') return ratingsJson();
      fail('unexpected GET $path');
    });

    final sub =
        t.c.listen(guardLocationControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    final track = await t.c.read(guardLocationControllerProvider('b1').future);
    expect(track.guard?.lat, closeTo(13.71, 1e-9));
    expect(track.status, BookingStatus.accepted);
    expect(track.reference, GeoPoint.bangkok,
        reason: 'device fix is the fallback target (no booking pin)');
    expect(track.profile?.fullName, 'ณัฐพล วงศ์ดี',
        reason: 'public mini-profile enriches the track');
    expect(track.ratings?.hasRatings, isTrue);
    expect(locationGets(t.api), 1);

    // A pushed status frame (guard_en_route) re-runs the build → ONE fresh snapshot.
    t.feed.emit(BookingStatusEvent(
        bookingId: 'b1',
        status: BookingStatus.enRoute,
        occurredAt: DateTime.utc(2026)));
    await Future<void>.delayed(Duration.zero);
    final updated =
        await t.c.read(guardLocationControllerProvider('b1').future);
    expect(updated.status, BookingStatus.enRoute);
    expect(updated.guard?.lat, closeTo(13.72, 1e-9),
        reason: 'event-driven snapshot refresh picked up the new fix');
    expect(locationGets(t.api), 2);

    // The booking snapshot itself was fetched exactly once (status came from the push).
    expect(t.api.calls.where((c) => c == 'GET /bookings/b1').length, 1);

    // Distance guard ↔ target is derived in the model (no widget math).
    expect(updated.distanceToTarget, isNotNull);
  });

  test(
      'booking with a pinned coordinate → the destination is the booking pin '
      '(not the device fix), and distance is measured to it', () async {
    final t = make(onGet: (path, _) async {
      if (path == '/bookings/b1') {
        return bookingJson(guardId: 'g1', lat: 13.80, lng: 100.60);
      }
      if (path == '/guards/g1/location') return locationJson(13.70);
      if (path == '/guards/g1/public') return publicJson();
      if (path == '/guards/g1/ratings') return ratingsJson();
      fail('unexpected GET $path');
    });
    final sub = t.c.listen(guardLocationControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    final track = await t.c.read(guardLocationControllerProvider('b1').future);
    expect(track.destination, const GeoPoint(13.80, 100.60));
    expect(track.target, const GeoPoint(13.80, 100.60),
        reason: 'the pinned destination wins over the device fix');
    expect(track.targetIsDestination, isTrue);
    expect(
      track.distanceToTarget,
      closeTo(
        distanceMeters(
            const GeoPoint(13.70, 100.5018), const GeoPoint(13.80, 100.60)),
        1,
      ),
      reason: 'distance is guard→destination, not guard→device',
    );
  });

  test(
      'booking with no pinned coordinate → falls back to the device fix as the '
      'target (legacy/address-only booking)', () async {
    final t = make(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      if (path == '/guards/g1/location') return locationJson(13.70);
      if (path == '/guards/g1/public') return publicJson();
      if (path == '/guards/g1/ratings') return ratingsJson();
      fail('unexpected GET $path');
    });
    final sub = t.c.listen(guardLocationControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    final track = await t.c.read(guardLocationControllerProvider('b1').future);
    expect(track.destination, isNull);
    expect(track.target, GeoPoint.bangkok,
        reason: 'device fix is the fallback target');
    expect(track.targetIsDestination, isFalse);
  });

  test(
      'a half-null coordinate (lat without lng — contract violation) is NOT a '
      'destination; falls back to the device fix', () async {
    final t = make(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1', lat: 13.80);
      if (path == '/guards/g1/location') return locationJson(13.70);
      if (path == '/guards/g1/public') return publicJson();
      if (path == '/guards/g1/ratings') return ratingsJson();
      fail('unexpected GET $path');
    });
    final sub = t.c.listen(guardLocationControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    final track = await t.c.read(guardLocationControllerProvider('b1').future);
    expect(track.destination, isNull,
        reason: 'both-or-neither: a lone lat is not a usable pin');
    expect(track.targetIsDestination, isFalse);
    expect(track.target, GeoPoint.bangkok);
  });

  test(
      'profile/ratings enrichment degrades to null on error without erroring '
      'the screen (the core location read still succeeds)', () async {
    final t = make(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      if (path == '/guards/g1/location') return locationJson(13.75);
      if (path == '/guards/g1/public') {
        throw const ApiException(message: 'no active booking', statusCode: 403);
      }
      if (path == '/guards/g1/ratings') {
        throw const ApiException(message: 'boom', statusCode: 500);
      }
      fail('unexpected GET $path');
    });
    final sub = t.c.listen(guardLocationControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    final track = await t.c.read(guardLocationControllerProvider('b1').future);
    expect(track.profile, isNull, reason: '403 enrichment degrades, no rethrow');
    expect(track.ratings, isNull, reason: '500 enrichment degrades, no rethrow');
    expect(track.guard, isNotNull, reason: 'core location read still succeeded');
  });

  test('no guard assigned → no location fetch; assignment event starts it',
      () async {
    final t = make(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: null);
      if (path == '/guards/g1/location') return locationJson(13.75);
      if (path == '/guards/g1/public') return publicJson();
      if (path == '/guards/g1/ratings') return ratingsJson();
      fail('unexpected GET $path');
    });

    final sub = t.c.listen(guardLocationControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    final track = await t.c.read(guardLocationControllerProvider('b1').future);
    expect(track.guard, isNull);
    expect(track.guardId, isNull);
    expect(locationGets(t.api), 0, reason: 'nothing to fetch yet');

    // Guard gets assigned via the push → the next build fetches the location.
    t.feed.emit(BookingStatusEvent(
        bookingId: 'b1',
        status: BookingStatus.accepted,
        occurredAt: DateTime.utc(2026),
        guardId: 'g1'));
    await Future<void>.delayed(Duration.zero);
    final assigned =
        await t.c.read(guardLocationControllerProvider('b1').future);
    expect(assigned.guard?.guardId, 'g1');
    expect(locationGets(t.api), 1);
  });

  test('404 (no fix recorded) and 403 (booking not active) degrade to '
      'guard=null instead of erroring the screen', () async {
    var status = 404;
    final t = make(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      throw ApiException(message: 'nope', statusCode: status);
    });

    final sub = t.c.listen(guardLocationControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    final track = await t.c.read(guardLocationControllerProvider('b1').future);
    expect(track.guard, isNull);
    expect(track.booking.address, 'หมู่บ้านลัดดารมย์ ซ.5',
        reason: 'the rest of the state still renders');

    status = 403;
    await t.c.read(guardLocationControllerProvider('b1').notifier).refresh();
    expect(
        t.c.read(guardLocationControllerProvider('b1')).value?.guard, isNull);
  });

  test('other API failures surface as errors (screen shows retry)', () async {
    final t = make(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      throw const ApiException(message: 'boom', statusCode: 500);
    });
    final sub = t.c.listen(guardLocationControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);
    await expectLater(t.c.read(guardLocationControllerProvider('b1').future),
        throwsA(isA<ApiException>()));
  });

  test('refresh() is a one-shot gesture re-pull', () async {
    final t = make(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      return locationJson(13.75);
    });
    final sub = t.c.listen(guardLocationControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    await t.c.read(guardLocationControllerProvider('b1').future);
    expect(locationGets(t.api), 1);
    await t.c.read(guardLocationControllerProvider('b1').notifier).refresh();
    expect(locationGets(t.api), 2);
  });

  test('refresh() while the backend keeps failing does NOT rethrow into the '
      'fire-and-forget button handler (state carries the error)', () async {
    var failNow = false;
    final t = make(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      if (failNow) {
        throw const ApiException(message: 'boom', statusCode: 500);
      }
      return locationJson(13.75);
    });
    final sub = t.c.listen(guardLocationControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    await t.c.read(guardLocationControllerProvider('b1').future);
    failNow = true;
    await t.c
        .read(guardLocationControllerProvider('b1').notifier)
        .refresh(); // must complete normally
    expect(
        t.c.read(guardLocationControllerProvider('b1')).hasError, isTrue);
  });

  test('dispose cleans up: the booking feed closes and no further fetches run',
      () async {
    final t = make(onGet: (path, _) async {
      if (path == '/bookings/b1') return bookingJson(guardId: 'g1');
      return locationJson(13.75);
    });
    final sub = t.c.listen(guardLocationControllerProvider('b1'), (_, __) {});
    await t.c.read(guardLocationControllerProvider('b1').future);
    final fetchesBeforeDispose = t.api.calls.length;

    sub.close();
    t.c.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(t.feed.closed, isTrue,
        reason: 'watch chain released → booking WS closed (ref.onDispose)');
    expect(t.api.calls.length, fetchesBeforeDispose,
        reason: 'nothing fetches after dispose');
  });
}
