import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/geo.dart';

// NOTE: the old equirectangular `MapViewport` projection was removed when the hand-painted map
// backdrop was replaced by a real OpenStreetMap surface (flutter_map handles geo→screen now), so
// its tests are gone. The pure GEO helpers below (used by the live-map / navigation distance
// readouts) stay — flutter_map renders tiles, but distances are still straight-line via geo.dart.
void main() {
  group('distanceMeters', () {
    test('zero for identical points', () {
      expect(distanceMeters(GeoPoint.bangkok, GeoPoint.bangkok), 0);
    });

    test('~111km per degree of latitude', () {
      const a = GeoPoint(13.0, 100.0);
      const b = GeoPoint(14.0, 100.0);
      expect(distanceMeters(a, b), closeTo(111195, 200));
    });

    test('is symmetric', () {
      const a = GeoPoint(13.7563, 100.5018);
      const b = GeoPoint(13.7463, 100.5345);
      expect(distanceMeters(a, b), closeTo(distanceMeters(b, a), 1e-6));
    });
  });

  group('formatDistance', () {
    test('metres below 1km', () {
      expect(formatDistance(850, thai: true), '850 ม.');
      expect(formatDistance(850, thai: false), '850 m');
    });

    test('one-decimal kilometres at/above 1km', () {
      expect(formatDistance(1234, thai: true), '1.2 กม.');
      expect(formatDistance(1234, thai: false), '1.2 km');
    });
  });
}
