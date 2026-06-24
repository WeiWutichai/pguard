import 'package:dio/dio.dart';

import '../models/geo.dart';

/// A REAL road route between two coordinates: the road-following polyline plus the road distance
/// and the OSRM-computed driving time. The per-mode ETA is derived from these (see
/// [TravelMode.durationSeconds]); the geometry is the same for every mode (the public OSRM demo
/// only serves the `driving` profile). Pure value type — parsing is unit-testable from a captured
/// sample, no I/O here.
class RouteResult {
  const RouteResult({
    required this.polyline,
    required this.distanceMeters,
    required this.drivingSeconds,
  });

  /// The route geometry as a list of [GeoPoint]s following the roads (≥2 points). Drawn through
  /// [PgPolyline] in place of the straight 2-point segment.
  final List<GeoPoint> polyline;

  /// The road distance in metres (along the route), NOT the straight-line haversine. Shown via
  /// the shared [formatDistance].
  final double distanceMeters;

  /// OSRM's driving duration in seconds. The car ETA uses this directly; the other modes scale it
  /// or recompute from distance — see [TravelMode.durationSeconds].
  final double drivingSeconds;

  /// Parse one OSRM `route/v1` response object (the parsed JSON body). OSRM returns
  /// `routes[0].geometry.coordinates` as `[lon, lat]` pairs (lon FIRST — note the order),
  /// `routes[0].distance` (metres) and `routes[0].duration` (seconds). Returns null on any
  /// missing/garbled/empty field (defensive — never throws). Pure (no I/O) so it is unit-testable
  /// from a captured sample.
  static RouteResult? fromOsrm(dynamic body) {
    if (body is! Map) return null;
    final routes = body['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final route = routes.first;
    if (route is! Map) return null;

    final distance = _toDouble(route['distance']);
    final duration = _toDouble(route['duration']);
    final geometry = route['geometry'];
    if (distance == null || duration == null || geometry is! Map) return null;

    final coords = geometry['coordinates'];
    if (coords is! List || coords.length < 2) return null;

    final points = <GeoPoint>[];
    for (final c in coords) {
      // Each coordinate is [lon, lat] (OSRM/GeoJSON order). Map to GeoPoint(lat, lng).
      if (c is! List || c.length < 2) continue;
      final lon = _toDouble(c[0]);
      final lat = _toDouble(c[1]);
      if (lat == null || lon == null) continue;
      points.add(GeoPoint(lat, lon));
    }
    if (points.length < 2) return null;

    return RouteResult(
      polyline: points,
      distanceMeters: distance,
      drivingSeconds: duration,
    );
  }

  static double? _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

/// The guard's chosen travel mode — switches ONLY the ETA label/calculation; the route geometry is
/// identical (the OSRM public demo serves the `driving` profile only, so all modes follow the same
/// driving road geometry).
enum TravelMode {
  /// รถยนต์ — uses OSRM's driving duration directly.
  car,

  /// มอเตอร์ไซค์ — there is no moto profile on the public demo, so this APPROXIMATES the moto ETA as
  /// the driving time ×0.95 (a motorcycle filters through traffic slightly faster than a car). A
  /// coarse heuristic, not a routed speed.
  motorcycle,

  /// เดิน — recomputed from the road distance at a walking pace (5 km/h ≈ 1.39 m/s); the driving
  /// duration is irrelevant on foot.
  walk;

  /// Walking pace in metres/second (5 km/h).
  static const double walkSpeedMps = 1.39;

  /// Motorcycle approximation factor applied to the driving duration.
  static const double motoFactor = 0.95;

  /// Per-mode duration in seconds, derived from a [RouteResult]. PURE + unit-tested:
  ///  - [car]:        `drivingSeconds` (OSRM's driving time)
  ///  - [motorcycle]: `drivingSeconds * 0.95` (documented approximation — no moto profile)
  ///  - [walk]:       `distanceMeters / 1.39` (5 km/h; the driving time does not apply on foot)
  double durationSeconds(RouteResult route) {
    switch (this) {
      case TravelMode.car:
        return route.drivingSeconds;
      case TravelMode.motorcycle:
        return route.drivingSeconds * motoFactor;
      case TravelMode.walk:
        return route.distanceMeters / walkSpeedMps;
    }
  }

  /// Whole-minute ETA (floored to at least 1), the value shown on the sheet. Pure.
  int etaMinutes(RouteResult route) {
    final mins = (durationSeconds(route) / 60).ceil();
    return mins < 1 ? 1 : mins;
  }

  /// "12 นาที" / "12 min" — NO tilde: this is a routed (real) ETA, distinct from the fallback's
  /// approximate "~" label (see [TravelEstimate.etaLabel] in geo.dart).
  String etaLabel(RouteResult route, bool isThai) {
    final m = etaMinutes(route);
    return isThai ? '$m นาที' : '$m min';
  }
}

/// Turn-by-turn (road-following) routing between two coordinates.
///
/// Abstracted so the navigation screen + the inline travel-map preview are testable without
/// network, and so the host or a future backend routing proxy can swap in via the provider — the
/// same pattern as [PlaceSearchService]/[LocationService]. Best-effort: an implementation NEVER
/// throws and returns null on any failure (network/timeout/no route/empty), so the caller can
/// DEGRADE to the straight-line geo.dart estimate rather than show a blank map or crash.
abstract class RoutingService {
  /// Road route from [origin] to [dest], or null when no route is available (offline / OSRM down /
  /// no route found / empty geometry). Never throws.
  Future<RouteResult?> route({required GeoPoint origin, required GeoPoint dest});
}

/// Live [RoutingService] hitting the **public OSRM demo** (`router.project-osrm.org`) — free, no
/// API key. The public demo only serves the `driving` profile, so the request is always
/// `/route/v1/driving/...`; the per-mode difference is the ETA (computed by [TravelMode]), not the
/// geometry. External host (NOT the `/v1` gateway), so — like [NominatimPlaceSearchService] — it
/// uses its own bare Dio with a timeout, not [PguardApi].
class OsrmRoutingService implements RoutingService {
  OsrmRoutingService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _base,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              // Accept any <500 so a 4xx surfaces as a null result (not an exception); the catch
              // below also guarantees null on any transport failure.
              validateStatus: (s) => s != null && s < 500,
            ));

  static const String _base = 'https://router.project-osrm.org';

  final Dio _dio;

  @override
  Future<RouteResult?> route({
    required GeoPoint origin,
    required GeoPoint dest,
  }) async {
    try {
      // OSRM expects `{lon},{lat};{lon},{lat}` (longitude FIRST). geojson geometry so we can read
      // the coordinate list directly; `overview=full` keeps every vertex for an accurate line.
      final coords =
          '${origin.lng},${origin.lat};${dest.lng},${dest.lat}';
      final res = await _dio.get<dynamic>(
        '/route/v1/driving/$coords',
        queryParameters: const {
          'overview': 'full',
          'geometries': 'geojson',
        },
      );
      return RouteResult.fromOsrm(res.data);
    } catch (_) {
      return null;
    }
  }
}
