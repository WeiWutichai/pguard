import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/auth_controller.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  ProviderContainer container(
      {required FakeApi api, required InMemoryStore store}) {
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(store),
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

    expect(
        await ctrl.loginWithPin(phone: '0812345678', pin: '135790'), isTrue);
    expect(store.refresh, 'r1');
    expect(store.access, isNotNull);
    expect(store.phone, '0812345678', reason: 'verified phone persisted');
    expect(store.pinHash, isNotNull,
        reason: 'PIN persisted locally for offline unlock');
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

  group('normalizeThaiPhone — UI shows +66, backend wants national 0XXXXXXXXX', () {
    test('9-digit significant (what the +66 prefix implies) gets the trunk 0', () {
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
      expect(AuthController.normalizeThaiPhone('1812345678'), isNull); // 10, no leading 0
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
}
