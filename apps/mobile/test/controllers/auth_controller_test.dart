import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/auth_controller.dart';
import 'package:pguard_mobile/core/controllers/locale_controller.dart';
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
            expect(
                (data as Map<String, dynamic>).containsKey('purpose'), isFalse,
                reason: 'a REGISTRATION request binds no purpose (server '
                    'default phone_verify) — pin_reset is reset-run only');
            return {'message': 'sent', 'expires_in': 300};
          case '/otp/verify':
            expect(
                (data as Map<String, dynamic>).containsKey('purpose'), isFalse,
                reason:
                    'a REGISTRATION verify sends no purpose (server default '
                    'phone_verify) — pin_reset is reset-run only');
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
      onGet: (path, _) async {
        expect(path, '/otp/challenge');
        return {
          'challenge_id': 'chR',
          'question': '1 + 1 = ?',
          'expires_in': 180,
        };
      },
      onPost: (path, data) async {
        calls.add(path);
        switch (path) {
          case '/otp/request':
            expect((data as Map<String, dynamic>)['purpose'], 'pin_reset',
                reason: 'a RESET run BINDS the purpose at request time — the '
                    'server stores it on the code row and words the SMS as a '
                    'PIN reset');
            return {'message': 'sent', 'expires_in': 300};
          case '/otp/verify':
            expect((data as Map<String, dynamic>)['purpose'], 'pin_reset',
                reason: 'the verify cross-checks the same flow; the token '
                    'purpose itself comes from the request-time binding');
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

    // Captcha → OTP request (binds purpose) → verify (as the reset screens do).
    expect(await ctrl.loadChallenge(), isTrue);
    expect(await ctrl.sendOtp('2'), isTrue);
    expect(await ctrl.verifyOtp('123456'), isTrue);

    // Reset the PIN → POST /auth/reset-pin, then log in with the NEW PIN → session authenticated.
    expect(await ctrl.resetPin(newPin: '654321'), ResetPinOutcome.loggedIn);
    expect(calls,
        ['/otp/request', '/otp/verify', '/auth/reset-pin', '/auth/login']);
    expect(store.refresh, 'r-new',
        reason: 'logged in with the new PIN post-reset');
    expect(store.pinHash, isNotNull, reason: 'new PIN persisted locally');
    expect(c.read(sessionProvider).status, SessionStatus.authenticated);
  });

  test('resetPin with no verified token surfaces an error and posts nothing',
      () async {
    final api = FakeApi(onPost: (_, __) async => throw StateError('no call'));
    final c = container(api: api, store: InMemoryStore());
    final ctrl = c.read(authControllerProvider.notifier);
    ctrl.startReset('0812345678'); // no verifyOtp → no phone_verified_token
    expect(await ctrl.resetPin(newPin: '654321'), ResetPinOutcome.failed,
        reason: 'no token → nothing was changed, so this is a plain failure');
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
        throw const ApiException(
            message: 'Rate limit exceeded', statusCode: 429);
      },
    );
    final c = container(api: api, store: store);
    final ctrl = c.read(authControllerProvider.notifier);

    ctrl.setPhone('0812345678');
    await ctrl.loadChallenge();
    expect(c.read(authControllerProvider).challenge?.challengeId, 'ch1');

    expect(await ctrl.sendOtp('2'), isFalse);
    final st = c.read(authControllerProvider);
    // A 429 is now LOCALIZED (Thai default) — not the raw English 'Rate limit exceeded' the gateway
    // sends as a bare string (deep-review captcha/language fix).
    expect(st.error, 'ส่งคำขอถี่เกินไป กรุณารอสักครู่แล้วลองใหม่',
        reason: 'the failure reason stays visible, localized');
    expect(st.challenge?.challengeId, 'ch2',
        reason:
            'the burned ch1 is replaced by a fresh, usable challenge for the retry');
    expect(st.step, isNot(AuthStep.otp));
  });

  // ISSUE 5: a coded backend error is localized to the APP's language by CODE — not shown as the
  // raw server text (which is hard-coded Thai) — so the copy is consistent with the selected locale.
  FakeApi codedCooldownApi() {
    var hits = 0;
    return FakeApi(
      onGet: (path, _) async {
        hits++;
        return {
          'challenge_id': 'ch$hits',
          'question': '1 + 1 = ?',
          'expires_in': 180,
        };
      },
      // Server returns a Thai literal + a machine-readable code.
      onPost: (path, _) async => throw const ApiException(
          message: 'กรุณารอสักครู่ก่อนขอ OTP ใหม่',
          code: 'OTP_COOLDOWN',
          statusCode: 400),
    );
  }

  test(
      'sendOtp localizes a coded error by CODE, not the raw server text (issue 5, TH default)',
      () async {
    final c = container(api: codedCooldownApi(), store: InMemoryStore());
    final ctrl = c.read(authControllerProvider.notifier);
    ctrl.setPhone('0812345678');
    await ctrl.loadChallenge();
    expect(await ctrl.sendOtp('2'), isFalse);
    // The CLIENT's Thai copy (keyed on OTP_COOLDOWN) — distinct from the raw server string.
    expect(
        c.read(authControllerProvider).error, 'กรุณารอสักครู่ก่อนขอรหัสใหม่');
  });

  test(
      'sendOtp error copy follows the app language, not the server (issue 5, EN)',
      () async {
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(codedCooldownApi()),
      appStoreProvider.overrideWithValue(InMemoryStore()),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      localeControllerProvider.overrideWith(_EnLocale.new),
    ]);
    addTearDown(c.dispose);
    final ctrl = c.read(authControllerProvider.notifier);
    ctrl.setPhone('0812345678');
    await ctrl.loadChallenge();
    expect(await ctrl.sendOtp('2'), isFalse);
    // Server text was Thai, but the app is English → English copy (no Thai leak).
    expect(c.read(authControllerProvider).error,
        'Please wait a moment before requesting another code');
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

  test('a single-role login defaults available_roles to [active role]',
      () async {
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

  test('login failure surfaces a LOCALIZED error and stores no tokens',
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
    // A 401 on the auth flow is localized (Thai default) — NOT the raw English "Invalid
    // credentials" the returning-login screen used to surface (deep-review language fix).
    expect(c.read(authControllerProvider).error, 'ข้อมูลเข้าสู่ระบบไม่ถูกต้อง');
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
    final first =
        ctrl.verifyOtp('123456'); // in flight (busy set synchronously)
    final second =
        await ctrl.verifyOtp('123456'); // sees busy → bails immediately

    expect(second, isFalse, reason: 'the duplicate must be ignored');
    expect(api.calls.where((p) => p == 'POST /otp/verify').length, 1,
        reason: 'only the first verify should hit the network');

    gate.complete({'phone_verified_token': 'pvt'});
    expect(await first, isTrue);
    expect(store.phoneVerifiedToken, 'pvt');
  });

  test(
      're-entry: loadChallenge DROPS the burned challenge before fetching, so a '
      'correct answer can never hit a dead challenge_id (CAPTCHA_INVALID fix)',
      () async {
    // On-device repro: after "ไม่ได้รับรหัส? ขอใหม่" (OTP screen → go('/auth/captcha')) the keepAlive
    // state still holds the PREVIOUS challenge — already BURNED server-side (Redis GETDEL) by the
    // /otp/request that advanced to OTP. Re-entering must not leave that dead challenge submittable:
    // loadChallenge nulls it FIRST (screen shows loading + submit disabled) until a live one lands.
    final store = InMemoryStore();
    final gate = Completer<Map<String, dynamic>>();
    var served = 0;
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/otp/challenge');
        served++;
        if (served == 1) {
          return {
            'challenge_id': 'burned-ch1',
            'question': '1 + 1 = ?',
            'expires_in': 180
          };
        }
        return gate.future; // the re-entry fetch is held open
      },
    );
    final c = container(api: api, store: store);
    final ctrl = c.read(authControllerProvider.notifier);

    // First visit loads ch1 (the challenge the OTP request will burn).
    await ctrl.loadChallenge();
    expect(c.read(authControllerProvider).challenge?.challengeId, 'burned-ch1');

    // Re-enter the captcha screen: loadChallenge fires again, its fetch still open.
    final reentry = ctrl.loadChallenge();
    // The burned challenge is ALREADY gone (cleared synchronously before the await) — nothing is
    // submittable, so the dead challenge_id can never reach /otp/request.
    expect(c.read(authControllerProvider).challenge, isNull,
        reason:
            'the burned challenge must be dropped before the new fetch resolves');

    // The fresh challenge lands and becomes the only submittable one.
    gate.complete({
      'challenge_id': 'fresh-ch2',
      'question': '2 + 2 = ?',
      'expires_in': 180
    });
    await reentry;
    expect(c.read(authControllerProvider).challenge?.challengeId, 'fresh-ch2');
  });

  test(
      'a 500 from /otp/request (e.g. SMS gateway out of credits) shows the '
      'localized server-problem message, NOT the raw INTERNAL_ERROR text',
      () async {
    // The 2026-07-21 on-device shape: the captcha PASSED, the SMS send failed (INET code=08
    // "Insufficient SMS Credits") → 500 INTERNAL_ERROR. The raw server text under the captcha —
    // shown at the same moment the challenge auto-refreshes — read as "answer rejected", so QA
    // reported a captcha bug that wasn't one. A 5xx must localize to an infrastructure message.
    final store = InMemoryStore();
    var served = 0;
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/otp/challenge');
        served++;
        return {
          'challenge_id': 'ch$served',
          'question': '3 + 4 = ?',
          'expires_in': 180
        };
      },
      onPost: (path, _) async {
        expect(path, '/otp/request');
        throw const ApiException(
            message: 'Internal server error',
            code: 'INTERNAL_ERROR',
            statusCode: 500);
      },
    );
    final c = container(api: api, store: store);
    final ctrl = c.read(authControllerProvider.notifier);
    ctrl.setPhone('0812345678');
    await ctrl.loadChallenge();

    final ok = await ctrl.sendOtp('7');

    expect(ok, isFalse);
    final state = c.read(authControllerProvider);
    expect(state.error, 'ระบบขัดข้องชั่วคราว กรุณาลองใหม่ภายหลัง',
        reason: 'a 5xx must surface as an infrastructure problem in the app '
            'language — never the raw server text (which reads as a captcha '
            'rejection when the question refreshes at the same moment)');
    expect(served, 2,
        reason: 'the burned challenge is still auto-refreshed after the 500');
  });

  test(
      'forgot-PIN: a reset that succeeds but cannot sign in reports the PIN AS CHANGED',
      () async {
    // The incident: reset-pin succeeded (PIN changed, token spent, every session revoked) and the
    // login right after it did not go through. The screen said "could not reset the PIN", so the
    // user re-submitted — and the only possible answer was "token already used", while their PIN
    // had in fact changed. The outcome must tell the two apart.
    final calls = <String>[];
    final api = FakeApi(
      onGet: (_, __) async =>
          {'challenge_id': 'chR', 'question': '1 + 1 = ?', 'expires_in': 180},
      onPost: (path, _) async {
        calls.add(path);
        switch (path) {
          case '/otp/request':
            return {'message': 'sent', 'expires_in': 300};
          case '/otp/verify':
            return {'phone_verified_token': 'PVT'};
          case '/auth/reset-pin':
            return <String, dynamic>{'pin_reset': true};
          case '/auth/login':
            throw const ApiException(
                message: 'Invalid credentials', statusCode: 401);
          default:
            throw StateError('unexpected POST $path');
        }
      },
    );
    final c = container(api: api, store: InMemoryStore());
    c.listen(sessionProvider, (_, __) {});
    final ctrl = c.read(authControllerProvider.notifier);
    ctrl.startReset('0812345678');
    expect(await ctrl.loadChallenge(), isTrue);
    expect(await ctrl.sendOtp('2'), isTrue);
    expect(await ctrl.verifyOtp('123456'), isTrue);

    expect(await ctrl.resetPin(newPin: '654321'),
        ResetPinOutcome.pinChangedSignInNeeded,
        reason: 'the PIN changed — never report this as a failed reset');
    expect(calls.last, '/auth/login',
        reason: 'the reset itself was reached and did succeed');
  });

  test('forgot-PIN: a rejected reset leaves the PIN alone and never logs in',
      () async {
    final calls = <String>[];
    final api = FakeApi(
      onGet: (_, __) async =>
          {'challenge_id': 'chR', 'question': '1 + 1 = ?', 'expires_in': 180},
      onPost: (path, _) async {
        calls.add(path);
        switch (path) {
          case '/otp/request':
            return {'message': 'sent', 'expires_in': 300};
          case '/otp/verify':
            return {'phone_verified_token': 'PVT'};
          case '/auth/reset-pin':
            throw const ApiException(
                message:
                    'Phone verification token is invalid, expired, or already used',
                statusCode: 400);
          default:
            throw StateError('unexpected POST $path');
        }
      },
    );
    final c = container(api: api, store: InMemoryStore());
    c.listen(sessionProvider, (_, __) {});
    final ctrl = c.read(authControllerProvider.notifier);
    ctrl.startReset('0812345678');
    expect(await ctrl.loadChallenge(), isTrue);
    expect(await ctrl.sendOtp('2'), isTrue);
    expect(await ctrl.verifyOtp('123456'), isTrue);

    expect(await ctrl.resetPin(newPin: '654321'), ResetPinOutcome.failed);
    expect(calls, isNot(contains('/auth/login')),
        reason: 'nothing changed, so there is no new PIN to sign in with');
  });

  test(
      'change-phone: startPhoneChange binds purpose=phone_change through OTP, then '
      'changePhone PATCHes /auth/phone and drops to returning-login on the NEW number',
      () async {
    final store = InMemoryStore()..phone = '0811111111';
    final calls = <String>[];
    Map<String, dynamic>? patchBody;
    final api = FakeApi(
      onGet: (_, __) async =>
          {'challenge_id': 'chC', 'question': '1 + 1 = ?', 'expires_in': 180},
      onPost: (path, data) async {
        calls.add(path);
        switch (path) {
          case '/otp/request':
            expect((data as Map<String, dynamic>)['purpose'], 'phone_change',
                reason: 'a phone-change run BINDS purpose=phone_change at '
                    'request time (SMS names the action; the token can only '
                    'drive a phone change)');
            return {'message': 'sent', 'expires_in': 300};
          case '/otp/verify':
            expect((data as Map<String, dynamic>)['purpose'], 'phone_change');
            return {'phone_verified_token': 'PCT'};
          default:
            throw StateError('unexpected POST $path');
        }
      },
      onPatch: (path, data) async {
        calls.add(path);
        expect(path, '/auth/phone');
        patchBody = data as Map<String, dynamic>;
        return <String, dynamic>{'phone_changed': true};
      },
    );
    final c = container(api: api, store: store);
    c.listen(sessionProvider, (_, __) {});
    final ctrl = c.read(authControllerProvider.notifier);

    ctrl.startPhoneChange('0899999999');
    expect(c.read(authControllerProvider).phoneChange, isTrue);
    expect(c.read(authControllerProvider).phone, '0899999999');

    expect(await ctrl.loadChallenge(), isTrue);
    expect(await ctrl.sendOtp('2'), isTrue);
    expect(await ctrl.verifyOtp('123456'), isTrue);
    expect(c.read(authControllerProvider).phoneVerifiedToken, 'PCT');

    // Confirm the current PIN → PATCH /auth/phone → success (null = no error).
    expect(await ctrl.changePhone(currentPin: '135790'), isNull);
    expect(patchBody!['phone_change_token'], 'PCT',
        reason: 'the just-verified token authorises the change');
    expect(patchBody!['current_pin_hash'], isA<String>(),
        reason: 'the current PIN is sent as its SHA-256 hash (step-up)');
    expect(patchBody!.containsKey('phone'), isFalse,
        reason: 'the new phone comes from the token, never the body');
    expect(calls, ['/otp/request', '/otp/verify', '/auth/phone']);

    // Every session was revoked server-side → drop to returning-login on the NEW number (local PIN
    // unchanged), and persist the new number for the PIN-login screen.
    expect(c.read(sessionProvider).status, SessionStatus.returning);
    expect(store.phone, '0899999999',
        reason: 'the new login number is persisted for PIN-login');
  });

  test(
      'change-phone: a PHONE_TAKEN 409 is localized and does NOT change the session',
      () async {
    final store = InMemoryStore()..phone = '0811111111';
    final api = FakeApi(
      onGet: (_, __) async =>
          {'challenge_id': 'chC', 'question': '1 + 1 = ?', 'expires_in': 180},
      onPost: (path, _) async {
        switch (path) {
          case '/otp/request':
            return {'message': 'sent', 'expires_in': 300};
          case '/otp/verify':
            return {'phone_verified_token': 'PCT'};
          default:
            throw StateError('unexpected POST $path');
        }
      },
      onPatch: (_, __) async => throw const ApiException(
          message: 'This phone number is already in use by another account.',
          code: 'PHONE_TAKEN',
          statusCode: 409),
    );
    final c = container(api: api, store: store);
    c.listen(sessionProvider, (_, __) {});
    final ctrl = c.read(authControllerProvider.notifier);
    ctrl.startPhoneChange('0899999999');
    await ctrl.loadChallenge();
    await ctrl.sendOtp('2');
    await ctrl.verifyOtp('123456');

    final err = await ctrl.changePhone(currentPin: '135790');
    expect(err, 'เบอร์นี้ถูกใช้สมัครแล้ว',
        reason: 'PHONE_TAKEN is localized to the app language (Thai default)');
    expect(c.read(sessionProvider).status, isNot(SessionStatus.returning),
        reason: 'a rejected change must not sign the user out');
    expect(store.phone, '0811111111',
        reason:
            'the persisted login phone is unchanged after a rejected change');
  });
}

/// Forces the English locale so the localized-error test can assert the app-language copy.
class _EnLocale extends LocaleController {
  @override
  AppLocale build() => AppLocale.en;
}
