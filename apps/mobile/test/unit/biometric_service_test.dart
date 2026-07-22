import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/biometric_service.dart';

import '../support/fakes.dart';

void main() {
  ({BiometricService svc, InMemoryStore store, FakeBiometricAuthenticator auth})
      build({
    bool deviceSupported = true,
    bool canCheck = true,
    bool? enrolled,
    bool authResult = true,
    bool enabled = false,
  }) {
    final store = InMemoryStore()..biometricEnabled = enabled;
    final auth = FakeBiometricAuthenticator(
      deviceSupported: deviceSupported,
      canCheck: canCheck,
      enrolled: enrolled,
      authResult: authResult,
    );
    return (
      svc: BiometricService(store: store, authenticator: auth),
      store: store,
      auth: auth,
    );
  }

  group('isAvailable', () {
    test('true only when device supported AND a biometric is enrolled',
        () async {
      expect(await build().svc.isAvailable(), isTrue);
    });

    test('false when the device is unsupported', () async {
      expect(await build(deviceSupported: false).svc.isAvailable(), isFalse);
    });

    test('false when no biometric is enrolled', () async {
      expect(await build(canCheck: false).svc.isAvailable(), isFalse);
    });

    test('false when hardware is present but NOTHING is enrolled (Android)',
        () async {
      // The exact deep-review case: canCheckBiometrics is TRUE on Android for a sensor with no
      // enrolled fingerprint. isAvailable must key off getAvailableBiometrics (enrolled), not
      // canCheckBiometrics — otherwise the enroll screen shows a dead "Enable" button.
      expect(await build(canCheck: true, enrolled: false).svc.isAvailable(),
          isFalse);
    });
  });

  group('shouldOffer', () {
    test('false when the user has not opted in (even if available)', () async {
      expect(await build(enabled: false).svc.shouldOffer(), isFalse);
    });

    test('true when opted in AND available', () async {
      expect(await build(enabled: true).svc.shouldOffer(), isTrue);
    });

    test('false when opted in but no longer available (unenrolled)', () async {
      expect(await build(enabled: true, canCheck: false).svc.shouldOffer(),
          isFalse);
    });
  });

  group('enable', () {
    test('persists the opt-in only after the OS prompt succeeds', () async {
      final b = build(authResult: true);
      expect(await b.svc.enable(reason: 'r'), isTrue);
      expect(b.store.biometricEnabled, isTrue);
      expect(b.auth.authCalls, 1);
      expect(b.auth.lastReason, 'r');
    });

    test('does NOT persist when the OS prompt is cancelled/fails', () async {
      final b = build(authResult: false);
      expect(await b.svc.enable(reason: 'r'), isFalse);
      expect(b.store.biometricEnabled, isFalse);
    });
  });

  test('disable clears the opt-in', () async {
    final b = build(enabled: true);
    await b.svc.disable();
    expect(b.store.biometricEnabled, isFalse);
  });

  group('authenticate', () {
    test('delegates to the OS prompt and returns its result', () async {
      final b = build(authResult: true);
      expect(await b.svc.authenticate(reason: 'unlock'), isTrue);
      expect(b.auth.authCalls, 1);
    });

    test('returns false when the prompt fails (caller falls back to PIN)',
        () async {
      expect(await build(authResult: false).svc.authenticate(reason: 'x'),
          isFalse);
    });
  });
}
