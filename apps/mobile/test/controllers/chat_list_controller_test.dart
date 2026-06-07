import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/chat_list_controller.dart';
import 'package:pguard_mobile/core/models/chat.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

Map<String, dynamic> convJson(
  String id, {
  String requestId = 'r1',
  int unread = 0,
  String? status,
  String? name = 'Somchai',
}) =>
    {
      'id': id,
      'request_id': requestId,
      'created_at': '2026-06-05T10:00:00Z',
      'unread_count': unread,
      'participant_name': name,
      'last_message': 'hello',
      'last_message_at': '2026-06-05T10:05:00Z',
      'request_status': status,
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

  test('loads the enriched list for the acting role in ONE call (no polling)',
      () async {
    final api = FakeApi(onGet: (path, query) async {
      expect(path, '/conversations');
      expect(query, {'role': 'guard'}, reason: 'acting role passed as ?role=');
      return [
        convJson('cv1', unread: 2, status: 'accepted'),
        convJson('cv2', unread: 0, status: 'completed'),
      ];
    });
    final c = container(api);

    final list =
        await c.read(chatListControllerProvider(ChatRole.guard).future);

    expect(list, hasLength(2));
    expect(list.first.id, 'cv1');
    expect(list.first.hasUnread, isTrue, reason: 'unread_count 2 → badge');
    expect(list.first.isReadOnly, isFalse);
    expect(list[1].hasUnread, isFalse);
    expect(list[1].isReadOnly, isTrue, reason: 'completed booking → read-only');
    expect(api.getCount, 1, reason: 'N+1-free: exactly one enriched GET');
  });

  test('customer acting role is threaded into the query', () async {
    final api = FakeApi(onGet: (path, query) async {
      expect(query, {'role': 'customer'});
      return [convJson('cv9')];
    });
    final c = container(api);
    final list =
        await c.read(chatListControllerProvider(ChatRole.customer).future);
    expect(list.single.id, 'cv9');
  });
}
