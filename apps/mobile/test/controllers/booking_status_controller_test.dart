import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/booking_status_controller.dart';
import 'package:pguard_mobile/core/controllers/progress_reports_controller.dart';
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

  test(
      'a guard check-in nudge (progress_reported) re-pulls the progress reports '
      'WITHOUT changing booking status — the customer live feed updates, no refresh',
      () async {
    // The booking is `arrived` with 3 booked hours; the guard submits hour-2's check-in. The
    // gateway fans that out as a refresh-only `progress_reported` frame. We assert: (a) the
    // booking status STAYS arrived, and (b) the progress-reports controller (which watches the
    // booking-status controller) RE-PULLS `/bookings/b1/progress-reports` — so the new photo +
    // the advancing countdown appear live, with no manual refresh.
    var reportRows = <Map<String, dynamic>>[
      {
        'id': 'pr1',
        'booking_id': 'b1',
        'hour_number': 1,
        'photo_url': 'https://x/1.jpg',
        'created_at': '2026-06-25T10:00:00Z',
      },
    ];
    final feed = FakeBookingFeed();
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings/b1') {
        return {
          'id': 'b1',
          'customer_id': 'c1',
          'status': 'arrived',
          'guard_id': 'g1',
          'hours': 3,
        };
      }
      if (path == '/bookings/b1/progress-reports') return reportRows;
      return <dynamic>[];
    });

    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      bookingStatusFeedBuilderProvider.overrideWithValue((id, tp) => feed),
    ]);
    addTearDown(c.dispose);

    final statusSub =
        c.listen(bookingStatusControllerProvider('b1'), (_, __) {});
    addTearDown(statusSub.close);
    final progressSub =
        c.listen(progressReportsControllerProvider('b1'), (_, __) {});
    addTearDown(progressSub.close);

    // Initial pull: one report so far.
    final first = await c.read(progressReportsControllerProvider('b1').future);
    expect(first.reportedCount, 1);
    final pullsBefore = api.calls
        .where((x) => x == 'GET /bookings/b1/progress-reports')
        .length;

    // The guard checks in hour 2 — the server now returns 2 reports.
    reportRows = [
      ...reportRows,
      {
        'id': 'pr2',
        'booking_id': 'b1',
        'hour_number': 2,
        'photo_url': 'https://x/2.jpg',
        'created_at': '2026-06-25T11:00:00Z',
      },
    ];

    // The refresh-only nudge arrives over the WS (NO status field → status null, isRefresh true).
    feed.emit(BookingStatusEvent(
      bookingId: 'b1',
      status: null,
      occurredAt: DateTime.utc(2026, 6, 25, 11),
      guardId: 'g1',
      isRefresh: true,
    ));
    await Future<void>.delayed(Duration.zero);

    // Status is UNCHANGED (a check-in is not a lifecycle transition).
    expect(c.read(bookingStatusControllerProvider('b1')).value?.status,
        BookingStatus.arrived);

    // The progress-reports controller RE-PULLED and now shows the new check-in.
    final reloaded =
        await c.read(progressReportsControllerProvider('b1').future);
    expect(reloaded.reportedCount, 2,
        reason: 'the new check-in appears live, no manual refresh');
    final pullsAfter = api.calls
        .where((x) => x == 'GET /bookings/b1/progress-reports')
        .length;
    expect(pullsAfter, greaterThan(pullsBefore),
        reason: 'the nudge forced a fresh progress-reports fetch');
  });
}
