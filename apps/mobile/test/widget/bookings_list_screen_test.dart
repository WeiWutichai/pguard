import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/bookings_list_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson(
  String id,
  String status, {
  String address = 'หมู่บ้านลัดดารมย์',
  String baseFee = '230.00',
  int hours = 8,
  int guards = 1,
  String tip = '0',
}) =>
    {
      'id': id,
      'customer_id': 'c1',
      'status': status,
      'address': address,
      'scheduled_at': '2026-06-03T07:00:00Z',
      'hours': hours,
      'guard_count': guards,
      'base_fee': baseFee,
      'tip': tip,
    };

String _jwt() => fakeJwt({
      'sub': 'c1',
      'role': 'customer',
      'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
    });

Future<void> pumpScreen(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = _jwt()),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ],
    child: const MaterialApp(home: BookingsListScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('renders rows with badge + mono total and filters by tab',
      (tester) async {
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/bookings');
        return [
          bookingJson('b1', 'completed'),
          bookingJson('b2', 'cancelled', address: 'โรงงาน ปทุม'),
          bookingJson('b3', 'en_route', address: 'คอนโด ไอดีโอ'),
        ];
      },
    );
    await pumpScreen(tester, api);

    // All three rows + their design badge words.
    expect(find.text('หมู่บ้านลัดดารมย์'), findsOneWidget);
    expect(find.text('โรงงาน ปทุม'), findsOneWidget);
    expect(find.text('คอนโด ไอดีโอ'), findsOneWidget);
    expect(find.text('done'), findsOneWidget);
    expect(find.text('cancelled'), findsOneWidget);
    expect(find.text('active'), findsOneWidget);
    // Booked total = ฿230 × 8h × 1 guard (mono row amount).
    expect(find.text('฿1,840'), findsNWidgets(3));
    // One fetch — no polling.
    expect(api.getCount, 1);

    // "สำเร็จ" narrows to the completed row only.
    await tester.tap(find.text('สำเร็จ'));
    await tester.pump();
    expect(find.text('หมู่บ้านลัดดารมย์'), findsOneWidget);
    expect(find.text('โรงงาน ปทุม'), findsNothing);
    expect(find.text('คอนโด ไอดีโอ'), findsNothing);

    // "ยกเลิก" shows the cancelled row only.
    await tester.tap(find.text('ยกเลิก'));
    await tester.pump();
    expect(find.text('โรงงาน ปทุม'), findsOneWidget);
    expect(find.text('หมู่บ้านลัดดารมย์'), findsNothing);
  });

  testWidgets('shows the empty state when there are no bookings',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => <Map<String, dynamic>>[]);
    await pumpScreen(tester, api);

    expect(find.textContaining('ยังไม่มีการจอง'), findsOneWidget);
  });

  testWidgets('shows PgErrorState with retry on load failure', (tester) async {
    var failures = 0;
    final api = FakeApi(onGet: (_, __) async {
      failures++;
      if (failures == 1) throw Exception('boom');
      return [bookingJson('b1', 'completed')];
    });
    await pumpScreen(tester, api);

    expect(find.textContaining('โหลดประวัติการจ้างไม่สำเร็จ'), findsOneWidget);

    await tester.tap(find.textContaining('ลองอีกครั้ง'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('หมู่บ้านลัดดารมย์'), findsOneWidget);
  });
}
