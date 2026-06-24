import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/location/routing_service.dart';
import 'package:pguard_mobile/core/models/geo.dart';

/// A captured-shape OSRM `route/v1/driving` response: `geometry.coordinates` as [lon, lat] pairs
/// (lon FIRST — GeoJSON order), `distance` in metres (along roads), `duration` in seconds.
Map<String, dynamic> _osrmSample() => {
      'code': 'Ok',
      'routes': [
        {
          'distance': 3200.5,
          'duration': 600.0, // 10 min driving
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [100.5018, 13.7563], // [lon, lat] — Bangkok-ish
              [100.5100, 13.7600],
              [100.5200, 13.7650],
            ],
          },
        },
      ],
      'waypoints': const [],
    };

void main() {
  group('RouteResult.fromOsrm', () {
    test('parses geometry as lat/lng (coordinates are [lon, lat]) + distance + duration', () {
      final r = RouteResult.fromOsrm(_osrmSample());
      expect(r, isNotNull);
      expect(r!.distanceMeters, 3200.5);
      expect(r.drivingSeconds, 600.0);
      expect(r.polyline.length, 3);
      // First coordinate [100.5018, 13.7563] → GeoPoint(lat: 13.7563, lng: 100.5018).
      expect(r.polyline.first.lat, 13.7563);
      expect(r.polyline.first.lng, 100.5018);
      expect(r.polyline.last.lat, 13.7650);
      expect(r.polyline.last.lng, 100.5200);
    });

    test('returns null on an empty routes list', () {
      expect(RouteResult.fromOsrm({'code': 'NoRoute', 'routes': const []}), isNull);
    });

    test('returns null when the body is not a map / is garbled', () {
      expect(RouteResult.fromOsrm(null), isNull);
      expect(RouteResult.fromOsrm('boom'), isNull);
      expect(RouteResult.fromOsrm(const []), isNull);
    });

    test('returns null when geometry has fewer than 2 usable points', () {
      final body = {
        'routes': [
          {
            'distance': 10.0,
            'duration': 5.0,
            'geometry': {
              'coordinates': [
                [100.5, 13.7],
              ],
            },
          },
        ],
      };
      expect(RouteResult.fromOsrm(body), isNull);
    });

    test('returns null when distance/duration are missing', () {
      final body = {
        'routes': [
          {
            'geometry': {
              'coordinates': [
                [100.5, 13.7],
                [100.6, 13.8],
              ],
            },
          },
        ],
      };
      expect(RouteResult.fromOsrm(body), isNull);
    });

    test('skips garbled coordinate rows but keeps the route when ≥2 remain', () {
      final body = {
        'routes': [
          {
            'distance': 100.0,
            'duration': 50.0,
            'geometry': {
              'coordinates': [
                [100.5, 13.7],
                ['bad'], // dropped
                [100.6, 13.8],
                [100.7, 13.9],
              ],
            },
          },
        ],
      };
      final r = RouteResult.fromOsrm(body);
      expect(r, isNotNull);
      expect(r!.polyline.length, 3); // the 'bad' row was skipped
    });
  });

  group('TravelMode.durationSeconds / etaMinutes', () {
    // 6000 m of road, OSRM driving = 600 s (10 min).
    final route = RouteResult.fromOsrm({
      'routes': [
        {
          'distance': 6000.0,
          'duration': 600.0,
          'geometry': {
            'coordinates': [
              [100.50, 13.75],
              [100.55, 13.80],
            ],
          },
        },
      ],
    })!;

    test('car uses the OSRM driving time directly', () {
      expect(TravelMode.car.durationSeconds(route), 600.0);
      expect(TravelMode.car.etaMinutes(route), 10);
    });

    test('motorcycle is the driving time ×0.95 (documented approximation)', () {
      expect(TravelMode.motorcycle.durationSeconds(route), closeTo(570.0, 0.001));
      // 570 s = 9.5 min → ceil to 10.
      expect(TravelMode.motorcycle.etaMinutes(route), 10);
    });

    test('walk is recomputed from road distance at ~5 km/h (much slower than driving)', () {
      // 6000 m / 1.39 m/s ≈ 4317 s ≈ 72 min — far longer than the 10-min drive.
      expect(TravelMode.walk.durationSeconds(route), closeTo(6000 / 1.39, 0.01));
      expect(TravelMode.walk.etaMinutes(route), greaterThan(TravelMode.car.etaMinutes(route)));
      expect(TravelMode.walk.etaMinutes(route), 72);
    });

    test('etaLabel carries NO tilde (real routed ETA, unlike the ~ fallback)', () {
      expect(TravelMode.car.etaLabel(route, true), '10 นาที');
      expect(TravelMode.car.etaLabel(route, false), '10 min');
      expect(TravelMode.car.etaLabel(route, true), isNot(startsWith('~')));
    });

    test('etaMinutes floors to at least 1 even for a near-zero route', () {
      final tiny = RouteResult.fromOsrm({
        'routes': [
          {
            'distance': 1.0,
            'duration': 0.0,
            'geometry': {
              'coordinates': [
                [100.50, 13.75],
                [100.50001, 13.75001],
              ],
            },
          },
        ],
      })!;
      expect(TravelMode.car.etaMinutes(tiny), 1);
      expect(TravelMode.walk.etaMinutes(tiny), 1);
    });
  });

  group('GeoPoint round-trip sanity (lon/lat ordering)', () {
    test('the parsed polyline is usable by distanceMeters (lat/lng order is right)', () {
      final r = RouteResult.fromOsrm(_osrmSample())!;
      // A Bangkok-area route should be a few km, not ~thousands (which a swapped lat/lng yields).
      final d = distanceMeters(r.polyline.first, r.polyline.last);
      expect(d, lessThan(20000));
    });
  });
}
