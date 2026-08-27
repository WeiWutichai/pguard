import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';
import 'package:pguard_mobile/core/models/registration.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

/// A secure store whose reads THROW (Android keystore corruption / restore-from-backup key
/// mismatch → PlatformException/BadPaddingException) — drives the startup classifier's error path.
class _ThrowingStore extends InMemoryStore {
  @override
  Future<String?> readRefreshToken() async =>
      throw Exception('EncryptedSharedPreferences decryption failed');
}

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
      'a secure-storage read failure classifies as unauthenticated (never stuck on '
      'the splash screen forever)', () async {
    // Before the fix, _load errored unhandled → status stayed `unknown` → the router pinned the
    // user to /splash permanently. Now the read failure is caught → tokens best-effort wiped →
    // land on the login flow.
    final store = _ThrowingStore()
      ..refresh = 'r'
      ..pinHash = 'h';
    expect(await resolved(container(store, FakePrefsStore())),
        SessionStatus.unauthenticated,
        reason:
            'an unreadable keystore falls to the login flow, not an eternal splash');
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
    test('onLoggedIn persists the enrolled roles (prefs) and exposes them',
        () async {
      final prefs = FakePrefsStore();
      final c = container(InMemoryStore(), prefs);
      c.listen(sessionProvider, (_, __) {});
      c.read(sessionProvider.notifier).onLoggedIn(const AuthUser(
          userId: 'u1', role: 'customer', roles: ['customer', 'guard']));

      expect(c.read(sessionProvider).user!.hasMultipleRoles, isTrue);
      // Persisted (non-sensitive) so a cold start lands on the picker.
      expect(prefs.values[kEnrolledRolesKey], 'customer,guard');
    });

    test(
        'cold start rebuilds the enrolled set from prefs (dual-role survives a restart)',
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

    test(
        'switchActiveRole swaps the active role, keeps the enrolled set, no logout',
        () async {
      final c = container(InMemoryStore(), FakePrefsStore());
      c.listen(sessionProvider, (_, __) {});
      c.read(sessionProvider.notifier).onLoggedIn(const AuthUser(
          userId: 'u1', role: 'customer', roles: ['customer', 'guard']));

      c.read(sessionProvider.notifier).switchActiveRole('guard');
      final s = c.read(sessionProvider);
      expect(s.status, SessionStatus.authenticated);
      expect(s.user!.role, 'guard');
      expect(s.user!.enrolledRoles, containsAll(['customer', 'guard']));
    });

    test(
        'refreshRoles grows the enrolled set after an approval (and persists it)',
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

  group('returning device (logout → PIN login, no OTP)', () {
    test('logout keeps a remembered device (phone + PIN) → returning',
        () async {
      final store = InMemoryStore()
        ..refresh = 'r' // a live session → starts locked
        ..phone = '0812345678'
        ..pinHash = 'h';
      final c = container(store, FakePrefsStore());
      expect(await resolved(c), SessionStatus.locked);
      await c.read(sessionProvider.notifier).logout();
      expect(c.read(sessionProvider).status, SessionStatus.returning);
      // The login identifier is retained (clearSession drops it) so the PIN-login knows who to
      // log in; the local PIN is left in place for that login.
      expect(store.phone, '0812345678');
      expect(store.pinHash, isNotNull);
    });

    test('logout(forgetDevice: true) wipes the device → unauthenticated',
        () async {
      final store = InMemoryStore()
        ..refresh = 'r'
        ..phone = '0812345678'
        ..pinHash = 'h';
      final c = container(store, FakePrefsStore());
      await resolved(c);
      await c.read(sessionProvider.notifier).logout(forgetDevice: true);
      expect(c.read(sessionProvider).status, SessionStatus.unauthenticated);
      expect(store.phone, isNull);
      expect(store.pinHash, isNull,
          reason: 'a full sign-out wipes the local PIN too');
    });

    test('cold start with a remembered PIN + phone (no tokens) → returning',
        () async {
      final store = InMemoryStore()
        ..phone = '0812345678'
        ..pinHash = 'h'; // no refresh token
      expect(await resolved(container(store, FakePrefsStore())),
          SessionStatus.returning);
    });

    test('cold start with a PIN but NO phone → unauthenticated', () async {
      final store = InMemoryStore()..pinHash = 'h'; // no phone, no refresh
      expect(await resolved(container(store, FakePrefsStore())),
          SessionStatus.unauthenticated);
    });

    test(
        'logout with a PIN but a missing phone still lands on returning (never forces set-PIN)',
        () async {
      // The set-new-PIN-after-logout bug: a device that HOLDS a PIN but whose phone was dropped
      // (a racing partial teardown) must NOT be classified as brand-new → OTP → set-PIN. logout
      // now lands on returning whenever a PIN exists; the returning screen recovers a null phone.
      final store = InMemoryStore()
        ..refresh = 'r'
        ..pinHash = 'h'; // PIN present, phone absent
      final c = container(store, FakePrefsStore());
      await resolved(c);
      await c.read(sessionProvider.notifier).logout();
      expect(c.read(sessionProvider).status, SessionStatus.returning);
      expect(store.pinHash, isNotNull);
    });

    test('concurrent logout calls are single-flight (no returning→phone race)',
        () async {
      final store = InMemoryStore()
        ..refresh = 'r'
        ..phone = '0812345678'
        ..pinHash = 'h';
      final c = container(store, FakePrefsStore());
      await resolved(c);
      // Fire two logouts at once (the user-tap + the API client's auth-lost path). The latch
      // must serialize them so the phone is re-saved exactly once and the device stays
      // remembered — never dropped to unauthenticated by an interleaved clear.
      await Future.wait([
        c.read(sessionProvider.notifier).logout(),
        c.read(sessionProvider.notifier).logout(),
      ]);
      expect(c.read(sessionProvider).status, SessionStatus.returning);
      expect(store.phone, '0812345678');
    });
  });
}
