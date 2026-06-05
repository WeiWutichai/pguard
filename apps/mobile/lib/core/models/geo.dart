// Geographic value types for the booking location picker. Pure (no Flutter), so the
// projection/parsing is unit-testable.
//
// NOTE on the v2 booking contract: `POST /v1/bookings` (CreateBookingRequest) persists only a
// free-text `address` — there are NO lat/lng fields and no geocoding endpoint. We still capture
// coordinates in the draft (the map picker is a real lat/lng picker) for the UX and to keep the
// flow ready if the contract gains location fields; only the resolved `address` string is sent.

/// A WGS84 coordinate.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  /// Bangkok city centre — the default map focus when there is no GPS fix.
  static const GeoPoint bangkok = GeoPoint(13.7563, 100.5018);

  GeoPoint copyWith({double? lat, double? lng}) =>
      GeoPoint(lat ?? this.lat, lng ?? this.lng);

  /// A compact coordinate label, e.g. `13.75630, 100.50180`.
  String get label => '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GeoPoint($label)';
}

/// A picked location: a coordinate plus its human-readable place name (what gets sent as the
/// booking `address`).
class GeoPlace {
  const GeoPlace({required this.point, required this.placeName});

  final GeoPoint point;
  final String placeName;

  GeoPlace copyWith({GeoPoint? point, String? placeName}) => GeoPlace(
        point: point ?? this.point,
        placeName: placeName ?? this.placeName,
      );
}
