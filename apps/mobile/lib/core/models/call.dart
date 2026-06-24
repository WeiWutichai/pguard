// Calling domain models — mirror `contracts/openapi/calling.yaml` (+ the `/ws/call` signaling
// frames in its description). PURE (no Flutter / no flutter_webrtc) so the call-state machine,
// the signal envelope, and parsing are unit-testable without the platform plugin.

import 'dart:convert';

/// Audio or video call (the media kind requested at initiate).
enum CallType {
  audio('audio'),
  video('video');

  const CallType(this.wire);

  final String wire;

  bool get isVideo => this == CallType.video;

  static CallType parse(String? value) =>
      value == 'video' ? CallType.video : CallType.audio;

  /// Parse a wire value, or `null` if absent/unrecognised (the incoming-call route uses this for
  /// the optional `?type=` push hint — a missing hint is null, not a defaulted-to-audio guess).
  static CallType? tryParse(String? value) {
    for (final t in CallType.values) {
      if (t.wire == value) return t;
    }
    return null;
  }
}

/// Server-side call lifecycle status (the `status` field on [Call]).
enum CallStatus {
  initiated('initiated'),
  accepted('accepted'),
  connected('connected'),
  ended('ended'),
  rejected('rejected'),
  missed('missed');

  const CallStatus(this.wire);

  final String wire;

  bool get isTerminal =>
      this == CallStatus.ended ||
      this == CallStatus.rejected ||
      this == CallStatus.missed;

  static CallStatus parse(String? value) {
    for (final s in CallStatus.values) {
      if (s.wire == value) return s;
    }
    return CallStatus.initiated;
  }
}

/// A call as returned by the calling REST endpoints (`POST /calls/initiate`, `GET /calls/{id}`,
/// and the lifecycle PUTs). The `callee_id` is DERIVED server-side from the booking.
class Call {
  const Call({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.bookingId,
    required this.callType,
    required this.status,
    this.durationSeconds,
    this.endReason,
  });

  final String id;
  final String callerId;
  final String calleeId;
  final String bookingId;
  final CallType callType;
  final CallStatus status;
  final int? durationSeconds;
  final String? endReason;

  factory Call.fromJson(Map<String, dynamic> json) => Call(
        id: json['id'] as String,
        callerId: (json['caller_id'] as String?) ?? '',
        calleeId: (json['callee_id'] as String?) ?? '',
        bookingId: (json['booking_id'] as String?) ?? '',
        callType: CallType.parse(json['call_type'] as String?),
        status: CallStatus.parse(json['status'] as String?),
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
        endReason: json['end_reason'] as String?,
      );
}

/// How a call finished, for the chat-thread summary line (WhatsApp-style). DERIVED SERVER-SIDE now
/// (chat consumes the `calling.ended` event) and shipped to the client inside the pinned `system`
/// chat-message JSON — the mobile only RENDERS it (it no longer decides the outcome).
///  - [completed]: the call was answered → show a duration ("2:34").
///  - [missed]: never answered (callee didn't pick up / dial cancelled).
///  - [rejected]: the callee actively declined.
enum CallOutcome {
  completed('completed'),
  missed('missed'),
  rejected('rejected');

  const CallOutcome(this.wire);

  /// The `oc` value on the pinned call-summary JSON.
  final String wire;

  static CallOutcome? tryParse(String? value) {
    for (final o in CallOutcome.values) {
      if (o.wire == value) return o;
    }
    return null;
  }
}

/// PURE renderer for the SERVER-EMITTED call-summary `system` chat message. No Flutter / no IO so
/// parsing + localisation are unit-testable.
///
/// The chat service emits the call summary as a `system` message whose `content` is the pinned JSON
/// `{"k":"call","ct":"audio"|"video","oc":"completed"|"missed"|"rejected","ds":<int|null>}`. The
/// mobile [tryParseContent]s that and renders the localized WhatsApp-style line `<emoji> <kind> ·
/// <detail>`, e.g. "📞 สายเสียง · 2:34" (completed audio) or "📹 Video call · Missed call". A
/// `content` that is NOT this JSON renders verbatim (a plain system notice).
class CallSummary {
  const CallSummary._();

  /// The pinned content marker for a call-summary `system` message.
  static const String kind = 'call';

  /// Parse a `system` message's [content] as the pinned call-summary JSON, returning the call type,
  /// outcome and duration (seconds, `null` if never answered) — or `null` when [content] is not a
  /// call summary (a plain system notice / any non-JSON / a different `k`). Defensive: a malformed
  /// payload returns `null` (rendered verbatim) rather than throwing.
  static ({CallType type, CallOutcome outcome, int? durationSeconds})?
      tryParseContent(String? content) {
    if (content == null || content.isEmpty || content[0] != '{') return null;
    Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      return null; // not JSON → a plain system line
    }
    if (decoded is! Map || decoded['k'] != kind) return null;
    final outcome = CallOutcome.tryParse(decoded['oc'] as String?);
    if (outcome == null) return null; // unknown outcome → render verbatim
    return (
      type: CallType.parse(decoded['ct'] as String?),
      outcome: outcome,
      durationSeconds: (decoded['ds'] as num?)?.toInt(),
    );
  }

  /// `M:SS` (e.g. `2:34`, `0:09`) for a completed call's duration. Negative/absent → `0:00`.
  static String formatDuration(int? seconds) {
    final s = (seconds == null || seconds < 0) ? 0 : seconds;
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  /// The localized chat-thread line for a finished call. [durationSeconds] is used only for
  /// [CallOutcome.completed]. The server can send any of the three outcomes (it decides), so all
  /// three render.
  static String line({
    required CallType type,
    required CallOutcome outcome,
    required bool thai,
    int? durationSeconds,
  }) {
    final emoji = type.isVideo ? '📹' : '📞';
    final kindLabel = type.isVideo
        ? (thai ? 'วิดีโอคอล' : 'Video call')
        : (thai ? 'สายเสียง' : 'Voice call');
    final detail = switch (outcome) {
      CallOutcome.completed => formatDuration(durationSeconds),
      CallOutcome.missed => thai ? 'ไม่ได้รับสาย' : 'Missed call',
      CallOutcome.rejected => thai ? 'ปฏิเสธสาย' : 'Declined',
    };
    return '$emoji $kindLabel · $detail';
  }
}

