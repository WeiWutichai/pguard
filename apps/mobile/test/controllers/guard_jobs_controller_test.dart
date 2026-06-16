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
  test(
      'merges assigned (/bookings) + open discovery (/bookings/open) and partitions '
      'incoming from the open feed, active/completed from the assigned feed', () async {
    final api = FakeApi(
      onGet: (path, _) async {
        switch (path) {
          case '/bookings':
            return [bookingJson('b2', 'accepted'), bookingJson('b3', 'completed')];
          case '/bookings/open':
            return [bookingJson('b1', 'requested')];
          default:
            throw StateError('unexpected GET $path');
        }
      },
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    final list = await c.read(guardJobsControllerProvider.future);
    expect(list, hasLength(3));
    expect(GuardJobsController.incoming(list).map((b) => b.id), ['b1'],
        reason: 'incoming = the open-discovery feed (requested, unassigned)');
    expect(GuardJobsController.active(list).map((b) => b.id), ['b2']);
    expect(GuardJobsController.completed(list).map((b) => b.id), ['b3']);
    // Assigned first, then open — both fetched.
    expect(api.calls, ['GET /bookings', 'GET /bookings/open']);
  });

  test('open-feed failure degrades to assigned-only (no throw, incoming empty)', () async {
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings') return [bookingJson('b2', 'accepted')];
        throw const ApiException(
            message: 'discovery down', code: 'UNAVAILABLE', statusCode: 503);
      },
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    final list = await c.read(guardJobsControllerProvider.future);
    expect(list.map((b) => b.id), ['b2'],
        reason: 'a discovery hiccup must NOT blank the guard\'s assigned jobs');
    expect(GuardJobsController.incoming(list), isEmpty);
  });

  test('accept POSTs the correct path (claiming an open job)', () async {
    final api = FakeApi(
      onGet: (path, _) async =>
          path == '/bookings/open' ? [bookingJson('b1', 'requested')] : const [],
      onPost: (path, _) async {
        expect(path, '/bookings/b1/accept');
        return bookingJson('b1', 'accepted');
      },
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);
    await c.read(guardJobsControllerProvider.future);

    expect(await c.read(guardJobsControllerProvider.notifier).accept('b1'),
        isNull); // null = success
    expect(api.calls, contains('POST /bookings/b1/accept'));
  });

  test('dismiss hides an offer locally with NO mutating API call', () async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/open'
          ? [bookingJson('b1', 'requested'), bookingJson('b2', 'requested')]
          : const [],
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);
    await c.read(guardJobsControllerProvider.future);

    c.read(guardJobsControllerProvider.notifier).dismiss('b1');
    expect(c.read(guardJobsControllerProvider).value!.map((b) => b.id), ['b2']);
    // First-come-accept: dismiss must not call the (illegal pre-accept) decline endpoint —
    // only the two read calls from build happened.
    expect(api.calls, ['GET /bookings', 'GET /bookings/open']);
  });

  test('accept surfaces the server error message (and does not throw)', () async {
    final api = FakeApi(
      onGet: (path, _) async =>
          path == '/bookings/open' ? [bookingJson('b1', 'requested')] : const [],
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
