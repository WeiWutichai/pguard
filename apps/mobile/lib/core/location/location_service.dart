import '../models/geo.dart';

/// Resolves the device location and turns coordinates into a human place name.
///
/// Abstracted so the booking form/map picker are testable without GPS or native channels, and
/// so a real implementation (a `geolocator`/`geocoding` plugin, or — preferably — a backend
/// geocode proxy) can be swapped in via the provider WITHOUT touching the UI or controller.
/// We deliberately do NOT repeat v1's anti-pattern of hammering the public Nominatim API
/// directly from the client (rate-limited, fragile, requires a UA header).
abstract class LocationService {
  /// Best-effort current GPS position; `null` if unavailable or permission-denied.
  Future<GeoPoint?> currentLocation();

  /// Reverse-geocode a coordinate to a human place name (Thai).
  Future<String> reverseGeocode(GeoPoint point);
}

/// Offline-safe default used in this frontend slice: no GPS plugin and no network calls. The
/// map picker still provides a real, draggable lat/lng selection; this just supplies a sensible
/// focus point and a coordinate-derived place label the user can refine before submitting.
class DefaultLocationService implements LocationService {
  const DefaultLocationService();

  @override
  Future<GeoPoint?> currentLocation() async => null;

  @override
  Future<String> reverseGeocode(GeoPoint point) async =>
      'พิกัด ${point.label}';
}
