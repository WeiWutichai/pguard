import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/chat.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/chat/chat_list_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> convJson(String id,
        {int unread = 0, String name = 'Somchai', String? status}) =>
    {
      'id': id,
      'request_id': 'r_$id',
      'created_at': '2026-06-05T10:00:00Z',
      'unread_count': unread,
      'participant_name': name,
      'last_message': 'hello',
      'last_message_at': '2026-06-05T10:05:00Z',
      'request_status': status,
    };

Widget host(FakeApi api) => ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      ],
      child: const MaterialApp(
        home: ChatListScreen(actingRole: ChatRole.customer),
      ),
    );

void main() {
  testWidgets('renders conversation rows with an unread badge', (tester) async {
    final api = FakeApi(onGet: (_, __) async => [
          convJson('cv1', unread: 3, name: 'Somchai'),
          convJson('cv2', unread: 0, name: 'Anan'),
        ]);
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Somchai'), findsOneWidget);
    expect(find.text('Anan'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: 'unread badge for cv1');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows the empty state when there are no conversations',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => <Map<String, dynamic>>[]);
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.textContaining('ยังไม่มีการสนทนา'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
