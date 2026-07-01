import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/auth_controller.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/models/registration.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  ProviderContainer container(
      {required FakeApi api, required InMemoryStore store}) {
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(store),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test(
      'full flow: challenge → otp → verify → login persists tokens + local PIN',
      () async {
    final store = InMemoryStore();
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/otp/challenge');
        return {
          'challenge_id': 'ch1',
          'question': '1 + 1 = ?',
          'expires_in': 180
        };
      },
      onPost: (path, data) async {
        switch (path) {
          case '/otp/request':
            return {'message': 'sent', 'expires_in': 300};
          case '/otp/verify':
            return {'phone_verified_token': 'pvt', 'expires_in': 300};
          case '/auth/login':
            return {
              'access_token':
                  fakeJwt({'sub': 'u1', 'role': 'customer', 'exp': 9999999999}),
              'refresh_token': 'r1',
              'expires_in': 3600,
              'token_type': 'Bearer',
            };
          default:
            throw StateError('unexpected POST $path');
        }
      },
    );
    final c = container(api: api, store: store);
    final ctrl = c.read(authControllerProvider.notifier);

    ctrl.setPhone('0812345678');
    expect(await ctrl.loadChallenge(), isTrue);
    expect(c.read(authControllerProvider).challenge?.challengeId, 'ch1');

    expect(await ctrl.sendOtp('2'), isTrue);
    expect(c.read(authControllerProvider).step, AuthStep.otp);
    expect(c.read(authControllerProvider).otpSentAt, isNotNull);

    expect(await ctrl.verifyOtp('123456'), isTrue);
    expect(c.read(authControllerProvider).step, AuthStep.pin);
    expect(c.read(authControllerProvider).phoneVerifiedToken, 'pvt',
        reason: 'phone-verified token captured for the register step');
    expect(store.phoneVerifiedToken, 'pvt', reason: 'and persisted (secure)');

    expect(await ctrl.loginWithPin(phone: '0812345678', pin: '135790'), isTrue);
    expect(store.refresh, 'r1');
    expect(store.access, isNotNull);
    expect(store.phone, '0812345678', reason: 'verified phone persisted');
    expect(store.pinHash, isNotNull,
        reason: 'PIN persisted locally for offline unlock');
  });

  test(
      'forgot-PIN: startReset marks the run, resetPin POSTs /auth/reset-pin then logs in',
      () async {
    final store = InMemoryStore();
    final calls = <String>[];
    final api = FakeApi(
      onPost: (path, data) async {
        calls.add(path);
        switch (path) {
          case '/otp/verify':
            return {'phone_verified_token': 'PVT'};
          case '/auth/reset-pin':
            final m = data as Map<String, dynamic>;
            expect(m['phone_verified_token'], 'PVT',
                reason: 'the just-verified token authorises the reset');
            expect(m['new_pin_hash'], isA<String>());
            expect(m.containsKey('phone'), isFalse,
                reason: 'phone comes from the token, never the body');
            return <String, dynamic>{'pin_reset': true};
          case '/auth/login':
            expect((data as Map<String, dynamic>)['identifier'], '0812345678');
            return {
              'access_token':
                  fakeJwt({'sub': 'u1', 'role': 'guard', 'exp': 9999999999}),
              'refresh_token': 'r-new',
              'expires_in': 900,
              'available_roles': ['guard'],
            };
          default:
            throw StateError('unexpected POST $path');
        }
      },
    );
    final c = container(api: api, store: store);
    c.listen(sessionProvider, (_, __) {});
    final ctrl = c.read(authControllerProvider.notifier);

    ctrl.startReset('0812345678');
    expect(c.read(authControllerProvider).reset, isTrue,
        reason: 'the run is a reset, not a registration');
    expect(c.read(authControllerProvider).phone, '0812345678');

    // OTP verify captures the phone-verified token (as the OTP screen does).
    expect(await ctrl.verifyOtp('123456'), isTrue);

    // Reset the PIN → POST /auth/reset-pin, then log in with the NEW PIN → session authenticated.
    expect(await ctrl.resetPin(newPin: '654321'), isTrue);
    expect(calls, ['/otp/verify', '/auth/reset-pin', '/auth/login']);
    expect(store.refresh, 'r-new', reason: 'logged in with the new PIN post-reset');
    expect(store.pinHash, isNotNull, reason: 'new PIN persisted locally');
    expect(c.read(sessionProvider).status, SessionStatus.authenticated);
  });

  test('resetPin with no verified token surfaces an error and posts nothing',
      () async {
    final api = FakeApi(onPost: (_, __) async => throw StateError('no call'));
    final c = container(api: api, store: InMemoryStore());
    final ctrl = c.read(authControllerProvider.notifier);
    ctrl.startReset('0812345678'); // no verifyOtp → no phone_verified_token
    expect(await ctrl.resetPin(newPin: '654321'), isFalse);
    expect(c.read(authControllerProvider).error, isNotNull);
  });

  test(
      'a failed /otp/request reloads a FRESH challenge (the old one is burned) and keeps the error',
      () async {
    // The otp service GETDELs the captcha on EVERY /otp/request, so a retry with the same
    // challenge_id would fail the captcha even with a correct answer. After a failure the controller
    // must fetch a new question while leaving the error message visible.
    final store = InMemoryStore();
    var challengeHits = 0;
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/otp/challenge');
        challengeHits++;
        return {
          'challenge_id': 'ch$challengeHits',
          'question': '1 + 1 = ?',
          'expires_in': 180,
        };
      },
      onPost: (path, _) async {
        expect(path, '/otp/request');
        throw const ApiException(message: 'Rate limit exceeded', statusCode: 429);
      },
    );
    final c = container(api: api, store: store);
    final ctrl = c.read(authControllerProvider.notifier);

    ctrl.setPhone('0812345678');
    await ctrl.loadChallenge();
    expect(c.read(authControllerProvider).challenge?.challengeId, 'ch1');

    expect(await ctrl.sendOtp('2'), isFalse);
    final st = c.read(authControllerProvider);
    expect(st.error, 'Rate limit exceeded', reason: 'the failure reason stays visible');
    expect(st.challenge?.challengeId, 'ch2',
        reason: 'the burned ch1 is replaced by a fresh, usable challenge for the retry');
    expect(st.step, isNot(AuthStep.otp));
  });

  test('invalid Thai phone is rejected before any network call', () async {
    final store = InMemoryStore();
    final api = FakeApi(
        onPost: (_, __) async => throw StateError('should not be called'));
    final ctrl =
        container(api: api, store: store).read(authControllerProvider.notifier);
    ctrl.setPhone('123');
    expect(await ctrl.sendOtp('2'), isFalse);
  });

  test(
      'flow state survives the watching screen unmounting (keepAlive) — phone is '
      'NOT lost navigating phone → captcha', () async {
    final c = container(api: FakeApi(), store: InMemoryStore());
    // Phone screen mounts (watches), stores the canonical number, then unmounts as the
    // captcha is pushed. With an autoDispose controller the state would reset here and the
    // captcha's sendOtp would wrongly reject the already-entered phone (the smoke-test bug).
    final sub = c.listen(authControllerProvider, (_, __) {});
    c.read(authControllerProvider.notifier).setPhone('0812345678');
    sub.close();
    await Future<void>.delayed(
        Duration.zero); // let any autoDispose scheduler run
    expect(c.read(authControllerProvider).phone, '0812345678');
  });

  group('normalizeThaiPhone — UI shows +66, backend wants national 0XXXXXXXXX',
      () {
    test('9-digit significant (what the +66 prefix implies) gets the trunk 0',
        () {
      expect(AuthController.normalizeThaiPhone('812345678'), '0812345678');
      // Spaced as the field renders it — separators are stripped.
      expect(AuthController.normalizeThaiPhone('81 234 5678'), '0812345678');
    });
    test('full national 0XXXXXXXXX (typed by habit) is kept as-is', () {
      expect(AuthController.normalizeThaiPhone('0812345678'), '0812345678');
    });
    test('pasted 66-country-code form is folded to national', () {
      expect(AuthController.normalizeThaiPhone('66812345678'), '0812345678');
    });
    test('non-numbers / wrong lengths are rejected (null)', () {
      expect(AuthController.normalizeThaiPhone(''), isNull);
      expect(AuthController.normalizeThaiPhone('123'), isNull);
      expect(AuthController.normalizeThaiPhone('81234567'), isNull); // 8 digits
      expect(AuthController.normalizeThaiPhone('1812345678'),
          isNull); // 10, no leading 0
      // A 9-digit input that already starts with 0 is malformed behind +66 — reject it
      // instead of producing a double-zero '0012345678'.
      expect(AuthController.normalizeThaiPhone('012345678'), isNull);
    });
    test('isValidPhone accepts both the 9- and 10-digit forms', () {
      final ctrl = container(api: FakeApi(), store: InMemoryStore())
          .read(authControllerProvider.notifier);
      expect(ctrl.isValidPhone('812345678'), isTrue);
      expect(ctrl.isValidPhone('0812345678'), isTrue);
      expect(ctrl.isValidPhone('123'), isFalse);
    });
  });

  test('a 9-digit +66 entry is sent to the backend as national 0XXXXXXXXX',
      () async {
    final store = InMemoryStore();
    String? sentRequestPhone;
    String? sentVerifyPhone;
    final api = FakeApi(
      onGet: (_, __) async =>
          {'challenge_id': 'ch1', 'question': '1 + 1 = ?', 'expires_in': 180},
      onPost: (path, data) async {
        switch (path) {
          case '/otp/request':
            sentRequestPhone = (data as Map?)?['phone'] as String?;
            return {'message': 'sent', 'expires_in': 300};
          case '/otp/verify':
            sentVerifyPhone = (data as Map?)?['phone'] as String?;
            return {'phone_verified_token': 'pvt', 'expires_in': 300};
          default:
            throw StateError('unexpected POST $path');
        }
      },
    );
    final c = container(api: api, store: store);
    final ctrl = c.read(authControllerProvider.notifier);

    // The phone screen stores the canonical form; emulate that handoff.
    ctrl.setPhone(AuthController.normalizeThaiPhone('812345678')!);
    await ctrl.loadChallenge();
    expect(await ctrl.sendOtp('2'), isTrue);
    expect(await ctrl.verifyOtp('123456'), isTrue);

    expect(sentRequestPhone, '0812345678',
        reason: 'backend otp.validate_thai_phone needs the leading 0');
    expect(sentVerifyPhone, '0812345678');
  });

  test(
      'login parses available_roles into the session (dual-role → mode picker eligible)',
      () async {
    final store = InMemoryStore();
    final prefs = FakePrefsStore();
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(FakeApi(onPost: (path, _) async {
        expect(path, '/auth/login');
        return {
          'access_token':
              fakeJwt({'sub': 'u1', 'role': 'customer', 'exp': 9999999999}),
          'refresh_token': 'r1',
          'expires_in': 3600,
          // Multi-role (Option A): the account holds BOTH approved roles.
          'available_roles': ['customer', 'guard'],
        };
      })),
      appStoreProvider.overrideWithValue(store),
      prefsStoreProvider.overrideWithValue(prefs),
    ]);
    addTearDown(c.dispose);

    final ok = await c
        .read(authControllerProvider.notifier)
        .loginWithPin(phone: '0812345678', pin: '135790');
    expect(ok, isTrue);

    final user = c.read(sessionProvider).user!;
    expect(user.role, 'customer', reason: 'active role from the access token');
    expect(user.isEnrolledIn('guard'), isTrue);
    expect(user.hasMultipleRoles, isTrue);
    // Persisted (non-sensitive) so a cold start lands on the picker.
    expect(prefs.values[kEnrolledRolesKey], 'customer,guard');
  });

  test('a single-role login defaults available_roles to [active role]', () async {
    final store = InMemoryStore();
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(FakeApi(onPost: (path, _) async {
        return {
          'access_token':
              fakeJwt({'sub': 'u9', 'role': 'guard', 'exp': 9999999999}),
          'refresh_token': 'r9',
          'expires_in': 3600,
          // No available_roles field (older shape) → fall back to [active].
        };
      })),
      appStoreProvider.overrideWithValue(store),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ]);
    addTearDown(c.dispose);

    await c
        .read(authControllerProvider.notifier)
        .loginWithPin(phone: '0812345678', pin: '135790');
    final user = c.read(sessionProvider).user!;
    expect(user.enrolledRoles, ['guard']);
    expect(user.hasMultipleRoles, isFalse);
  });

  test('login failure surfaces the server message and stores no tokens',
      () async {
    final store = InMemoryStore();
    final api = FakeApi(onPost: (path, _) async {
      if (path == '/auth/login') {
        throw const ApiException(
            message: 'Invalid credentials',
            code: 'UNAUTHORIZED',
            statusCode: 401);
      }
      return <String, dynamic>{};
    });
    final c = container(api: api, store: store);
    final ctrl = c.read(authControllerProvider.notifier);
    ctrl.setPhone('0812345678');
    expect(
        await ctrl.loginWithPin(phone: '0812345678', pin: '135790'), isFalse);
    expect(c.read(authControllerProvider).error, 'Invalid credentials');
    expect(store.access, isNull);
  });

  test(
      'a fresh OTP request clears stale registration tokens (no cross-flow '
      'resume from a previous abandoned register)', () async {
    // A profile_token + phone-verified token left over from a prior, abandoned register on a
    // DIFFERENT phone. Starting a new OTP flow must wipe them so they can't later trigger a
    // spurious "resume to profile" against the wrong account.
    final store = InMemoryStore()
      ..profileToken = 'stale-A'
      ..phoneVerifiedToken = 'stale-pvt';
    final api = FakeApi(
      onGet: (path, _) async =>
          {'challenge_id': 'ch1', 'question': '1 + 1 = ?', 'expires_in': 180},
      onPost: (path, data) async {
        expect(path, '/otp/request');
        return {'message': 'sent', 'expires_in': 300};
      },
    );
    final c = container(api: api, store: store);
    final ctrl = c.read(authControllerProvider.notifier);
    ctrl.setPhone('0812345678');
    await ctrl.loadChallenge();

    expect(await ctrl.sendOtp('2'), isTrue);
    expect(store.profileToken, isNull, reason: 'stale profile_token cleared');
    expect(store.phoneVerifiedToken, isNull, reason: 'stale pvt cleared');
  });

  test(
      're-entrancy: a duplicate verify while one is in flight is a no-op '
      '(only ONE /otp/verify POST)', () async {
    final store = InMemoryStore();
    final gate = Completer<Map<String, dynamic>>();
    final api = FakeApi(onPost: (path, data) {
      expect(path, '/otp/verify');
      return gate.future; // first call blocks here, holding busy=true
    });
    final c = container(api: api, store: store);
    final ctrl = c.read(authControllerProvider.notifier);
    ctrl.setPhone('0812345678');

    // Fire two verifies back-to-back (mimics OtpInput auto-submit firing twice / a double-tap).
    final first = ctrl.verifyOtp('123456'); // in flight (busy set synchronously)
    final second = await ctrl.verifyOtp('123456'); // sees busy → bails immediately

    expect(second, isFalse, reason: 'the duplicate must be ignored');
    expect(api.calls.where((p) => p == 'POST /otp/verify').length, 1,
        reason: 'only the first verify should hit the network');

    gate.complete({'phone_verified_token': 'pvt'});
    expect(await first, isTrue);
    expect(store.phoneVerifiedToken, 'pvt');
  });
}
