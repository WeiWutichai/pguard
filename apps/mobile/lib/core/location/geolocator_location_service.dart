import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:geolocator/geolocator.dart';

import '../models/geo.dart';
import '../models/tracking.dart';
import 'location_service.dart';

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
/// `reverseGeocode` stays the coordinate-label stub — turning a coordinate into a place NAME needs
/// a (deferred) backend geocode proxy, not a client geocoding package.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

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

  @override
  Future<GeoPoint?> currentLocation() async {
    try {
      if (!await _ready()) return null;
      // Bound the one-shot fix: a slow GPS (indoors / cold start) must not hang the map-picker /
      // navigation UI — on timeout the catch below returns null → graceful Bangkok fallback.
      return pointFromPosition(await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10)));
    } catch (_) {
      // ServiceDisabled / PermissionDenied / timeout / platform error → best-effort null.
      return null;
    }
  }

  @override
  Stream<GpsSample> positionStream() async* {
    if (!await _ready()) return; // empty stream when not granted / GPS off
    yield* Geolocator.getPositionStream(locationSettings: _streamSettings())
        .map(sampleFromPosition)
        .handleError((Object _) {}); // swallow transient platform errors
  }

  @override
  Future<String> reverseGeocode(GeoPoint point) async => 'พิกัด ${point.label}';
}
