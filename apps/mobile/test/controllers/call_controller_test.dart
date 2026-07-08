import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/calling/call_engine.dart';
import 'package:pguard_mobile/core/controllers/call_controller.dart';
import 'package:pguard_mobile/core/models/call.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

/// A [FakeCallEngine] whose [createOffer] BLOCKS on a [Completer] — lets a test interleave a callee
/// `ready` signal WHILE the offer is still being created (the PR #170 offer-on-ready race).
class _BlockingOfferEngine extends FakeCallEngine {
  _BlockingOfferEngine(this._gate);
  final Completer<SignalDescription> _gate;
  @override
  Future<SignalDescription> createOffer() async {
    createOfferCount++;
    return _gate.future; // resolves only when the test completes the gate
  }
}

Map<String, dynamic> callJson(
  String id, {
  String status = 'initiated',
  String callType = 'audio',
}) =>
    {
      'id': id,
      'caller_id': 'caller1',
      'callee_id': 'callee1',
      'booking_id': 'bk1',
      'call_type': callType,
      'status': status,
      'started_at': '2026-06-05T10:00:00Z',
      'created_at': '2026-06-05T10:00:00Z',
      'updated_at': '2026-06-05T10:00:00Z',
    };

/// The shape `GET /calls/ice` returns (public STUN + a short-lived per-caller TURN credential),
/// matching the calling OpenAPI `IceConfig`/`IceServer` schemas.
Map<String, dynamic> iceJson() => {
      'ice_servers': [
        {
          'urls': ['stun:stun.l.google.com:19302']
        },
        {
          'urls': [
            'turn:turn.pguard.app:3478?transport=udp',
            'turn:turn.pguard.app:3478?transport=tcp'
          ],
          'username': '1700000000:user-1',
          'credential': 'c2hvcnQtbGl2ZWQtY3JlZA==',
        },
      ],
      'ttl_secs': 3600,
    };

typedef Harness = ({
  ProviderContainer c,
  FakeCallEngine engine,
  FakeCallSignalFeed feed,
  FakeApi api,
});

