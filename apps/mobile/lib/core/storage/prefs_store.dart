import 'package:shared_preferences/shared_preferences.dart';

/// Non-sensitive key/value preferences (language, etc.). Tokens/PIN/PII NEVER go here — those
/// use [SecureStore]. An interface so controllers are unit-testable against an in-memory fake.
abstract class PrefsStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);

  /// Remove a key entirely (so a reader sees it as truly absent, not an empty sentinel).
  Future<void> remove(String key);
}

/// Production [PrefsStore] backed by SharedPreferences.
class SharedPrefsStore implements PrefsStore {
  const SharedPrefsStore();

  @override
  Future<String?> getString(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> setString(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<void> remove(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}
