import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/customer_home_controller.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson(String id,
        {required String customerId, String? guardId}) =>
    {
      'id': id,
      'customer_id': customerId,
      'guard_id': guardId,
      'status': 'accepted',
      'address': 'คอนโด ไอดีโอ',
      'scheduled_at': '2026-06-05T14:00:00Z',
      'hours': 4,
      'base_fee': '300.00',
      'guard_count': 1,
      'tip': '0',
      'created_at': '2026-06-05T10:00:00Z',
      'updated_at': '2026-06-05T10:00:00Z',
    };

void main() {
  test(
      'customer bookings are scoped by the SESSION user id even when the stored token '
      'is momentarily unreadable (mirrors the guard sibling fix)', () async {
    // GET /bookings returns rows where customer_id = me OR guard_id = me. The dashboard must show
    // ONLY the account\'s own hires. Before the fix, identity came from Jwt.subject(readAccessToken())
    // — a null token read yielded me == null → the fail-closed branch emptied the ENTIRE list even
    // though the fetch succeeded (interceptor refresh). Identity now comes from the session.
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/bookings');
        return [
          bookingJson('own-hire', customerId: 'c1'), // the account\'s own hire
          bookingJson('guard-job',
              customerId: 'someone-else',
              guardId: 'c1'), // the account acting as GUARD
        ];
      },
    );
    // No stored token at all (the exact null-read that used to blank the list); the session is a
    // valid customer `c1`.
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ]);
    addTearDown(c.dispose);
    c.read(sessionProvider.notifier).onLoggedIn(
          const AuthUser(userId: 'c1', role: 'customer', roles: ['customer']),
        );

    final list = await c.read(customerHomeControllerProvider.future);
    expect(list.map((b) => b.id), ['own-hire'],
        reason:
            'only the customer\'s own hire; the accepted guard job never leaks onto the '
            'customer surface, and the list is NOT emptied by a null token read');
  });

  test(
      'falls back to the JWT subject when there is no live session user (bare unit '
      'container)', () async {
    final api = FakeApi(
      onGet: (_, __) async => [
        bookingJson('own-hire', customerId: 'c9'),
        bookingJson('guard-job', customerId: 'x', guardId: 'c9'),
      ],
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      // A well-formed access token whose subject is c9; no session user set.
      appStoreProvider.overrideWithValue(
          InMemoryStore()..access = fakeJwt({'sub': 'c9', 'role': 'customer'})),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ]);
    addTearDown(c.dispose);

    final list = await c.read(customerHomeControllerProvider.future);
    expect(list.map((b) => b.id), ['own-hire'],
        reason:
            'the JWT subject still scopes the list when the session is absent');
  });

  test(
      'fail-closed: no session AND no token → empty (never the unfiltered OR-list)',
      () async {
    final api = FakeApi(
      onGet: (_, __) async => [
        bookingJson('own-hire', customerId: 'c1'),
        bookingJson('guard-job', customerId: 'x', guardId: 'c1'),
      ],
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()), // no token
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ]);
    addTearDown(c.dispose);

    final list = await c.read(customerHomeControllerProvider.future);
    expect(list, isEmpty,
        reason: 'no resolvable identity → show nothing, never the raw OR-list');
  });
}
