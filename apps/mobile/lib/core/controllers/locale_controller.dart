import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers.dart';

part 'locale_controller.g.dart';

/// The app's display language. Pure enum (no Flutter) so the controller stays testable.
enum AppLocale {
  th('th', 'ไทย'),
  en('en', 'EN');

  const AppLocale(this.code, this.label);

  final String code;
  final String label;

  static AppLocale? tryParse(String? code) {
    for (final l in AppLocale.values) {
      if (l.code == code) return l;
    }
    return null;
  }
}

/// Language preference (TH/EN), persisted to non-sensitive prefs. The app UI is predominantly
/// inline-bilingual; this preference drives locale-aware client rendering (e.g. notification
/// relative-times) and is the seam for full per-string i18n later. Defaults to Thai.
@Riverpod(keepAlive: true)
class LocaleController extends _$LocaleController {
  static const _key = 'pg_locale';

  /// True once the user has explicitly chosen — so the async startup [_load] can't clobber a
  /// choice the user made before it finished.
  bool _userSet = false;

  @override
  AppLocale build() {
    Future.microtask(_load);
    return AppLocale.th;
  }

  Future<void> _load() async {
    // Now that screens AND controllers read this provider for single-language rendering, the
    // startup prefs read must never throw — a unit test (or an unprovisioned SharedPreferences)
    // would otherwise surface an unhandled microtask error. Fall back to the Thai default.
    try {
      final saved = AppLocale.tryParse(
          await ref.read(prefsStoreProvider).getString(_key));
      if (saved != null && !_userSet) state = saved;
    } catch (_) {
      // Keep the default (Thai); the preference simply isn't available here.
    }
  }

  bool get isThai => state == AppLocale.th;

  Future<void> setLocale(AppLocale locale) async {
    _userSet = true;
    state = locale;
    await ref.read(prefsStoreProvider).setString(_key, locale.code);
  }

  Future<void> toggle() => setLocale(isThai ? AppLocale.en : AppLocale.th);
}
