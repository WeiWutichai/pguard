import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/tracking.dart';

void main() {
  group('GpsAccuracyBand.of', () {
    test('bands by metres', () {
      expect(GpsAccuracyBand.of(5), GpsAccuracyBand.high);
      expect(GpsAccuracyBand.of(10), GpsAccuracyBand.high);
      expect(GpsAccuracyBand.of(20), GpsAccuracyBand.medium);
      expect(GpsAccuracyBand.of(30), GpsAccuracyBand.medium);
      expect(GpsAccuracyBand.of(75), GpsAccuracyBand.low);
    });

    test('null/negative → unknown', () {
      expect(GpsAccuracyBand.of(null), GpsAccuracyBand.unknown);
      expect(GpsAccuracyBand.of(-1), GpsAccuracyBand.unknown);
    });
  });

  test('GpsSample.toFrame matches the documented presence frame', () {
    final s = GpsSample(
      lat: 13.7,
      lng: 100.5,
      accuracy: 6,
      recordedAt: DateTime.utc(2026, 6, 5, 14),
    );
    final f = s.toFrame();
    expect(f['type'], 'location');
    expect(f['lat'], 13.7);
    expect(f['lng'], 100.5);
    expect(f['accuracy'], 6);
    expect(f['recorded_at'], '2026-06-05T14:00:00.000Z');
  });

  test('GpsSample.toFrame omits accuracy when null', () {
    final f = GpsSample(lat: 1, lng: 2, recordedAt: DateTime.utc(2026)).toFrame();
    expect(f.containsKey('accuracy'), isFalse);
  });
}
