import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/geo.dart';

void main() {
  test('TravelEstimate: sub-1km uses metre label + approximate ETA', () {
    // ~0.005° latitude ≈ 556 m.
    final e = TravelEstimate.between(
        const GeoPoint(13.75, 100.50), const GeoPoint(13.755, 100.50));
    expect(e.metres, closeTo(556, 20));
    expect(e.distanceLabel(true), endsWith(' ม.'));
    expect(e.distanceLabel(false), endsWith(' m'));
    expect(e.etaLabel(true), startsWith('~'));
    expect(e.etaLabel(true), endsWith('นาที'));
    expect(e.minutes, greaterThanOrEqualTo(1));
  });

  test('TravelEstimate: ≥1km uses kilometre label', () {
    final e = TravelEstimate.between(
        const GeoPoint(13, 100), const GeoPoint(14, 100));
    expect(e.distanceLabel(true), endsWith(' กม.'));
    expect(e.distanceLabel(false), endsWith(' km'));
    expect(e.minutes, greaterThan(1));
  });

  test('TravelEstimate: zero distance still floors the ETA to 1 minute', () {
    final e = TravelEstimate.between(
        const GeoPoint(13.75, 100.5), const GeoPoint(13.75, 100.5));
    expect(e.minutes, 1);
  });
}
