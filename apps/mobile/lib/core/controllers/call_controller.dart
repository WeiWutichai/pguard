import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../calling/call_engine.dart';
import '../models/call.dart';
import '../network/api_error_l10n.dart';
import '../network/api_exception.dart';
import '../network/sockets/call_socket.dart';
import '../providers.dart';
import 'locale_controller.dart';

part 'call_controller.g.dart';

/// Drives one WebRTC voice/video call: the call-state machine (idle → dialing|incoming →
/// connecting → active → ended), the `RTCPeerConnection` (via the plugin-free [CallEngine] seam),
/// the trickle-ICE queue, and the `/ws/call` signaling socket. ALL media/WebRTC lifecycle lives
/// here, never in widget state; the screen only renders + binds renderers to the engine streams.
/// No `Timer.periodic` — everything is event-driven (signals + engine callbacks).
///
/// Single active call at a time (keepAlive singleton). The `/ws/call` relay has no presence /
/// lifecycle push, so the SDP exchange is bootstrapped by a `ready` signal: the callee announces
/// itself on open and the caller (re)sends the offer in response.
@Riverpod(keepAlive: true)
class CallController extends _$CallController {
  CallEngine? _engine;
  CallSignalFeed? _feed;
  StreamSubscription<SignalCandidate>? _localCandSub;
  StreamSubscription<CallMediaEvent>? _mediaSub;
  StreamSubscription<void>? _remoteSub;
  StreamSubscription<CallSignalFrame>? _signalSub;

  /// Inbound ICE candidates that arrived BEFORE the remote description was set (trickle ICE).
  final List<SignalCandidate> _iceQueue = [];

  /// OUTBOUND local ICE candidates gathered BEFORE the peer joined the relay. The relay has no
  /// store-and-forward: a candidate sent while the peer's socket is not yet open is DROPPED (the
  /// server replies "peer is offline"). The caller's PC starts gathering the moment it is built —
  /// seconds before the callee opens its socket (the callee only learns of the call via the push,
  /// which travels outbox → NATS → notification → FCM). Without buffering, the caller's early
  /// host/srflx/relay candidates are lost, which on restrictive Thai-mobile NAT can stop the call
  /// from connecting at all. So we QUEUE local candidates until the peer is `ready`, then flush —
  /// symmetric with the inbound [_iceQueue] and the offer-on-`ready` bootstrap.
  final List<SignalCandidate> _localIceQueue = [];
  bool _peerReady = false;
  bool _remoteSet = false;
  bool _maybeAnswering =
      false; // in-flight guard: prevents a concurrent double-answer
  bool _accepted = false; // callee has accepted → answer once the offer is in
  SignalDescription? _pendingOffer; // callee: offer received before accept
  SignalDescription?
      _localOffer; // caller: offer to (re)send on the callee's `ready`
  String? _callId;
  bool _tornDown = false;

  /// One-shot connect timeout (a single Timer is fine — NOT `Timer.periodic`): ends a call that
  /// never reaches `active` (callee never answers / media never connects) so it can't hang.
  Timer? _connectTimeout;
  static const Duration _connectTimeoutDuration = Duration(seconds: 60);

  @override
  CallState build() {
    ref.onDispose(_teardown);
    return CallState.idle;
  }

  /// Whether the app is rendering in Thai — used to localize the transport/generic failure text this
  /// controller stores in [CallState.error] (rendered raw on the call-ended screen).
  bool get _isThai => ref.read(localeControllerProvider) == AppLocale.th;

  /// The media engine for the VIEW to bind renderers to (local/remote streams). The controller
  /// owns the call lifecycle; the screen only renders the streams. `null` before a call starts.
  CallEngine? get engine => _engine;

  bool get _busy =>
      state.phase == CallPhase.dialing ||
      state.phase == CallPhase.incoming ||
      state.phase == CallPhase.connecting ||
      state.phase == CallPhase.active;

  // ---------------------------------------------------------------------------
  // Lifecycle entry points
  // ---------------------------------------------------------------------------

