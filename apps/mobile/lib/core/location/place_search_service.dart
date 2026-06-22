import 'package:dio/dio.dart';

import '../models/geo.dart';

/// A single place-search hit: a human-readable name plus its coordinate. The coordinate is what
/// the booking flow sends as `lat`/`lng`; [displayName] becomes the `address`.
class PlaceResult {
  const PlaceResult({required this.displayName, required this.point});

  final String displayName;
  final GeoPoint point;

  /// As a [GeoPlace] (the picker/booking-form's value type).
  GeoPlace toGeoPlace() => GeoPlace(point: point, placeName: displayName);

  /// Parse one Nominatim `jsonv2` result object. Nominatim returns `lat`/`lon` as STRINGS and a
  /// `display_name`. Returns null when a row is missing/garbled coordinates (defensive — never
  /// throws on a single bad row). Pure (no I/O) so it is unit-testable from a captured sample.
  static PlaceResult? fromNominatim(Map<String, dynamic> json) {
    final lat = _toDouble(json['lat']);
    final lon = _toDouble(json['lon']);
    final name = json['display_name'];
    if (lat == null || lon == null || name is! String || name.isEmpty) {
      return null;
    }
    return PlaceResult(displayName: name, point: GeoPoint(lat, lon));
  }

  /// Parse a Nominatim `/search` response (a JSON array) into a result list, dropping any
  /// malformed rows. Pure.
  static List<PlaceResult> listFromNominatim(dynamic body) {
    if (body is! List) return const [];
    final out = <PlaceResult>[];
    for (final row in body) {
      if (row is Map<String, dynamic>) {
        final r = fromNominatim(row);
        if (r != null) out.add(r);
      }
    }
    return out;
  }

  /// Pull a place name out of a Nominatim `/reverse` response (`jsonv2` → a single object with a
  /// `display_name`). Returns null when absent so the caller can fall back to the coord label.
  /// Pure.
  static String? nameFromReverse(dynamic body) {
    if (body is Map && body['display_name'] is String) {
      final name = body['display_name'] as String;
      return name.isEmpty ? null : name;
    }
    return null;
  }

  static double? _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

/// Forward + reverse geocoding against OpenStreetMap **Nominatim** (free, no API key).
///
/// Abstracted so the search field / picker are testable without network, and so the host or a
/// future backend geocode proxy can swap in via the provider. NOTE: Nominatim is an EXTERNAL host
/// (not our `/v1` gateway), so it is NOT called through [PguardApi] — it uses its own bare Dio with
/// the mandatory `User-Agent` header and its 1-req/sec usage policy respected by the debounced
/// caller (see PlaceSearchField).
abstract class PlaceSearchService {
  /// Forward-geocode free text → up to a handful of candidate places (Thailand-scoped). Best
  /// effort: returns an empty list on a network/parse failure (never throws into the UI).
  Future<List<PlaceResult>> search(String query);

  /// Reverse-geocode a coordinate → a human place name, or null when unavailable/offline (the
  /// caller then keeps the coord label). Best effort.
  Future<String?> reverse(GeoPoint point);
}

/// Live [PlaceSearchService] hitting `nominatim.openstreetmap.org`.
class NominatimPlaceSearchService implements PlaceSearchService {
  NominatimPlaceSearchService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _base,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              // Nominatim's usage policy REQUIRES an identifying User-Agent; anonymous clients are
              // blocked. Identify the app (bundle id + version).
              headers: const {'User-Agent': _userAgent},
              // Accept any <500 so a 4xx surfaces as an empty result, not an exception.
              validateStatus: (s) => s != null && s < 500,
            ));

  static const String _base = 'https://nominatim.openstreetmap.org';
  static const String _userAgent = 'pguard-mobile/1.0';

  final Dio _dio;

  @override
  Future<List<PlaceResult>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final res = await _dio.get<dynamic>('/search', queryParameters: {
        'q': q,
        'format': 'jsonv2',
        'addressdetails': 1,
        'limit': 6,
        'countrycodes': 'th',
      });
      return PlaceResult.listFromNominatim(res.data);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<String?> reverse(GeoPoint point) async {
    try {
      final res = await _dio.get<dynamic>('/reverse', queryParameters: {
        'lat': point.lat,
        'lon': point.lng,
        'format': 'jsonv2',
      });
      return PlaceResult.nameFromReverse(res.data);
    } catch (_) {
      return null;
    }
  }
}
