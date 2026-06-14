import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/models/registration.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  ProviderContainer container(InMemoryStore store, FakePrefsStore prefs) {
    final c = ProviderContainer(overrides: [
      appStoreProvider.overrideWithValue(store),
      prefsStoreProvider.overrideWithValue(prefs),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  // _load() runs as a startup microtask with several awaits; wait until it settles.
  Future<SessionStatus> resolved(ProviderContainer c) async {
    c.listen(sessionProvider, (_, __) {});
    for (var i = 0; i < 50; i++) {
      if (c.read(sessionProvider).status != SessionStatus.unknown) break;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    return c.read(sessionProvider).status;
  }

  test(
      'cold start resumes at role-select when the onboarding marker is set (no refresh token)',
      () async {
    final prefs = FakePrefsStore();
    await prefs.setString(kRegOnboardingStageKey, kRegOnboardingStageRole);
    expect(await resolved(container(InMemoryStore(), prefs)),
        SessionStatus.onboardingRole);
  });

  test('a registered-pending account outranks the onboarding marker', () async {
    final prefs = FakePrefsStore();
    await prefs.setString(kRegPendingRoleKey, 'customer');
    await prefs.setString(kRegOnboardingStageKey, kRegOnboardingStageRole);
    expect(await resolved(container(InMemoryStore(), prefs)),
        SessionStatus.pendingApproval);
  });

  test('no marker, no pending, no token → unauthenticated (regression)',
      () async {
    expect(await resolved(container(InMemoryStore(), FakePrefsStore())),
        SessionStatus.unauthenticated);
  });

  test(
      'a refresh token + PIN → locked (the onboarding marker does not interfere)',
      () async {
    final store = InMemoryStore()
      ..refresh = 'r'
      ..pinHash = 'h';
    final prefs = FakePrefsStore();
    await prefs.setString(kRegOnboardingStageKey, kRegOnboardingStageRole);
    expect(await resolved(container(store, prefs)), SessionStatus.locked);
  });

  test('logout clears the onboarding marker + raw PIN', () async {
    final store = InMemoryStore()..onboardingPin = '135790';
    final prefs = FakePrefsStore();
    await prefs.setString(kRegOnboardingStageKey, kRegOnboardingStageRole);
    final c = container(store, prefs);
    await resolved(c);
    await c.read(sessionProvider.notifier).logout();
    expect(await prefs.getString(kRegOnboardingStageKey), isNull);
    expect(store.onboardingPin, isNull);
    expect(c.read(sessionProvider).status, SessionStatus.unauthenticated);
  });
}
