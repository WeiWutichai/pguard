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
