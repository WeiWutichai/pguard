import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The token-persistence surface the [ApiClient] and auth controller depend on. An interface
/// so they are unit-testable against an in-memory fake (the real impl is [SecureStore]).
abstract class SessionStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> saveTokens({required String access, required String refresh});
  Future<void> clearSession();

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

  // ---- keys ----
  static const _kAccess = 'pg_access_token';
  static const _kRefresh = 'pg_refresh_token';
  static const _kPhone = 'pg_phone';
  static const _kPhoneVerifiedToken = 'pg_phone_verified_token';
  static const _kProfileToken = 'pg_profile_token';
  static const _kPinHash = 'pg_pin_hash';
  static const _kPinSalt = 'pg_pin_salt';
  static const _kPinAttempts = 'pg_pin_attempts';
  static const _kPinLockUntil = 'pg_pin_lock_until_ms';

  // ---- tokens ----
  @override
  Future<String?> readAccessToken() => _s.read(key: _kAccess);
  @override
  Future<String?> readRefreshToken() => _s.read(key: _kRefresh);

  @override
  Future<void> saveTokens(
      {required String access, required String refresh}) async {
    await _s.write(key: _kAccess, value: access);
    await _s.write(key: _kRefresh, value: refresh);
  }

  /// Drop the session tokens + phone + any in-flight registration tokens (logout /
  /// unrecoverable 401). Leaves the PIN so the same user can re-unlock and re-login.
  @override
  Future<void> clearSession() async {
    await _s.delete(key: _kAccess);
    await _s.delete(key: _kRefresh);
    await _s.delete(key: _kPhone);
    await clearRegistrationTokens();
  }

  // ---- phone (PII; the login identifier, shown read-only on the profile) ----
  @override
  Future<String?> readPhone() => _s.read(key: _kPhone);
  @override
  Future<void> savePhone(String phone) => _s.write(key: _kPhone, value: phone);

  // ---- registration tokens (single-use; phone-verify → register → profile) ----
  @override
  Future<String?> readPhoneVerifiedToken() => _s.read(key: _kPhoneVerifiedToken);
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

  /// Nuke everything (PIN-wipe threshold reached, or full sign-out).
  @override
  Future<void> wipe() => _s.deleteAll();
}
