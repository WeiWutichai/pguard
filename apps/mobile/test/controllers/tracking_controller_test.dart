import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/controllers/tracking_controller.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';
import 'package:pguard_mobile/core/models/tracking.dart';
import 'package:pguard_mobile/core/network/sockets/presence_socket.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

/// Stub [Session] that starts AUTHENTICATED (so the controller's logout-teardown listener is
/// dormant) and exposes [signOut] to flip it to `unauthenticated` mid-test — driving the
/// follow-the-guard-out-of-the-session teardown without the real async secure-storage load.
class _StubSession extends Session {
  @override
  SessionState build() => const SessionState(SessionStatus.authenticated,
      user: AuthUser(userId: 'guard1', role: 'guard'));

  void signOut() => state = const SessionState(SessionStatus.unauthenticated);
}

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
    // The immediate one-shot start fix makes the guard fresh from t=0 (before any movement).
    expect(feed.sent, hasLength(1), reason: 'a start fix is sent on stream start');
    expect(loc.sampleCount, 1, reason: 'one one-shot fix taken on start');

    loc.emit(GpsSample(
        lat: 13.7, lng: 100.5, accuracy: 6, recordedAt: DateTime.utc(2026)));
    await flush();

    final s = c.read(trackingControllerProvider);
    expect(s.lastSample?.accuracy, 6);
    expect(s.accuracyBand, GpsAccuracyBand.high);
    expect(s.isTracking, isTrue);
    // The start fix + the movement-stream fix were both forwarded to presence.
    expect(feed.sent, hasLength(2));
  });

  test('goOffline tears down the feed and resets state', () async {
    final feed = FakePresenceFeed();
    final loc = FakeLocationService();
    final c = makeContainer(feed, loc);
    final ctrl = c.read(trackingControllerProvider.notifier);

    await ctrl.goOnline();
    await flush();
    final sentAtOnline = feed.sent.length; // the start fix
    await ctrl.goOffline();

    expect(feed.closed, isTrue);
    final s = c.read(trackingControllerProvider);
    expect(s.online, isFalse);
    expect(s.link, PresenceLink.offline);

    // After going offline, late GPS fixes are NOT forwarded (nothing beyond the start fix).
    loc.emit(GpsSample(lat: 1, lng: 2, recordedAt: DateTime.utc(2026)));
    await flush();
    expect(feed.sent, hasLength(sentAtOnline));
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
    final sentAfterStart = feed.sent.length; // the start fix taken on lease

    loc.emit(GpsSample(lat: 13.7, lng: 100.5, recordedAt: DateTime.utc(2026)));
    await flush();
    expect(feed.sent.length, sentAfterStart + 1,
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
    final sentBeforeRelease = feed.sent.length; // the start fix
    await ctrl.stopJobStreaming('b1');

    expect(feed.closed, isTrue);
    final s = c.read(trackingControllerProvider);
    expect(s.streaming, isFalse);
    expect(s.link, PresenceLink.offline);

    // Late fixes after the lease is dropped are NOT forwarded (nothing beyond the start fix).
    loc.emit(GpsSample(lat: 1, lng: 2, recordedAt: DateTime.utc(2026)));
    await flush();
    expect(feed.sent, hasLength(sentBeforeRelease));
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

  test('logging out while a job lease is held tears it down (feed closed, state reset, late fix dropped)',
      () async {
    // Going offline must follow the guard out of the session: if the guard logs out (or is
    // force-revoked) WHILE on an active job — holding a streaming lease — the keepAlive controller
    // would otherwise keep streaming GPS after logout. The session listener in build() must shut it
    // all down: drop the lease, close the feed, reset state, and stop forwarding any late fix.
    final feed = FakePresenceFeed();
    final loc = FakeLocationService();
    late final _StubSession session;
    final c = ProviderContainer(overrides: [
      presenceFeedBuilderProvider.overrideWithValue((_) => feed),
      locationServiceProvider.overrideWithValue(loc),
      pguardApiProvider.overrideWithValue(FakeApi()),
      permissionGateProvider
          .overrideWithValue(FakePermissionGate(PgPermissionState.granted)),
      appStoreProvider
          .overrideWithValue(InMemoryStore()..access = 't'..refresh = 'r'),
      sessionProvider.overrideWith(() => session = _StubSession()),
    ]);
    addTearDown(c.dispose);
    final ctrl = c.read(trackingControllerProvider.notifier);

    // Take a job lease (no manual toggle) → streaming over the active-job lease alone.
    await ctrl.startJobStreaming('b1');
    await flush();
    expect(c.read(trackingControllerProvider).streaming, isTrue);
    expect(feed.connected, isTrue);
    final sentBeforeLogout = feed.sent.length; // the start fix

    // Log out: the session flips to unauthenticated → the controller's listener tears everything
    // down even though the lease is still nominally held.
    session.signOut();
    await flush();

    expect(feed.closed, isTrue, reason: 'the presence feed is closed on logout');
    final s = c.read(trackingControllerProvider);
    expect(s.streaming, isFalse, reason: 'the job lease is dropped on logout');
    expect(s.jobIds, isEmpty);
    expect(s.online, isFalse);
    expect(s.link, PresenceLink.offline);

    // A GPS fix that arrives AFTER logout is NOT forwarded (the subscription is gone + the guard).
    loc.emit(GpsSample(lat: 13.7, lng: 100.5, recordedAt: DateTime.utc(2026)));
    await flush();
    expect(feed.sent, hasLength(sentBeforeLogout),
        reason: 'no GPS leaks to presence after logout');
  });

  // ── Stationary-guard freshness (the discoverability bug) ──────────────────────────────────
  // A guard who goes online and then sits still waiting for a job emits NOTHING on the
  // movement-gated positionStream (distanceFilter 15m). Without the start fix + keepalive their
  // last presence fix goes stale (>5min) and the presence service drops them from online-guards,
  // so customers can no longer be matched to them. These tests pin both halves of the fix.

  test('a STATIONARY guard (no movement fixes) is sent an immediate start fix on go-online',
      () async {
    final feed = FakePresenceFeed();
    final loc = FakeLocationService();
    final c = makeContainer(feed, loc);
    final ctrl = c.read(trackingControllerProvider.notifier);

    await ctrl.goOnline();
    await flush();

    // The positionStream NEVER emits (the guard is stationary) — yet a fix is already on the wire
    // from the one-shot start fix, so the guard is fresh + discoverable from t=0.
    expect(loc.sampleCount, 1, reason: 'one one-shot fix taken on start');
    expect(feed.sent, hasLength(1), reason: 'the start fix reached presence without movement');
    expect(c.read(trackingControllerProvider).lastSample, isNotNull);
  });

  test('a STATIONARY guard keeps presence fresh via the ~90s keepalive', () {
    fakeAsync((async) {
      final feed = FakePresenceFeed();
      final loc = FakeLocationService();
      final c = makeContainer(feed, loc);
      final ctrl = c.read(trackingControllerProvider.notifier);

      ctrl.goOnline();
      async.flushMicrotasks(); // resolve goOnline → start fix
      expect(feed.sent, hasLength(1), reason: 'start fix');
      expect(loc.sampleCount, 1);

      // No movement fix ever arrives. Three keepalive ticks (~90s each) re-send a current fix so
      // recorded_at stays well inside the 5-min freshness window.
      async.elapse(const Duration(seconds: 90));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 90));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 90));
      async.flushMicrotasks();

      expect(feed.sent, hasLength(4),
          reason: 'start fix + one keepalive fix per ~90s tick');
      expect(loc.sampleCount, 4, reason: 'each tick takes a fresh one-shot fix');

      ctrl.goOffline(); // stop the timer so FakeAsync has no pending periodic timer
      async.flushMicrotasks();
      c.dispose();
    });
  });

  test('the keepalive stops on goOffline (no further fixes after going offline)', () {
    fakeAsync((async) {
      final feed = FakePresenceFeed();
      final loc = FakeLocationService();
      final c = makeContainer(feed, loc);
      final ctrl = c.read(trackingControllerProvider.notifier);

      ctrl.goOnline();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 90));
      async.flushMicrotasks();
      final sentWhileOnline = feed.sent.length; // start fix + one keepalive
      final samplesWhileOnline = loc.sampleCount;

      ctrl.goOffline();
      async.flushMicrotasks();

      // Far past several keepalive intervals — nothing more is taken or sent once offline.
      async.elapse(const Duration(minutes: 10));
      async.flushMicrotasks();
      expect(feed.sent, hasLength(sentWhileOnline),
          reason: 'no keepalive fixes after goOffline');
      expect(loc.sampleCount, samplesWhileOnline,
          reason: 'the keepalive timer is cancelled in teardown');

      c.dispose();
    });
  });

  test('with no permission/fix, currentSample() is null and the keepalive sends nothing', () {
    fakeAsync((async) {
      final feed = FakePresenceFeed();
      final loc = FakeLocationService()..sample = null; // permission denied / no fix
      final c = makeContainer(feed, loc);
      final ctrl = c.read(trackingControllerProvider.notifier);

      ctrl.goOnline();
      async.flushMicrotasks();
      // The start fix found no sample (and there is no prior lastSample) → nothing is sent.
      expect(loc.sampleCount, 1, reason: 'a one-shot fix was attempted on start');
      expect(feed.sent, isEmpty, reason: 'no fix available → nothing pushed');

      // Keepalive keeps attempting (the guard might regain a fix later) but sends nothing while
      // currentSample stays null and there is no cached sample.
      async.elapse(const Duration(seconds: 90));
      async.flushMicrotasks();
      expect(loc.sampleCount, 2, reason: 'the keepalive tick attempts a fix');
      expect(feed.sent, isEmpty, reason: 'still no fix → still nothing pushed');

      ctrl.goOffline();
      async.flushMicrotasks();
      c.dispose();
    });
  });

  test('logout cancels the keepalive (no fixes after the session ends)', () {
    fakeAsync((async) {
      final feed = FakePresenceFeed();
      final loc = FakeLocationService();
      late final _StubSession session;
      final c = ProviderContainer(overrides: [
        presenceFeedBuilderProvider.overrideWithValue((_) => feed),
        locationServiceProvider.overrideWithValue(loc),
        pguardApiProvider.overrideWithValue(FakeApi()),
        permissionGateProvider
            .overrideWithValue(FakePermissionGate(PgPermissionState.granted)),
        appStoreProvider
            .overrideWithValue(InMemoryStore()..access = 't'..refresh = 'r'),
        sessionProvider.overrideWith(() => session = _StubSession()),
      ]);
      final ctrl = c.read(trackingControllerProvider.notifier);

      ctrl.goOnline();
      async.flushMicrotasks();
      final samplesBeforeLogout = loc.sampleCount; // start fix
      final sentBeforeLogout = feed.sent.length;

      session.signOut(); // session-out teardown cancels the keepalive
      async.flushMicrotasks();

      async.elapse(const Duration(minutes: 10));
      async.flushMicrotasks();
      expect(loc.sampleCount, samplesBeforeLogout,
          reason: 'no keepalive fixes are taken after logout');
      expect(feed.sent, hasLength(sentBeforeLogout));

      c.dispose();
    });
  });
}
