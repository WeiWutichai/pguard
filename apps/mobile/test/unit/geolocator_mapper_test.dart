import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pguard_mobile/core/location/geolocator_location_service.dart';
import 'package:pguard_mobile/core/models/geo.dart';
import 'package:pguard_mobile/core/models/tracking.dart';

/// A `Position` with only the fields the mapper reads set; the rest are filled with neutral
/// defaults (geolocator requires them all).
Position _pos({
  required double lat,
  required double lng,
  required double accuracy,
  DateTime? ts,
}) =>
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: ts ?? DateTime.utc(2026, 6, 18, 10, 30),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  group('sampleFromPosition', () {
    test('maps lat/lng/timestamp 1:1; recordedAt is UTC', () {
      final s =
          sampleFromPosition(_pos(lat: 13.123456, lng: 100.654321, accuracy: 8));
      expect(s.lat, 13.123456);
      expect(s.lng, 100.654321);
      expect(s.recordedAt.isUtc, isTrue);
    });

    test('accuracy 12 → preserved → medium band', () {
      final s = sampleFromPosition(_pos(lat: 0, lng: 0, accuracy: 12));
      expect(s.accuracy, 12);
      expect(GpsAccuracyBand.of(s.accuracy), GpsAccuracyBand.medium);
    });

    test('accuracy 8 → high band', () {
      final s = sampleFromPosition(_pos(lat: 0, lng: 0, accuracy: 8));
      expect(GpsAccuracyBand.of(s.accuracy), GpsAccuracyBand.high);
    });

    test('accuracy 0 (unreported) → null → unknown band (not a fake "high")', () {
      final s = sampleFromPosition(_pos(lat: 0, lng: 0, accuracy: 0));
      expect(s.accuracy, isNull);
      expect(GpsAccuracyBand.of(s.accuracy), GpsAccuracyBand.unknown);
    });

    test('accuracy -1 (invalid fix) → null → unknown band', () {
      final s = sampleFromPosition(_pos(lat: 0, lng: 0, accuracy: -1));
      expect(s.accuracy, isNull);
      expect(GpsAccuracyBand.of(s.accuracy), GpsAccuracyBand.unknown);
    });

    test('coordinate precision survives toFrame() (≥5 dp, no rounding)', () {
      final s =
          sampleFromPosition(_pos(lat: 13.123456, lng: 100.654321, accuracy: 5));
      final frame = s.toFrame();
      expect(frame['lat'], 13.123456);
      expect(frame['lng'], 100.654321);
      expect(frame['type'], 'location');
    });
  });

  test('pointFromPosition → GeoPoint with the same coordinate', () {
    final p = pointFromPosition(_pos(lat: 13.75, lng: 100.50, accuracy: 5));
    expect(p, const GeoPoint(13.75, 100.50));
  });
}