  /// Place an OUTGOING call to the other participant of [bookingId] (callee derived server-side).
  Future<void> startOutgoing({
    required String bookingId,
    required CallType type,
  }) async {
    if (_busy) return; // one call at a time
    _resetSession();
    state = CallState(
      phase: CallPhase.dialing,
      callType: type,
      isCaller: true,
      speakerOn: type.isVideo,
    );
    try {
      final data = await ref.read(pguardApiProvider).post('/calls/initiate',
          data: {'booking_id': bookingId, 'call_type': type.wire});
      final call = Call.fromJson(data as Map<String, dynamic>);
      _callId = call.id;
      state = state.copyWith(call: call);

      await _setupSession(video: type.isVideo);
      // Create the offer now but do NOT send it yet — the callee isn't on the relay until it opens
      // its socket. We send (and re-send) on the callee's `ready` signal, which avoids a wasted
      // send + a spurious "peer is offline" error frame on the happy path, and means the caller
      // emits exactly one offer per `ready`.
      _localOffer = await _engine!.createOffer();
      // If the callee already announced `ready` WHILE we were setting up media + creating the offer,
      // send it now. This is the common case on a VIDEO call: getUserMedia + the camera-permission
      // prompt make the caller's setup slow, so the push → callee `ready` can BEAT `_localOffer`.
      // `ready` is one-shot, so `_onPeerReady` already ran with a null offer and sent nothing —
      // without this the offer is never delivered, the callee accepts but can never answer, and the
      // caller hangs on "calling". Idempotent: the callee dedupes a duplicate offer (_maybeAnswering).
      if (_peerReady) _resendOffer();
    } on ApiException catch (e) {
      // Localize the transport/5xx failure (offline → hardcoded English "Network error…" was leaking
      // into the Thai call-ended screen — deep-review).
      _fail(localizeApiError(_isThai, e));
    } on CallException catch (e) {
      // A media/permission error carries a specific message (e.g. "Microphone permission…") — kept
      // verbatim; localizing it into Thai codes is a larger refactor (see api_error_l10n).
      _fail(e.message);
    } catch (_) {
      _fail(_isThai ? 'เริ่มการโทรไม่สำเร็จ' : 'Could not start the call');
    }
  }

