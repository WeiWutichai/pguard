import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/booking_status_controller.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  test('one REST snapshot, then status advances from WS pushes (NO polling)',
      () async {
    final feed = FakeBookingFeed();
    final store = InMemoryStore()..access = 'token';
    final api = FakeApi(onGet: (path, _) async {
      expect(path, '/bookings/b1');
      return {
        'id': 'b1',
        'customer_id': 'c1',
        'status': 'accepted',
        'guard_id': null
      };
    });

    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(store),
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tokenProvider) => feed),
    ]);
    addTearDown(c.dispose);

    // Keep the provider alive across emits.
    final sub = c.listen(bookingStatusControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    final initial = await c.read(bookingStatusControllerProvider('b1').future);
    expect(initial.status, BookingStatus.accepted);
    expect(feed.connected, isTrue,
        reason: 'controller subscribed to the live feed');

    // Push transitions over the (fake) WebSocket — the controller folds them in.
    feed.emit(BookingStatusEvent(
        bookingId: 'b1',
        status: BookingStatus.enRoute,
        occurredAt: DateTime.utc(2026)));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(bookingStatusControllerProvider('b1')).value?.status,
        BookingStatus.enRoute);

    feed.emit(BookingStatusEvent(
        bookingId: 'b1',
        status: BookingStatus.arrived,
        occurredAt: DateTime.utc(2026),
        guardId: 'g7'));
    await Future<void>.delayed(Duration.zero);
    final arrived = c.read(bookingStatusControllerProvider('b1')).value!;
    expect(arrived.status, BookingStatus.arrived);
    expect(arrived.guardId, 'g7');

    // THE proof: only the single initial snapshot was fetched — updates came via push.
    expect(api.getCount, 1);
  });

  test('disposing the provider closes the feed', () async {
    final feed = FakeBookingFeed();
    final store = InMemoryStore();
    final api = FakeApi(
        onGet: (_, __) async => {
              'id': 'b1',
              'customer_id': 'c1',
              'status': 'accepted',
              'guard_id': null
            });
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(store),
      bookingStatusFeedBuilderProvider.overrideWithValue((id, tp) => feed),
    ]);
    final sub = c.listen(bookingStatusControllerProvider('b1'), (_, __) {});
    await c.read(bookingStatusControllerProvider('b1').future);
    sub.close();
    c.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(feed.closed, isTrue);
  });

  test(
      'cancel PUTs /bookings/{id}/cancel with NO body (contract: cancelBooking '
      'takes none — reason is display-only) and folds the cancelled booking in',
      () async {
    final api = FakeApi(
      onGet: (_, __) async => {
        'id': 'b1',
        'customer_id': 'c1',
        'status': 'accepted',
        'guard_id': null,
      },
      onPut: (path, data) async {
        expect(path, '/bookings/b1/cancel');
        expect(data, isNull, reason: 'the contract endpoint takes no body');
        return {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'cancelled',
          'guard_id': null,
        };
      },
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tp) => FakeBookingFeed()),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(bookingStatusControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);
    await c.read(bookingStatusControllerProvider('b1').future);

    final error = await c
        .read(bookingStatusControllerProvider('b1').notifier)
        .cancel(reason: 'เปลี่ยนแผน');
    expect(error, isNull);
    expect(api.calls, contains('PUT /bookings/b1/cancel'));
    expect(c.read(bookingStatusControllerProvider('b1')).value?.status,
        BookingStatus.cancelled);
  });

  test('markPaid marks the booking paid optimistically', () async {
    final api = FakeApi(onGet: (_, __) async => {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'accepted',
          'guard_id': 'g1',
          // No paid_at — the booking service sets it ASYNC after the charge.
        });
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tp) => FakeBookingFeed()),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(bookingStatusControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    final initial = await c.read(bookingStatusControllerProvider('b1').future);
    expect(initial.isPaid, isFalse, reason: 'snapshot has no paid_at yet');

    c.read(bookingStatusControllerProvider('b1').notifier).markPaid();
    expect(c.read(bookingStatusControllerProvider('b1')).value?.isPaid, isTrue,
        reason: 'pay banner disappears immediately, no async wait');
  });

  test(
      'paid is MONOTONIC — a stale unpaid snapshot after a re-fetch does NOT '
      'un-pay an already-paid booking (no pay-loop)', () async {
    // The snapshot the server returns STAYS unpaid (simulates `paid_at` lagging the charge).
    final api = FakeApi(onGet: (_, __) async => {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'accepted',
          'guard_id': 'g1',
        });
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tp) => FakeBookingFeed()),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(bookingStatusControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    await c.read(bookingStatusControllerProvider('b1').future);
    // Pay optimistically.
    c.read(bookingStatusControllerProvider('b1').notifier).markPaid();
    expect(c.read(bookingStatusControllerProvider('b1')).value?.isPaid, isTrue);

    // Re-pull a FRESH snapshot (e.g. live-status resume) — it still lacks paid_at.
    c.invalidate(bookingStatusControllerProvider('b1'));
    final reloaded =
        await c.read(bookingStatusControllerProvider('b1').future);
    expect(reloaded.isPaid, isTrue,
        reason: 'a stale unpaid snapshot must NOT downgrade paid → unpaid');
  });

  test(
      'a fresh snapshot that DOES carry paid_at stays paid (real server '
      'paid_at also honoured)', () async {
    final api = FakeApi(onGet: (_, __) async => {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'en_route',
          'guard_id': 'g1',
          'paid_at': '2026-06-05T10:05:00Z',
        });
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tp) => FakeBookingFeed()),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(bookingStatusControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);

    final booking = await c.read(bookingStatusControllerProvider('b1').future);
    expect(booking.isPaid, isTrue);
  });

  test('cancel surfaces the server error message and keeps the booking',
      () async {
    final api = FakeApi(
      onGet: (_, __) async => {
        'id': 'b1',
        'customer_id': 'c1',
        'status': 'arrived',
        'guard_id': 'g1',
      },
      onPut: (path, _) async => throw const ApiException(
          message: 'ยกเลิกไม่ได้หลังเจ้าหน้าที่ถึงแล้ว',
          code: 'CONFLICT',
          statusCode: 409),
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tp) => FakeBookingFeed()),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(bookingStatusControllerProvider('b1'), (_, __) {});
    addTearDown(sub.close);
    await c.read(bookingStatusControllerProvider('b1').future);

    final error =
        await c.read(bookingStatusControllerProvider('b1').notifier).cancel();
    expect(error, 'ยกเลิกไม่ได้หลังเจ้าหน้าที่ถึงแล้ว');
    expect(c.read(bookingStatusControllerProvider('b1')).value?.status,
        BookingStatus.arrived,
        reason: 'state unchanged on failure');
  });
}
