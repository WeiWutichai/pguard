import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/location/place_search_service.dart';
import 'package:pguard_mobile/core/models/geo.dart';

/// A captured Nominatim `/search?format=jsonv2` response (trimmed): coordinates come back as
/// STRINGS and there is a `display_name` per row.
const _searchSample = '''
[
  {
    "place_id": 12345,
    "lat": "13.7466",
    "lon": "100.5390",
    "display_name": "MBK Center, ถนนพญาไท, ปทุมวัน, กรุงเทพมหานคร, 10330, ประเทศไทย",
    "type": "mall"
  },
  {
    "place_id": 67890,
    "lat": "13.7392",
    "lon": "100.5602",
    "display_name": "Siam Paragon, ปทุมวัน, กรุงเทพมหานคร, ประเทศไทย"
  }
]
''';

void main() {
  group('PlaceResult.fromNominatim', () {
    test('parses lat/lon (string) + display_name into a GeoPoint result', () {
      final r = PlaceResult.fromNominatim({
        'lat': '13.7466',
        'lon': '100.5390',
        'display_name': 'MBK Center, กรุงเทพมหานคร',
      });
      expect(r, isNotNull);
      expect(r!.displayName, 'MBK Center, กรุงเทพมหานคร');
      expect(r.point.lat, closeTo(13.7466, 1e-9));
      expect(r.point.lng, closeTo(100.5390, 1e-9));
    });

    test('accepts numeric lat/lon too', () {
      final r = PlaceResult.fromNominatim({
        'lat': 13.5,
        'lon': 100.1,
        'display_name': 'x',
      });
      expect(r, isNotNull);
      expect(r!.point, const GeoPoint(13.5, 100.1));
    });

    test('returns null on missing/garbled coordinates', () {
      expect(
          PlaceResult.fromNominatim(
              {'lat': 'nope', 'lon': '100', 'display_name': 'x'}),
          isNull);
      expect(
          PlaceResult.fromNominatim({'lon': '100', 'display_name': 'x'}),
          isNull);
    });

    test('returns null on missing/empty display_name', () {
      expect(
          PlaceResult.fromNominatim(
              {'lat': '13', 'lon': '100', 'display_name': ''}),
          isNull);
      expect(PlaceResult.fromNominatim({'lat': '13', 'lon': '100'}), isNull);
    });
  });

  group('PlaceResult.listFromNominatim', () {
    test('parses a full search response array', () {
      final list = PlaceResult.listFromNominatim(jsonDecode(_searchSample));
      expect(list, hasLength(2));
      expect(list.first.displayName, startsWith('MBK Center'));
      expect(list.first.point.lat, closeTo(13.7466, 1e-9));
      expect(list[1].displayName, startsWith('Siam Paragon'));
    });

    test('drops malformed rows but keeps the good ones', () {
      final list = PlaceResult.listFromNominatim([
        {'lat': '13.7', 'lon': '100.5', 'display_name': 'good'},
        {'lat': 'bad', 'lon': '100.5', 'display_name': 'dropped'},
        'not even a map',
      ]);
      expect(list, hasLength(1));
      expect(list.single.displayName, 'good');
    });

    test('non-list body → empty', () {
      expect(PlaceResult.listFromNominatim({'oops': true}), isEmpty);
      expect(PlaceResult.listFromNominatim(null), isEmpty);
    });
  });

  group('PlaceResult.nameFromReverse', () {
    test('extracts display_name from a /reverse object', () {
      final name = PlaceResult.nameFromReverse({
        'display_name': '99 ถนนสุขุมวิท, วัฒนา, กรุงเทพมหานคร',
        'lat': '13.73',
        'lon': '100.56',
      });
      expect(name, '99 ถนนสุขุมวิท, วัฒนา, กรุงเทพมหานคร');
    });

    test('null when display_name is absent/empty or body is wrong shape', () {
      expect(PlaceResult.nameFromReverse({'display_name': ''}), isNull);
      expect(PlaceResult.nameFromReverse({'error': 'Unable to geocode'}), isNull);
      expect(PlaceResult.nameFromReverse('nope'), isNull);
    });
  });

  test('toGeoPlace carries the name + coordinate', () {
    const r = PlaceResult(
        displayName: 'Somewhere', point: GeoPoint(13.0, 100.0));
    final gp = r.toGeoPlace();
    expect(gp.placeName, 'Somewhere');
    expect(gp.point, const GeoPoint(13.0, 100.0));
  });
}
