import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/chat.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/chat/chat_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> msgJson(String id, String role, String content) => {
      'id': id,
      'conversation_id': 'cv1',
      'sender_id': 'u_$role',
      'sender_role': role,
      'content': content,
      'message_type': 'text',
      'created_at': '2026-06-05T10:00:00Z',
    };

Widget host(FakeApi api, FakeChatFeed feed, {required bool readOnly}) =>
    ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        chatFeedBuilderProvider.overrideWithValue((tokenProvider) => feed),
      ],
      child: MaterialApp(
        home: ChatScreen(
          conversationId: 'cv1',
          acting: ChatRole.guard,
          readOnly: readOnly,
        ),
      ),
    );

void main() {
  testWidgets('aligns own role right, counterpart left; composer is shown',
      (tester) async {
    final feed = FakeChatFeed();
    final api = FakeApi(
      onGet: (_, __) async => [
        msgJson('m1', 'guard', 'from guard'),
        msgJson('m2', 'customer', 'from customer'),
      ],
      onPut: (_, __) async => {'success': true},
    );

    await tester.pumpWidget(host(api, feed, readOnly: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('from guard'), findsOneWidget);
    expect(find.text('from customer'), findsOneWidget);

    // Alignment is by sender_role vs acting (guard): own → right, counterpart → left.
    final mine = tester.widget<Align>(find
        .ancestor(of: find.text('from guard'), matching: find.byType(Align))
        .first);
    expect(mine.alignment, Alignment.centerRight);
    final theirs = tester.widget<Align>(find
        .ancestor(of: find.text('from customer'), matching: find.byType(Align))
        .first);
    expect(theirs.alignment, Alignment.centerLeft);

    // Writable conversation → composer present.
    expect(find.byType(TextField), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('read-only conversation hides the composer + shows locked banner',
      (tester) async {
    final feed = FakeChatFeed();
    final api = FakeApi(
      onGet: (_, __) async => <Map<String, dynamic>>[],
      onPut: (_, __) async => {'success': true},
    );

    await tester.pumpWidget(host(api, feed, readOnly: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byType(TextField), findsNothing, reason: 'composer hidden');
    expect(find.textContaining('งานสิ้นสุดแล้ว'), findsOneWidget,
        reason: 'locked banner');

    await tester.pumpWidget(const SizedBox());
  });
}
