import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/active_job_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson(String status) => {
      'id': 'b1',
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': status,
      'address': 'หมู่บ้านลัดดารมย์ ซ.5',
      'scheduled_at': '2026-06-05T14:00:00Z',
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'tip': '0',
      'created_at': '2026-06-05T10:00:00Z',
      'updated_at': '2026-06-05T10:00:00Z',
    };

void main() {
  testWidgets('start → working panel shows the countdown + complete action',
      (tester) async {
    final api = FakeApi(
      onGet: (_, __) async => bookingJson('arrived'),
      onPut: (path, _) async {
        expect(path, '/bookings/b1/start');
        return bookingJson('arrived'); // start keeps status arrived
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      ],
      child: const MaterialApp(home: ActiveJobScreen(bookingId: 'b1')),
    ));
    // Resolve the initial load.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Arrived but not started → Start action; the working panel (ring + timeline) is not shown.
    expect(find.textContaining('เริ่มงาน'), findsOneWidget);
    expect(find.textContaining('ความคืบหน้า'), findsNothing);
    expect(find.text('หมู่บ้านลัดดารมย์ ซ.5'), findsOneWidget); // address shown

    // Tap "Start job" → records start time → working panel appears.
    await tester.tap(find.textContaining('เริ่มงาน'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Working panel = the ring countdown ("เหลือ") + the per-hour timeline header.
    expect(find.text('เหลือ'), findsOneWidget);
    expect(find.textContaining('ความคืบหน้า'), findsOneWidget);
    expect(find.textContaining('จบงาน'), findsOneWidget); // end action
    expect(api.calls, contains('PUT /bookings/b1/start'));

    // Unmount to cancel the display ticker (no pending timers at teardown).
    await tester.pumpWidget(const SizedBox());
  });
}
