import 'package:shared_preferences/shared_preferences.dart';

import 'secure_store.dart';

/// Wipes secure storage on the first launch after an install.
///
/// iOS Keychain items are NOT removed when an app is uninstalled, so without this a reinstall
/// (or a device that changed hands) would retain the previous owner's tokens + PIN hash and
/// could be unlocked offline with the old PIN (v1 security risk 3.2). `SharedPreferences` IS
/// cleared on uninstall, so the absence of our flag reliably marks a fresh install.
class FirstRunGuard {
  const FirstRunGuard();

  static const String _installedKey = 'pg_installed_v1';

  /// Must run BEFORE any session/token read at startup.
  Future<void> wipeIfFreshInstall(AppStore store) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_installedKey) != true) {
      await store.wipe();
      await prefs.setBool(_installedKey, true);
    }
  }
}