  /// Receive an INCOMING call (the call id arrives via a notification / push). Loads the call,
  /// opens signaling, and announces readiness so the caller sends its offer. Shows the ring UI.
  ///
  /// [typeHint] is the push's `call_type` (when it carried one): the ring UI shows the video
  /// indicator immediately, before `GET /calls/{id}` resolves the authoritative type — the callee
  /// must know it is a video call BEFORE answering. The GET still overwrites it (server is truth).
  Future<void> startIncoming(
      {required String callId, CallType? typeHint}) async {
    if (_busy) return;
    _resetSession();
    _callId = callId;
    state = CallState(
      phase: CallPhase.incoming,
      callType: typeHint ?? CallType.audio,
      isCaller: false,
      speakerOn: (typeHint ?? CallType.audio).isVideo,
    );
    try {
      final data = await ref.read(pguardApiProvider).get('/calls/$callId');
      final call = Call.fromJson(data as Map<String, dynamic>);
      if (call.status.isTerminal) {
        _end(reason: call.endReason ?? call.status.wire);
        return;
      }
      state = state.copyWith(
        call: call,
        callType: call.callType,
        speakerOn: call.callType.isVideo,
      );
      await _setupSession(video: call.callType.isVideo);
      // Relay has no lifecycle push → tell the caller we're here so it (re)sends the offer. The
      // callee's PEER (the caller) is already on the relay (it dialed first; we only learned of the
      // call via the push), so our local ICE may flow immediately — mark the peer ready and flush
      // anything that gathered during `_setupSession`.
      _peerReady = true;
      _sendSignal(CallSignal.ready());
      _flushLocalIce();
    } on ApiException catch (e) {
      _fail(localizeApiError(_isThai, e));
    } on CallException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail(_isThai ? 'รับสายไม่สำเร็จ' : 'Could not load the call');
    }
  }

  /// Callee accepts a ringing call → `PUT /calls/{id}/accept`, then answer once the offer is in.
  Future<void> accept() async {
    if (state.phase != CallPhase.incoming || _callId == null) return;
    _accepted = true;
    state = state.copyWith(phase: CallPhase.connecting);
    try {
      await ref.read(pguardApiProvider).put('/calls/$_callId/accept');
    } on ApiException catch (e) {
      // A 4xx means the call is already terminal (ended/rejected/missed) — don't negotiate against
      // a dead call. A transient/network error: proceed (the server may already be `accepted`).
      if (e.statusCode != null && e.statusCode! >= 400 && e.statusCode! < 500) {
        _end(reason: 'accept_failed');
        return;
      }
    } catch (_) {
      // Transient — proceed with the media path.
    }
    await _maybeAnswer();
  }

  /// Callee rejects a ringing call → `PUT /calls/{id}/reject` + a `bye` + teardown.
  Future<void> reject() async {
    final id = _callId;
    if (id == null) {
      _end(reason: 'rejected');
      return;
    }
    _sendSignal(CallSignal
        .bye()); // notify the peer immediately (before the REST round-trip)
    try {
      await ref.read(pguardApiProvider).put('/calls/$id/reject');
    } catch (_) {}
    _end(reason: 'rejected');
  }

  /// Either party ends the call → `PUT /calls/{id}/end` + a `bye` + teardown.
  Future<void> end() async {
    final id = _callId;
    if (id != null) {
      _sendSignal(CallSignal
          .bye()); // notify the peer immediately (before the REST round-trip)
      try {
        await ref.read(pguardApiProvider).put('/calls/$id/end');
      } catch (_) {}
    }
    _end(reason: 'hangup');
  }

  /// Return the (keepAlive) singleton to `idle` once a call has finished, so a NEW call can start
  /// cleanly. Called when the call screen is disposed after a terminal (`ended`) call. WITHOUT
  /// this the singleton lingers in `ended`: the next `/call` route briefly renders the stale
  /// call-ended summary, and a pending auto-dismiss `pop()` from the previous call can dismiss the
  /// next call's screen. Guarded on `ended` ONLY so it can never tear down a LIVE call (preserving
  /// the single-active-call invariant). Idempotent — a no-op when already idle or mid-call.
  void reset() {
    if (state.phase != CallPhase.ended) return;
    _resetSession();
    state = CallState.idle;
  }

  /// A `call_cancelled` push arrived — the caller hung up BEFORE we answered. Clear the incoming
  /// ring for THIS call (treated as a remote end → the screen shows the ended summary + auto-pops).
  /// No-op unless we are actually ringing for this exact call_id, so a stale/duplicate signal — or
  /// one for another call — can never tear down a live or unrelated call. This is the fallback for
  /// when the WS `bye` was missed (the callee's socket wasn't registered yet when the caller left).
  void dismissIncoming(String callId) {
    if (state.phase != CallPhase.incoming || _callId != callId) return;
    _end(reason: 'cancelled');
  }

  // ---------------------------------------------------------------------------
  // In-call controls
  // ---------------------------------------------------------------------------

  Future<void> toggleMute() async {
    final muted = !state.muted;
    await _engine?.setMuted(muted);
    state = state.copyWith(muted: muted);
  }

  Future<void> toggleSpeaker() async {
    final on = !state.speakerOn;
    await _engine?.setSpeaker(on);
    state = state.copyWith(speakerOn: on);
  }

  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }

  // ---------------------------------------------------------------------------
  // Session wiring
  // ---------------------------------------------------------------------------

  Future<void> _setupSession({required bool video}) async {
    final api = ref.read(pguardApiProvider);

    final feed =
        ref.read(callSignalFeedBuilderProvider)(() => api.validAccessToken());
    _feed = feed;
    _signalSub = feed.signals.listen(_onSignal);
    await feed.connect();

    // Fetch the ICE list the calling service serves (public STUN + short-lived, per-caller TURN
    // credentials) — never hard-coded in the client. A failed fetch throws and fails call setup
    // (handled by the start* entry points); we don't silently fall back to a baked-in STUN.
    final ice = await api.get('/calls/ice') as Map<String, dynamic>;
    final iceServers = (ice['ice_servers'] as List<dynamic>)
        .map((e) => IceServer.fromJson(e as Map<String, dynamic>))
        .toList();

    final engine = ref.read(callEngineFactoryProvider)();
    _engine = engine;
    // may throw CallException (permission denied)
    await engine.initialize(video: video, iceServers: iceServers);
    _localCandSub = engine.onLocalCandidate.listen(_onLocalCandidate);
    _mediaSub = engine.onMediaEvent.listen(_onMediaEvent);
    _remoteSub = engine.onRemoteStreamChanged.listen((_) {
      if (state.phase == CallPhase.ended) return;
      state = state.copyWith(
        remoteVideoActive:
            engine.remoteStream != null && state.callType.isVideo,
      );
    });

    // One-shot: end the call if it never reaches `active` (callee never answers / media never
    // connects) so the dialing/connecting screen can't hang. Cancelled on `active` + teardown.
    _connectTimeout = Timer(_connectTimeoutDuration, () async {
      if (state.phase == CallPhase.active || state.phase == CallPhase.ended) {
        return;
      }
      // Tell the SERVER the dial timed out so the call row advances initiated→missed. WITHOUT this
      // (the old local-only `_end`) the row lingers 'initiated' forever, and a later tap on the
      // stale "incoming call" notification GETs a non-terminal call and re-opens the ringing screen
      // for a call that is long over. Mirror end()'s server hit; keep the local 'no_answer' state.
      final id = _callId;
      if (id != null) {
        _sendSignal(CallSignal.bye());
        try {
          await ref.read(pguardApiProvider).put('/calls/$id/end');
        } catch (_) {}
      }
      _end(reason: 'no_answer');
    });
  }

  // ---------------------------------------------------------------------------
  // Signal routing (relay frames; filtered by call id)
  // ---------------------------------------------------------------------------

  void _onSignal(CallSignalFrame frame) {
    if (_tornDown || frame.callId != _callId) return; // not our call
    switch (frame.signal.kind) {
      case CallSignalKind.ready:
        // The callee is on the relay: the caller re-sends its offer AND flushes the local ICE it
        // buffered while the callee was still offline (the relay has no store-and-forward).
        _onPeerReady();
      case CallSignalKind.offer:
        unawaited(_onRemoteOffer(frame.signal).catchError(_onSignalError));
      case CallSignalKind.answer:
        unawaited(_onRemoteAnswer(frame.signal).catchError(_onSignalError));
      case CallSignalKind.candidate:
        _onRemoteCandidate(frame.signal);
      case CallSignalKind.bye:
        _end(reason: 'remote_hangup');
    }
  }

  // A fire-and-forget SDP handler threw (e.g. bad SDP / engine disposed mid-flight) — log it
  // (no PII) instead of letting it reach the zone's unhandled-error handler.
  void _onSignalError(Object error, StackTrace _) =>
      debugPrint('call signal handling failed: $error');

  /// The peer is now on the relay: (re)send the caller's offer and flush any local ICE candidates
  /// that were gathered + buffered before the peer joined (the relay drops anything sent earlier).
  void _onPeerReady() {
    _peerReady = true;
    _resendOffer();
    _flushLocalIce();
  }

  void _resendOffer() {
    final offer = _localOffer;
    if (state.isCaller && offer != null) {
      _sendSignal(CallSignal.offer(offer.sdp));
    }
  }

  /// A local ICE candidate fired: relay it if the peer is already on the room, else QUEUE it until
  /// the peer signals `ready` (the relay has no store-and-forward — see [_localIceQueue]).
  void _onLocalCandidate(SignalCandidate c) {
    if (_peerReady) {
      _sendLocalCandidate(c);
    } else {
      _localIceQueue.add(c);
    }
  }

  void _flushLocalIce() {
    if (_localIceQueue.isEmpty) return;
    for (final c in _localIceQueue) {
      _sendLocalCandidate(c);
    }
    _localIceQueue.clear();
  }

  void _sendLocalCandidate(SignalCandidate c) => _sendSignal(
        CallSignal.candidate(
          candidate: c.candidate,
          sdpMid: c.sdpMid,
          sdpMLineIndex: c.sdpMLineIndex,
        ),
      );

  Future<void> _onRemoteOffer(CallSignal signal) async {
    final sdp = signal.sdp;
    if (sdp == null) return;
    _pendingOffer = SignalDescription(type: 'offer', sdp: sdp);
    await _maybeAnswer();
  }

  /// Callee: once accepted AND the offer is in, set remote → flush queued ICE → answer.
  Future<void> _maybeAnswer() async {
    // `_maybeAnswering` is set SYNCHRONOUSLY so a second entry — a duplicate offer arriving while
    // the first invocation is suspended at an `await`, before `_remoteSet` flips — is rejected.
    // Otherwise the peer connection would get two setRemoteDescription calls + two answers.
    if (_maybeAnswering ||
        !_accepted ||
        _pendingOffer == null ||
        _engine == null ||
        _remoteSet) {
      return;
    }
    _maybeAnswering = true;
    try {
      await _engine!.setRemoteDescription(_pendingOffer!);
      _remoteSet = true;
      await _flushIce();
      final answer = await _engine!.createAnswer();
      _sendSignal(CallSignal.answer(answer.sdp));
    } finally {
      _maybeAnswering = false;
    }
  }

  Future<void> _onRemoteAnswer(CallSignal signal) async {
    final sdp = signal.sdp;
    if (sdp == null || _engine == null || _remoteSet) return;
    await _engine!
        .setRemoteDescription(SignalDescription(type: 'answer', sdp: sdp));
    _remoteSet = true;
    await _flushIce();
    // Caller now traverses `connecting` (matching the callee) until media reports `connected` —
    // so the failed/closed handler covers the caller too.
    if (state.phase == CallPhase.dialing) {
      state = state.copyWith(phase: CallPhase.connecting);
    }
  }

  /// Trickle ICE: apply now if the remote description is set, else QUEUE until it is.
  void _onRemoteCandidate(CallSignal signal) {
    final candidate = signal.candidate;
    if (candidate == null) return;
    final c = SignalCandidate(
      candidate: candidate,
      sdpMid: signal.sdpMid,
      sdpMLineIndex: signal.sdpMLineIndex,
    );
    if (_remoteSet && _engine != null) {
      unawaited(_engine!.addIceCandidate(c));
    } else {
      _iceQueue.add(c);
    }
  }

  Future<void> _flushIce() async {
    for (final c in _iceQueue) {
      await _engine?.addIceCandidate(c);
    }
    _iceQueue.clear();
  }

  Future<void> _onMediaEvent(CallMediaEvent event) async {
    switch (event) {
      case CallMediaEvent.connected:
        if (state.phase != CallPhase.active && state.phase != CallPhase.ended) {
          _connectTimeout?.cancel();
          // Only the CALLEE reports accepted→connected (it owns that server transition); the caller
          // flips its phase locally — avoids a guaranteed cross-participant 409 + an
          // initiated→connected race.
          final id = _callId;
          if (id != null && !state.isCaller) {
            try {
              await ref.read(pguardApiProvider).put('/calls/$id/connected');
            } catch (_) {}
          }
          state = state.copyWith(phase: CallPhase.active);
        }
      case CallMediaEvent.failed:
      case CallMediaEvent.closed:
        // Terminal in ANY live phase (dialing/incoming/connecting/active): the caller doesn't
        // enter `connecting` until the answer, so guarding on connecting/active alone would strand
        // a dialing caller when media fails.
        if (state.phase != CallPhase.idle && state.phase != CallPhase.ended) {
          _end(reason: 'media_${event.name}');
        }
      case CallMediaEvent.connecting:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Teardown
  // ---------------------------------------------------------------------------

  void _sendSignal(CallSignal signal) {
    final id = _callId;
    if (id != null) _feed?.send(callId: id, signal: signal);
  }

  void _fail(String message) {
    state = state.copyWith(
        phase: CallPhase.ended, error: message, endReason: 'error');
    _teardown();
  }

  void _end({String? reason}) {
    if (state.phase != CallPhase.ended) {
      state = state.copyWith(phase: CallPhase.ended, endReason: reason);
    }
    // The chat call-summary line is emitted SERVER-SIDE now (chat consumes `calling.ended`), so the
    // mobile no longer posts a `system` chat frame on end — it only renders the server's line (see
    // [CallSummary.tryParseContent] + ChatBubble). One row per call, with the server-derived outcome.
    _teardown();
  }

  /// Close the socket + peer connection and release all tracks (idempotent).
  void _teardown() {
    if (_tornDown) return;
    _tornDown = true;
    _connectTimeout?.cancel();
    _localCandSub?.cancel();
    _mediaSub?.cancel();
    _remoteSub?.cancel();
    _signalSub?.cancel();
    _feed?.close();
    _engine?.dispose();
  }

  /// Reset for a fresh call after a previous one ended (the singleton is reused app-wide).
  void _resetSession() {
    _teardown();
    _tornDown = false;
    _iceQueue.clear();
    _localIceQueue.clear();
    _peerReady = false;
    _remoteSet = false;
    _maybeAnswering = false;
    _accepted = false;
    _pendingOffer = null;
    _localOffer = null;
    _callId = null;
    _connectTimeout = null;
    _localCandSub = null;
    _mediaSub = null;
    _remoteSub = null;
    _signalSub = null;
    _feed = null;
    _engine = null;
  }
}
