import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/registration_controller.dart';
import 'package:pguard_mobile/core/controllers/role_switch_controller.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';
import 'package:pguard_mobile/core/models/registration.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  ProviderContainer container({
    required FakeApi api,
    required InMemoryStore store,
    FakePrefsStore? prefs,
  }) {
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(store),
      prefsStoreProvider.overrideWithValue(prefs ?? FakePrefsStore()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// Seed an authenticated dual-role (or single-role) session with the given active role.
  void seedSession(ProviderContainer c,
      {required String active, required List<String> roles}) {
    c
        .read(sessionProvider.notifier)
        .onLoggedIn(AuthUser(userId: 'u1', role: active, roles: roles));
  }

  group('switchTo (enrolled role)', () {
    test('swaps the session token pair + active role, no logout', () async {
      final store = InMemoryStore()
        ..access = 'old-access'
        ..refresh = 'old-refresh';
      Map<String, dynamic>? body;
      final api = FakeApi(onPost: (path, data) async {
        expect(path, '/auth/switch-role');
        body = data as Map<String, dynamic>;
        return {
          'access_token':
              fakeJwt({'sub': 'u1', 'role': 'guard', 'exp': 9999999999}),
          'refresh_token': 'new-refresh',
          'expires_in': 3600,
        };
      });
      final c = container(api: api, store: store);
      seedSession(c, active: 'customer', roles: ['customer', 'guard']);

      final outcome =
          await c.read(roleSwitchControllerProvider.notifier).switchTo(
                RegistrationRole.guard,
              );

      expect(outcome, RoleActionOutcome.switched);
      expect(body!['role'], 'guard');
      // The NEW pair is persisted (no logout — the same account, different mode).
      expect(store.access, isNot('old-access'));
      expect(store.refresh, 'new-refresh');
      // The session stays authenticated with the new ACTIVE role + the same enrolled set.
      final session = c.read(sessionProvider);
      expect(session.status, SessionStatus.authenticated);
      expect(session.user!.role, 'guard');
      expect(session.user!.enrolledRoles, containsAll(['customer', 'guard']));
    });

    test('a 409 ROLE_NOT_ENROLLED falls back to the add-role flow', () async {
      final store = InMemoryStore();
      final api = FakeApi(onPost: (path, data) async {
        switch (path) {
          case '/auth/switch-role':
            throw const ApiException(
                message: 'not enrolled',
                code: 'ROLE_NOT_ENROLLED',
                statusCode: 409);
          case '/auth/roles':
            return {'user_id': 'u1', 'profile_token': 'ptok-guard'};
          default:
            throw StateError('unexpected $path');
        }
      });
      final c = container(api: api, store: store);
      seedSession(c, active: 'customer', roles: ['customer']);

      final outcome = await c
          .read(roleSwitchControllerProvider.notifier)
          .switchTo(RegistrationRole.guard);

      // Stale enrolled set → enrolment started instead of dead-ending.
      expect(outcome, RoleActionOutcome.needsProfile);
      expect(store.profileToken, 'ptok-guard');
      // The session is untouched (still the current role).
      expect(c.read(sessionProvider).user!.role, 'customer');
    });
  });

  group('enrol (not-yet-enrolled role)', () {
    test('POST /auth/roles → profile_token handed to the registration flow',
        () async {
      final store = InMemoryStore();
      Map<String, dynamic>? body;
      final api = FakeApi(onPost: (path, data) async {
        expect(path, '/auth/roles');
        body = data as Map<String, dynamic>;
        return {'user_id': 'u1', 'profile_token': 'ptok-guard'};
      });
      final c = container(api: api, store: store);
      seedSession(c, active: 'customer', roles: ['customer']);

      final outcome = await c
          .read(roleSwitchControllerProvider.notifier)
          .enrol(RegistrationRole.guard);

      expect(outcome, RoleActionOutcome.needsProfile);
      expect(body!['role'], 'guard');
      // The registration controller now holds the role + profile_token for the profile form.
      expect(
          c.read(registrationControllerProvider).role, RegistrationRole.guard);
      expect(store.profileToken, 'ptok-guard');
      // The user stays AUTHENTICATED in their current role (NOT bounced to pendingApproval).
      expect(c.read(sessionProvider).status, SessionStatus.authenticated);
      expect(c.read(sessionProvider).user!.role, 'customer');
    });

    test(
        'add-role profile submit does NOT flip the session or set the pending markers',
        () async {
      final store = InMemoryStore();
      final prefs = FakePrefsStore();
      final api = FakeApi(onPost: (path, data) async {
        switch (path) {
          case '/auth/roles':
            return {'user_id': 'u1', 'profile_token': 'ptok-guard'};
          case '/profile/guard':
            return {'user_id': 'u1'};
          default:
            throw StateError('unexpected $path');
        }
      });
      final c = container(api: api, store: store, prefs: prefs);
      seedSession(c, active: 'customer', roles: ['customer']);

      await c
          .read(roleSwitchControllerProvider.notifier)
          .enrol(RegistrationRole.guard);
      // Submit the second role's profile form (as the existing guard form would).
      final ok = await c
          .read(registrationControllerProvider.notifier)
          .submitGuardProfile(accountNumber: '1234567890');

      expect(ok, isTrue);
      // The profile_token was the Bearer for the write.
      expect(api.postBearer['/profile/guard'], 'ptok-guard');
      // CRITICAL: an add-role must NOT strand the user on the pending screen — the cold-start
      // pending markers are NOT written and the session stays authenticated in the CURRENT role.
      expect(prefs.values[kRegPendingRoleKey], isNull);
      expect(prefs.values[kRegSummaryKey], isNull);
      expect(c.read(sessionProvider).status, SessionStatus.authenticated);
      expect(c.read(sessionProvider).user!.role, 'customer');
    });
  });

  group('choose (router by enrolment)', () {
    test('an enrolled role → switch; a not-enrolled role → add-role', () async {
      final store = InMemoryStore();
      final api = FakeApi(onPost: (path, data) async {
        switch (path) {
          case '/auth/switch-role':
            return {
              'access_token':
                  fakeJwt({'sub': 'u1', 'role': 'guard', 'exp': 9999999999}),
              'refresh_token': 'r',
              'expires_in': 3600,
            };
          case '/auth/roles':
            return {'user_id': 'u1', 'profile_token': 'ptok'};
          default:
            throw StateError('unexpected $path');
        }
      });
      final c = container(api: api, store: store);
      seedSession(c, active: 'customer', roles: ['customer', 'guard']);

      // guard is enrolled → switch
      expect(
        await c
            .read(roleSwitchControllerProvider.notifier)
            .choose(RegistrationRole.guard),
        RoleActionOutcome.switched,
      );

      // Back to a single-role customer session: guard is NOT enrolled → add-role.
      seedSession(c, active: 'customer', roles: ['customer']);
      expect(
        await c
            .read(roleSwitchControllerProvider.notifier)
            .choose(RegistrationRole.guard),
        RoleActionOutcome.needsProfile,
      );
    });
  });

  test('switchTo surfaces a non-409 server error and keeps the session',
      () async {
    final store = InMemoryStore()
      ..access = 'a'
      ..refresh = 'r';
    final api = FakeApi(onPost: (path, _) async {
      throw const ApiException(message: 'boom', statusCode: 500);
    });
    final c = container(api: api, store: store);
    seedSession(c, active: 'customer', roles: ['customer', 'guard']);

    final outcome = await c
        .read(roleSwitchControllerProvider.notifier)
        .switchTo(RegistrationRole.guard);

    expect(outcome, RoleActionOutcome.error);
    // A 5xx is localized (infrastructure), never the raw English server text (deep-review lang fix).
    expect(c.read(roleSwitchControllerProvider).error,
        'ระบบขัดข้องชั่วคราว กรุณาลองใหม่ภายหลัง');
    expect(c.read(sessionProvider).user!.role, 'customer', reason: 'unchanged');
    expect(store.refresh, 'r', reason: 'old refresh kept');
  });
}
