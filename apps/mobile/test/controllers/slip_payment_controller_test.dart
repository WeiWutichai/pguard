import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/booking_status_controller.dart';
import 'package:pguard_mobile/core/controllers/slip_payment_controller.dart';
import 'package:pguard_mobile/core/media/slip_picker.dart';
import 'package:pguard_mobile/core/models/payment.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

Map<String, dynamic> promptpayJson() => {
      'amount': '2000.00',
      'amount_satang': 200000,
      'receiving_account': '081-234-5678',
      'qr_payload':
          '00020101021229370016A00000067701011101130066812345678530376454072000.005802TH6304XXXX',
    };

Map<String, dynamic> paymentJson(String status) => {
      'id': 'p1',
      'booking_id': 'b1',
      'customer_id': 'c1',
      'guard_id': 'g1',
      'amount': '2000.00',
      'status': status,
      'created_at': '2026-06-05T10:00:00Z',
      'updated_at': '2026-06-05T10:00:00Z',
    };

void main() {
  // A real temp JPEG so the upload's MultipartFile.fromFile() + magic-byte sniff can read it.
  late File tempSlip;
  setUp(() async {
    tempSlip = File(
        '${Directory.systemTemp.path}/pg_slip_test_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await tempSlip
        .writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]);
  });
  tearDown(() async {
    if (await tempSlip.exists()) await tempSlip.delete();
  });

  ProviderContainer container(FakeApi api, {FakeSlipPicker? picker}) {
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      if (picker != null) slipPickerProvider.overrideWithValue(picker),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test(
      'build fetches the PromptPay instructions → ready phase with QR/amount/account',
      () async {
    final api = FakeApi(onGet: (path, _) async {
      expect(path, '/payments/b1/promptpay');
      return promptpayJson();
    });
    final c = container(api);
    // Keep the autoDispose controller alive across the microtask fetch.
    final sub = c.listen(slipPaymentControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    // The build kicks off the fetch in a microtask — let it settle.
    await Future<void>.delayed(Duration.zero);

    final s = c.read(slipPaymentControllerProvider('b1'));
    expect(s.phase, SlipPhase.ready);
    expect(s.info?.amount, '2000.00');
    expect(s.info?.amountSatang, 200000);
    expect(s.info?.receivingAccount, '081-234-5678');
    expect(s.info?.qrPayload, contains('A000000677010111'));
    expect(s.error, isNull);
    expect(api.calls, contains('GET /payments/b1/promptpay'));
  });

  test(
      'a failed instructions fetch stays loading with a banner error (retryable)',
      () async {
    var calls = 0;
    final api = FakeApi(onGet: (_, __) async {
      calls++;
      if (calls == 1) {
        throw const ApiException(message: 'temporarily down', statusCode: 503);
      }
      return promptpayJson();
    });
    final c = container(api);
    final sub = c.listen(slipPaymentControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);

    var s = c.read(slipPaymentControllerProvider('b1'));
    expect(s.phase, SlipPhase.loading);
    // A 5xx is localized (infrastructure), never the raw English server text (deep-review lang fix).
    expect(s.error, 'ระบบขัดข้องชั่วคราว กรุณาลองใหม่ภายหลัง');

    // Retry succeeds.
    await c.read(slipPaymentControllerProvider('b1').notifier).loadInfo();
    s = c.read(slipPaymentControllerProvider('b1'));
    expect(s.phase, SlipPhase.ready);
    expect(s.error, isNull);
  });

  test(
      'a successful slip upload settles the payment → done phase, booking proceeds',
      () async {
    Object? postPath;
    final api = FakeApi(
      onGet: (_, __) async => promptpayJson(),
      onPost: (path, _) async {
        postPath = path;
        return paymentJson('completed');
      },
    );
    final picker = FakeSlipPicker(path: tempSlip.path);
    final c = container(api, picker: picker);
    final sub = c.listen(slipPaymentControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);

    final ok = await c
        .read(slipPaymentControllerProvider('b1').notifier)
        .pickAndUpload(SlipSource.gallery);

    expect(ok, isTrue);
    expect(picker.picks, [SlipSource.gallery]);
    expect(postPath, '/payments/b1/slip');
    final s = c.read(slipPaymentControllerProvider('b1'));
    expect(s.phase, SlipPhase.done);
    expect(s.isDone, isTrue);
    expect(s.payment?.status, PaymentStatus.completed);
    expect(s.error, isNull);
  });

  test('a successful slip upload OPTIMISTICALLY marks the live booking paid',
      () async {
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/payments/b1/promptpay') return promptpayJson();
        // The live booking snapshot — accepted, not yet paid (paid_at set async).
        return {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'accepted',
          'guard_id': 'g1',
        };
      },
      onPost: (_, __) async => paymentJson('completed'),
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      // Inject a fake WS feed so the live BookingStatusController never opens a real socket.
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tp) => FakeBookingFeed()),
    ]);
    addTearDown(c.dispose);

    // Keep BOTH controllers alive: the slip controller + the live booking the screen watches.
    final slipSub = c.listen(slipPaymentControllerProvider('b1'), (_, __) {});
    addTearDown(slipSub.close);
    final bookingSub =
        c.listen(bookingStatusControllerProvider('b1'), (_, __) {});
    addTearDown(bookingSub.close);
    final booking = await c.read(bookingStatusControllerProvider('b1').future);
    expect(booking.isPaid, isFalse);
    await Future<void>.delayed(Duration.zero);

    await c
        .read(slipPaymentControllerProvider('b1').notifier)
        .uploadSlip(tempSlip.path);

    expect(c.read(bookingStatusControllerProvider('b1')).value?.isPaid, isTrue,
        reason: 'slip verified → live booking marked paid → pay banner clears');
  });

  test(
      'each typed 409 renders its specific Thai message and returns to ready (re-pickable)',
      () async {
    final cases = <String, String>{
      'SLIP_VERIFY_FAILED': 'สลิปไม่ถูกต้อง',
      'SLIP_AMOUNT_TOO_LOW': 'ยอดโอนไม่พอ',
      'SLIP_WRONG_RECEIVER': 'โอนผิดบัญชี',
      'SLIP_DUPLICATE': 'สลิปนี้ถูกใช้แล้ว',
    };

    for (final entry in cases.entries) {
      final api = FakeApi(
        onGet: (_, __) async => promptpayJson(),
        onPost: (_, __) async => throw ApiException(
            message: 'server technical text', code: entry.key, statusCode: 409),
      );
      final c = container(api);
      final sub = c.listen(slipPaymentControllerProvider('b1'), (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      final ok = await c
          .read(slipPaymentControllerProvider('b1').notifier)
          .uploadSlip(tempSlip.path);

      expect(ok, isFalse, reason: '${entry.key} → upload did not succeed');
      final s = c.read(slipPaymentControllerProvider('b1'));
      expect(s.phase, SlipPhase.ready,
          reason: '${entry.key} → back to ready so the customer can re-pick');
      expect(s.error, contains(entry.value),
          reason: '${entry.key} → its specific Thai message');
      // It branches on the CODE, never the raw server message.
      expect(s.error, isNot(contains('server technical text')));
      c.dispose();
    }
  });

  test('an unrecognised slip error falls back to the server message', () async {
    final api = FakeApi(
      onGet: (_, __) async => promptpayJson(),
      onPost: (_, __) async => throw const ApiException(
          message: 'รูปใหญ่เกินไป', code: 'PAYLOAD_TOO_LARGE', statusCode: 413),
    );
    final c = container(api);
    final sub = c.listen(slipPaymentControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);

    await c
        .read(slipPaymentControllerProvider('b1').notifier)
        .uploadSlip(tempSlip.path);
    expect(c.read(slipPaymentControllerProvider('b1')).error, 'รูปใหญ่เกินไป');
  });

  test('cancelling the picker is a no-op (no upload, stays ready)', () async {
    var posts = 0;
    final api = FakeApi(
      onGet: (_, __) async => promptpayJson(),
      onPost: (_, __) async {
        posts++;
        return paymentJson('completed');
      },
    );
    final picker = FakeSlipPicker(path: null); // user cancelled
    final c = container(api, picker: picker);
    final sub = c.listen(slipPaymentControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);

    final ok = await c
        .read(slipPaymentControllerProvider('b1').notifier)
        .pickAndUpload(SlipSource.camera);
    expect(ok, isFalse);
    expect(posts, 0, reason: 'no slip picked → no POST');
    expect(c.read(slipPaymentControllerProvider('b1')).phase, SlipPhase.ready);
  });

  test('per-booking instances do not share slip state', () async {
    final api = FakeApi(onGet: (_, __) async => promptpayJson());
    final c = container(api);
    final s1 = c.listen(slipPaymentControllerProvider('b1'), (_, __) {});
    final s2 = c.listen(slipPaymentControllerProvider('b2'), (_, __) {});
    addTearDown(s1.close);
    addTearDown(s2.close);
    await Future<void>.delayed(Duration.zero);

    expect(c.read(slipPaymentControllerProvider('b1')).info, isNotNull);
    expect(c.read(slipPaymentControllerProvider('b2')).info, isNotNull);
    // Distinct instances — they fetched independently.
    expect(api.calls.where((x) => x.contains('promptpay')).length, 2);
  });
}
