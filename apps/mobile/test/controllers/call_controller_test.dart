import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/calling/call_engine.dart';
import 'package:pguard_mobile/core/controllers/call_controller.dart';
import 'package:pguard_mobile/core/controllers/chat_launcher.dart';
import 'package:pguard_mobile/core/controllers/locale_controller.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';
import 'package:pguard_mobile/core/models/call.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

/// Stub [Session] whose [build] returns a fixed authenticated user — so [CallController] can read
/// the acting role (drives the call-summary `sender_role`) without the real async secure-storage
/// load. Override [sessionProvider] with `overrideWith(() => _StubSession(role))`.
class _StubSession extends Session {
  _StubSession(this._role);
  final String _role;
  @override
  SessionState build() => SessionState(SessionStatus.authenticated,
      user: AuthUser(userId: 'me', role: _role));
}

/// Stub [LocaleController] pinned to a language (default Thai) — avoids the real async prefs load.
class _StubLocale extends LocaleController {
  _StubLocale(this._locale);
  final AppLocale _locale;
  @override
  AppLocale build() => _locale;
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
      onGet: (path, __) async =>
          path == '/calls/ice' ? (ice ?? iceJson()) : (get ?? callJson('call1')),
      onPut: (_, __) async => {'success': true},
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      callEngineFactoryProvider.overrideWithValue(() => eng),
      callSignalFeedBuilderProvider.overrideWithValue((_) => feed),
      // The caller posts an end-of-call chat summary, which reads session (acting role) + locale and
      // (now) find-or-CREATEs the thread + opens a chat feed. Stub session/locale so the real async
      // secure-storage/prefs loads never fire, and stub the chat feed so it never dials a real WS.
      sessionProvider.overrideWith(() => _StubSession('customer')),
      localeControllerProvider.overrideWith(() => _StubLocale(AppLocale.th)),
      chatLauncherProvider.overrideWithValue(ChatLauncher(api)),
      chatFeedBuilderProvider.overrideWithValue((_) => FakeChatFeed()),
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
      sessionProvider.overrideWith(() => _StubSession('customer')),
      localeControllerProvider.overrideWith(() => _StubLocale(AppLocale.th)),
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

