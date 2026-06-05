import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/guard_jobs_controller.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson(String id, String status) => {
      'id': id,
      'customer_id': 'c1',
      'guard_id': status == 'requested' ? null : 'g1',
      'status': status,
      'address': 'หมู่บ้านลัดดารมย์',
      'scheduled_at': '2026-06-05T14:00:00Z',
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'tip': '0',
      'created_at': '2026-06-05T10:00:00Z',
      'updated_at': '2026-06-05T10:00:00Z',
    };

void main() {
  test('loads bookings and partitions into incoming vs active', () async {
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/bookings');
        return [
          bookingJson('b1', 'requested'),
          bookingJson('b2', 'accepted'),
          bookingJson('b3', 'completed'),
        ];
      },
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    final list = await c.read(guardJobsControllerProvider.future);
    expect(list, hasLength(3));
    expect(GuardJobsController.incoming(list).map((b) => b.id), ['b1']);
    expect(GuardJobsController.active(list).map((b) => b.id), ['b2']);
  });

  test('accept POSTs and decline PUTs the correct paths', () async {
    final api = FakeApi(
      onGet: (_, __) async => [bookingJson('b1', 'requested')],
      onPost: (path, _) async {
        expect(path, '/bookings/b1/accept');
        return bookingJson('b1', 'accepted');
      },
      onPut: (path, _) async {
        expect(path, '/bookings/b1/decline');
        return bookingJson('b1', 'declined');
      },
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);
    await c.read(guardJobsControllerProvider.future);
    final ctrl = c.read(guardJobsControllerProvider.notifier);

    expect(await ctrl.accept('b1'), isNull); // null = success
    expect(api.calls, contains('POST /bookings/b1/accept'));

    expect(await ctrl.decline('b1'), isNull);
    expect(api.calls, contains('PUT /bookings/b1/decline'));
  });

  test('accept surfaces the server error message (and does not throw)', () async {
    final api = FakeApi(
      onGet: (_, __) async => [bookingJson('b1', 'requested')],
      onPost: (_, __) async => throw const ApiException(
          message: 'Already taken', code: 'CONFLICT', statusCode: 409),
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);
    await c.read(guardJobsControllerProvider.future);
    final err = await c.read(guardJobsControllerProvider.notifier).accept('b1');
    expect(err, 'Already taken');
  });
}
