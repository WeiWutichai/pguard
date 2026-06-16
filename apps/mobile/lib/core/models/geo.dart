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

/// A pure equirectangular viewport: maps WGS84 coordinates onto canvas fractions, the same
/// local projection the booking map picker uses (no map-tile SDK — see `MapPicker`). The
/// live-map widget only positions markers; ALL the projection math lives here, unit-tested.
///
/// Known inaccuracy (accepted): no cos(lat) correction is applied to the longitude axis, so
/// markers skew slightly at high latitudes. At Bangkok (~14°N) and street-scale spans the
/// distortion is < 3% — revisit only if the market ever leaves the tropics.
class MapViewport {
  const MapViewport({required this.center, required this.span});

  /// The coordinate at the centre of the canvas.
  final GeoPoint center;

  /// Degrees of latitude/longitude spanned across the canvas (the "zoom").
  final double span;

  /// Span used when there is nothing to fit (matches the picker's city-scale feel).
  static const double defaultSpan = 0.02;

  /// Fit a viewport around [points]: centred on their bounding box, spanning the larger axis
  /// padded by [paddingFactor], floored at [minSpan] so two near-identical points (or a single
  /// point) still get a sensible street-scale view. Empty input → Bangkok at [defaultSpan].
  factory MapViewport.fit(
    Iterable<GeoPoint> points, {
    double minSpan = 0.012,
    double paddingFactor = 1.6,
  }) {
    final list = points.toList();
    if (list.isEmpty) {
      return const MapViewport(center: GeoPoint.bangkok, span: defaultSpan);
    }
    var minLat = list.first.lat, maxLat = list.first.lat;
    var minLng = list.first.lng, maxLng = list.first.lng;
    for (final p in list.skip(1)) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    final extent =
        math.max(maxLat - minLat, maxLng - minLng) * paddingFactor;
    return MapViewport(
      center: GeoPoint((minLat + maxLat) / 2, (minLng + maxLng) / 2),
      span: math.max(extent, minSpan),
    );
  }

  /// [p] as a fraction of the canvas — `(x: 0, y: 0)` top-left, `(x: 1, y: 1)` bottom-right —
  /// clamped into `[inset, 1-inset]` so a marker never renders half off-canvas.
  ({double x, double y}) fractionFor(GeoPoint p, {double inset = 0.07}) {
    final x = ((p.lng - center.lng) / span + 0.5).clamp(inset, 1 - inset);
    final y = (0.5 - (p.lat - center.lat) / span).clamp(inset, 1 - inset);
    return (x: x.toDouble(), y: y.toDouble());
  }
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
