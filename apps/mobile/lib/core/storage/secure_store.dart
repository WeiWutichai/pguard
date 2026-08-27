import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The token-persistence surface the [ApiClient] and auth controller depend on. An interface
/// so they are unit-testable against an in-memory fake (the real impl is [SecureStore]).
abstract class SessionStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> saveTokens({required String access, required String refresh});
  Future<void> clearSession();

  /// Drop ONLY the access/refresh token pair — the credential teardown for a session that died
  /// SERVER-SIDE (refresh rejected / kicked by another device). Deliberately narrower than
  /// [clearSession]: it must NOT touch the remembered phone, or the follow-up
  /// `Session.logout()` reads `phone == null`, classifies the device as brand-new and routes
  /// the user into OTP + SET-A-NEW-PIN instead of the returning PIN-login (the reported
  /// "ตั้ง PIN ใหม่หลัง logout" bug).
  Future<void> clearTokens();

  /// The verified login phone (PII) — persisted in secure storage at login so the profile can
  /// show it read-only (it is the login identifier and is not returned by any API). Cleared on
  /// logout. Mirrors v1's `verified_phone` PDPA decision (PII never in SharedPreferences).
  Future<String?> readPhone();
  Future<void> savePhone(String phone);

  /// Single-use registration JWTs (secure storage — they are credentials, never SharedPreferences):
  ///  - `phone_verified_token` from `POST /otp/verify`, exchanged at `POST /auth/register`;
  ///  - `profile_token` from `POST /auth/register` (202), exchanged at `POST /profile/{role}`.
  /// Both are purpose-scoped and consumed single-use server-side; persisted so a backgrounded
  /// registration survives a brief app restart. Cleared on logout / session drop.
  Future<String?> readPhoneVerifiedToken();
  Future<void> savePhoneVerifiedToken(String token);
  Future<String?> readProfileToken();
  Future<void> saveProfileToken(String token);
  Future<void> clearRegistrationTokens();

  /// Clear ONLY the single-use `phone_verified_token` (keeps the `profile_token`, still needed
  /// after a 202 register). Called the moment a register POST reaches the server — the token is
  /// then either consumed (202) or unusable (4xx), so it must never be re-presented (e.g. on a
  /// back-out + re-tap of a role), which would surface as a confusing "verification expired".
  Future<void> clearPhoneVerifiedToken();

  /// The RAW PIN, persisted ONLY during the onboarding resume window (PIN-confirm → register).
  /// A cold-start `register()` needs it to compute the backend `pin_hash` AND to seed the local
  /// PIN at the subsequent login, so it must survive a process kill before role-select. It sits
  /// in the OS keychain/keystore (same protection class as the access token) and is CLEARED on
  /// every onboarding exit path (register success, login, logout, wipe, forgot-PIN, re-OTP) —
  /// see [clearOnboardingCredentials]. Acceptable because the same PIN ends up persisted as a
  /// salted hash via the PIN service after login anyway.
  Future<String?> readOnboardingPin();
  Future<void> saveOnboardingPin(String pin);

  /// Delete ONLY the onboarding raw PIN (leaves the registration tokens + phone, which are still
  /// needed right after a 202 register for the profile/check-status step). Full teardown of the
  /// session/onboarding goes through [clearSession] (which also drops the onboarding PIN).
  Future<void> clearOnboardingPin();
}

/// The PIN-persistence surface the PIN service depends on (hash/salt + lockout counters).
/// An interface so the service is unit-testable against an in-memory fake.
abstract class PinStore {
  Future<bool> hasPin();
  Future<String?> readPinHash();
  Future<String?> readPinSalt();
  Future<void> savePin({required String hash, required String salt});
  Future<int> readPinAttempts();
  Future<void> writePinAttempts(int value);
  Future<void> resetPinAttempts();
  Future<int?> readPinLockUntilMs();
  Future<void> writePinLockUntilMs(int? epochMs);

  /// Whether the user opted into biometric unlock (fingerprint/Face ID) as a fast path over the
  /// PIN gate. A local UX flag only — the real protection is the OS biometric + the PIN fallback.
  /// Lives in secure storage so a wipe (10 wrong PINs) also clears it.
  Future<bool> isBiometricEnabled();
  Future<void> setBiometricEnabled(bool value);

  Future<void> wipe();
}

/// The full app storage surface (tokens + PIN). Providers expose this interface so the app
/// can run against [SecureStore] in production and an in-memory fake in unit tests.
abstract class AppStore implements SessionStore, PinStore {}

/// Typed wrapper over [FlutterSecureStorage] for ALL sensitive values: JWT access/refresh
/// tokens, the local PIN hash + salt, and PIN lockout counters (which must survive app
/// restarts — CLAUDE.md). Non-sensitive prefs belong in SharedPreferences, never here, and
/// tokens/PIN never go to SharedPreferences (CLAUDE.md Flutter rules).
class SecureStore implements AppStore {
  SecureStore([FlutterSecureStorage? storage])
      : _s = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions:
                  IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _s;

  /// Write-through in-memory cache of the ACCESS token so the auth interceptor's per-request read
  /// (`ApiClient._onRequest`, run on EVERY protected request) doesn't decrypt the Keychain/Keystore
  /// each time — a non-trivial cost that multiplies with a screen that fans out several controllers
  /// (perf-review #19). Safe because `SecureStore` is the SOLE writer of the token (every mutator —
  /// saveTokens / clearSession / clearTokens / wipe — lives here and runs on the single app-wide
  /// instance from `appStoreProvider`), so this cache stays authoritative. `_accessCached` guards the
  /// "cached null" case (a cleared token) so a logged-out state doesn't re-hit storage each request.
  String? _accessCache;
  bool _accessCached = false;

