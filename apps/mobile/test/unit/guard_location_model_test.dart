import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/tracking.dart';

Map<String, dynamic> locationJson() => {
      'guard_id': 'g1',
      'lat': 13.7563,
      'lng': 100.5018,
      'accuracy': 12.5,
      'heading': 270.0,
      'speed': 1.4,
      'recorded_at': '2026-06-10T10:30:45Z',
      'is_online': true,
      'is_live': true,
    };

void main() {
  test('GuardLocation.fromJson parses the full presence contract shape', () {
    final loc = GuardLocation.fromJson(locationJson());
    expect(loc.guardId, 'g1');
    expect(loc.lat, 13.7563);
    expect(loc.lng, 100.5018);
    expect(loc.accuracy, 12.5);
    expect(loc.heading, 270.0);
    expect(loc.speed, 1.4);
    expect(loc.recordedAt, DateTime.utc(2026, 6, 10, 10, 30, 45));
    expect(loc.isOnline, isTrue);
    expect(loc.isLive, isTrue);
    expect(loc.point.lat, 13.7563);
  });

  test('nullable fields parse as null and freshness flags default to false',
      () {
    final json = locationJson()
      ..remove('accuracy')
      ..remove('heading')
      ..remove('speed')
      ..remove('is_online')
      ..remove('is_live');
    final loc = GuardLocation.fromJson(json);
    expect(loc.accuracy, isNull);
    expect(loc.heading, isNull);
    expect(loc.speed, isNull);
    expect(loc.isOnline, isFalse);
    expect(loc.isLive, isFalse);
  });

  test('tryParse rejects non-map and malformed bodies', () {
    expect(GuardLocation.tryParse(null), isNull);
    expect(GuardLocation.tryParse('nope'), isNull);
    expect(GuardLocation.tryParse(<String, dynamic>{}), isNull);
    expect(GuardLocation.tryParse({'guard_id': 'g1', 'lat': 'x', 'lng': 1.0}),
        isNull);
    expect(GuardLocation.tryParse(locationJson()), isNotNull);
  });
}
