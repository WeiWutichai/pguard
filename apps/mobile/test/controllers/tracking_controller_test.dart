import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/tracking_controller.dart';
import 'package:pguard_mobile/core/models/tracking.dart';
import 'package:pguard_mobile/core/network/sockets/presence_socket.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  ProviderContainer makeContainer(FakePresenceFeed feed, FakeLocationService loc) {
    // access + refresh present + no PIN → Session resolves to `authenticated`, so the
    // controller's logout-teardown listener stays dormant during the test.
    final c = ProviderContainer(overrides: [
      presenceFeedBuilderProvider.overrideWithValue((_) => feed),
      locationServiceProvider.overrideWithValue(loc),
      pguardApiProvider.overrideWithValue(FakeApi()),
      // goOnline() now requests location permission on every path — grant it in the fake so the
      // test exercises the connect/stream path (the real gate would hit platform channels).
      permissionGateProvider
          .overrideWithValue(FakePermissionGate(PgPermissionState.granted)),
      appStoreProvider
          .overrideWithValue(InMemoryStore()..access = 't'..refresh = 'r'),
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

  test('goOnline requests location permission (OS dialog shows on every path, incl. the duty FAB)',
      () async {
    final gate = FakePermissionGate(PgPermissionState.granted);
    final c = ProviderContainer(overrides: [
      presenceFeedBuilderProvider.overrideWithValue((_) => FakePresenceFeed()),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
      pguardApiProvider.overrideWithValue(FakeApi()),
      permissionGateProvider.overrideWithValue(gate),
      appStoreProvider
          .overrideWithValue(InMemoryStore()..access = 't'..refresh = 'r'),
    ]);
    addTearDown(c.dispose);
    expect(gate.requestCount, 0);
    await c.read(trackingControllerProvider.notifier).goOnline();
    expect(gate.requestCount, 1, reason: 'goOnline must request the location permission');
  });

  test(
      'an active-job lease streams GPS even while the manual online toggle is OFF',
      () async {
    final feed = FakePresenceFeed();
    final loc = FakeLocationService();
    final c = makeContainer(feed, loc);
    final ctrl = c.read(trackingControllerProvider.notifier);

    // No manual go-online. Taking a job lease alone opens the feed + streams.
    await ctrl.startJobStreaming('b1');
    await flush();
    final s = c.read(trackingControllerProvider);
    expect(s.online, isFalse, reason: 'the manual toggle stays off');
    expect(s.streaming, isTrue, reason: 'the job lease keeps GPS flowing');
    expect(feed.connected, isTrue);

    loc.emit(GpsSample(lat: 13.7, lng: 100.5, recordedAt: DateTime.utc(2026)));
    await flush();
    expect(feed.sent, hasLength(1),
        reason: 'the active job forwards live fixes to presence');
  });

  test('releasing the last job lease tears the feed down (toggle still off)',
      () async {
    final feed = FakePresenceFeed();
    final loc = FakeLocationService();
    final c = makeContainer(feed, loc);
    final ctrl = c.read(trackingControllerProvider.notifier);

    await ctrl.startJobStreaming('b1');
    await flush();
    await ctrl.stopJobStreaming('b1');

    expect(feed.closed, isTrue);
    final s = c.read(trackingControllerProvider);
    expect(s.streaming, isFalse);
    expect(s.link, PresenceLink.offline);

    // Late fixes after the lease is dropped are NOT forwarded.
    loc.emit(GpsSample(lat: 1, lng: 2, recordedAt: DateTime.utc(2026)));
    await flush();
    expect(feed.sent, isEmpty);
  });

  test('going offline keeps streaming while a job lease is still held', () async {
    final feed = FakePresenceFeed();
    final loc = FakeLocationService();
    final c = makeContainer(feed, loc);
    final ctrl = c.read(trackingControllerProvider.notifier);

    await ctrl.goOnline();
    await flush();
    await ctrl.startJobStreaming('b1');
    await flush();

    // Manually go offline (no longer discoverable) — but the active job must stay live.
    await ctrl.goOffline();
    final s = c.read(trackingControllerProvider);
    expect(s.online, isFalse);
    expect(s.streaming, isTrue, reason: 'the job lease outlives the toggle');
    expect(feed.closed, isFalse, reason: 'the feed stays open for the active job');

    loc.emit(GpsSample(lat: 13.7, lng: 100.5, recordedAt: DateTime.utc(2026)));
    await flush();
    expect(feed.sent, isNotEmpty);
  });

  test('startJobStreaming is idempotent per booking (one feed, no double-connect)',
      () async {
    var built = 0;
    final feed = FakePresenceFeed();
    final c = ProviderContainer(overrides: [
      presenceFeedBuilderProvider.overrideWithValue((_) {
        built++;
        return feed;
      }),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
      pguardApiProvider.overrideWithValue(FakeApi()),
      permissionGateProvider
          .overrideWithValue(FakePermissionGate(PgPermissionState.granted)),
      appStoreProvider
          .overrideWithValue(InMemoryStore()..access = 't'..refresh = 'r'),
    ]);
    addTearDown(c.dispose);
    final ctrl = c.read(trackingControllerProvider.notifier);

    await ctrl.startJobStreaming('b1');
    await ctrl.startJobStreaming('b1'); // same job again
    await ctrl.goOnline(); // toggle on top of the lease
    await flush();
    expect(built, 1, reason: 'a single presence feed serves the toggle + all leases');
    expect(c.read(trackingControllerProvider).jobIds, {'b1'});
  });
}