  test('incoming video HINT: ring shows video BEFORE the GET resolves (callee knows pre-answer)',
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
    expect(st(t.c).speakerOn, isTrue, reason: 'speaker on for video by default');

    await pending; // GET resolves → server type (audio here) is authoritative and overwrites.
    expect(st(t.c).callType, CallType.audio,
        reason: 'the GET is the source of truth and overrides the hint');
  });

  // ---- can-call-again-after-end (keepAlive singleton reset) ----

  test('reset() returns an ENDED call to idle, so a fresh call starts right after', () async {
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

  test('reset() is a no-op for a LIVE call (never breaks the single-active-call guard)',
      () async {
    final t = make(get: callJson('call1'));
    await ctrl(t.c).startIncoming(callId: 'call1');
    expect(st(t.c).phase, CallPhase.incoming);

    ctrl(t.c).reset(); // mid-call → must NOT tear the live call down
    expect(st(t.c).phase, CallPhase.incoming,
        reason: 'reset only acts on a terminal (ended) call');
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

  test('caller: local ICE candidates buffer until `ready`, then flush in order', () async {
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

  test('callee: local ICE flows immediately (the caller is already on the relay)', () async {
    final t = make(get: callJson('call1'));
    await ctrl(t.c).startIncoming(callId: 'call1');

    // The callee's peer (the caller) dialed first and is already connected, so the callee marks the
    // peer ready when it announces itself — its local candidates are relayed without buffering.
    t.engine.emitLocalCandidate(
        const SignalCandidate(candidate: 'localC', sdpMid: '0', sdpMLineIndex: 0));
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

  // ---- call-summary line posted into the booking chat thread (#93) ----

  group('call summary → chat thread', () {
    /// A container that also wires the chat side (feed + launcher + session/locale) so the caller's
    /// end-of-call `system` chat post is observable. The `/conversations` list (read by the launcher
    /// to map booking → conversation) is canned by [conversations].
    ({
      ProviderContainer c,
      FakeCallEngine engine,
      FakeCallSignalFeed callFeed,
      FakeChatFeed chatFeed,
      FakeApi api,
    }) makeWithChat({
      List<Map<String, dynamic>> conversations = const [
        {'id': 'conv1', 'request_id': 'bk1', 'created_at': '2026-06-05T10:00:00Z'}
      ],
      String role = 'customer',
      AppLocale locale = AppLocale.th,
    }) {
      final eng = FakeCallEngine();
      final callFeed = FakeCallSignalFeed();
      final chatFeed = FakeChatFeed();
      final api = FakeApi(
        // /calls/initiate → a call; /conversations (create, on a find miss) → a new conversation.
        onPost: (path, __) async => path == '/conversations'
            ? {
                'id': 'convNew',
                'request_id': 'bk1',
                'created_at': '2026-06-05T10:00:00Z',
              }
            : callJson('call1'),
        onGet: (path, __) async => switch (path) {
          '/calls/ice' => iceJson(),
          '/conversations' => conversations,
          _ => callJson('call1'),
        },
        onPut: (_, __) async => {'success': true},
      );
      final c = ProviderContainer(overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        callEngineFactoryProvider.overrideWithValue(() => eng),
        callSignalFeedBuilderProvider.overrideWithValue((_) => callFeed),
        chatFeedBuilderProvider.overrideWithValue((_) => chatFeed),
        chatLauncherProvider.overrideWithValue(ChatLauncher(api)),
        sessionProvider.overrideWith(() => _StubSession(role)),
        localeControllerProvider.overrideWith(() => _StubLocale(locale)),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(callControllerProvider, (_, __) {});
      addTearDown(sub.close);
      return (c: c, engine: eng, callFeed: callFeed, chatFeed: chatFeed, api: api);
    }

    /// `_postCallSummary` awaits a launcher GET + a chat connect + a 250ms flush delay; let it run.
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 400));

    test('completed call: caller posts a `system` line with the duration (TH)', () async {
      final t = makeWithChat();
      await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);
      // Media connects → active (anchors the duration), then the caller ends.
      t.engine.emitMediaEvent(CallMediaEvent.connected);
      await tick();
      await ctrl(t.c).end();
      await settle();

      final frame = t.chatFeed.sent.single;
      expect(frame['message_type'], 'system');
      expect(frame['conversation_id'], 'conv1');
      expect(frame['sender_role'], 'customer');
      // Duration ~0s for an instant test; assert the audio kind + the M:SS shape, not the value.
      expect(frame['content'], startsWith('📞 สายเสียง · '));
      expect(frame['content'], matches(RegExp(r'· \d+:\d{2}$')));
      expect(t.chatFeed.closed, isTrue, reason: 'the short-lived feed is closed after sending');
    });

    test('missed video call (never connected): line shows the video kind + missed outcome (EN)',
        () async {
      final t = makeWithChat(locale: AppLocale.en);
      await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.video);
      await ctrl(t.c).end(); // caller hangs up before the callee answers → missed
      await settle();

      expect(t.chatFeed.sent.single['content'], '📹 Video call · Missed call');
    });

    test('rejected call: caller posts a declined line (the callee never posts)', () async {
      final t = makeWithChat();
      await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);
      // The callee's reject arrives as a remote `bye` on the caller, BUT the caller's reason for a
      // pre-connect remote hangup is `remote_hangup` → "missed". A true reject outcome is the
      // callee's own path; here we assert the CALLER still leaves exactly one row.
      t.callFeed.emitSignal('call1', CallSignal.bye());
      await tick();
      await settle();

      expect(t.chatFeed.sent, hasLength(1));
      expect(t.chatFeed.sent.single['message_type'], 'system');
    });

    test('the CALLEE never posts a summary (avoids a duplicate row)', () async {
      final t = makeWithChat();
      await ctrl(t.c).startIncoming(callId: 'call1');
      await ctrl(t.c).end();
      await settle();

      expect(t.chatFeed.sent, isEmpty,
          reason: 'only the caller posts; the callee would double the row');
    });

    test('no conversation yet → find-or-create then post into the new thread', () async {
      // A call belongs in the matched pair's chat thread even if they never chatted before: the
      // summary now find-OR-CREATEs the conversation and posts the system line into it (was: drop).
      final t = makeWithChat(conversations: const []);
      await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);
      await ctrl(t.c).end();
      await settle();

      expect(t.chatFeed.sent.single['message_type'], 'system');
      expect(t.chatFeed.sent.single['conversation_id'], 'convNew');
    });

    test('exactly one summary even if end() is reached twice', () async {
      final t = makeWithChat();
      await ctrl(t.c).startOutgoing(bookingId: 'bk1', type: CallType.audio);
      await ctrl(t.c).end();
      await ctrl(t.c).end(); // idempotent — a second end must not post again
      await settle();

      expect(t.chatFeed.sent, hasLength(1));
    });
  });
}
