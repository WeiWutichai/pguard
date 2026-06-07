import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/profile_controller.dart';
import 'package:pguard_mobile/core/models/profile.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  ProviderContainer container(FakeApi api, {InMemoryStore? store}) {
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider
          .overrideWithValue(store ?? (InMemoryStore()..access = 't')),
      // logout() now also clears pending-registration prefs — keep it off real SharedPreferences.
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('merges /auth/me + /profile/me (customer) + local phone', () async {
    final api = FakeApi(onGet: (path, _) async {
      switch (path) {
        case '/auth/me':
          return {'user_id': 'u1', 'role': 'customer'};
        case '/profile/me':
          return {
            'kind': 'customer',
            'user_id': 'u1',
            'full_name': 'นภาพร ศรีสุข',
            'address': 'บางนา',
          };
        default:
          throw StateError(path);
      }
    });
    final store = InMemoryStore()
      ..access = 't'
      ..phone = '0812345678';
    final p = await container(api, store: store)
        .read(profileControllerProvider.future);
    expect(p.role, 'customer');
    expect(p.isCustomer, isTrue);
    expect(p.fullName, 'นภาพร ศรีสุข');
    expect(p.address, 'บางนา');
    expect(p.phone, '0812345678');
    expect(p.displayName, 'นภาพร ศรีสุข');
  });

  test('parses guard profile (approval + masked account)', () async {
    final api = FakeApi(onGet: (path, _) async {
      switch (path) {
        case '/auth/me':
          return {'user_id': 'g1', 'role': 'guard'};
        case '/profile/me':
          return {
            'kind': 'guard',
            'user_id': 'g1',
            'years_of_experience': 6,
            'account_number': '••••7890',
            'account_name': 'สมชาย ก.',
            'approval_status': 'approved',
          };
        default:
          throw StateError(path);
      }
    });
    final p = await container(api).read(profileControllerProvider.future);
    expect(p.isGuard, isTrue);
    expect(p.yearsOfExperience, 6);
    expect(p.accountNumberMasked, '••••7890');
    expect(p.approvalStatus, ApprovalStatus.approved);
    expect(p.displayName, 'สมชาย ก.'); // falls back to account_name (no name field)
  });

  test('tolerates a 404 profile (not set up yet)', () async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/auth/me') return {'user_id': 'u1', 'role': 'customer'};
      throw const ApiException(message: 'not found', statusCode: 404);
    });
    final p = await container(api).read(profileControllerProvider.future);
    expect(p.kind, 'customer'); // inferred from role
    expect(p.fullName, isNull);
  });

  test('save (customer) POSTs /profile/customer', () async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/auth/me'
          ? {'user_id': 'u1', 'role': 'customer'}
          : {'kind': 'customer', 'user_id': 'u1'},
      onPost: (path, data) async {
        expect(path, '/profile/customer');
        expect(data, {'full_name': 'ใหม่', 'address': 'ที่อยู่ใหม่'});
        return {'kind': 'customer', 'user_id': 'u1', 'full_name': 'ใหม่'};
      },
    );
    final c = container(api);
    await c.read(profileControllerProvider.future);
    final err = await c
        .read(profileControllerProvider.notifier)
        .save(fullName: 'ใหม่', address: 'ที่อยู่ใหม่');
    expect(err, isNull);
    expect(api.calls, contains('POST /profile/customer'));
  });

  test('save (guard) POSTs /profile/guard with only provided fields', () async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/auth/me'
          ? {'user_id': 'g1', 'role': 'guard'}
          : {'kind': 'guard', 'user_id': 'g1'},
      onPost: (path, data) async {
        expect(path, '/profile/guard');
        expect(data, {'years_of_experience': 8, 'account_name': 'สมชาย'});
        return {'kind': 'guard', 'user_id': 'g1'};
      },
    );
    final c = container(api);
    await c.read(profileControllerProvider.future);
    final err = await c
        .read(profileControllerProvider.notifier)
        .save(yearsOfExperience: 8, accountName: 'สมชาย');
    expect(err, isNull);
    expect(api.calls, contains('POST /profile/guard'));
  });

  test('logout POSTs /auth/logout with the refresh token then clears session',
      () async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/auth/me'
          ? {'user_id': 'u1', 'role': 'customer'}
          : {'kind': 'customer', 'user_id': 'u1'},
      onPost: (path, data) async {
        expect(path, '/auth/logout');
        expect(data, {'refresh_token': 'r1'});
        return null;
      },
    );
    final store = InMemoryStore()
      ..access = 'a1'
      ..refresh = 'r1'
      ..phone = '0812345678';
    final c = container(api, store: store);
    await c.read(profileControllerProvider.future);
    await c.read(profileControllerProvider.notifier).logout();

    expect(api.calls, contains('POST /auth/logout'));
    expect(store.access, isNull);
    expect(store.refresh, isNull);
    expect(store.phone, isNull); // PII cleared on logout
  });
}
