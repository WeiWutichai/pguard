import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/location/routing_service.dart';
import 'package:pguard_mobile/core/models/geo.dart';

/// Resilience tests for the LIVE [OsrmRoutingService] (network behaviour), distinct from the pure
/// [RouteResult.fromOsrm] parsing tests. We drive a scriptable Dio adapter so no real network is hit:
///  - the primary host failing falls through to the mirror,
///  - a 429 rate-limit on the primary also falls through,
///  - a transient all-hosts failure is served from the per-leg SUCCESS cache (not blanked),
///  - a genuine no-route (everything fails, nothing cached) returns null for the straight fallback,
///  - the service never throws.
void main() {
  const origin = GeoPoint(13.7563, 100.5018);
  const dest = GeoPoint(13.7367, 100.5331);

  // A minimal valid OSRM body the parser accepts (coordinates are [lon, lat]).
  Map<String, dynamic> okBody() => {
        'code': 'Ok',
        'routes': [
          {
            'distance': 4200.0,
            'duration': 700.0,
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [origin.lng, origin.lat],
                [100.5200, 13.7460],
                [dest.lng, dest.lat],
              ],
            },
          },
        ],
      };

  OsrmRoutingService serviceWith(
    Future<ResponseBody> Function(RequestOptions o) handler, {
    List<String>? mirrors,
  }) {
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500))
      ..httpClientAdapter = _StubAdapter(handler);
    return OsrmRoutingService(dio: dio, mirrors: mirrors);
  }

  test('returns the parsed road route on a primary-host success', () async {
    final svc = serviceWith((o) async => _json(200, okBody()));
    final r = await svc.route(origin: origin, dest: dest);
    expect(r, isNotNull);
    expect(r!.distanceMeters, 4200.0);
    expect(r.polyline.length, 3);
  });

  test('falls through to the mirror host when the primary throws (transient)', () async {
    var primaryHits = 0;
    var mirrorHits = 0;
    final svc = serviceWith(
      (o) async {
        if (o.uri.host == 'primary.test') {
          primaryHits++;
          throw DioException(
              requestOptions: o, type: DioExceptionType.connectionTimeout);
        }
        mirrorHits++;
        return _json(200, okBody());
      },
      mirrors: const ['https://primary.test', 'https://mirror.test'],
    );
    final r = await svc.route(origin: origin, dest: dest);
    expect(r, isNotNull, reason: 'mirror should have served the route');
    expect(primaryHits, 1);
    expect(mirrorHits, 1);
  });

  test('a 429 rate-limit on the primary falls through to the mirror', () async {
    final svc = serviceWith(
      (o) async {
        if (o.uri.host == 'primary.test') {
          // 429 is <500 → surfaces as a non-OSRM body that fails to parse (null), not an exception.
          return _json(429, {'message': 'Too Many Requests'});
        }
        return _json(200, okBody());
      },
      mirrors: const ['https://primary.test', 'https://mirror.test'],
    );
    final r = await svc.route(origin: origin, dest: dest);
    expect(r, isNotNull, reason: 'the mirror should cover a primary 429');
  });

  test('a transient all-hosts failure is served from the success cache (not blanked)', () async {
    var fail = false;
    final svc = serviceWith(
      (o) async {
        if (fail) {
          throw DioException(
              requestOptions: o, type: DioExceptionType.connectionError);
        }
        return _json(200, okBody());
      },
      mirrors: const ['https://primary.test', 'https://mirror.test'],
    );

    // First call succeeds and primes the per-leg cache.
    final first = await svc.route(origin: origin, dest: dest);
    expect(first, isNotNull);

    // Now every host fails — the SAME leg must still resolve to the cached road route.
    fail = true;
    final second = await svc.route(origin: origin, dest: dest);
    expect(second, isNotNull, reason: 'cached route should survive a transient blip');
    expect(second!.distanceMeters, first!.distanceMeters);
  });

  test('returns null when every host fails and nothing is cached (straight-line fallback)', () async {
    final svc = serviceWith(
      (o) async => throw DioException(
          requestOptions: o, type: DioExceptionType.connectionError),
      mirrors: const ['https://primary.test', 'https://mirror.test'],
    );
    final r = await svc.route(origin: origin, dest: dest);
    expect(r, isNull);
  });

  test('never throws even on a 5xx from every host', () async {
    final svc = serviceWith(
      (o) async => _json(503, 'upstream down'),
      mirrors: const ['https://primary.test', 'https://mirror.test'],
    );
    // 503 is >=500 → Dio raises (validateStatus<500), caught internally → null, no throw.
    final r = await svc.route(origin: origin, dest: dest);
    expect(r, isNull);
  });
}

/// A scriptable [HttpClientAdapter] (same shape as the api-client test) so no real network is hit.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
      body is String ? body : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
