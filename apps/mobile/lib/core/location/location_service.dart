import '../models/geo.dart';
import '../models/tracking.dart';

/// Resolves the device location and turns coordinates into a human place name.
///
/// Abstracted so the booking form/map picker AND the guard GPS tracking are testable without
/// GPS or native channels, and so a real implementation (a `geolocator`/`geocoding` plugin, or
/// — preferably — a backend geocode proxy) can be swapped in via the provider WITHOUT touching
/// the UI or controllers. We deliberately do NOT repeat v1's anti-pattern of hammering the
/// public Nominatim API directly from the client (rate-limited, fragile, requires a UA header).
abstract class LocationService {
  /// Best-effort current GPS position; `null` if unavailable or permission-denied.
  Future<GeoPoint?> currentLocation();

  /// One-shot CURRENT GPS fix as a full [GpsSample] (lat/lng + accuracy + timestamp), or `null`
  /// when unavailable / permission-denied / no fix — never throws. Unlike [currentLocation]
  /// (lat/lng only), this carries the whole sample so the presence uplink can be kept fresh while
  /// the guard is STATIONARY: the movement-gated [positionStream] emits nothing until the guard
  /// moves >15 m, so the tracking controller takes a one-shot fix on start and on a periodic
  /// keepalive to stay inside the presence freshness window (and therefore discoverable).
  Future<GpsSample?> currentSample();

  /// Reverse-geocode a coordinate to a human place name (Thai).
  Future<String> reverseGeocode(GeoPoint point);

  /// A continuous stream of GPS fixes while the guard is online (movement/cadence-driven). The
  /// controller subscribes to this rather than running a `Timer.periodic`, so there is no
  /// polling in the tracking path. Returns an empty stream when no GPS source is available.
  Stream<GpsSample> positionStream();

  /// The guard's OWN position as a live [GeoPoint] stream for the guard's self map: a one-shot
  /// seed (so the map shows a pin immediately, before the movement-gated [positionStream] emits)
  /// followed by every subsequent fix. Emits `null` first when no fix is available yet (the map
  /// then shows "กำลังหาตำแหน่ง" rather than a blank crosshair). Implementations compose
  /// [currentLocation] + [positionStream].
  Stream<GeoPoint?> selfLocationStream();
}

/// Offline-safe default used in this frontend slice: no GPS plugin and no network calls. The
/// map picker still provides a real, draggable lat/lng selection; this just supplies a sensible
/// focus point and a coordinate-derived place label the user can refine before submitting.
///
/// NATIVE DEPENDENCY (documented): real GPS needs the `geolocator` plugin (foreground-service +
/// always-permission for background tracking) wired into this provider; until then
/// [positionStream] is empty and the guard shows "no signal".
class DefaultLocationService implements LocationService {
  const DefaultLocationService();

  @override
  Future<GeoPoint?> currentLocation() async => null;

  @override
  Future<GpsSample?> currentSample() async => null;

  @override
  Future<String> reverseGeocode(GeoPoint point) async =>
      'พิกัด ${point.label}';

  @override
  Stream<GpsSample> positionStream() => const Stream<GpsSample>.empty();

  @override
  Stream<GeoPoint?> selfLocationStream() async* {
    yield null; // no GPS source → the guard map shows "กำลังหาตำแหน่ง"
  }
}
