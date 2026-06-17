import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';

void main() {
  test('mapPermissionStatus maps every plugin status to the app state', () {
    expect(mapPermissionStatus(PermissionStatus.granted),
        PgPermissionState.granted);
    expect(mapPermissionStatus(PermissionStatus.limited),
        PgPermissionState.granted);
    expect(mapPermissionStatus(PermissionStatus.provisional),
        PgPermissionState.granted);
    expect(mapPermissionStatus(PermissionStatus.permanentlyDenied),
        PgPermissionState.permanentlyDenied);
    expect(mapPermissionStatus(PermissionStatus.restricted),
        PgPermissionState.restricted);
    expect(mapPermissionStatus(PermissionStatus.denied),
        PgPermissionState.denied);
  });
}
