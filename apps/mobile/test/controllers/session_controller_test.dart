import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';
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

  group('multi-role enrolled set', () {
    test('onLoggedIn persists the enrolled roles (prefs) and exposes them', () async {
      final prefs = FakePrefsStore();
      final c = container(InMemoryStore(), prefs);
      c.listen(sessionProvider, (_, __) {});
      c.read(sessionProvider.notifier).onLoggedIn(
          const AuthUser(userId: 'u1', role: 'customer', roles: ['customer', 'guard']));

      expect(c.read(sessionProvider).user!.hasMultipleRoles, isTrue);
      // Persisted (non-sensitive) so a cold start lands on the picker.
      expect(prefs.values[kEnrolledRolesKey], 'customer,guard');
    });

    test('cold start rebuilds the enrolled set from prefs (dual-role survives a restart)',
        () async {
      final store = InMemoryStore()
        ..refresh = 'r'
        ..access = fakeJwt({'sub': 'u1', 'role': 'guard', 'exp': 9999999999});
      // No PIN → authenticated straight away (not locked).
      final prefs = FakePrefsStore()
        ..values[kEnrolledRolesKey] = 'customer,guard';
      final c = container(store, prefs);
      expect(await resolved(c), SessionStatus.authenticated);
      final user = c.read(sessionProvider).user!;
      expect(user.role, 'guard', reason: 'active role from the access token');
      expect(user.hasMultipleRoles, isTrue,
          reason: 'enrolled set restored from prefs');
    });

    test('switchActiveRole swaps the active role, keeps the enrolled set, no logout',
        () async {
      final c = container(InMemoryStore(), FakePrefsStore());
      c.listen(sessionProvider, (_, __) {});
      c.read(sessionProvider.notifier).onLoggedIn(
          const AuthUser(userId: 'u1', role: 'customer', roles: ['customer', 'guard']));

      c.read(sessionProvider.notifier).switchActiveRole('guard');
      final s = c.read(sessionProvider);
      expect(s.status, SessionStatus.authenticated);
      expect(s.user!.role, 'guard');
      expect(s.user!.enrolledRoles, containsAll(['customer', 'guard']));
    });

    test('refreshRoles grows the enrolled set after an approval (and persists it)',
        () async {
      final prefs = FakePrefsStore();
      final c = container(InMemoryStore(), prefs);
      c.listen(sessionProvider, (_, __) {});
      c.read(sessionProvider.notifier).onLoggedIn(
          const AuthUser(userId: 'u1', role: 'customer', roles: ['customer']));
      expect(c.read(sessionProvider).user!.hasMultipleRoles, isFalse);

      // Admin approved the guard role → /auth/me now returns both.
      c.read(sessionProvider.notifier).refreshRoles(['customer', 'guard']);
      expect(c.read(sessionProvider).user!.hasMultipleRoles, isTrue);
      expect(prefs.values[kEnrolledRolesKey], 'customer,guard');
    });

    test('logout clears the persisted enrolled-role set', () async {
      final prefs = FakePrefsStore()
        ..values[kEnrolledRolesKey] = 'customer,guard';
      final c = container(InMemoryStore(), prefs);
      await resolved(c);
      await c.read(sessionProvider.notifier).logout();
      expect(prefs.values[kEnrolledRolesKey], isNull);
    });
  });
}