  // ---- keys ----
  static const _kAccess = 'pg_access_token';
  static const _kRefresh = 'pg_refresh_token';
  static const _kPhone = 'pg_phone';
  static const _kPhoneVerifiedToken = 'pg_phone_verified_token';
  static const _kProfileToken = 'pg_profile_token';
  static const _kOnboardingPin = 'pg_onboarding_pin';
  static const _kPinHash = 'pg_pin_hash';
  static const _kPinSalt = 'pg_pin_salt';
  static const _kPinAttempts = 'pg_pin_attempts';
  static const _kPinLockUntil = 'pg_pin_lock_until_ms';
  static const _kBiometricEnabled = 'pg_biometric_enabled';

  // ---- tokens ----
  @override
  Future<String?> readAccessToken() async {
    if (_accessCached) return _accessCache;
    final v = await _s.read(key: _kAccess);
    _accessCache = v;
    _accessCached = true;
    return v;
  }

  @override
  Future<String?> readRefreshToken() => _s.read(key: _kRefresh);

  @override
  Future<void> saveTokens(
      {required String access, required String refresh}) async {
    await _s.write(key: _kAccess, value: access);
    await _s.write(key: _kRefresh, value: refresh);
    _cacheAccess(access);
  }

  /// Drop the session tokens + phone + any in-flight registration tokens (logout /
  /// unrecoverable 401). Leaves the PIN so the same user can re-unlock and re-login.
  @override
  Future<void> clearSession() async {
    await _s.delete(key: _kAccess);
    await _s.delete(key: _kRefresh);
    await _s.delete(key: _kPhone);
    await _s.delete(key: _kOnboardingPin);
    await clearRegistrationTokens();
    _cacheAccess(null);
  }

  @override
  Future<void> clearTokens() async {
    await _s.delete(key: _kAccess);
    await _s.delete(key: _kRefresh);
    _cacheAccess(null);
  }

  /// Update the write-through access-token cache after any mutation.
  void _cacheAccess(String? value) {
    _accessCache = value;
    _accessCached = true;
  }

  // ---- phone (PII; the login identifier, shown read-only on the profile) ----
  @override
  Future<String?> readPhone() => _s.read(key: _kPhone);
  @override
  Future<void> savePhone(String phone) => _s.write(key: _kPhone, value: phone);

  // ---- registration tokens (single-use; phone-verify → register → profile) ----
  @override
  Future<String?> readPhoneVerifiedToken() =>
      _s.read(key: _kPhoneVerifiedToken);
  @override
  Future<void> savePhoneVerifiedToken(String token) =>
      _s.write(key: _kPhoneVerifiedToken, value: token);
  @override
  Future<String?> readProfileToken() => _s.read(key: _kProfileToken);
  @override
  Future<void> saveProfileToken(String token) =>
      _s.write(key: _kProfileToken, value: token);
  @override
  Future<void> clearRegistrationTokens() async {
    await _s.delete(key: _kPhoneVerifiedToken);
    await _s.delete(key: _kProfileToken);
  }

  @override
  Future<void> clearPhoneVerifiedToken() =>
      _s.delete(key: _kPhoneVerifiedToken);

  // ---- onboarding resume credential (raw PIN; transient, see interface doc) ----
  @override
  Future<String?> readOnboardingPin() => _s.read(key: _kOnboardingPin);
  @override
  Future<void> saveOnboardingPin(String pin) =>
      _s.write(key: _kOnboardingPin, value: pin);
  @override
  Future<void> clearOnboardingPin() => _s.delete(key: _kOnboardingPin);

  // ---- PIN (local gate; never sent to the server) ----
  @override
  Future<bool> hasPin() async => (await _s.read(key: _kPinHash)) != null;
  @override
  Future<String?> readPinHash() => _s.read(key: _kPinHash);
  @override
  Future<String?> readPinSalt() => _s.read(key: _kPinSalt);

  @override
  Future<void> savePin({required String hash, required String salt}) async {
    await _s.write(key: _kPinHash, value: hash);
    await _s.write(key: _kPinSalt, value: salt);
    await resetPinAttempts();
  }

  // ---- PIN lockout counters (persisted so a restart can't reset them) ----
  @override
  Future<int> readPinAttempts() async =>
      int.tryParse(await _s.read(key: _kPinAttempts) ?? '') ?? 0;

  @override
  Future<void> writePinAttempts(int value) =>
      _s.write(key: _kPinAttempts, value: value.toString());

  @override
  Future<void> resetPinAttempts() async {
    await _s.write(key: _kPinAttempts, value: '0');
    await _s.delete(key: _kPinLockUntil);
  }

  /// Lockout deadline as epoch millis (UTC), or `null` if not locked.
  @override
  Future<int?> readPinLockUntilMs() async =>
      int.tryParse(await _s.read(key: _kPinLockUntil) ?? '');

  @override
  Future<void> writePinLockUntilMs(int? epochMs) async {
    if (epochMs == null) {
      await _s.delete(key: _kPinLockUntil);
    } else {
      await _s.write(key: _kPinLockUntil, value: epochMs.toString());
    }
  }

  // ---- biometric opt-in (local UX flag; cleared by wipe via deleteAll) ----
  @override
  Future<bool> isBiometricEnabled() async =>
      (await _s.read(key: _kBiometricEnabled)) == 'true';
  @override
  Future<void> setBiometricEnabled(bool value) =>
      _s.write(key: _kBiometricEnabled, value: value.toString());

  /// Nuke everything (PIN-wipe threshold reached, or full sign-out).
  @override
  Future<void> wipe() async {
    await _s.deleteAll();
    _cacheAccess(null);
  }
}
