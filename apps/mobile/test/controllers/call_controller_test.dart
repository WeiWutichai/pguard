import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/calling/call_engine.dart';
import 'package:pguard_mobile/core/controllers/call_controller.dart';
import 'package:pguard_mobile/core/models/call.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

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
      onGet: (path, __) async =>
          path == '/calls/ice' ? (ice ?? iceJson()) : (get ?? callJson('call1')),
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

  test('outgoing: POST /calls/initiate → dialing, engine + socket up; offer held until `ready`',
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
        reason: '…but NOT sent until the callee signals `ready` (no wasted send)');
  });

  test('ICE config applied: served STUN+TURN list is fetched and passed to the engine (not hard-coded)',
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
    expect(servers[0].credential, isNull, reason: 'STUN entry carries no credential');
    // The TURN entry carries the short-lived, per-caller credential from the server.
    expect(servers[1].urls, contains('turn:turn.pguard.app:3478?transport=udp'));
    expect(servers[1].username, '1700000000:user-1');
    expect(servers[1].credential, 'c2hvcnQtbGl2ZWQtY3JlZA==');
  });

  test('ICE fetch failure fails call setup + tears down (no silent hard-coded fallback)',
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
    expect(eng.initialized, isFalse, reason: 'engine never initialised without ICE');
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

  test('two offers (eager + ready-resend) produce exactly ONE answer (no double-answer race)',
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

  test('accept: PUT /calls/{id}/accept → connecting; answers once the offer is in',
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

  test('media connected → PUT /calls/{id}/connected and phase active', () async {
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

  test('trickle ICE: candidates before the remote description queue, then flush in order',
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
    expect(t.engine.addedCandidates.map((c) => c.candidate), ['c1', 'c2', 'c3']);
  });

  test('local ICE candidates are relayed as candidate signals', () async {
    final t = make(initiate: callJson('call1'));
    await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);

    t.engine.emitLocalCandidate(
        const SignalCandidate(candidate: 'localC', sdpMid: '0', sdpMLineIndex: 0));
    await tick();

    final cands =
        t.feed.sent.where((s) => s.signal.kind == CallSignalKind.candidate);
    expect(cands.last.signal.candidate, 'localC');
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
          throwOnInit: const CallException('Microphone permission is required')),
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
}
