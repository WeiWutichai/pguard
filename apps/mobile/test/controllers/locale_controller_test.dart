import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/locale_controller.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  ProviderContainer container(FakePrefsStore prefs) {
    final c = ProviderContainer(
        overrides: [prefsStoreProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    return c;
  }

  test('defaults to Thai when nothing is stored', () async {
    final c = container(FakePrefsStore());
    expect(c.read(localeControllerProvider), AppLocale.th);
    await Future<void>.delayed(Duration.zero); // let _load run
    expect(c.read(localeControllerProvider), AppLocale.th);
  });

  test('loads the persisted locale', () async {
    final prefs = FakePrefsStore()..values['pg_locale'] = 'en';
    final c = container(prefs);
    c.read(localeControllerProvider); // trigger build → _load microtask
    await Future<void>.delayed(Duration.zero);
    expect(c.read(localeControllerProvider), AppLocale.en);
  });

  test('setLocale updates state and persists', () async {
    final prefs = FakePrefsStore();
    final c = container(prefs);
    await c.read(localeControllerProvider.notifier).setLocale(AppLocale.en);
    expect(c.read(localeControllerProvider), AppLocale.en);
    expect(prefs.values['pg_locale'], 'en');
  });

  test('toggle flips TH<->EN', () async {
    final prefs = FakePrefsStore();
    final c = container(prefs);
    final ctrl = c.read(localeControllerProvider.notifier);
    await ctrl.toggle();
    expect(c.read(localeControllerProvider), AppLocale.en);
    await ctrl.toggle();
    expect(c.read(localeControllerProvider), AppLocale.th);
  });
}
