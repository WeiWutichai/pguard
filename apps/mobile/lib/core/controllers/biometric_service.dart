import 'package:local_auth/local_auth.dart';

import '../storage/secure_store.dart';

/// The biometric platform surface the [BiometricService] depends on. An interface so the
/// service is unit-testable against a fake (the real impl, [LocalAuthAuthenticator], wraps the
/// `local_auth` plugin and its platform channels).
abstract class BiometricAuthenticator {
  /// The device has biometric hardware AND the OS can use it (or a device credential is set).
  Future<bool> isDeviceSupported();

  /// At least one biometric (fingerprint/face) is currently enrolled and usable.
  Future<bool> canCheckBiometrics();

  /// Show the OS biometric prompt. Returns `true` on success, `false` on user cancel / failure.
  /// Implementations must NOT throw — platform errors are swallowed to `false`.
  Future<bool> authenticate({required String localizedReason});
}

/// Production [BiometricAuthenticator] backed by the `local_auth` plugin. Biometric-only (no
/// device-PIN fallback) — the app's own PIN keypad is the fallback credential.
class LocalAuthAuthenticator implements BiometricAuthenticator {
  LocalAuthAuthenticator([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> canCheckBiometrics() async {
    try {
      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String localizedReason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          // App PIN is the fallback, not the device passcode → biometric-only.
          biometricOnly: true,
          // Survive a brief app background (the OS prompt can pause the app).
          stickyAuth: true,
        ),
      );
    } catch (_) {
      // Plugin throws PlatformException (no hardware / not enrolled / lockout / cancel) — treat
      // every failure as "not authenticated"; the caller falls back to the PIN keypad.
      return false;
    }
  }
}

/// Local biometric gate: combines device capability (via [BiometricAuthenticator]) with the
/// user's opt-in flag (persisted in the [PinStore]). Biometric is ALWAYS optional — it never
/// replaces the PIN, only fast-paths it. Testable: inject a fake authenticator + in-memory store.
class BiometricService {
  BiometricService({
    required PinStore store,
    required BiometricAuthenticator authenticator,
  })  : _store = store,
        _auth = authenticator;

  final PinStore _store;
  final BiometricAuthenticator _auth;

  /// The device can do biometrics right now (hardware present + at least one enrolled). Drives
  /// whether to even show the enroll screen / the lock-screen biometric key.
  Future<bool> isAvailable() async {
    if (!await _auth.isDeviceSupported()) return false;
    return _auth.canCheckBiometrics();
  }

  /// The user opted in. (UX flag only; meaningless unless [isAvailable] is also true.)
  Future<bool> isEnabled() => _store.isBiometricEnabled();

  /// Biometric should be offered on the lock screen: opted in AND currently available.
  Future<bool> shouldOffer() async {
    if (!await _store.isBiometricEnabled()) return false;
    return isAvailable();
  }

  /// Prompt the OS, and on success persist the opt-in. Returns whether enrolment succeeded.
  Future<bool> enable({required String reason}) async {
    final ok = await _auth.authenticate(localizedReason: reason);
    if (ok) await _store.setBiometricEnabled(true);
    return ok;
  }

  /// Forget the opt-in (e.g. a settings toggle, or after a failed re-auth).
  Future<void> disable() => _store.setBiometricEnabled(false);

  /// Prompt the OS to unlock (lock screen). Returns whether the user authenticated.
  Future<bool> authenticate({required String reason}) =>
      _auth.authenticate(localizedReason: reason);
}
