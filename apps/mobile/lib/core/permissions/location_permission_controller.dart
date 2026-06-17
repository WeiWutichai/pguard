import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers.dart';
import 'permission_gate.dart';

part 'location_permission_controller.g.dart';

/// Exposes the REAL OS location-permission state (never a local bool) and the actions the
/// rationale/denied screens drive. Reads `permissionGateProvider` so tests inject a fake gate.
/// Keeps all permission logic out of the widgets (Riverpod rule).
@riverpod
class LocationPermissionController extends _$LocationPermissionController {
  @override
  Future<PgPermissionState> build() =>
      ref.read(permissionGateProvider).locationStatus();

  /// Show the OS permission prompt (no-op dialog if permanently denied) and reflect the result.
  Future<PgPermissionState> request() async {
    final next = await ref.read(permissionGateProvider).requestLocation();
    state = AsyncData(next);
    return next;
  }

  /// Deep-link to device Settings (permanently-denied recovery).
  Future<bool> openSettings() => ref.read(permissionGateProvider).openSettings();

  /// Re-read the OS permission — call on app-resume after returning from Settings so the UI
  /// reflects what the user actually did, not a stale value.
  Future<PgPermissionState> refresh() async {
    final next = await ref.read(permissionGateProvider).locationStatus();
    state = AsyncData(next);
    return next;
  }
}
