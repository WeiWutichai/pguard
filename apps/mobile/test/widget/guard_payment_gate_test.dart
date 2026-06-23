import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/active_job_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson({required bool paid}) => {
      'id': 'b1',
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': 'accepted', // JobStage.enRoute → the "Go en route" CTA is the gated action
      'address': 'หมู่บ้านลัดดารมย์ ซ.5',
      'scheduled_at': '2026-06-05T14:00:00Z',
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'tip': '0',
      if (paid) 'paid_at': '2026-06-05T10:30:00Z',
      'created_at': '2026-06-05T10:00:00Z',
      'updated_at': '2026-06-05T10:00:00Z',
    };

/// Find the ElevatedButton backing the "Go en route" PgPrimaryButton (by its label) and report
/// whether it is enabled.
bool _enRouteEnabled(WidgetTester tester) {
  final button = tester.widget<ElevatedButton>(
    find.ancestor(
      of: find.text('เริ่มเดินทาง'),
      matching: find.byType(ElevatedButton),
    ),
  );
  return button.onPressed != null;
}

void main() {
  testWidgets(
      'PRE-PAY gate: en_route is DISABLED with "รอลูกค้าชำระเงิน" until the '
      'booking is paid', (tester) async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? bookingJson(paid: false)
          : const <Map<String, dynamic>>[],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      ],
      child: const MaterialApp(home: ActiveJobScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The awaiting-payment notice is shown and the en-route CTA is disabled.
    expect(find.text('รอลูกค้าชำระเงิน'), findsOneWidget);
    expect(_enRouteEnabled(tester), isFalse,
        reason: 'en_route stays disabled until the customer pays (backend 409s too)');
  });

  testWidgets('PRE-PAY gate: en_route is ENABLED once the booking is paid',
      (tester) async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? bookingJson(paid: true)
          : const <Map<String, dynamic>>[],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      ],
      child: const MaterialApp(home: ActiveJobScreen(bookingId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Paid → no notice, and the en-route CTA is live.
    expect(find.text('รอลูกค้าชำระเงิน'), findsNothing);
    expect(_enRouteEnabled(tester), isTrue,
        reason: 'a paid booking un-gates the guard start action');
  });
}
