import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/active_job_controller.dart';
import 'package:pguard_mobile/core/media/photo_capture.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson(String id, String status) => {
      'id': id,
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': status,
      'address': 'หมู่บ้านลัดดารมย์',
      'scheduled_at': '2026-06-05T14:00:00Z',
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'tip': '0',
      'created_at': '2026-06-05T10:00:00Z',
      'updated_at': '2026-06-05T10:00:00Z',
    };

void main() {
  test('drives transitions to the correct PUT paths; start records startedAt',
      () async {
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/bookings/b1');
        return bookingJson('b1', 'accepted');
      },
      onPut: (path, _) async {
        switch (path) {
          case '/bookings/b1/en-route':
            return bookingJson('b1', 'en_route');
          case '/bookings/b1/arrived':
            return bookingJson('b1', 'arrived');
          case '/bookings/b1/start':
            return bookingJson('b1', 'arrived'); // start keeps status = arrived
          case '/bookings/b1/complete':
            return bookingJson('b1', 'pending_completion');
          default:
            throw StateError('unexpected PUT $path');
        }
      },
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    final s0 = await c.read(activeJobControllerProvider('b1').future);
    expect(s0.booking.status, BookingStatus.accepted);
    expect(s0.startedAt, isNull);
    expect(s0.clock, isNull); // no countdown until started

    final ctrl = c.read(activeJobControllerProvider('b1').notifier);
    ActiveJobState state() => c.read(activeJobControllerProvider('b1')).value!;

    expect(await ctrl.enRoute(), isTrue);
    expect(state().booking.status, BookingStatus.enRoute);

    expect(await ctrl.arrived(), isTrue);
    expect(state().booking.status, BookingStatus.arrived);

    expect(await ctrl.start(), isTrue);
    expect(state().startedAt, isNotNull); // client-recorded (API doesn't expose it)
    expect(state().clock, isNotNull);
    expect(state().booking.status, BookingStatus.arrived);

    expect(await ctrl.complete(), isTrue);
    expect(state().booking.status, BookingStatus.pendingCompletion);

    expect(
        api.calls,
        containsAllInOrder([
          'PUT /bookings/b1/en-route',
          'PUT /bookings/b1/arrived',
          'PUT /bookings/b1/start',
          'PUT /bookings/b1/complete',
        ]));
  });

  test('withdraw PUTs decline (assigned-guard withdraw → declined)', () async {
    final api = FakeApi(
      onGet: (_, __) async => bookingJson('b1', 'accepted'),
      onPut: (path, _) async {
        expect(path, '/bookings/b1/decline');
        return bookingJson('b1', 'declined');
      },
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);
    await c.read(activeJobControllerProvider('b1').future);

    expect(await c.read(activeJobControllerProvider('b1').notifier).withdraw(),
        isTrue);
    expect(c.read(activeJobControllerProvider('b1')).value!.booking.status,
        BookingStatus.declined);
    expect(api.calls, contains('PUT /bookings/b1/decline'));
  });

  test('submitCheckIn records the slot via the check-in service', () async {
    final checkIn = FakeCheckInService();
    final api = FakeApi(onGet: (_, __) async => bookingJson('b1', 'arrived'));
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      checkInServiceProvider.overrideWithValue(checkIn),
    ]);
    addTearDown(c.dispose);

    await c.read(activeJobControllerProvider('b1').future);
    final ctrl = c.read(activeJobControllerProvider('b1').notifier);

    final ok = await ctrl.submitCheckIn(
      hourNumber: 1,
      photo: const CapturedPhoto(path: '/tmp/p.jpg', sizeBytes: 10),
    );
    expect(ok, isTrue);
    expect(checkIn.submitted, [1]);
    expect(c.read(activeJobControllerProvider('b1')).value!.completedCheckIns,
        contains(1));
  });

  test('submitCheckIn surfaces failure and does not mark the slot done',
      () async {
    final checkIn = FakeCheckInService(fail: true);
    final api = FakeApi(onGet: (_, __) async => bookingJson('b1', 'arrived'));
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      checkInServiceProvider.overrideWithValue(checkIn),
    ]);
    addTearDown(c.dispose);

    await c.read(activeJobControllerProvider('b1').future);
    final ctrl = c.read(activeJobControllerProvider('b1').notifier);
    final ok = await ctrl.submitCheckIn(
      hourNumber: 1,
      photo: const CapturedPhoto(path: '/tmp/p.jpg', sizeBytes: 10),
    );
    expect(ok, isFalse);
    final s = c.read(activeJobControllerProvider('b1')).value!;
    expect(s.completedCheckIns, isEmpty);
    expect(s.error, isNotNull);
  });
}
