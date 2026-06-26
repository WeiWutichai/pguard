import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/location/routing_service.dart';
import 'package:pguard_mobile/core/models/geo.dart';

/// Behaviour tests for the LIVE [OsrmRoutingService] (now routing THROUGH the api-gateway OSRM
/// proxy), distinct from the pure [RouteResult.fromOsrm] parsing tests. We drive a scriptable Dio
/// adapter so no real network is hit, asserting:
///  - the request targets the gateway `{base}/v1/osrm/route/v1/driving/{lon},{lat};{lon},{lat}` URL
///    (lon FIRST) with the `overview=full&geometries=geojson` query and a sample geojson parses;
///  - the access token is attached as `Authorization: Bearer <token>` (the proxy is token-gated);
///  - a transient failure is served from the per-leg SUCCESS cache (not blanked);
///  - a genuine failure (request fails, nothing cached) returns null for the straight-line fallback;
///  - the service never throws.
///
/// NOTE: the in-app primary/mirror host list is GONE — the gateway owns that failover now, so this
/// client only ever talks to ONE host (the VPS).
void main() {
  const origin = GeoPoint(13.7563, 100.5018);
  const dest = GeoPoint(13.7367, 100.5331);
  const base = 'http://gateway.test';

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
    Future<String?> Function()? tokenProvider,
  }) {
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500))
      ..httpClientAdapter = _StubAdapter(handler);
    return OsrmRoutingService(
      dio: dio,
      baseUrl: '$base/v1/osrm',
      tokenProvider: tokenProvider ?? () async => 'access-token',
    );
  }

  test('builds the gateway /v1/osrm URL with the geojson query and parses the body', () async {
    Uri? seenUri;
    final svc = serviceWith((o) async {
      seenUri = o.uri;
      return _json(200, okBody());
    });

    final r = await svc.route(origin: origin, dest: dest);

    expect(r, isNotNull);
    expect(r!.distanceMeters, 4200.0);
    expect(r.polyline.length, 3);

    // Targets the gateway OSRM proxy, lon FIRST in each coordinate, /route/v1/driving path.
    expect(seenUri, isNotNull);
    expect(seenUri!.path, '/v1/osrm/route/v1/driving/'
        '${origin.lng},${origin.lat};${dest.lng},${dest.lat}');
    expect(seenUri!.queryParameters['overview'], 'full');
    expect(seenUri!.queryParameters['geometries'], 'geojson');
  });

  test('attaches the access token as Authorization: Bearer (the proxy is token-gated)', () async {
    String? seenAuth;
    final svc = serviceWith(
      (o) async {
        seenAuth = o.headers['Authorization'] as String?;
        return _json(200, okBody());
      },
      tokenProvider: () async => 'tok-123',
    );

    final r = await svc.route(origin: origin, dest: dest);
    expect(r, isNotNull);
    expect(seenAuth, 'Bearer tok-123');
  });

  test('sends no Authorization header when there is no session token', () async {
    var sawHeader = true;
    final svc = serviceWith(
      (o) async {
        sawHeader = o.headers.containsKey('Authorization');
        return _json(200, okBody());
      },
      tokenProvider: () async => null,
    );
    await svc.route(origin: origin, dest: dest);
    expect(sawHeader, isFalse, reason: 'no token → no Authorization header');
  });

  test('a transient failure is served from the success cache (not blanked)', () async {
    var fail = false;
    final svc = serviceWith((o) async {
      if (fail) {
        throw DioException(
            requestOptions: o, type: DioExceptionType.connectionError);
      }
      return _json(200, okBody());
    });

    // First call succeeds and primes the per-leg cache.
    final first = await svc.route(origin: origin, dest: dest);
    expect(first, isNotNull);

    // Now the gateway request fails — the SAME leg must still resolve to the cached road route.
    fail = true;
    final second = await svc.route(origin: origin, dest: dest);
    expect(second, isNotNull, reason: 'cached route should survive a transient blip');
    expect(second!.distanceMeters, first!.distanceMeters);
  });

  test('returns null when the request fails and nothing is cached (straight-line fallback)',
      () async {
    final svc = serviceWith((o) async => throw DioException(
        requestOptions: o, type: DioExceptionType.connectionError));
    final r = await svc.route(origin: origin, dest: dest);
    expect(r, isNull);
  });

  test('never throws even on a 5xx from the gateway', () async {
    final svc = serviceWith((o) async => _json(503, 'upstream down'));
    // 503 is >=500 → Dio raises (validateStatus<500), caught internally → null, no throw.
    final r = await svc.route(origin: origin, dest: dest);
    expect(r, isNull);
  });

  test('a 401/429 from the gateway degrades to null (4xx parses to null, no throw)', () async {
    final svc = serviceWith((o) async => _json(401, {'error': 'Unauthorized'}));
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
