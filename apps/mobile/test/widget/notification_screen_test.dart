import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/notifications/notification_screen.dart';
import 'package:pguard_mobile/features/notifications/widgets/notification_tile.dart';

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
  testWidgets(
      'renders the list and OPENING the centre auto-marks everything read',
      (tester) async {
    var readAllCalls = 0;
    final api = FakeApi(
      onGet: (_, __) async => [notifJson('n1', false), notifJson('n2', true)],
      onPut: (path, _) async {
        expect(path,
            '/notifications/read-all'); // the only mutating call is the open-time read-all
        readAllCalls++;
        return {'count': 0};
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

    // Both notifications render (type-localized copy replaces the raw server title).
    expect(find.byType(NotificationTile), findsNWidgets(2));
    // Opening the centre auto-marked everything read (the reported "read them all but the badge
    // stays" fix) → read-all fired once and the explicit "mark all read" action is gone.
    expect(readAllCalls, 1);
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
