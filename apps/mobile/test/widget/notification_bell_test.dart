import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/notifications/widgets/notification_bell.dart';

import '../support/fakes.dart';

void main() {
  Future<void> pumpBell(WidgetTester tester, int count) async {
    final api = FakeApi(onGet: (path, _) async {
      expect(path, '/notifications/unread-count');
      return {'count': count};
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      ],
      child: const MaterialApp(home: Scaffold(body: NotificationBell())),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('renders the unread count badge', (tester) async {
    await pumpBell(tester, 3);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('caps the badge at 9+', (tester) async {
    await pumpBell(tester, 25);
    expect(find.text('9+'), findsOneWidget);
  });

  testWidgets('hides the badge when there are no unread', (tester) async {
    await pumpBell(tester, 0);
    expect(find.text('0'), findsNothing);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
  });
}
