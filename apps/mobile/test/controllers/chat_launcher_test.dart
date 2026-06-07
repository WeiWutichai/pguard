import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/chat_launcher.dart';
import 'package:pguard_mobile/core/models/chat.dart';

import '../support/fakes.dart';

void main() {
  final participants = [
    const ParticipantInput(userId: 'me', role: ChatRole.guard),
    const ParticipantInput(userId: 'them', role: ChatRole.customer),
  ];

  test('finds an existing conversation by request_id — no POST', () async {
    Object? postData;
    final api = FakeApi(
      onGet: (path, query) async {
        expect(path, '/conversations');
        expect(query, {'role': 'guard'});
        return [
          {
            'id': 'cvX',
            'request_id': 'r1',
            'created_at': '2026-06-05T10:00:00Z',
            'unread_count': 0,
          },
        ];
      },
      onPost: (path, data) async {
        postData = data;
        return {'id': 'should-not-happen'};
      },
    );

    final id = await ChatLauncher(api).resolveConversationId(
      requestId: 'r1',
      acting: ChatRole.guard,
      participants: participants,
    );

    expect(id, 'cvX');
    expect(postData, isNull, reason: 'POST is not idempotent — find first, do not create');
    expect(api.calls.where((c) => c.startsWith('POST')), isEmpty);
  });

  test('creates the conversation when none exists for the booking', () async {
    Object? postData;
    final api = FakeApi(
      onGet: (_, __) async => <Map<String, dynamic>>[], // no existing convos
      onPost: (path, data) async {
        expect(path, '/conversations');
        postData = data;
        return {
          'id': 'cvNew',
          'request_id': 'r2',
          'created_at': '2026-06-05T10:00:00Z',
        };
      },
    );

    final id = await ChatLauncher(api).resolveConversationId(
      requestId: 'r2',
      acting: ChatRole.guard,
      requestStatus: 'accepted',
      participants: participants,
    );

    expect(id, 'cvNew');
    final body = postData as Map<String, dynamic>;
    expect(body['request_id'], 'r2');
    expect(body['request_status'], 'accepted');
    final ps = body['participants'] as List;
    expect(ps, hasLength(2));
    expect((ps.first as Map)['user_id'], 'me');
    expect((ps.first as Map)['role'], 'guard');
  });
}
