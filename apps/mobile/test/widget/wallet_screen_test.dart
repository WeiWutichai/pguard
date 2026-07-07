import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/wallet/wallet_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> paymentJson(
  String id, {
  String bookingId = '3f2a9b1c-0000-4000-8000-000000000001',
  String amount = '2000.00',
  String status = 'completed',
  String? finalAmount,
}) =>
    {
      'id': id,
      'booking_id': bookingId,
      'customer_id': 'c1',
      'amount': amount,
      'status': status,
      'final_amount': finalAmount,
      // Noon UTC keeps the local calendar date stable across test-machine timezones.
      'created_at': '2026-06-03T12:00:00Z',
      'updated_at': '2026-06-03T12:00:00Z',
    };

Future<void> pumpScreen(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ],
    child: const MaterialApp(home: WalletScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('renders receipt rows + the total-spent hero', (tester) async {
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/payments');
        return [
          paymentJson('p1'), // ฿2,000 spent
          paymentJson('p2',
              bookingId: 'aabbccdd-0000-4000-8000-000000000002',
              amount: '500.00',
              status: 'refunded'), // ฿0 spent
        ];
      },
    );
    await pumpScreen(tester, api);

    // Hero: refunded charge contributes 0 → total = ฿2,000. Satang precision (sub-฿1 finals must
    // not floor to ฿0), so figures carry .00.
    expect(find.text('รวมจ่ายแล้ว'), findsOneWidget);
    expect(
        find.text('฿2,000.00'), findsNWidgets(2)); // hero + the p1 row amount
    // Rows: mono booking refs, design date format, status badges.
    expect(find.text('PG-3F2A9B1C'), findsOneWidget);
    expect(find.text('PG-AABBCCDD'), findsOneWidget);
    expect(find.text('3 มิ.ย. 2026'), findsNWidgets(2));
    expect(find.text('ชำระแล้ว'), findsOneWidget);
    expect(find.text('คืนเงินแล้ว'), findsOneWidget);
    // One fetch — no polling.
    expect(api.getCount, 1);
  });

  testWidgets(
      'a prorated completed payment shows final_amount on the ROW — row sums match the hero',
      (tester) async {
    final api = FakeApi(
      onGet: (_, __) async => [
        // Proration ran: charged ฿2,000, effective ฿1,725 (review-gate fold —
        // the row must NOT show ฿2,000 next to "Paid" while the hero counts ฿1,725).
        paymentJson('p1', finalAmount: '1725.00'),
      ],
    );
    await pumpScreen(tester, api);

    // Hero AND the row both show the effective figure — no silent disagreement.
    expect(find.text('฿1,725.00'), findsNWidgets(2));
    expect(find.text('฿2,000.00'), findsNothing);
    expect(find.text('ชำระแล้ว'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no payments',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => <Map<String, dynamic>>[]);
    await pumpScreen(tester, api);

    expect(find.textContaining('ยังไม่มีใบเสร็จ'), findsOneWidget);
    expect(find.text('฿0.00'), findsOneWidget); // honest empty total
  });

  testWidgets('shows PgErrorState with retry on load failure', (tester) async {
    var failures = 0;
    final api = FakeApi(onGet: (_, __) async {
      failures++;
      if (failures == 1) throw Exception('boom');
      return [paymentJson('p1')];
    });
    await pumpScreen(tester, api);

    expect(find.textContaining('โหลดใบเสร็จไม่สำเร็จ'), findsOneWidget);

    await tester.tap(find.textContaining('ลองอีกครั้ง'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('PG-3F2A9B1C'), findsOneWidget);
  });
}
