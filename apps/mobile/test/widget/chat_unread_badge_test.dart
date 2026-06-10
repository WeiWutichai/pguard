import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/chat.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/chat/widgets/chat_unread_badge.dart';

import '../support/fakes.dart';

Map<String, dynamic> convJson(String id, String requestId, int unread) => {
      'id': id,
      'request_id': requestId,
      'created_at': '2026-06-10T00:00:00Z',
      'unread_count': unread,
    };

Widget host(FakeApi api, {String? requestId}) => ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ChatUnreadBadge(
            acting: ChatRole.customer,
            requestId: requestId,
            child: const Icon(Icons.chat_bubble_outline),
          ),
        ),
      ),
    );

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets('shows the total unread count from the conversation list',
      (tester) async {
    final api = FakeApi(
        onGet: (_, __) async =>
            [convJson('c1', 'b1', 2), convJson('c2', 'b2', 3)]);

    await tester.pumpWidget(host(api));
    await settle(tester);

    expect(find.text('5'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('requestId narrows the count to one booking', (tester) async {
    final api = FakeApi(
        onGet: (_, __) async =>
            [convJson('c1', 'b1', 2), convJson('c2', 'b2', 3)]);

    await tester.pumpWidget(host(api, requestId: 'b2'));
    await settle(tester);

    expect(find.text('3'), findsOneWidget);
    expect(find.text('5'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renders only the child when there is nothing unread',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => [convJson('c1', 'b1', 0)]);

    await tester.pumpWidget(host(api));
    await settle(tester);

    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(ChatUnreadBadge), matching: find.byType(Text)),
      findsNothing,
      reason: 'no badge overlay',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('caps the display at 99+', (tester) async {
    final api = FakeApi(onGet: (_, __) async => [convJson('c1', 'b1', 150)]);

    await tester.pumpWidget(host(api));
    await settle(tester);

    expect(find.text('99+'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