void main() {
  Harness make({
    Map<String, dynamic>? initiate,
    Map<String, dynamic>? get,
    Map<String, dynamic>? ice,
    FakeCallEngine? engine,
    bool autoDispose = true,
  }) {
    final eng = engine ?? FakeCallEngine();
    final feed = FakeCallSignalFeed();
    final api = FakeApi(
      onPost: (_, __) async => initiate ?? callJson('call1'),
      // The controller GETs both the call (`/calls/{id}`) and the served ICE list (`/calls/ice`).
      onGet: (path, __) async => path == '/calls/ice'
          ? (ice ?? iceJson())
          : (get ?? callJson('call1')),
      onPut: (_, __) async => {'success': true},
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      callEngineFactoryProvider.overrideWithValue(() => eng),
      callSignalFeedBuilderProvider.overrideWithValue((_) => feed),
    ]);
    if (autoDispose) addTearDown(c.dispose);
    // Keep the keepAlive provider alive + built.
    final sub = c.listen(callControllerProvider, (_, __) {});
    addTearDown(sub.close);
    return (c: c, engine: eng, feed: feed, api: api);
  }

  CallController ctrl(ProviderContainer c) =>
      c.read(callControllerProvider.notifier);
  CallState st(ProviderContainer c) => c.read(callControllerProvider);
  Iterable<CallSignalKind> kinds(FakeCallSignalFeed f) =>
      f.sent.map((s) => s.signal.kind);
  Future<void> tick() => Future<void>.delayed(Duration.zero);

  // ---- state machine + REST verbs ----

  test(
      'outgoing: POST /calls/initiate → dialing, engine + socket up; offer held until `ready`',
      () async {
    final t = make(initiate: callJson('call1'));
    await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);

    expect(st(t.c).phase, CallPhase.dialing);
    expect(st(t.c).isCaller, isTrue);
    expect(t.api.calls, contains('POST /calls/initiate'));
    expect(t.engine.initialized, isTrue);
    expect(t.engine.createOfferCount, 1, reason: 'the offer is created…');
    expect(t.feed.connected, isTrue);
    expect(kinds(t.feed), isEmpty,
        reason:
            '…but NOT sent until the callee signals `ready` (no wasted send)');
  });

  test(
      'offer-on-ready RACE: callee `ready` beats a still-pending createOffer → exactly ONE offer (PR #170)',
      () async {
    // PR #170. On a VIDEO call the caller's media setup + camera-permission prompt make
    // `createOffer()` slow, so the push → callee `ready` can BEAT the offer being created. While
    // `createOffer()` is suspended, `_onPeerReady` runs with a null `_localOffer` (the one-shot
    // `ready` already consumed) and sends nothing. The offer must NOT be lost: once createOffer
    // completes, `startOutgoing`'s `if (_peerReady) _resendOffer()` sends it — exactly once.
    final gate = Completer<SignalDescription>();
    final eng = _BlockingOfferEngine(gate);
    final feed = FakeCallSignalFeed();
    final api = FakeApi(
      onPost: (_, __) async => callJson('call1'),
      onGet: (path, __) async =>
          path == '/calls/ice' ? iceJson() : callJson('call1'),
      onPut: (_, __) async => {'success': true},
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      callEngineFactoryProvider.overrideWithValue(() => eng),
      callSignalFeedBuilderProvider.overrideWithValue((_) => feed),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(callControllerProvider, (_, __) {});
    addTearDown(sub.close);

    // Start the call but do NOT await — createOffer is blocked on the gate, so startOutgoing is
    // suspended at `_localOffer = await _engine!.createOffer()`.
    final pending =
        ctrl(c).startOutgoing(bookingId: 'bk1', type: CallType.video);
    await tick(); // let setup run up to the blocked createOffer
    expect(eng.createOfferCount, 1,
        reason: 'createOffer is in-flight (blocked)');
    expect(kinds(feed), isEmpty,
        reason: 'no offer can be sent before it exists');

    // The callee opens its socket and announces `ready` WHILE createOffer is still pending. The
    // one-shot `ready` is consumed now with a null offer — it sends nothing.
    feed.emitSignal('call1', CallSignal.ready());
    await tick();
    expect(
      feed.sent.where((s) => s.signal.kind == CallSignalKind.offer),
      isEmpty,
      reason: '`ready` beat the offer → nothing to (re)send yet',
    );

    // Now the offer is created → startOutgoing resumes and, seeing `_peerReady`, sends it.
    gate.complete(const SignalDescription(type: 'offer', sdp: 'OFFER_SDP'));
    await pending;
    await tick();

    final offers =
        feed.sent.where((s) => s.signal.kind == CallSignalKind.offer).toList();
    expect(offers, hasLength(1),
        reason:
            'exactly ONE offer — not lost when `ready` beat createOffer, not doubled');
    expect(offers.single.signal.sdp, 'OFFER_SDP');
  });

  test(
      'ICE config applied: served STUN+TURN list is fetched and passed to the engine (not hard-coded)',
      () async {
    final t = make(initiate: callJson('call1'));
    await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);

    // The controller fetched the served ICE list…
    expect(t.api.calls, contains('GET /calls/ice'));
    // …and handed it to the engine verbatim (no client-side hard-coding).
    final servers = t.engine.initIceServers;
    expect(servers, isNotNull);
    expect(servers!.length, 2);
    expect(servers[0].urls, ['stun:stun.l.google.com:19302']);
    expect(servers[0].credential, isNull,
        reason: 'STUN entry carries no credential');
    // The TURN entry carries the short-lived, per-caller credential from the server.
    expect(
        servers[1].urls, contains('turn:turn.pguard.app:3478?transport=udp'));
    expect(servers[1].username, '1700000000:user-1');
    expect(servers[1].credential, 'c2hvcnQtbGl2ZWQtY3JlZA==');
  });

  test(
      'ICE fetch failure fails call setup + tears down (no silent hard-coded fallback)',
      () async {
    final eng = FakeCallEngine();
    final feed = FakeCallSignalFeed();
    final api = FakeApi(
      onPost: (_, __) async => callJson('call1'),
      onGet: (path, __) async => path == '/calls/ice'
          ? throw const ApiException(message: 'ice unavailable')
          : callJson('call1'),
      onPut: (_, __) async => {'success': true},
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      callEngineFactoryProvider.overrideWithValue(() => eng),
      callSignalFeedBuilderProvider.overrideWithValue((_) => feed),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(callControllerProvider, (_, __) {});
    addTearDown(sub.close);

    await c
        .read(callControllerProvider.notifier)
        .startOutgoing(bookingId: 'bk1', type: CallType.audio);

    expect(c.read(callControllerProvider).phase, CallPhase.ended);
    expect(eng.initialized, isFalse,
        reason: 'engine never initialised without ICE');
    expect(feed.closed, isTrue, reason: 'setup torn down on failure');
  });

  test('caller: an inbound answer moves dialing → connecting', () async {
    final t = make(initiate: callJson('call1'));
    await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);
    expect(st(t.c).phase, CallPhase.dialing);

    t.feed.emitSignal('call1', CallSignal.answer('ANSWER_SDP'));
    await tick();

    expect(st(t.c).phase, CallPhase.connecting,
        reason: 'caller traverses connecting (symmetric with the callee)');
  });

  test(
      'two offers (eager + ready-resend) produce exactly ONE answer (no double-answer race)',
      () async {
    final t = make(get: callJson('call1'));
    await ctrl(t.c).startIncoming(callId: 'call1');
    await ctrl(t.c).accept(); // accept BEFORE any offer arrives
    expect(t.engine.createAnswerCount, 0, reason: 'no offer yet → no answer');

    // Two offers delivered in the same turn (the concurrent interleaving the guard protects).
    t.feed.emitSignal('call1', CallSignal.offer('O1'));
    t.feed.emitSignal('call1', CallSignal.offer('O1'));
    await tick();
    await tick();

    expect(t.engine.createAnswerCount, 1,
        reason: 'exactly one answer despite two offers');
    expect(t.engine.remoteDescriptions.length, 1,
        reason: 'setRemoteDescription called once');
    expect(st(t.c).phase, CallPhase.connecting);
  });

  test('incoming: GET /calls/{id} → ringing, announces `ready`', () async {
    final t = make(get: callJson('call1', callType: 'video'));
    await ctrl(t.c).startIncoming(callId: 'call1');

    expect(st(t.c).phase, CallPhase.incoming);
    expect(st(t.c).isCaller, isFalse);
    expect(st(t.c).callType, CallType.video);
    expect(t.api.calls, contains('GET /calls/call1'));
    expect(t.feed.sent.single.signal.kind, CallSignalKind.ready);
  });

  test(
      'dismissIncoming (call_cancelled push) clears the ring for THIS call; no-op otherwise',
      () async {
    final t = make(get: callJson('call1'));
    await ctrl(t.c).startIncoming(callId: 'call1');
    expect(st(t.c).phase, CallPhase.incoming);

    // A cancel for a DIFFERENT / stale call must never tear down a live ring.
    ctrl(t.c).dismissIncoming('other');
    expect(st(t.c).phase, CallPhase.incoming,
        reason: 'only the matching call_id may clear the ring');

    // The caller hung up before we answered → the ring clears (→ ended, screen auto-pops).
    ctrl(t.c).dismissIncoming('call1');
    expect(st(t.c).phase, CallPhase.ended);
  });

  test(
      'incoming video HINT: ring shows video BEFORE the GET resolves (callee knows pre-answer)',
      () async {
    // The push carried `call_type: video`; the GET would resolve audio (here) — but the ring UI
    // must reflect the video hint IMMEDIATELY (synchronously, before the GET), so the callee knows
    // it is a video call before answering. `startIncoming` sets state synchronously, then awaits.
    final t = make(get: callJson('call1', callType: 'audio'));
    final pending =
        ctrl(t.c).startIncoming(callId: 'call1', typeHint: CallType.video);

    // Synchronous part has run: ringing + video from the hint (the GET has NOT resolved yet).
    expect(st(t.c).phase, CallPhase.incoming);
    expect(st(t.c).callType, CallType.video,
        reason: 'video hint reflected before the GET');
    expect(st(t.c).speakerOn, isTrue,
        reason: 'speaker on for video by default');

    await pending; // GET resolves → server type (audio here) is authoritative and overwrites.
    expect(st(t.c).callType, CallType.audio,
        reason: 'the GET is the source of truth and overrides the hint');
  });

  // ---- can-call-again-after-end (keepAlive singleton reset) ----

  test(
      'reset() returns an ENDED call to idle, so a fresh call starts right after',
      () async {
    final t = make(get: callJson('call1'));
    // A callee call that is rejected → ended (callee path does not hit the caller-only summary).
    await ctrl(t.c).startIncoming(callId: 'call1');
    await ctrl(t.c).reject();
    expect(st(t.c).phase, CallPhase.ended);

    // The screen's dispose calls reset(): the singleton must return to idle (not linger in ended).
    ctrl(t.c).reset();
    expect(st(t.c).phase, CallPhase.idle);

    // A NEW outgoing call now works immediately (was blocked/stuck before the reset fix).
    await ctrl(t.c).startOutgoing(bookingId: 'bk2', type: CallType.audio);
    expect(st(t.c).phase, CallPhase.dialing);
  });

  test(
      'reset() is a no-op for a LIVE call (never breaks the single-active-call guard)',
      () async {
    final t = make(get: callJson('call1'));
    await ctrl(t.c).startIncoming(callId: 'call1');
    expect(st(t.c).phase, CallPhase.incoming);

    ctrl(t.c).reset(); // mid-call → must NOT tear the live call down
    expect(st(t.c).phase, CallPhase.incoming,
        reason: 'reset only acts on a terminal (ended) call');
  });

  test(
      'accept: PUT /calls/{id}/accept → connecting; answers once the offer is in',
      () async {
    final t = make(get: callJson('call1'));
    await ctrl(t.c).startIncoming(callId: 'call1');

    t.feed.emitSignal('call1', CallSignal.offer('REMOTE_OFFER'));
    await tick();
    await ctrl(t.c).accept();

    expect(st(t.c).phase, CallPhase.connecting);
    expect(t.api.calls, contains('PUT /calls/call1/accept'));
    expect(t.engine.remoteDescriptions.single.sdp, 'REMOTE_OFFER');
    expect(t.engine.createAnswerCount, 1);
    expect(kinds(t.feed), contains(CallSignalKind.answer));
  });

  test('media connected → PUT /calls/{id}/connected and phase active',
      () async {
    final t = make(get: callJson('call1'));
    await ctrl(t.c).startIncoming(callId: 'call1');
    t.feed.emitSignal('call1', CallSignal.offer('O'));
    await tick();
    await ctrl(t.c).accept();

    t.engine.emitMediaEvent(CallMediaEvent.connected);
    await tick();

    expect(st(t.c).phase, CallPhase.active);
    expect(t.api.calls, contains('PUT /calls/call1/connected'));
  });

  // ---- trickle ICE queue ----

  test(
      'trickle ICE: candidates before the remote description queue, then flush in order',
      () async {
    final t = make(get: callJson('call1'));
    await ctrl(t.c).startIncoming(callId: 'call1');

    t.feed.emitSignal('call1', CallSignal.candidate(candidate: 'c1'));
    t.feed.emitSignal('call1', CallSignal.candidate(candidate: 'c2'));
    await tick();
    expect(t.engine.addedCandidates, isEmpty,
        reason: 'queued until the remote description is set');

    t.feed.emitSignal('call1', CallSignal.offer('OFFER'));
    await tick();
    await ctrl(t.c).accept(); // sets remote description → flush

    expect(t.engine.addedCandidates.map((c) => c.candidate), ['c1', 'c2']);

    // A candidate AFTER the remote description is applied immediately.
    t.feed.emitSignal('call1', CallSignal.candidate(candidate: 'c3'));
    await tick();
    expect(
        t.engine.addedCandidates.map((c) => c.candidate), ['c1', 'c2', 'c3']);
  });

  test('caller: local ICE candidates buffer until `ready`, then flush in order',
      () async {
    final t = make(initiate: callJson('call1'));
    await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);

    // Candidates gathered BEFORE the callee joins the relay must NOT be sent (the relay has no
    // store-and-forward — it would drop them as "peer offline"). They are buffered.
    t.engine.emitLocalCandidate(
        const SignalCandidate(candidate: 'c1', sdpMid: '0', sdpMLineIndex: 0));
    t.engine.emitLocalCandidate(
        const SignalCandidate(candidate: 'c2', sdpMid: '0', sdpMLineIndex: 0));
    await tick();
    expect(
      t.feed.sent.where((s) => s.signal.kind == CallSignalKind.candidate),
      isEmpty,
      reason: 'no candidate is relayed before the peer is `ready`',
    );

    // The callee announces `ready` → the buffered candidates flush, in order.
    t.feed.emitSignal('call1', CallSignal.ready());
    await tick();
    expect(
      t.feed.sent
          .where((s) => s.signal.kind == CallSignalKind.candidate)
          .map((s) => s.signal.candidate),
      ['c1', 'c2'],
    );

    // A candidate gathered AFTER `ready` is relayed immediately (no buffering once the peer is in).
    t.engine.emitLocalCandidate(
        const SignalCandidate(candidate: 'c3', sdpMid: '0', sdpMLineIndex: 0));
    await tick();
    expect(
      t.feed.sent
          .where((s) => s.signal.kind == CallSignalKind.candidate)
          .map((s) => s.signal.candidate),
      ['c1', 'c2', 'c3'],
    );
  });

  test(
      'callee: local ICE flows immediately (the caller is already on the relay)',
      () async {
    final t = make(get: callJson('call1'));
    await ctrl(t.c).startIncoming(callId: 'call1');

    // The callee's peer (the caller) dialed first and is already connected, so the callee marks the
    // peer ready when it announces itself — its local candidates are relayed without buffering.
    t.engine.emitLocalCandidate(const SignalCandidate(
        candidate: 'localC', sdpMid: '0', sdpMLineIndex: 0));
    await tick();
    expect(
      t.feed.sent
          .where((s) => s.signal.kind == CallSignalKind.candidate)
          .map((s) => s.signal.candidate),
      ['localC'],
    );
  });

  // ---- signal relay routing ----

  test('caller: an inbound answer sets the remote description and flushes ICE',
      () async {
    final t = make(initiate: callJson('call1'));
    await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);

    t.feed.emitSignal('call1', CallSignal.candidate(candidate: 'c1'));
    await tick();
    expect(t.engine.addedCandidates, isEmpty);

    t.feed.emitSignal('call1', CallSignal.answer('ANSWER_SDP'));
    await tick();

    expect(t.engine.remoteDescriptions.single.type, 'answer');
    expect(t.engine.addedCandidates.map((c) => c.candidate), ['c1']);
  });

  test('caller re-sends its offer when the callee signals `ready`', () async {
    final t = make(initiate: callJson('call1'));
    await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);
    final before =
        t.feed.sent.where((s) => s.signal.kind == CallSignalKind.offer).length;

    t.feed.emitSignal('call1', CallSignal.ready());
    await tick();

    final after =
        t.feed.sent.where((s) => s.signal.kind == CallSignalKind.offer).length;
    expect(after, before + 1);
  });

  test('signals for a DIFFERENT call id are ignored', () async {
    final t = make(initiate: callJson('call1'));
    await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);

    t.feed.emitSignal('OTHER', CallSignal.bye());
    await tick();

    expect(st(t.c).phase, CallPhase.dialing, reason: 'foreign call id ignored');
  });

  // ---- end / reject / remote-bye + teardown ----

  test('reject: PUT /calls/{id}/reject + bye, ends + tears down', () async {
    final t = make(get: callJson('call1'));
    await ctrl(t.c).startIncoming(callId: 'call1');
    await ctrl(t.c).reject();

    expect(t.api.calls, contains('PUT /calls/call1/reject'));
    expect(kinds(t.feed), contains(CallSignalKind.bye));
    expect(st(t.c).phase, CallPhase.ended);
    expect(t.engine.disposed, isTrue);
    expect(t.feed.closed, isTrue);
  });

  test('end: PUT /calls/{id}/end + bye, tears down engine + socket', () async {
    final t = make(initiate: callJson('call1'));
    await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);
    await ctrl(t.c).end();

    expect(t.api.calls, contains('PUT /calls/call1/end'));
    expect(st(t.c).phase, CallPhase.ended);
    expect(t.engine.disposed, isTrue);
    expect(t.feed.closed, isTrue);
  });

  test('an inbound `bye` ends the call and tears down', () async {
    final t = make(initiate: callJson('call1'));
    await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);

    t.feed.emitSignal('call1', CallSignal.bye());
    await tick();

    expect(st(t.c).phase, CallPhase.ended);
    expect(t.engine.disposed, isTrue);
  });

  test('a denied mic/camera permission fails the call gracefully', () async {
    final t = make(
      initiate: callJson('call1'),
      engine: FakeCallEngine(
          throwOnInit:
              const CallException('Microphone permission is required')),
    );
    await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);

    expect(st(t.c).phase, CallPhase.ended);
    expect(st(t.c).error, contains('Microphone'));
  });

  // ---- in-call controls ----

  test('toggleMute / toggleSpeaker drive the engine + state', () async {
    final t = make(initiate: callJson('call1'));
    await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);

    await ctrl(t.c).toggleMute();
    expect(st(t.c).muted, isTrue);
    expect(t.engine.muted, isTrue);

    await ctrl(t.c).toggleSpeaker();
    expect(st(t.c).speakerOn, isTrue);
    expect(t.engine.speakerOn, isTrue);
  });

  test('disposing the container tears down the engine + socket', () async {
    final t = make(autoDispose: false);
    await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);

    t.c.dispose();
    await tick();

    expect(t.engine.disposed, isTrue);
    expect(t.feed.closed, isTrue);
  });

  // ---- call summary is now SERVER-SIDE (chat consumes `calling.ended`) ----

  group('call summary is no longer posted by the client', () {
    /// Wire a [FakeChatFeed] (via [chatFeedBuilderProvider]) so we can ASSERT the controller never
    /// opens a chat feed / sends a `system` frame on end — the call summary is emitted server-side
    /// now, so the mobile must NOT send a chat frame anymore. A short settle window lets any stray
    /// fire-and-forget post (there should be none) run before we assert.
    ({ProviderContainer c, FakeCallEngine engine, FakeChatFeed chatFeed})
        makeWithChatSpy() {
      final eng = FakeCallEngine();
      final feed = FakeCallSignalFeed();
      final chatFeed = FakeChatFeed();
      final api = FakeApi(
        onPost: (_, __) async => callJson('call1'),
        onGet: (path, __) async =>
            path == '/calls/ice' ? iceJson() : callJson('call1'),
        onPut: (_, __) async => {'success': true},
      );
      final c = ProviderContainer(overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        callEngineFactoryProvider.overrideWithValue(() => eng),
        callSignalFeedBuilderProvider.overrideWithValue((_) => feed),
        chatFeedBuilderProvider.overrideWithValue((_) => chatFeed),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(callControllerProvider, (_, __) {});
      addTearDown(sub.close);
      return (c: c, engine: eng, chatFeed: chatFeed);
    }

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 400));

    test('caller end(): does NOT open a chat feed or send a `system` frame',
        () async {
      final t = makeWithChatSpy();
      await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);
      t.engine.emitMediaEvent(CallMediaEvent.connected);
      await tick();
      await ctrl(t.c).end();
      await settle();

      expect(t.chatFeed.connected, isFalse,
          reason:
              'the call summary is server-side now — no chat feed is opened');
      expect(t.chatFeed.sent, isEmpty,
          reason: 'the mobile no longer posts the call-summary chat frame');
    });

    test('missed caller end(): still no client chat frame', () async {
      final t = makeWithChatSpy();
      await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.video);
      await ctrl(t.c).end(); // never connected
      await settle();

      expect(t.chatFeed.sent, isEmpty);
    });

    test('callee end(): no client chat frame', () async {
      final t = makeWithChatSpy();
      await ctrl(t.c).startIncoming(callId: 'call1');
      await ctrl(t.c).end();
      await settle();

      expect(t.chatFeed.sent, isEmpty);
    });
  });
}
