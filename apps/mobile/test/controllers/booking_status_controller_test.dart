import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/booking_status_controller.dart';
import 'package:pguard_mobile/core/models/booking.dart';
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
}
