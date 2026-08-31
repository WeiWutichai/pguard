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

  testWidgets(
      'badge hugs the icon top-right (anchored to the glyph, not a wide box)',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => [convJson('c1', 'b1', 4)]);

    await tester.pumpWidget(host(api));
    await settle(tester);

    final iconRect = tester.getRect(find.byIcon(Icons.chat_bubble_outline));
    final badgeRect = tester.getRect(find.text('4'));
    // Positioned(right:-4, top:-4) relative to the icon box → the badge sits a few px off the
    // icon's own top-right corner. The float bug (badge anchored to a 44/48px tap box around a
    // ~24px glyph) would push it >20px away; keep it hugging the glyph.
    expect((badgeRect.right - iconRect.right).abs(), lessThan(14),
        reason:
            'badge right edge hugs the icon right edge, not a wide tap box');
    expect((badgeRect.top - iconRect.top).abs(), lessThan(14),
        reason: 'badge top hugs the icon top, not a wide tap box');
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
