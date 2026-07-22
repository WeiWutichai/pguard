import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/notification_controller.dart';
import 'package:pguard_mobile/core/models/notification.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

Map<String, dynamic> notifJson(String id, bool isRead,
        {String type = 'booking_created'}) =>
    {
      'id': id,
      'user_id': 'u1',
      'title': 'หัวข้อ $id',
      'body': 'รายละเอียด $id',
      'notification_type': type,
      'is_read': isRead,
      'sent_at': '2026-06-06T11:55:00Z',
      'read_at': null,
    };

void main() {
  ProviderContainer container(FakeApi api) {
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      // The controller now reads the active role off sessionProvider (to scope /notifications by
      // role); sessionProvider.build loads SharedPreferences, so override the prefs store with a
      // fake or the pure unit test crashes on an uninitialized binding. No session is seeded → role
      // is null → the calls stay unscoped (exactly what these path assertions expect).
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('loads notifications and parses the real field names', () async {
    final api = FakeApi(onGet: (path, _) async {
      expect(path, '/notifications');
      return [notifJson('n1', false), notifJson('n2', true)];
    });
    final c = container(api);
    final list = await c.read(notificationControllerProvider.future);
    expect(list, hasLength(2));
    expect(list.first.id, 'n1');
    expect(list.first.isRead, isFalse);
    expect(list.first.body, 'รายละเอียด n1');
    expect(list.first.type, NotificationType.bookingCreated);
  });

  test('markRead is optimistic and PUTs the right path', () async {
    final api = FakeApi(
      onGet: (_, __) async => [notifJson('n1', false), notifJson('n2', true)],
      onPut: (path, _) async {
        expect(path, '/notifications/n1/read');
        return notifJson('n1', true);
      },
    );
    final c = container(api);
    await c.read(notificationControllerProvider.future);
    await c.read(notificationControllerProvider.notifier).markRead('n1');

    final list = c.read(notificationControllerProvider).value!;
    expect(list.firstWhere((n) => n.id == 'n1').isRead, isTrue);
    expect(api.calls, contains('PUT /notifications/n1/read'));
  });

  test(
      'markRead refreshes the bell badge (unread count) after the server write',
      () async {
    var counts = 0;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/notifications/unread-count') {
          counts++;
          return {'count': counts == 1 ? 2 : 1};
        }
        return [notifJson('n1', false), notifJson('n2', true)];
      },
      onPut: (_, __) async => notifJson('n1', true),
    );
    final c = container(api);
    // Keep the count provider listened so an invalidation REFETCHES (badge actually clears).
    final sub = c.listen(unreadCountProvider, (_, __) {});
    addTearDown(sub.close);
    expect(await c.read(unreadCountProvider.future), 2);

    await c.read(notificationControllerProvider.future);
    await c.read(notificationControllerProvider.notifier).markRead('n1');
    await c.read(unreadCountProvider.future); // settle the refetch
    expect(counts, 2); // the count endpoint was re-hit
    expect(c.read(unreadCountProvider).value, 1);
  });

  test('markRead ROLLS BACK on failure', () async {
    final api = FakeApi(
      onGet: (_, __) async => [notifJson('n1', false)],
      onPut: (_, __) async =>
          throw const ApiException(message: 'boom', statusCode: 500),
    );
    final c = container(api);
    await c.read(notificationControllerProvider.future);
    await c.read(notificationControllerProvider.notifier).markRead('n1');

    // The optimistic change was reverted — n1 is unread again.
    expect(
        c.read(notificationControllerProvider).value!.single.isRead, isFalse);
  });

  test('markAllRead marks everything (optimistic) and PUTs read-all', () async {
    final api = FakeApi(
      onGet: (_, __) async => [notifJson('n1', false), notifJson('n2', false)],
      onPut: (path, _) async {
        expect(path, '/notifications/read-all');
        return {'count': 2};
      },
    );
    final c = container(api);
    await c.read(notificationControllerProvider.future);
    await c.read(notificationControllerProvider.notifier).markAllRead();

    expect(c.read(notificationControllerProvider).value!.every((n) => n.isRead),
        isTrue);
    expect(api.calls, contains('PUT /notifications/read-all'));
  });

  test('markAllRead ROLLS BACK on failure', () async {
    final api = FakeApi(
      onGet: (_, __) async => [notifJson('n1', false), notifJson('n2', false)],
      onPut: (_, __) async =>
          throw const ApiException(message: 'boom', statusCode: 500),
    );
    final c = container(api);
    await c.read(notificationControllerProvider.future);
    await c.read(notificationControllerProvider.notifier).markAllRead();

    expect(
        c.read(notificationControllerProvider).value!.every((n) => !n.isRead),
        isTrue);
  });

  test('markAllRead refreshes the bell badge (unread count) to zero', () async {
    var counts = 0;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/notifications/unread-count') {
          counts++;
          return {'count': counts == 1 ? 2 : 0};
        }
        return [notifJson('n1', false), notifJson('n2', false)];
      },
      onPut: (_, __) async => {'count': 2},
    );
    final c = container(api);
    final sub = c.listen(unreadCountProvider, (_, __) {});
    addTearDown(sub.close);
    expect(await c.read(unreadCountProvider.future), 2);

    await c.read(notificationControllerProvider.future);
    await c.read(notificationControllerProvider.notifier).markAllRead();
    await c.read(unreadCountProvider.future);
    expect(counts, 2);
    expect(c.read(unreadCountProvider).value, 0);
  });

  test('unread count parses {count}', () async {
    final api = FakeApi(onGet: (path, _) async {
      expect(path, '/notifications/unread-count');
      return {'count': 7};
    });
    final c = container(api);
    expect(await c.read(unreadCountProvider.future), 7);
  });
}
