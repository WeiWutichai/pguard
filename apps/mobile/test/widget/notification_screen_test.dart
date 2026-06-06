import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/notifications/notification_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> notifJson(String id, bool isRead) => {
      'id': id,
      'user_id': 'u1',
      'title': 'หัวข้อ $id',
      'body': 'รายละเอียด $id',
      'notification_type': 'booking_created',
      'is_read': isRead,
      'sent_at': '2026-06-06T11:55:00Z',
      'read_at': null,
    };

void main() {
  testWidgets('renders the list and mark-all marks everything read',
      (tester) async {
    final api = FakeApi(
      onGet: (_, __) async => [notifJson('n1', false), notifJson('n2', true)],
      onPut: (path, _) async {
        expect(path, '/notifications/read-all');
        return {'count': 1};
      },
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      ],
      child: const MaterialApp(home: NotificationScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('หัวข้อ n1'), findsOneWidget);
    expect(find.text('หัวข้อ n2'), findsOneWidget);
    // There is an unread item → the "mark all read" action shows.
    expect(find.text('อ่านทั้งหมด'), findsOneWidget);

    await tester.tap(find.text('อ่านทั้งหมด'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Optimistically everything is read → the action disappears.
    expect(find.text('อ่านทั้งหมด'), findsNothing);
  });

  testWidgets('shows the empty state when there are no notifications',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => <Map<String, dynamic>>[]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      ],
      child: const MaterialApp(home: NotificationScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.textContaining('ยังไม่มีการแจ้งเตือน'), findsOneWidget);
    expect(find.text('อ่านทั้งหมด'), findsNothing);
  });
}
