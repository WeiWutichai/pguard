// Geographic value types for the booking location picker + the customer live-map. Pure (no
// Flutter), so the projection/parsing is unit-testable.

import 'dart:math' as math;
//
// NOTE on the v2 booking contract: `POST /v1/bookings` (CreateBookingRequest) carries the
// free-text `address` PLUS optional `lat`/`lng` (both-or-neither). There is no forward-geocoding
// endpoint — the map picker IS the coordinate source. The booking flow sends the map-pinned
// coordinate alongside the resolved `address` when the customer picks on the map (null otherwise).

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

/// A straight-line travel estimate (haversine distance + a rough ETA at an assumed urban speed)
/// for the guard navigation screen. NOT turn-by-turn — there is no directions API — so the UI
/// must present it as APPROXIMATE. Pure (no Flutter), so it is unit-testable.
class TravelEstimate {
  const TravelEstimate({required this.metres, required this.minutes});

  final double metres;

  /// ETA in whole minutes, floored to at least 1.
  final int minutes;

  /// Default urban travel speed for the ETA (km/h) — a coarse assumption, not a routed speed.
  static const double defaultSpeedKmh = 22;

  factory TravelEstimate.between(GeoPoint from, GeoPoint to,
      {double speedKmh = defaultSpeedKmh}) {
    final metres = distanceMeters(from, to); // reuse the shared haversine helper
    final mins = (metres / 1000 / speedKmh * 60).ceil();
    return TravelEstimate(metres: metres, minutes: mins < 1 ? 1 : mins);
  }

  /// Localised distance ("350 ม." / "1.2 กม."), via the shared [formatDistance].
  String distanceLabel(bool isThai) => formatDistance(metres, thai: isThai);

  /// "~4 นาที" / "~4 min" — the tilde marks it approximate.
  String etaLabel(bool isThai) =>
      isThai ? '~$minutes นาที' : '~$minutes min';
}

/// Great-circle (haversine) distance between two coordinates, in metres. Pure.
double distanceMeters(GeoPoint a, GeoPoint b) {
  const earthRadius = 6371000.0;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h.toDouble())));
}

/// Compact bilingual distance label: `< 1km` → metres ("850 ม." / "850 m"), else one-decimal
/// kilometres ("1.2 กม." / "1.2 km"). Pure — the live-map's "how far is my guard" line.
String formatDistance(double meters, {required bool thai}) {
  if (meters < 1000) {
    final m = meters.round();
    return thai ? '$m ม.' : '$m m';
  }
  final km = (meters / 1000).toStringAsFixed(1);
  return thai ? '$km กม.' : '$km km';
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
