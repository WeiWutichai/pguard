import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/controllers/slip_payment_controller.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/payment_screen.dart';
import 'package:pguard_mobile/widgets/qr_view.dart';

import '../support/fakes.dart';

/// Screen-level coverage of the CUSTOMER PromptPay + slip pay UX wired into [PaymentScreen]:
///  - a simulated `POST /payments` → 409 SLIP_REQUIRED switches the screen to the PromptPay panel
///    (QR + amount + receiving account + the upload CTA);
///  - a successful slip upload flips the screen to the "slip verified" success state;
///  - a typed 409 (e.g. SLIP_DUPLICATE) shows its specific Thai message and stays on the QR panel;
///  - the SIMULATED provider path (no SLIP_REQUIRED) is unchanged — it pays in one tap.
///
/// The slip UPLOAD itself runs through the real [SlipPaymentController] (it reads the temp slip file
/// + multiparts it), driven inside `tester.runAsync` so the real file I/O completes; the assertions
/// are all on the rendered [PaymentScreen] widgets.
void main() {
  late File tempSlip;
  setUp(() async {
    tempSlip = File(
        '${Directory.systemTemp.path}/pg_slip_widget_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await tempSlip.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
  });
  tearDown(() async {
    if (await tempSlip.exists()) await tempSlip.delete();
  });

  Map<String, dynamic> acceptedBooking() => {
        'id': 'b1',
        'customer_id': 'c1',
        'guard_id': 'g1',
        'status': 'accepted',
        'base_fee': '500.00',
        'hours': 4,
        'guard_count': 1,
        'address': 'สยามพารากอน',
      };

  Map<String, dynamic> promptpay() => {
        'amount': '2000.00',
        'amount_satang': 200000,
        'receiving_account': '081-234-5678',
        'qr_payload':
            '00020101021229370016A00000067701011101130066812345678530376454072000.005802TH6304XXXX',
      };

  Map<String, dynamic> completedPayment() => {
        'id': 'p1',
        'booking_id': 'b1',
        'customer_id': 'c1',
        'guard_id': 'g1',
        'amount': '2000.00',
        'status': 'completed',
        'created_at': '2026-06-05T10:00:00Z',
        'updated_at': '2026-06-05T10:00:00Z',
      };

  ProviderContainer makeContainer(FakeApi api) => ProviderContainer(overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tp) => FakeBookingFeed()),
      ]);

  Future<void> pumpPay(WidgetTester tester, ProviderContainer container) async {
    final router = GoRouter(
      initialLocation: '/booking/b1/pay',
      routes: [
        GoRoute(
            path: '/booking/:id/pay',
            builder: (_, s) =>
                PaymentScreen(bookingId: s.pathParameters['id']!)),
        GoRoute(
            path: '/booking/:id/live',
            builder: (_, __) => const Scaffold(body: Text('LIVE'))),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'POST /payments → 409 SLIP_REQUIRED shows the PromptPay slip screen '
      '(QR + amount + receiving account + upload CTA)', (tester) async {
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') return acceptedBooking();
        if (path == '/payments/b1/promptpay') return promptpay();
        return null;
      },
      onPost: (path, _) async {
        if (path == '/payments') {
          throw const ApiException(
              message: 'Slip payment required',
              code: 'SLIP_REQUIRED',
              statusCode: 409);
        }
        return null;
      },
    );
    final container = makeContainer(api);
    addTearDown(container.dispose);
    await pumpPay(tester, container);

    // Tap the simulated "Pay" CTA → it returns SLIP_REQUIRED → the screen switches to PromptPay.
    await tester.tap(find.textContaining('ชำระเงิน').first);
    await tester.pumpAndSettle();

    expect(find.byType(QrView), findsOneWidget, reason: 'the PromptPay QR renders');
    expect(find.textContaining('PromptPay'), findsOneWidget);
    expect(find.text('081-234-5678'), findsOneWidget,
        reason: 'the receiving account is shown');
    expect(find.text('฿2,000.00'), findsWidgets,
        reason: 'the server estimate to transfer is shown');
    expect(find.textContaining('อัปโหลดสลิป'), findsOneWidget,
        reason: 'the upload-slip CTA is present');
  });

  testWidgets('a verified slip upload flips the screen to the success state',
      (tester) async {
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') return acceptedBooking();
        if (path == '/payments/b1/promptpay') return promptpay();
        return null;
      },
      onPost: (path, _) async {
        if (path == '/payments') {
          throw const ApiException(
              message: 'Slip required', code: 'SLIP_REQUIRED', statusCode: 409);
        }
        if (path == '/payments/b1/slip') return completedPayment();
        return null;
      },
    );
    final container = makeContainer(api);
    addTearDown(container.dispose);
    await pumpPay(tester, container);

    await tester.tap(find.textContaining('ชำระเงิน').first);
    await tester.pumpAndSettle();
    expect(find.byType(QrView), findsOneWidget);

    // Drive the real upload (reads the temp slip + multiparts it) to completion inside runAsync.
    await tester.runAsync(() => container
        .read(slipPaymentControllerProvider('b1').notifier)
        .uploadSlip(tempSlip.path));
    await tester.pumpAndSettle();

    // A verified slip settles the payment → the screen shows a success state and the booking
    // proceeds. (The slip success optimistically marks the live booking paid, so the screen lands
    // on the shared paid panel — the customer sees "ชำระเงินสำเร็จ".)
    expect(find.textContaining('สำเร็จ'), findsWidgets,
        reason: 'the slip verified → a payment-success state');
    expect(find.byType(QrView), findsNothing, reason: 'the QR is gone once paid');
  });

  testWidgets(
      'a typed 409 (SLIP_DUPLICATE) shows its Thai message and stays on the QR panel',
      (tester) async {
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') return acceptedBooking();
        if (path == '/payments/b1/promptpay') return promptpay();
        return null;
      },
      onPost: (path, _) async {
        if (path == '/payments') {
          throw const ApiException(
              message: 'Slip required', code: 'SLIP_REQUIRED', statusCode: 409);
        }
        if (path == '/payments/b1/slip') {
          throw const ApiException(
              message: 'duplicate slip',
              code: 'SLIP_DUPLICATE',
              statusCode: 409);
        }
        return null;
      },
    );
    final container = makeContainer(api);
    addTearDown(container.dispose);
    await pumpPay(tester, container);

    await tester.tap(find.textContaining('ชำระเงิน').first);
    await tester.pumpAndSettle();

    await tester.runAsync(() => container
        .read(slipPaymentControllerProvider('b1').notifier)
        .uploadSlip(tempSlip.path));
    await tester.pump();

    expect(find.textContaining('สลิปนี้ถูกใช้แล้ว'), findsOneWidget,
        reason: 'the specific duplicate-slip Thai message');
    expect(find.byType(QrView), findsOneWidget,
        reason: 'still on the QR panel so the customer can re-pick');
    expect(find.textContaining('อัปโหลดสลิป'), findsOneWidget,
        reason: 'the upload CTA is back so they can re-pick a slip');
  });

  testWidgets('the source bottom sheet offers gallery + camera and routes to the picker',
      (tester) async {
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') return acceptedBooking();
        if (path == '/payments/b1/promptpay') return promptpay();
        return null;
      },
      onPost: (path, _) async {
        if (path == '/payments') {
          throw const ApiException(
              message: 'Slip required', code: 'SLIP_REQUIRED', statusCode: 409);
        }
        return null;
      },
    );
    final container = makeContainer(api);
    addTearDown(container.dispose);
    await pumpPay(tester, container);

    await tester.tap(find.textContaining('ชำระเงิน').first);
    await tester.pumpAndSettle();

    // Open the slip-source sheet (the CTA lives in a ListView below the QR card — bring it into
    // view before tapping so the hit lands).
    final cta = find.ancestor(
        of: find.textContaining('อัปโหลดสลิป'),
        matching: find.byType(ElevatedButton));
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pumpAndSettle();

    expect(find.text('เลือกจากคลังรูป'), findsOneWidget,
        reason: 'gallery option');
    expect(find.text('ถ่ายรูปสลิป'), findsOneWidget, reason: 'camera option');
  });

  testWidgets('the SIMULATED provider path is unchanged: one tap pays, no slip screen',
      (tester) async {
    var promptpayCalled = false;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') return acceptedBooking();
        if (path == '/payments/b1/promptpay') {
          promptpayCalled = true;
          return promptpay();
        }
        return null;
      },
      onPost: (path, _) async {
        if (path == '/payments') return completedPayment();
        return null;
      },
    );
    final container = makeContainer(api);
    addTearDown(container.dispose);
    await pumpPay(tester, container);

    await tester.tap(find.textContaining('ชำระเงิน').first);
    await tester.pumpAndSettle();

    expect(find.text('ชำระเงินสำเร็จ'), findsOneWidget,
        reason: 'the existing simulated success panel');
    expect(find.byType(QrView), findsNothing,
        reason: 'no PromptPay QR on the simulated path');
    expect(promptpayCalled, isFalse,
        reason: 'the slip endpoint is never touched when no slip is required');
  });
}
