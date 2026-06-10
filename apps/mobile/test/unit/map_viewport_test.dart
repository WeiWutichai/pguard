import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/geo.dart';

void main() {
  group('MapViewport.fit', () {
    test('empty input falls back to Bangkok at the default span', () {
      final vp = MapViewport.fit(const []);
      expect(vp.center, GeoPoint.bangkok);
      expect(vp.span, MapViewport.defaultSpan);
    });

    test('a single point centres on it with the minimum span', () {
      const p = GeoPoint(13.70, 100.50);
      final vp = MapViewport.fit(const [p], minSpan: 0.012);
      expect(vp.center, p);
      expect(vp.span, 0.012);
    });

    test('two points centre on the midpoint and span the padded extent', () {
      const a = GeoPoint(13.70, 100.50);
      const b = GeoPoint(13.72, 100.52);
      final vp = MapViewport.fit(const [a, b], paddingFactor: 1.5);
      expect(vp.center.lat, closeTo(13.71, 1e-9));
      expect(vp.center.lng, closeTo(100.51, 1e-9));
      expect(vp.span, closeTo(0.02 * 1.5, 1e-9));
    });
  });

  group('MapViewport.fractionFor', () {
    const vp = MapViewport(center: GeoPoint(13.75, 100.50), span: 0.02);

    test('the centre maps to the canvas centre', () {
      final f = vp.fractionFor(const GeoPoint(13.75, 100.50));
      expect(f.x, closeTo(0.5, 1e-9));
      expect(f.y, closeTo(0.5, 1e-9));
    });

    test('north/east of centre maps up/right (y down-positive)', () {
      final f = vp.fractionFor(const GeoPoint(13.755, 100.505));
      expect(f.x, closeTo(0.75, 1e-9));
      expect(f.y, closeTo(0.25, 1e-9));
    });

    test('a far-away point clamps inside the canvas inset', () {
      final f = vp.fractionFor(const GeoPoint(14.5, 99.0), inset: 0.07);
      expect(f.x, 0.07);
      expect(f.y, 0.07);
    });
  });

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
