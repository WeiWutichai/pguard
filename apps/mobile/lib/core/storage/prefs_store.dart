import 'package:shared_preferences/shared_preferences.dart';

/// Non-sensitive key/value preferences (language, etc.). Tokens/PIN/PII NEVER go here — those
/// use [SecureStore]. An interface so controllers are unit-testable against an in-memory fake.
abstract class PrefsStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
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
}
