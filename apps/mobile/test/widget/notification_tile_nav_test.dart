import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/notifications/notification_screen.dart';
import 'package:pguard_mobile/features/notifications/widgets/notification_tile.dart';

import '../support/fakes.dart';

Map<String, dynamic> notifJson(
  String id, {
  required String type,
  required Map<String, dynamic> payload,
  bool isRead = false,
}) =>
    {
      'id': id,
      'user_id': 'u1',
      'title': 'หัวข้อ $id',
      'body': 'รายละเอียด $id',
      'notification_type': type,
      'is_read': isRead,
      'sent_at': '2026-06-06T11:55:00Z',
      'read_at': null,
      'payload': payload,
    };

String _customerJwt() => fakeJwt({
      'sub': 'c1',
      'role': 'customer',
      'exp':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
    });

void main() {
  testWidgets('tapping a booking tile marks it read AND opens the live screen',
      (tester) async {
    final puts = <String>[];
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/notifications') {
          return [
            notifJson('n1',
                type: 'guard_en_route', payload: {'booking_id': 'bk-7'}),
          ];
        }
        return {'count': 1}; // unread-count
      },
      onPut: (path, _) async {
        puts.add(path);
        return {'count': 0};
      },
    );

    String? landedAt;
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationScreen()),
        GoRoute(
          path: '/booking/:id/live',
          builder: (_, s) {
            landedAt = '/booking/${s.pathParameters['id']}/live';
            return const Scaffold(
                body: Text('LIVE', textDirection: TextDirection.ltr));
          },
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()
          ..access = _customerJwt()
          ..refresh = 'r'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Opening the centre auto-marks everything read (badge clears without per-row taps).
    expect(puts, contains('/notifications/read-all'));
    expect(find.byType(NotificationTile), findsOneWidget);

    await tester.tap(find.byType(NotificationTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Tapping the tile navigates to the customer live-status screen.
    expect(landedAt, '/booking/bk-7/live');
    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('tapping a tile with no target still marks it read (no crash)',
      (tester) async {
    final puts = <String>[];
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/notifications') {
          // A payment notice: system type, no call_id → no destination.
          return [
            notifJson('n2', type: 'system', payload: {'payment_id': 'p1'}),
          ];
        }
        return {'count': 1};
      },
      onPut: (path, _) async {
        puts.add(path);
        return {'count': 0};
      },
    );

    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationScreen()),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()
          ..access = _customerJwt()
          ..refresh = 'r'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Opening the centre auto-marks all read (read-all). `system` type keeps the server copy.
    expect(puts, contains('/notifications/read-all'));
    expect(find.textContaining('หัวข้อ n2'), findsOneWidget);

    await tester.tap(find.textContaining('หัวข้อ n2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Still on the notification screen (no navigation target) — no crash.
    expect(find.textContaining('หัวข้อ n2'), findsOneWidget);
  });
}
