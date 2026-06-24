import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/guard_route_controller.dart';
import 'package:pguard_mobile/core/models/geo.dart';

void main() {
  group('snapOrigin (~100 m grid for the route-cache key)', () {
    test('two fixes inside the same ~100 m cell snap to the SAME key (no re-fetch)', () {
      // ~15 m apart (a typical movement-gated GPS tick) → same 3-dp cell.
      final a = snapOrigin(const GeoPoint(13.75631, 100.50181));
      final b = snapOrigin(const GeoPoint(13.75639, 100.50189));
      expect(a, b);
    });

    test('a fix in a different cell snaps to a DIFFERENT key (re-fetch fires)', () {
      final a = snapOrigin(const GeoPoint(13.7563, 100.5018));
      final b = snapOrigin(const GeoPoint(13.7600, 100.5060)); // ~hundreds of m away
      expect(a, isNot(b));
    });

    test('snaps to 3 decimal places', () {
      final p = snapOrigin(const GeoPoint(13.756312, 100.501876));
      expect(p.lat, 13.756);
      expect(p.lng, 100.502);
    });
  });

  group('snapDest (≈1 m, 5 dp)', () {
    test('rounds to 5 decimal places', () {
      final p = snapDest(const GeoPoint(13.7501234, 100.5001987));
      expect(p.lat, 13.75012);
      expect(p.lng, 100.5002);
    });
  });
}
