import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/pin_hasher.dart';
import 'package:pguard_mobile/core/controllers/registration_controller.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/models/registration.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  const pin = '135790';
  const phone = '0812345678';
  // The wire credential is the UNsalted SHA-256 of the PIN (NOT the raw PIN).
  final pinHash = const PinHasher().pinHash(pin);

  ProviderContainer container({
    required FakeApi api,
    required InMemoryStore store,
    required FakePrefsStore prefs,
  }) {
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(store),
      prefsStoreProvider.overrideWithValue(prefs),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test(
      'register 202 → pendingApproval: NO access tokens stored, profile_token stashed, role threaded',
      () async {
    final store = InMemoryStore();
    final prefs = FakePrefsStore();
    Map<String, dynamic>? registerBody;
    final api = FakeApi(onPost: (path, data) async {
      expect(path, '/auth/register');
      registerBody = data as Map<String, dynamic>;
      return {'user_id': 'u1', 'profile_token': 'ptok-guard'};
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);

    await ctrl.beginFromAuth(
        phone: phone, phoneVerifiedToken: 'pvt-123', pin: pin);
    ctrl.selectRole(RegistrationRole.guard);
    final outcome = await ctrl.register();

    expect(outcome, RegisterOutcome.needsProfile);
    // Role + the single-use phone-verified token + the SHA-256 pin_hash were threaded into register.
    expect(registerBody!['role'], 'guard');
    expect(registerBody!['phone_verified_token'], 'pvt-123');
    expect(registerBody!['pin_hash'], pinHash);
    expect((registerBody!['pin_hash'] as String).length, 64);
    // IRON RULE: pending only — no access/refresh tokens, never authenticated.
    expect(store.access, isNull);
    expect(store.refresh, isNull);
    expect(c.read(sessionProvider).status, SessionStatus.pendingApproval);
    // profile_token stashed (secure). The pending flag is NOT set yet — it lands only after a
    // successful profile submit, so a kill between register and submit doesn't strand the user.
    expect(store.profileToken, 'ptok-guard');
    expect(prefs.values[kRegPendingRoleKey], isNull);
  });

  test(
      'register 409 → loginWithPin (returning approved user); password is SHA-256(pin)',
      () async {
    final store = InMemoryStore();
    final prefs = FakePrefsStore();
    Map<String, dynamic>? loginBody;
    final api = FakeApi(onPost: (path, data) async {
      switch (path) {
        case '/auth/register':
          throw const ApiException(
              message: 'exists', code: 'CONFLICT', statusCode: 409);
        case '/auth/login':
          loginBody = data as Map<String, dynamic>;
          return {
            'access_token':
                fakeJwt({'sub': 'u9', 'role': 'customer', 'exp': 9999999999}),
            'refresh_token': 'r9',
            'expires_in': 3600,
          };
        default:
          throw StateError('unexpected POST $path');
      }
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);

    await ctrl.beginFromAuth(phone: phone, phoneVerifiedToken: 'pvt', pin: pin);
    ctrl.selectRole(RegistrationRole.customer);
    final outcome = await ctrl.register();

    expect(outcome, RegisterOutcome.loggedIn);
    // Logged in (returning user) → tokens persisted, session authenticated.
    expect(store.access, isNotNull);
    expect(store.refresh, 'r9');
    expect(c.read(sessionProvider).status, SessionStatus.authenticated);
    // login presents the SHA-256 pin_hash (matches what register Argon2'd), NOT the raw PIN.
    expect(loginBody!['identifier'], phone);
    expect(loginBody!['password'], pinHash);
    expect(loginBody!['password'], isNot(pin));
  });

  test(
      'addSecondRoleWhilePending: POSTs /auth/register/add-role, stashes profile_token, needsProfile',
      () async {
    final store = InMemoryStore()..phoneVerifiedToken = 'pvt-fresh';
    final prefs = FakePrefsStore();
    Map<String, dynamic>? addBody;
    String? addPath;
    final api = FakeApi(onPost: (path, data) async {
      addPath = path;
      addBody = data as Map<String, dynamic>;
      return {'user_id': 'u1', 'profile_token': 'ptok-customer'};
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);

    // A pending GUARD adds the CUSTOMER role using the fresh OTP token (from store).
    final outcome =
        await ctrl.addSecondRoleWhilePending(RegistrationRole.customer);

    expect(outcome, RegisterOutcome.needsProfile);
    expect(addPath, '/auth/register/add-role');
    expect(addBody!['role'], 'customer');
    expect(addBody!['phone_verified_token'], 'pvt-fresh');
    // NO pin_hash — the account already has a PIN (this is not a fresh registration).
    expect(addBody!.containsKey('pin_hash'), isFalse);
    // The new-role profile_token is stashed for the profile submit; the spent OTP token is dropped.
    expect(store.profileToken, 'ptok-customer');
    expect(store.phoneVerifiedToken, isNull);
    // Session is untouched (still whatever it was — no accidental auth flip).
    expect(store.access, isNull);
    expect(
        c.read(registrationControllerProvider).role, RegistrationRole.customer);
  });

  test(
      'addSecondRoleWhilePending: 409 ROLE_ALREADY_HELD → error, no profile step',
      () async {
    final store = InMemoryStore()..phoneVerifiedToken = 'pvt-fresh';
    final prefs = FakePrefsStore();
    final api = FakeApi(
        onPost: (_, __) async =>
            throw const ApiException(message: 'already held', statusCode: 409));
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);

    final outcome =
        await ctrl.addSecondRoleWhilePending(RegistrationRole.guard);

    expect(outcome, RegisterOutcome.error);
    expect(c.read(registrationControllerProvider).error, isNotNull);
    expect(store.profileToken, isNull, reason: 'no profile step on 409');
  });

  test(
      'register 409 + set PIN mismatches stored → PIN-login handoff (returning), no silent reset',
      () async {
    // "Use a different account": the user set a PIN that does NOT match the existing approved
    // account's stored PIN → login 401s. The flow must NOT silently reset (it only holds a
    // phone_verify token) — it drops to `returning` (phone persisted) so the caller sends them to
    // PIN-login to enter their real PIN.
    final store = InMemoryStore();
    final prefs = FakePrefsStore();
    var loginCalls = 0;
    final api = FakeApi(onPost: (path, data) async {
      switch (path) {
        case '/auth/register':
          throw const ApiException(
              message: 'exists', code: 'CONFLICT', statusCode: 409);
        case '/auth/login':
          loginCalls++;
          throw const ApiException(
              message: 'bad creds', code: 'UNAUTHORIZED', statusCode: 401);
        case '/auth/reset-pin':
          fail('reset-pin must NOT be called with a phone_verify token');
        default:
          throw StateError('unexpected POST $path');
      }
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);

    await ctrl.beginFromAuth(phone: phone, phoneVerifiedToken: 'pvt', pin: pin);
    ctrl.selectRole(RegistrationRole.customer);
    final outcome = await ctrl.register();

    expect(outcome, RegisterOutcome.needsPinLogin);
    expect(loginCalls,
        1); // exactly one login attempt (the set PIN), then hand off — no retry
    // Session dropped to `returning` with the phone persisted so PIN-login can read it.
    expect(c.read(sessionProvider).status, SessionStatus.returning);
    expect(await store.readPhone(), phone);
    expect(store.access, isNull); // NOT logged in
  });

  test(
      'submitGuardProfile: POSTs /profile/guard with the profile_token Bearer; FULL acct to backend, MASKED locally',
      () async {
    final store = InMemoryStore();
    final prefs = FakePrefsStore();
    Map<String, dynamic>? guardBody;
    final api = FakeApi(onPost: (path, data) async {
      switch (path) {
        case '/auth/register':
          return {'user_id': 'u1', 'profile_token': 'ptok-123'};
        case '/profile/guard':
          guardBody = data as Map<String, dynamic>;
          return <String, dynamic>{};
        default:
          throw StateError('unexpected POST $path');
      }
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);

    await ctrl.beginFromAuth(phone: phone, phoneVerifiedToken: 'pvt', pin: pin);
    ctrl.selectRole(RegistrationRole.guard);
    await ctrl.register();

    final ok = await ctrl.submitGuardProfile(
      gender: 'male',
      yearsOfExperience: 5,
      bankName: 'KBank',
      accountNumber: '123-4-56789-0', // formatted; digits only to backend
      accountName: 'Somchai',
    );
    expect(ok, isTrue);
    // The profile_token (NOT a session token) was the Bearer.
    expect(api.postBearer['/profile/guard'], 'ptok-123');
    // FULL digits sent to the backend (server re-masks on reads).
    expect(guardBody!['account_number'], '1234567890');
    // No expiry dates passed → the key is omitted (never an empty array).
    expect(guardBody!.containsKey('document_expiries'), isFalse);
    // The LOCALLY persisted summary masks the account (last-4) — the full number never lands locally.
    final summary = prefs.values[kRegSummaryKey]!;
    expect(summary.contains('••••7890'), isTrue);
    expect(summary.contains('1234567890'), isFalse);
    // The pending flag is set now (after a successful submit), enabling cold-start resume.
    expect(prefs.values[kRegPendingRoleKey], 'guard');
  });

  test(
      'submitCustomerProfile rejects a leftover GUARD-purpose token (never POSTs the wrong token; clears it)',
      () async {
    // Regression: a stale guard `profile_token` from earlier guard onboarding must NOT be presented
    // to /profile/customer — the server rejects the wrong purpose and the access-token fallback then
    // fails with a confusing "missing field `role`". The client now catches the mismatch first.
    final store = InMemoryStore()
      ..profileToken =
          fakeJwt({'sub': 'u1', 'purpose': 'guard_profile', 'exp': 9999999999});
    final prefs = FakePrefsStore();
    var posted = false;
    final api = FakeApi(onPost: (path, data) async {
      posted = true;
      throw StateError('must not POST a wrong-purpose token to $path');
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);

    final ok =
        await ctrl.submitCustomerProfile(address: '123 Sukhumvit Road Bangkok');

    expect(ok, isFalse);
    expect(posted, isFalse); // the guard token never hit /profile/customer
    expect(await store.readProfileToken(),
        isNull); // dropped so the retry starts clean
    expect(c.read(registrationControllerProvider).error, isNotNull);
  });

  test('submitCustomerProfile accepts a matching CUSTOMER-purpose token',
      () async {
    final store = InMemoryStore()
      ..profileToken = fakeJwt(
          {'sub': 'u1', 'purpose': 'customer_profile', 'exp': 9999999999});
    final prefs = FakePrefsStore();
    final api = FakeApi(onPost: (path, data) async {
      expect(path, '/profile/customer');
      return <String, dynamic>{};
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);

    final ok =
        await ctrl.submitCustomerProfile(address: '123 Sukhumvit Road Bangkok');

    expect(ok, isTrue);
    expect(api.postBearer['/profile/customer'], store.profileToken ?? '');
    expect(prefs.values[kRegPendingRoleKey], 'customer');
  });

  test(
      'switch role without re-OTP: register reissues a customer token from a leftover guard token',
      () async {
    // After registering as guard, the single-use phone-verify token is spent. Backing out and
    // picking "customer" must NOT dead-end with "expired" — it re-issues a correct-role token via
    // the still-valid (guard) profile_token (POST /auth/register/reissue).
    final guardTok =
        fakeJwt({'sub': 'u1', 'purpose': 'guard_profile', 'exp': 9999999999});
    final customerTok = fakeJwt(
        {'sub': 'u1', 'purpose': 'customer_profile', 'exp': 9999999999});
    final store = InMemoryStore()
      ..profileToken = guardTok; // leftover guard token, no pvt
    final prefs = FakePrefsStore();
    String? reissueRole;
    final api = FakeApi(onPost: (path, data) async {
      expect(path, '/auth/register/reissue');
      reissueRole = (data as Map<String, dynamic>)['role'] as String;
      return {'user_id': 'u1', 'profile_token': customerTok};
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);
    ctrl.selectRole(RegistrationRole.customer);

    final outcome = await ctrl.register();

    expect(outcome, RegisterOutcome.needsProfile);
    expect(reissueRole, 'customer'); // asked the server for the new role
    expect(api.postBearer['/auth/register/reissue'],
        guardTok); // old token authorised it
    expect(store.profileToken, customerTok); // new correct-role token persisted
  });

  test(
      'submitGuardProfile folds per-document expiry dates into document_expiries (ISO date)',
      () async {
    final store = InMemoryStore();
    final prefs = FakePrefsStore();
    Map<String, dynamic>? guardBody;
    final api = FakeApi(onPost: (path, data) async {
      switch (path) {
        case '/auth/register':
          return {'user_id': 'u1', 'profile_token': 'ptok'};
        case '/profile/guard':
          guardBody = data as Map<String, dynamic>;
          return <String, dynamic>{};
        default:
          throw StateError('unexpected POST $path');
      }
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);
    await ctrl.beginFromAuth(phone: phone, phoneVerifiedToken: 'pvt', pin: pin);
    ctrl.selectRole(RegistrationRole.guard);
    await ctrl.register();

    final ok = await ctrl.submitGuardProfile(
      accountNumber: '1234567890',
      docExpiry: {
        GuardDocKind.idCard: DateTime(2030, 3, 9),
        GuardDocKind.driverLicense: DateTime(2031, 12, 1),
      },
    );
    expect(ok, isTrue);
    final expiries = guardBody!['document_expiries'] as List;
    expect(expiries.length, 2);
    // Wire keys + zero-padded ISO YYYY-MM-DD (the contract's expiry_date format).
    final byType = {
      for (final e in expiries) (e as Map)['document_type']: e['expiry_date'],
    };
    expect(byType['id_card'], '2030-03-09');
    expect(byType['driver_license'], '2031-12-01');
  });

  test(
      'submitCustomerProfile: POSTs /profile/customer with the profile_token Bearer',
      () async {
    final store = InMemoryStore();
    final prefs = FakePrefsStore();
    Map<String, dynamic>? body;
    final api = FakeApi(onPost: (path, data) async {
      switch (path) {
        case '/auth/register':
          return {'user_id': 'u2', 'profile_token': 'ptok-cust'};
        case '/profile/customer':
          body = data as Map<String, dynamic>;
          return <String, dynamic>{};
        default:
          throw StateError('unexpected POST $path');
      }
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);

    await ctrl.beginFromAuth(phone: phone, phoneVerifiedToken: 'pvt', pin: pin);
    ctrl.selectRole(RegistrationRole.customer);
    await ctrl.register();

    final ok = await ctrl.submitCustomerProfile(
      fullName: 'Nok',
      address: '99/1 Sukhumvit Rd, Bangkok',
    );
    expect(ok, isTrue);
    expect(api.postBearer['/profile/customer'], 'ptok-cust');
    expect(body!['full_name'], 'Nok');
    expect(body!['address'], '99/1 Sukhumvit Rd, Bangkok');
  });

  test(
      'checkStatus: stays pending while 401, then approved-login flips to authenticated',
      () async {
    final store = InMemoryStore();
    final prefs = FakePrefsStore();
    var approved = false;
    final api = FakeApi(onPost: (path, data) async {
      switch (path) {
        case '/auth/register':
          return {'user_id': 'u3', 'profile_token': 'ptok'};
        case '/auth/login':
          if (!approved) {
            // identity returns a generic 401 for a still-pending account.
            throw const ApiException(
                message: 'Invalid credentials', statusCode: 401);
          }
          return {
            'access_token':
                fakeJwt({'sub': 'u3', 'role': 'guard', 'exp': 9999999999}),
            'refresh_token': 'r3',
            'expires_in': 3600,
          };
        default:
          throw StateError('unexpected POST $path');
      }
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);

    await ctrl.beginFromAuth(phone: phone, phoneVerifiedToken: 'pvt', pin: pin);
    ctrl.selectRole(RegistrationRole.guard);
    await ctrl.register();
    expect(c.read(sessionProvider).status, SessionStatus.pendingApproval);

    // Not approved yet → stays pending (false, not an error).
    expect(await ctrl.checkStatus(), isFalse);
    expect(c.read(sessionProvider).status, SessionStatus.pendingApproval);

    // Approved → login succeeds → authenticated + pending flags cleared.
    approved = true;
    expect(await ctrl.checkStatus(), isTrue);
    expect(c.read(sessionProvider).status, SessionStatus.authenticated);
    expect(store.access, isNotNull);
    expect(RegistrationRole.tryParse(prefs.values[kRegPendingRoleKey]), isNull);
  });

  test('register without role/credentials → error outcome, no network',
      () async {
    final store = InMemoryStore();
    final prefs = FakePrefsStore();
    final api = FakeApi(
        onPost: (_, __) async => throw StateError('should not be called'));
    final ctrl = container(api: api, store: store, prefs: prefs)
        .read(registrationControllerProvider.notifier);
    // No beginFromAuth / selectRole.
    expect(await ctrl.register(), RegisterOutcome.error);
  });

  test(
      'beginFromAuth persists the resume state (phone + raw PIN + marker), then a COLD-START '
      'register rehydrates it and succeeds (202)', () async {
    final store = InMemoryStore();
    final prefs = FakePrefsStore();
    // 1) First segment finishes on container A: persist phone + raw PIN + stage marker.
    await container(api: FakeApi(), store: store, prefs: prefs)
        .read(registrationControllerProvider.notifier)
        .beginFromAuth(phone: phone, phoneVerifiedToken: 'pvt', pin: pin);
    expect(store.phone, phone);
    expect(store.onboardingPin, pin);
    expect(store.phoneVerifiedToken, 'pvt');
    expect(
        await prefs.getString(kRegOnboardingStageKey), kRegOnboardingStageRole);

    // 2) Cold start: a FRESH controller (in-memory _phone/_pin null) sharing the same storage.
    Map<String, dynamic>? body;
    final api = FakeApi(onPost: (path, data) async {
      expect(path, '/auth/register');
      body = data as Map<String, dynamic>;
      return {'profile_token': 'pt'};
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);
    ctrl.selectRole(RegistrationRole.customer);
    final outcome = await ctrl.register();

    expect(outcome, RegisterOutcome.needsProfile);
    expect(
        body!['phone_verified_token'], 'pvt'); // rehydrated from secure storage
    expect(body!['pin_hash'],
        pinHash); // = SHA-256 of the rehydrated onboarding PIN
    expect(c.read(sessionProvider).status, SessionStatus.pendingApproval);
    // The resume state is consumed: marker + raw PIN gone (profile token kept for the next step).
    expect(await prefs.getString(kRegOnboardingStageKey), isNull);
    expect(store.onboardingPin, isNull);
    expect(store.profileToken, 'pt');
  });

  for (final code in [401, 400]) {
    test(
        'an expired/consumed phone-verified token at register (HTTP $code) wipes onboarding '
        'state and bounces to unauthenticated', () async {
      final store = InMemoryStore();
      final prefs = FakePrefsStore();
      await container(api: FakeApi(), store: store, prefs: prefs)
          .read(registrationControllerProvider.notifier)
          .beginFromAuth(phone: phone, phoneVerifiedToken: 'pvt', pin: pin);

      final api = FakeApi(onPost: (_, __) async {
        throw ApiException(message: 'expired', code: 'X', statusCode: code);
      });
      final c = container(api: api, store: store, prefs: prefs);
      final ctrl = c.read(registrationControllerProvider.notifier);
      ctrl.selectRole(RegistrationRole.guard);

      expect(await ctrl.register(), RegisterOutcome.error);
      expect(c.read(sessionProvider).status, SessionStatus.unauthenticated);
      // Everything cleared so the user restarts cleanly from phone entry.
      expect(await prefs.getString(kRegOnboardingStageKey), isNull);
      expect(store.onboardingPin, isNull);
      expect(store.phoneVerifiedToken, isNull);
      expect(store.phone, isNull);
    });
  }

  test('register 202 clears the secure-storage phone-verified token (no reuse)',
      () async {
    final store = InMemoryStore();
    final prefs = FakePrefsStore();
    final api = FakeApi(onPost: (path, data) async {
      expect(path, '/auth/register');
      return {'user_id': 'u1', 'profile_token': 'ptok'};
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);
    await ctrl.beginFromAuth(
        phone: phone, phoneVerifiedToken: 'pvt-1', pin: pin);
    ctrl.selectRole(RegistrationRole.guard);

    expect(await ctrl.register(), RegisterOutcome.needsProfile);
    // The consumed phone-verified token is gone from storage (can't be re-presented)…
    expect(store.phoneVerifiedToken, isNull);
    // …while the profile_token (needed for the next step) is kept.
    expect(store.profileToken, 'ptok');
  });

  test(
      're-tapping a role after a successful 202 RESUMES to the profile step '
      '(no bounce, no second register POST)', () async {
    final store = InMemoryStore();
    final prefs = FakePrefsStore();
    // A REAL profile_token (JWT with a future exp) — the resume path now drops an expired/placeholder
    // token, so the fixture must carry a live one to prove the resume (deep-review expiry fix).
    final api = FakeApi(
        onPost: (path, data) async => {
              'user_id': 'u1',
              'profile_token': fakeJwt(
                  {'sub': 'u1', 'purpose': 'guard_profile', 'exp': 9999999999})
            });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);
    await ctrl.beginFromAuth(
        phone: phone, phoneVerifiedToken: 'pvt-1', pin: pin);
    ctrl.selectRole(RegistrationRole.guard);
    expect(await ctrl.register(), RegisterOutcome.needsProfile); // first 202

    // User backs out of the profile form and taps a role again — the spent phone-verified token
    // is gone, but the profile_token proves the account already exists (pending).
    ctrl.selectRole(RegistrationRole.guard);
    final second = await ctrl.register();

    expect(
        second, RegisterOutcome.needsProfile); // resumes, NOT an error/bounce
    expect(c.read(sessionProvider).status, SessionStatus.pendingApproval);
    // The resume short-circuits before the network → no second register call.
    expect(api.calls.where((p) => p == 'POST /auth/register').length, 1);
  });

  test(
      'a 400 (spent jti) WITH a profile_token resumes to the profile step '
      'instead of bouncing to phone', () async {
    // profile_token from a prior 202 + a (stale) phone-verified token still presented.
    final store = InMemoryStore()
      ..phoneVerifiedToken = 'pvt-stale'
      ..onboardingPin = pin
      ..phone = phone
      ..profileToken =
          fakeJwt({'sub': 'u1', 'purpose': 'guard_profile', 'exp': 9999999999});
    final prefs = FakePrefsStore();
    final api = FakeApi(onPost: (_, __) async {
      throw const ApiException(message: 'already used', statusCode: 400);
    });
    final c = container(api: api, store: store, prefs: prefs);
    final ctrl = c.read(registrationControllerProvider.notifier);
    ctrl.selectRole(RegistrationRole.guard);

    expect(await ctrl.register(), RegisterOutcome.needsProfile); // resumed
    expect(c.read(sessionProvider).status, SessionStatus.pendingApproval);
    // Did POST (token present) but recovered rather than wiping onboarding.
    expect(api.calls.where((p) => p == 'POST /auth/register').length, 1);
    expect(store.phoneVerifiedToken, isNull); // stale token dropped on resume
  });

  test('maskAccountNumber masks all but the last 4 digits', () {
    expect(maskAccountNumber('1234567890'), '••••••7890');
    expect(maskAccountNumber('123-45-6789'),
        '•••••6789'); // strips separators first
    expect(maskAccountNumber('123'), '•••');
    expect(maskAccountNumber(''), '');
    expect(maskAccountNumber('1234'), '••••');
  });
}
