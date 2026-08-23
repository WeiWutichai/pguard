import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/notifications/notification_screen.dart';
import 'package:pguard_mobile/features/notifications/widgets/notification_tile.dart';

import '../support/fakes.dart';

/// The background colour the tile paints for [notification]'s row (green tint = unread highlight).
Color? tileColor(WidgetTester tester, {int at = 0}) => tester
    .widget<Material>(find
        .descendant(
            of: find.byType(NotificationTile).at(at),
            matching: find.byType(Material))
        .first)
    .color;

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

  testWidgets(
      'N2: after opening (badge cleared) an untapped unread row stays highlighted, and tapping clears just that row',
      (tester) async {
    final api = FakeApi(
      onGet: (_, __) async => [notifJson('n1', false), notifJson('n2', false)],
      onPut: (path, _) async {
        // Opening the centre clears the BELL BADGE via the server read-all (unread-count → 0).
        expect(path, '/notifications/read-all');
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

    // Opening fired the read-all (badge cleared) yet BOTH rows are still painted unread — the
    // highlight is NOT erased wholesale the way it used to be.
    expect(find.byType(NotificationTile), findsNWidgets(2));
    expect(tileColor(tester, at: 0), PgTokens.colorGreen50);
    expect(tileColor(tester, at: 1), PgTokens.colorGreen50);

    // Tapping the first row clears ONLY its highlight (a `booking_created` with no booking_id has
    // no navigation target, so we stay on the screen); the second row stays highlighted.
    await tester.tap(find.byType(NotificationTile).at(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(tileColor(tester, at: 0), PgTokens.colorSurface);
    expect(tileColor(tester, at: 1), PgTokens.colorGreen50);
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