/// The client-side UI phase of the active call (the state machine the controller drives):
/// idle → (dialing | incoming) → connecting → active → ended.
enum CallPhase {
  /// No call.
  idle,

  /// Outgoing: placed, waiting for the callee to answer (ringing on their side).
  dialing,

  /// Incoming: a call is ringing for this user (accept / reject).
  incoming,

  /// Answered; the WebRTC media is negotiating (SDP/ICE in flight).
  connecting,

  /// Media connected — talking.
  active,

  /// Finished (ended / rejected / missed / failed). Terminal.
  ended,
}

/// Immutable controller state for the call screen.
class CallState {
  const CallState({
    required this.phase,
    required this.callType,
    required this.isCaller,
    this.call,
    this.muted = false,
    this.speakerOn = false,
    this.remoteVideoActive = false,
    this.error,
    this.endReason,
  });

  final CallPhase phase;
  final CallType callType;

  /// True when this client placed the call (caller) vs received it (callee).
  final bool isCaller;
  final Call? call;
  final bool muted;
  final bool speakerOn;

  /// A remote media stream is available → the view may show the remote video.
  final bool remoteVideoActive;
  final String? error;
  final String? endReason;

  static const idle = CallState(
    phase: CallPhase.idle,
    callType: CallType.audio,
    isCaller: false,
  );

  bool get isActive => phase == CallPhase.active;
  bool get isRinging =>
      phase == CallPhase.dialing || phase == CallPhase.incoming;

  CallState copyWith({
    CallPhase? phase,
    CallType? callType,
    bool? isCaller,
    Call? call,
    bool? muted,
    bool? speakerOn,
    bool? remoteVideoActive,
    String? error,
    String? endReason,
  }) =>
      CallState(
        phase: phase ?? this.phase,
        callType: callType ?? this.callType,
        isCaller: isCaller ?? this.isCaller,
        call: call ?? this.call,
        muted: muted ?? this.muted,
        speakerOn: speakerOn ?? this.speakerOn,
        remoteVideoActive: remoteVideoActive ?? this.remoteVideoActive,
        // Preserve a set error across unrelated transitions (consistent with every other field);
        // a fresh call always starts from a new CallState, so error is never stale.
        error: error ?? this.error,
        endReason: endReason ?? this.endReason,
      );
}

/// The kind of an opaque `/ws/call` signal frame's inner payload. The relay forwards the `signal`
/// object verbatim, so both clients agree on this envelope:
///  - [ready]: the callee has opened its socket → the caller (re)sends the offer (the relay has no
///    presence/lifecycle push, so this bootstraps the SDP exchange).
///  - [offer]/[answer]: SDP (with the matching [CallSignal.sdp]).
///  - [candidate]: a trickle ICE candidate.
///  - [bye]: the peer hung up / rejected → tear down.
enum CallSignalKind {
  ready,
  offer,
  answer,
  candidate,
  bye;

  static CallSignalKind? tryParse(String? value) {
    for (final k in CallSignalKind.values) {
      if (k.name == value) return k;
    }
    return null;
  }
}

/// The inner `signal` payload of a `/ws/call` frame (`{ type:"signal", call_id, signal:<this> }`).
/// PURE + serializable so signal routing is unit-testable without a socket.
class CallSignal {
  const CallSignal({
    required this.kind,
    this.sdp,
    this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  final CallSignalKind kind;
  final String? sdp; // offer / answer
  final String? candidate; // ICE
  final String? sdpMid;
  final int? sdpMLineIndex;

  factory CallSignal.ready() => const CallSignal(kind: CallSignalKind.ready);
  factory CallSignal.offer(String sdp) =>
      CallSignal(kind: CallSignalKind.offer, sdp: sdp);
  factory CallSignal.answer(String sdp) =>
      CallSignal(kind: CallSignalKind.answer, sdp: sdp);
  factory CallSignal.bye() => const CallSignal(kind: CallSignalKind.bye);
  factory CallSignal.candidate({
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) =>
      CallSignal(
        kind: CallSignalKind.candidate,
        candidate: candidate,
        sdpMid: sdpMid,
        sdpMLineIndex: sdpMLineIndex,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (sdp != null) 'sdp': sdp,
        if (candidate != null) 'candidate': candidate,
        if (sdpMid != null) 'sdpMid': sdpMid,
        if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
      };

  /// Parse a `signal` payload, or `null` if it carries no recognised `kind`.
  static CallSignal? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = CallSignalKind.tryParse(raw['kind'] as String?);
    if (kind == null) return null;
    return CallSignal(
      kind: kind,
      sdp: raw['sdp'] as String?,
      candidate: raw['candidate'] as String?,
      sdpMid: raw['sdpMid'] as String?,
      sdpMLineIndex: (raw['sdpMLineIndex'] as num?)?.toInt(),
    );
  }
}
