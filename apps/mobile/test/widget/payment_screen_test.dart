import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/booking_flow_controller.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/payment_screen.dart';

import '../support/fakes.dart';

void main() {
  testWidgets(
      'payment summary shows the authoritative subtotal/total from the booking',
      (tester) async {
    final api = FakeApi(
      onPost: (path, data) async {
        // createBooking → server-owned base_fee 500.00, hours 8, guards 2.
        final body = data as Map<String, dynamic>;
        return {
          'id': 'bk1',
          'customer_id': 'c1',
          'guard_id': null,
          'status': 'requested',
          'address': body['address'],
          'scheduled_at': body['scheduled_at'],
          'hours': 8,
          'base_fee': '500.00',
          'guard_count': 2,
          'tip': '0',
          'created_at': '2026-06-05T10:00:00Z',
          'updated_at': '2026-06-05T10:00:00Z',
        };
      },
    );
    final container = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(container.dispose);

    final ctrl = container.read(bookingFlowControllerProvider.notifier);
    ctrl.setAddress('123 ลัดดารมย์');
    ctrl.setHours(8);
    ctrl.setGuardCount(2);
    expect(await ctrl.createBooking(), isTrue);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PaymentScreen()),
    ));
    await tester.pump();

    // Line-item label uses the booking's hours/guards…
    expect(find.textContaining('× 8 ชม. × 2 คน'), findsOneWidget);
    // …and the authoritative total ฿500 × 8 × 2 = ฿8,000.00 (subtotal + total lines).
    expect(find.textContaining('฿8,000.00'), findsWidgets);
    // The pay button carries the total.
    expect(find.textContaining('ชำระเงิน · ฿8,000'), findsOneWidget);
  });
}
