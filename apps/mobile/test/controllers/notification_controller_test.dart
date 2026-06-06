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
    expect(c.read(notificationControllerProvider).value!.single.isRead, isFalse);
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

    expect(c.read(notificationControllerProvider).value!.every((n) => !n.isRead),
        isTrue);
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
