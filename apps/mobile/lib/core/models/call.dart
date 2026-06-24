// Calling domain models — mirror `contracts/openapi/calling.yaml` (+ the `/ws/call` signaling
// frames in its description). PURE (no Flutter / no flutter_webrtc) so the call-state machine,
// the signal envelope, and parsing are unit-testable without the platform plugin.

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

/// How a call finished, for the chat-thread summary line (WhatsApp-style). Derived from the
/// caller's local end flow: whether media ever connected + the `endReason` the controller set.
///  - [completed]: the call connected and then ended → show a duration ("2:34").
///  - [missed]: never connected because the callee didn't answer (timeout / cancelled dial).
///  - [rejected]: the callee actively declined.
///  - [failed]: a media/setup error ended it before it connected.
enum CallOutcome { completed, missed, rejected, failed }

/// PURE builder for the one-line call summary posted into the booking chat thread when a call
/// ends (a `system` chat message — rendered centred). No Flutter / no IO so it is unit-testable.
///
/// The line is `<emoji> <call-kind> · <detail>`, mirroring the design's WhatsApp-style row, e.g.
/// "📞 สายเสียง · 2:34" (completed audio) or "📹 วิดีโอคอล · ไม่ได้รับสาย" (missed video). Only the
/// CALLER posts (it alone knows the outcome+duration reliably and posting from both parties would
/// double the row); the chat backend renders the resulting `system` message centred regardless of
/// the server-derived `sender_role`.
class CallSummary {
  const CallSummary._();

  /// Map the controller's local end bookkeeping to a [CallOutcome]. [wentActive] is true once the
  /// call reached `active` (media connected). [endReason] is the controller's reason string
  /// (`rejected`, `no_answer`, `media_failed`, `error`, `hangup`, `remote_hangup`, …).
  static CallOutcome outcomeFrom({
    required bool wentActive,
    required String? endReason,
  }) {
    if (wentActive) return CallOutcome.completed;
    switch (endReason) {
      case 'rejected':
        return CallOutcome.rejected;
      case 'error':
      case 'media_failed':
      case 'media_closed':
        return CallOutcome.failed;
      default:
        // no_answer / hangup (caller cancelled the dial) / remote_hangup before connect → missed.
        return CallOutcome.missed;
    }
  }

  /// `M:SS` (e.g. `2:34`, `0:09`) for a completed call's duration. Negative/absent → `0:00`.
  static String formatDuration(int? seconds) {
    final s = (seconds == null || seconds < 0) ? 0 : seconds;
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  /// The chat-thread line for a finished call. [durationSeconds] is used only for [CallOutcome.completed].
  static String line({
    required CallType type,
    required CallOutcome outcome,
    required bool thai,
    int? durationSeconds,
  }) {
    final emoji = type.isVideo ? '📹' : '📞';
    final kind = type.isVideo
        ? (thai ? 'วิดีโอคอล' : 'Video call')
        : (thai ? 'สายเสียง' : 'Voice call');
    final detail = switch (outcome) {
      CallOutcome.completed => formatDuration(durationSeconds),
      CallOutcome.missed => thai ? 'ไม่ได้รับสาย' : 'Missed call',
      CallOutcome.rejected => thai ? 'ปฏิเสธสาย' : 'Declined',
      CallOutcome.failed => thai ? 'สายขัดข้อง' : 'Call failed',
    };
    return '$emoji $kind · $detail';
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
