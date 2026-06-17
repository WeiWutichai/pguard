import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/permissions/location_permission_controller.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

ProviderContainer makeC(FakePermissionGate gate) {
  final c = ProviderContainer(
    overrides: [permissionGateProvider.overrideWithValue(gate)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('build reads the current OS status', () async {
    final c = makeC(FakePermissionGate(PgPermissionState.denied));
    expect(await c.read(locationPermissionControllerProvider.future),
        PgPermissionState.denied);
  });

  test('request() prompts once and flips state to the granted result', () async {
    final gate = FakePermissionGate(PgPermissionState.denied,
        requestResult: PgPermissionState.granted);
    final c = makeC(gate);
    await c.read(locationPermissionControllerProvider.future);

    final result =
        await c.read(locationPermissionControllerProvider.notifier).request();

    expect(result, PgPermissionState.granted);
    expect(gate.requestCount, 1);
    expect(c.read(locationPermissionControllerProvider).value,
        PgPermissionState.granted);
  });

  test('openSettings() delegates to the gate exactly once', () async {
    final gate = FakePermissionGate(PgPermissionState.permanentlyDenied);
    final c = makeC(gate);
    await c.read(locationPermissionControllerProvider.future);

    await c.read(locationPermissionControllerProvider.notifier).openSettings();

    expect(gate.openSettingsCount, 1);
  });

  test('refresh() re-reads status (settings return flips denied → granted)',
      () async {
    final gate = FakePermissionGate(PgPermissionState.permanentlyDenied);
    final c = makeC(gate);
    await c.read(locationPermissionControllerProvider.future);

    gate.status = PgPermissionState.granted; // user enabled it in Settings
    final next =
        await c.read(locationPermissionControllerProvider.notifier).refresh();

    expect(next, PgPermissionState.granted);
    expect(c.read(locationPermissionControllerProvider).value,
        PgPermissionState.granted);
  });
}
