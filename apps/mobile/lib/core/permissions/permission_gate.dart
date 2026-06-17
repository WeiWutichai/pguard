import 'package:permission_handler/permission_handler.dart';

/// App-level location-permission outcome, decoupled from `permission_handler`'s [PermissionStatus]
/// so the permission UX logic is pure + unit-testable (the plugin is platform-channel/static).
enum PgPermissionState {
  /// The OS grants location (foreground / while-in-use).
  granted,

  /// Denied this time, but the OS dialog can be shown again.
  denied,

  /// Denied with "don't ask again" — only the device Settings can re-enable it.
  permanentlyDenied,

  /// Blocked by device policy (MDM / parental controls) — the user can't change it.
  restricted,

  /// Not yet determined.
  unknown,
}

/// PURE map from the plugin status → app state. The single place the mapping lives.
PgPermissionState mapPermissionStatus(PermissionStatus s) {
  // `isLimited` (iOS) still yields a usable foreground fix → treat as granted.
  if (s.isGranted || s.isLimited || s.isProvisional) return PgPermissionState.granted;
  if (s.isPermanentlyDenied) return PgPermissionState.permanentlyDenied;
  if (s.isRestricted) return PgPermissionState.restricted;
  if (s.isDenied) return PgPermissionState.denied;
  return PgPermissionState.unknown;
}

/// Seam over `permission_handler` for the LOCATION permission — wrapped so the permission UX is
/// testable with a fake (the plugin uses platform channels + statics). This governs ONLY the OS
/// permission; the GPS *source* (geolocator-backed `LocationService`) is wired separately and is
/// still stubbed, so a grant here does not yet produce live fixes.
abstract class PermissionGate {
  Future<PgPermissionState> locationStatus();
  Future<PgPermissionState> requestLocation();

  /// Deep-link to the app's OS settings page (for the permanently-denied recovery flow).
  Future<bool> openSettings();
}

/// Real implementation over `permission_handler` (foreground / while-in-use location).
class DefaultPermissionGate implements PermissionGate {
  const DefaultPermissionGate();

  @override
  Future<PgPermissionState> locationStatus() async =>
      mapPermissionStatus(await Permission.locationWhenInUse.status);

  @override
  Future<PgPermissionState> requestLocation() async =>
      mapPermissionStatus(await Permission.locationWhenInUse.request());

  @override
  Future<bool> openSettings() => openAppSettings();
}
