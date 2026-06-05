import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/tracking_controller.dart';
import 'package:pguard_mobile/core/models/tracking.dart';
import 'package:pguard_mobile/core/network/sockets/presence_socket.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  ProviderContainer makeContainer(FakePresenceFeed feed, FakeLocationService loc) {
    final c = ProviderContainer(overrides: [
      presenceFeedBuilderProvider.overrideWithValue((_) => feed),
      locationServiceProvider.overrideWithValue(loc),
      pguardApiProvider.overrideWithValue(FakeApi()),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('goOnline connects, streams GPS to the feed, and tracks accuracy', () async {
    final feed = FakePresenceFeed();
    final loc = FakeLocationService();
    final c = makeContainer(feed, loc);
    final ctrl = c.read(trackingControllerProvider.notifier);

    expect(c.read(trackingControllerProvider).online, isFalse);

    await ctrl.goOnline();
    await flush(); // deliver the link=online frame
    expect(c.read(trackingControllerProvider).online, isTrue);
    expect(feed.connected, isTrue);

    loc.emit(GpsSample(
        lat: 13.7, lng: 100.5, accuracy: 6, recordedAt: DateTime.utc(2026)));
    await flush();

    final s = c.read(trackingControllerProvider);
    expect(s.lastSample?.accuracy, 6);
    expect(s.accuracyBand, GpsAccuracyBand.high);
    expect(s.isTracking, isTrue);
    expect(feed.sent, hasLength(1)); // forwarded the fix to the presence feed
  });

  test('goOffline tears down the feed and resets state', () async {
    final feed = FakePresenceFeed();
    final loc = FakeLocationService();
    final c = makeContainer(feed, loc);
    final ctrl = c.read(trackingControllerProvider.notifier);

    await ctrl.goOnline();
    await flush();
    await ctrl.goOffline();

    expect(feed.closed, isTrue);
    final s = c.read(trackingControllerProvider);
    expect(s.online, isFalse);
    expect(s.link, PresenceLink.offline);

    // After going offline, late GPS fixes are NOT forwarded.
    loc.emit(GpsSample(lat: 1, lng: 2, recordedAt: DateTime.utc(2026)));
    await flush();
    expect(feed.sent, isEmpty);
  });

  test('toggle flips online/offline', () async {
    final feed = FakePresenceFeed();
    final c = makeContainer(feed, FakeLocationService());
    final ctrl = c.read(trackingControllerProvider.notifier);
    await ctrl.toggle();
    await flush();
    expect(c.read(trackingControllerProvider).online, isTrue);
    await ctrl.toggle();
    expect(c.read(trackingControllerProvider).online, isFalse);
  });
}
