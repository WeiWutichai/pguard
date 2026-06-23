import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/booking_status_controller.dart';
import 'package:pguard_mobile/core/controllers/payment_controller.dart';
import 'package:pguard_mobile/core/models/payment.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

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
  test(
      'createPayment POSTs /payments with ONLY { booking_id } (client never sends '
      'the amount) and flips to the paid success state', () async {
    Object? sentData;
    final api = FakeApi(
      onPost: (path, data) async {
        expect(path, '/payments');
        sentData = data;
        return paymentJson('completed');
      },
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    // Initial state: not busy, not paid, no error.
    final s0 = c.read(paymentControllerProvider('b1'));
    expect(s0.busy, isFalse);
    expect(s0.isPaid, isFalse);
    expect(s0.error, isNull);

    final ok =
        await c.read(paymentControllerProvider('b1').notifier).createPayment();
    expect(ok, isTrue);

    // The client sends ONLY the booking id — the amount is computed + charged server-side.
    expect(sentData, {'booking_id': 'b1'});
    expect(api.calls, contains('POST /payments'));

    final s1 = c.read(paymentControllerProvider('b1'));
    expect(s1.busy, isFalse);
    expect(s1.isPaid, isTrue);
    expect(s1.payment?.status, PaymentStatus.completed);
    expect(s1.error, isNull);
  });

  test('createPayment surfaces the server error and stays unpaid', () async {
    final api = FakeApi(
      onPost: (_, __) async => throw const ApiException(
          message: 'ยอดเงินไม่ถูกต้อง', code: 'BAD_AMOUNT', statusCode: 400),
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    final ok =
        await c.read(paymentControllerProvider('b1').notifier).createPayment();
    expect(ok, isFalse);

    final s = c.read(paymentControllerProvider('b1'));
    expect(s.busy, isFalse);
    expect(s.isPaid, isFalse);
    expect(s.error, 'ยอดเงินไม่ถูกต้อง');
  });

  test('createPayment is a no-op once already paid (no second POST)', () async {
    var posts = 0;
    final api = FakeApi(
      onPost: (_, __) async {
        posts++;
        return paymentJson('completed');
      },
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    final notifier = c.read(paymentControllerProvider('b1').notifier);
    expect(await notifier.createPayment(), isTrue);
    // A second tap after success must not re-charge.
    expect(await notifier.createPayment(), isTrue);
    expect(posts, 1, reason: 'paid → guarded against a double charge');
  });

  test(
      'a successful payment OPTIMISTICALLY marks the LIVE booking paid (the pay '
      'banner disappears without waiting for the async paid_at)', () async {
    final api = FakeApi(
      onGet: (_, __) async => {
        'id': 'b1',
        'customer_id': 'c1',
        'status': 'accepted',
        'guard_id': 'g1',
        // No paid_at yet — the booking service sets it ASYNC.
      },
      onPost: (_, __) async => paymentJson('completed'),
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tp) => FakeBookingFeed()),
    ]);
    addTearDown(c.dispose);

    // The PaymentScreen watches the live booking — keep it alive.
    final sub = c.listen(bookingStatusControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);
    final booking = await c.read(bookingStatusControllerProvider('b1').future);
    expect(booking.isPaid, isFalse);

    await c.read(paymentControllerProvider('b1').notifier).createPayment();

    expect(c.read(bookingStatusControllerProvider('b1')).value?.isPaid, isTrue,
        reason: 'payment success marks the live booking paid → banner clears');
  });

  test('per-booking instances do not share pay state', () async {
    final api = FakeApi(onPost: (_, __) async => paymentJson('completed'));
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    await c.read(paymentControllerProvider('b1').notifier).createPayment();
    expect(c.read(paymentControllerProvider('b1')).isPaid, isTrue);
    // A different booking is untouched.
    expect(c.read(paymentControllerProvider('b2')).isPaid, isFalse);
  });
}
