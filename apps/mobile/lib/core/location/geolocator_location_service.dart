import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:geolocator/geolocator.dart';

import '../models/geo.dart';
import '../models/tracking.dart';
import 'location_service.dart';
import 'place_search_service.dart';

/// Pure `Position` → [GpsSample] mapper (no platform channels → unit-testable).
///
/// `Position.accuracy` is a non-nullable double that is `0.0` when the platform doesn't report
/// accuracy (and can be negative for an invalid fix). Both mean "unknown", so anything `<= 0` is
/// normalised to `null` — otherwise [GpsAccuracyBand.of] would read `0` as "high" (wrong).
GpsSample sampleFromPosition(Position p) => GpsSample(
      lat: p.latitude,
      lng: p.longitude,
      accuracy: (p.accuracy.isFinite && p.accuracy > 0) ? p.accuracy : null,
      recordedAt: p.timestamp.toUtc(),
    );

/// Pure `Position` → [GeoPoint] mapper.
GeoPoint pointFromPosition(Position p) => GeoPoint(p.latitude, p.longitude);

/// Real device-GPS [LocationService] backed by the `geolocator` plugin. FOREGROUND / while-in-use
/// only — no background tracking in this slice.
///
/// PERMISSION: this never PROMPTS. The single user-facing request path is the
/// `permission_handler`-based rationale screen; here we only read the already-granted permission
/// via [Geolocator.checkPermission] (and check the GPS hardware via [isLocationServiceEnabled]),
/// so there is no second OS dialog. When permission isn't granted or location services are off,
/// [currentLocation] returns `null` and [positionStream] is empty — the map falls back to Bangkok
/// and the guard shows "no signal" (honest degrade; never throws into the UI).
///
/// `reverseGeocode` resolves the place NAME via OSM Nominatim ([PlaceSearchService.reverse]) and
/// falls back to the coordinate label when that is unavailable/offline (best-effort, never throws).
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService({PlaceSearchService? places})
      : _places = places;

  /// Nominatim-backed reverse geocoder. Injectable (tests pass a fake); a `null` keeps the legacy
  /// coordinate-label behaviour (no network) for any caller that wires it that way.
  final PlaceSearchService? _places;

  /// Continuous uplink: high accuracy, emit only after ~15 m of movement so a STATIONARY guard
  /// does not flood the presence WebSocket (event-driven; no `Timer.periodic`). On Android the
  /// stream runs inside a FOREGROUND SERVICE (a persistent notification) so the uplink keeps going
  /// with the screen off / app backgrounded — a guard waiting for jobs stays trackable.
  static LocationSettings _streamSettings() {
    const accuracy = LocationAccuracy.high;
    const distanceFilter = 15;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'pguard • พร้อมรับงาน',
          notificationText: 'กำลังแชร์ตำแหน่งเพื่อรับงานใกล้คุณ',
          enableWakeLock: true,
          setOngoing: true,
          notificationIcon:
              AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        ),
      );
    }
    return const LocationSettings(
        accuracy: accuracy, distanceFilter: distanceFilter);
  }

  /// True only when the GPS hardware is on AND the OS permission is already granted. Read-only —
  /// never prompts (the rationale screen owns the request).
  Future<bool> _ready() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  /// Bounded one-shot fix: a slow GPS (indoors / cold start) must not hang the map-picker /
  /// navigation UI or the tracking keepalive — on timeout/denial/error returns `null` (graceful
  /// degrade; never throws). Shared by [currentLocation], [currentSample] and [selfLocationStream].
  Future<Position?> _oneShot() async {
    try {
      if (!await _ready()) return null;
      return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10));
    } catch (_) {
      // ServiceDisabled / PermissionDenied / timeout / platform error → best-effort null.
      return null;
    }
  }

  @override
  Future<GeoPoint?> currentLocation() async {
    final p = await _oneShot();
    return p == null ? null : pointFromPosition(p);
  }

  @override
  Future<GpsSample?> currentSample() async {
    final p = await _oneShot();
    return p == null ? null : sampleFromPosition(p);
  }

  @override
  Stream<GpsSample> positionStream() async* {
    if (!await _ready()) return; // empty stream when not granted / GPS off
    yield* Geolocator.getPositionStream(locationSettings: _streamSettings())
        .map(sampleFromPosition)
        .handleError((Object _) {}); // swallow transient platform errors
  }

  /// Live self position for the guard's own map: a one-shot seed (so a pin shows immediately,
  /// before the movement-gated [positionStream] emits) then every subsequent fix. Yields `null`
  /// first when there is no fix yet → the map shows "กำลังหาตำแหน่ง" rather than a blank crosshair.
  @override
  Stream<GeoPoint?> selfLocationStream() async* {
    yield await currentLocation();
    yield* positionStream().map((s) => GeoPoint(s.lat, s.lng));
  }

  @override
  Future<String> reverseGeocode(GeoPoint point) async {
    // Best-effort place NAME via Nominatim; fall back to the coordinate label on failure/offline
    // or when no geocoder is wired in.
    final name = await _places?.reverse(point);
    return (name != null && name.isNotEmpty) ? name : 'พิกัด ${point.label}';
  }
}
