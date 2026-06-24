import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/call_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/models/call.dart';
import 'widgets/call_visuals.dart';

/// The full-screen call UI. It renders by [CallState.phase] (dialing / incoming / connecting /
/// active / ended) and owns ONLY the `RTCVideoRenderer` view objects (for video) plus the
/// presentation-only "when did we connect" timestamp for the duration display. ALL call +
/// WebRTC lifecycle lives in [CallController]; this screen binds renderers to the controller's
/// engine streams and forwards control taps. No `Timer.periodic` (the duration readout is a
/// frame `Ticker` that only repaints when the displayed second changes — [CallElapsedClock]).
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, this.incomingCallId, this.incomingCallType});

  /// When set, this is an INCOMING call (the id arrived via a notification/push) — the screen
  /// drives [CallController.startIncoming] on first frame. For OUTGOING the entry button has
  /// already called [CallController.startOutgoing] before navigating here.
  final String? incomingCallId;

  /// The push's `call_type` (when it carried one): a HINT so the ring UI shows the video indicator
  /// immediately, before `GET /calls/{id}` resolves the authoritative type. `null` → no hint.
  final CallType? incomingCallType;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  bool _initializingRenderers = false;

  /// Wall-clock moment the call reached `active` (drives the MM:SS readout). Presentation
  /// state only — the business state machine stays in [CallController].
  DateTime? _connectedAt;
  bool _wasActive = false;
  Duration? _finalElapsed;

  /// The keepAlive call singleton's notifier, captured in [initState] so [dispose] can reset it
  /// WITHOUT touching `ref` (Riverpod forbids using `ref` after the element is disposed). Same
  /// pattern the guard screens use to call their controllers from dispose.
  late final CallController _callController;

  @override
  void initState() {
    super.initState();
    _callController = ref.read(callControllerProvider.notifier);
    final incoming = widget.incomingCallId;
    if (incoming != null) {
      final typeHint = widget.incomingCallType;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _callController.startIncoming(callId: incoming, typeHint: typeHint);
      });
    }
  }

  @override
  void dispose() {
    _localRenderer?.dispose();
    _remoteRenderer?.dispose();
    // Return the keepAlive call singleton to `idle` once this (terminal) call screen goes away, so
    // the NEXT call starts from a clean slate — without this the singleton lingers in `ended` and
    // the user "can't call again immediately" (the next /call route renders the stale call-ended
    // summary / a pending auto-dismiss pop can swallow it). `reset()` is a no-op for a LIVE call,
    // so this never tears down an in-progress call (e.g. a transient widget rebuild). DEFER to a
    // microtask: changing the keepAlive provider's state synchronously here notifies listeners
    // while THIS element is mid-dispose (a `markNeedsBuild during dispose` assertion on the reject
    // path). By the time the microtask runs the screen is fully unmounted, so the reset is safe.
    // `reset()` is captured (no `ref`) + a no-op unless the call is terminal, so a brand-new call
    // started before it runs is left untouched.
    Future.microtask(_callController.reset);
    super.dispose();
  }

  Future<void> _ensureRenderers() async {
    if (_initializingRenderers || _localRenderer != null) return;
    _initializingRenderers = true;
    final local = RTCVideoRenderer();
    final remote = RTCVideoRenderer();
    await local.initialize();
    await remote.initialize();
    if (!mounted) {
      await local.dispose();
      await remote.dispose();
      return;
    }
    setState(() {
      _localRenderer = local;
      _remoteRenderer = remote;
    });
  }

  void _bindStreams() {
    final engine = ref.read(callControllerProvider.notifier).engine;
    _localRenderer?.srcObject = engine?.localStream as MediaStream?;
    _remoteRenderer?.srcObject = engine?.remoteStream as MediaStream?;
  }

  // End/reject are fire-and-forget: navigation is centralised in [_onCallStateChanged] (the
  // controller transitions to `ended`, which auto-pops when the call never connected) so a
  // REMOTE decline dismisses the screen too.
  void _end() => ref.read(callControllerProvider.notifier).end();
  void _reject() => ref.read(callControllerProvider.notifier).reject();

  /// React to controller state changes: renderer sync for video + ended-flow bookkeeping.
  /// Lives in a single `ref.listen` (NOT in build) so we don't register a fresh `.then`
  /// continuation / double-bind on every rebuild.
  void _onCallStateChanged(CallState? prev, CallState next) {
    if (next.callType.isVideo &&
        (next.phase == CallPhase.connecting || next.phase == CallPhase.active)) {
      _ensureRenderers().then((_) {
        if (mounted) _bindStreams();
      });
    } else if (_localRenderer != null) {
      _bindStreams();
    }
    // A fresh call started from this screen (e.g. "Call again" on the summary) — reset the
    // presentation clock.
    if ((next.phase == CallPhase.dialing || next.phase == CallPhase.incoming) &&
        prev?.phase != next.phase) {
      _connectedAt = null;
      _wasActive = false;
      _finalElapsed = null;
    }
    if (next.phase == CallPhase.active && prev?.phase != CallPhase.active) {
      _connectedAt ??= DateTime.now();
      _wasActive = true;
    }
    if (next.phase == CallPhase.ended && prev?.phase != CallPhase.ended) {
      final at = _connectedAt;
      if (_wasActive && at != null) {
        _finalElapsed = DateTime.now().difference(at);
      }
      // Auto-dismiss ONLY when the call ended cleanly WITHOUT ever connecting (cancelled dial,
      // declined, missed). A completed conversation shows the call-ended summary; an error end
      // keeps the summary so the user can read the reason.
      if (!_wasActive && next.error == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Re-check the controller is STILL on this ended call before popping: a fresh call may
          // have started in the same frame (the keepAlive singleton is reused), in which case this
          // pop would wrongly dismiss the NEW call's screen.
          if (mounted &&
              ref.read(callControllerProvider).phase == CallPhase.ended) {
            context.pop();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callControllerProvider);
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final notifier = ref.read(callControllerProvider.notifier);
    // The PEER is the opposite of the local session role: a guard talks to a customer and
    // vice-versa (v2 call models carry no peer profile).
    final peerIsCustomer = ref.watch(sessionProvider).user?.isGuard ?? false;

    ref.listen(callControllerProvider, _onCallStateChanged);

    if (call.phase == CallPhase.active && _connectedAt == null) {
      _connectedAt = DateTime.now(); // screen (re)built mid-call
      _wasActive = true;
    }

    final ended = call.phase == CallPhase.ended;
    return Scaffold(
      backgroundColor: ended ? PgTokens.colorSurface : PgTokens.colorBrand,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!ended)
            CallBackground(
              showGrid: call.phase == CallPhase.idle ||
                  call.phase == CallPhase.dialing ||
                  call.phase == CallPhase.incoming,
            ),
          SafeArea(
            child: switch (call.phase) {
              CallPhase.idle => const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
              CallPhase.dialing => _RingingView(
                  isThai: isThai,
                  call: call,
                  peerIsCustomer: peerIsCustomer,
                  onToggleMute: notifier.toggleMute,
                  onCancel: _end,
                ),
              CallPhase.incoming => _IncomingView(
                  isThai: isThai,
                  call: call,
                  peerIsCustomer: peerIsCustomer,
                  onAccept: notifier.accept,
                  onReject: _reject,
                ),
              CallPhase.connecting || CallPhase.active => _InCallView(
                  isThai: isThai,
                  call: call,
                  connectedAt: _connectedAt,
                  localRenderer: _localRenderer,
                  remoteRenderer: _remoteRenderer,
                  onToggleMute: notifier.toggleMute,
                  onToggleSpeaker: notifier.toggleSpeaker,
                  onSwitchCamera: notifier.switchCamera,
                  onEnd: _end,
                ),
              CallPhase.ended => _EndedView(
                  isThai: isThai,
                  call: call,
                  elapsed: _finalElapsed,
                  onCallAgain: () {
                    final bookingId = call.call?.bookingId;
                    if (bookingId == null || bookingId.isEmpty) return null;
                    return () => notifier.startOutgoing(
                        bookingId: bookingId, type: call.callType);
                  }(),
                ),
            },
          ),
        ],
      ),
    );
  }
}

String _peerLabel(bool isThai) => isThai ? 'คู่สนทนา' : 'Contact';

class _RingingView extends StatelessWidget {
  const _RingingView({
    required this.isThai,
    required this.call,
    required this.peerIsCustomer,
    required this.onToggleMute,
    required this.onCancel,
  });

  final bool isThai;
  final CallState call;
  final bool peerIsCustomer;
  final VoidCallback onToggleMute;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        const CallAvatar(),
        const SizedBox(height: PgTokens.space6),
        Text(_peerLabel(isThai),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: PgTokens.space2),
        CallRolePill(isThai: isThai, customer: peerIsCustomer),
        const SizedBox(height: PgTokens.space3),
        if (call.callType.isVideo) ...[
          CallTypeBadge(
            isThai: isThai,
            label: isThai ? 'วิดีโอคอล' : 'Video call',
          ),
          const SizedBox(height: PgTokens.space2),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: PgTokens.space2),
            Text(
              call.callType.isVideo
                  ? (isThai ? 'วิดีโอคอล…' : 'Video call…')
                  : (isThai ? 'กำลังเรียก…' : 'Calling…'),
              style: callStatusStyle(),
            ),
          ],
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 50),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CallLabeledButton(
                icon: call.muted ? Icons.mic_off : Icons.mic,
                label: isThai ? 'ปิดเสียง' : 'Mute',
                color: call.muted ? Colors.white : null,
                foreground: call.muted ? PgTokens.colorBrand : Colors.white,
                onPressed: onToggleMute,
              ),
              const SizedBox(width: 22),
              CallLabeledButton(
                icon: Icons.call_end,
                label: isThai ? 'วางสาย' : 'End',
                color: PgTokens.colorDanger,
                onPressed: onCancel,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IncomingView extends StatelessWidget {
  const _IncomingView({
    required this.isThai,
    required this.call,
    required this.peerIsCustomer,
    required this.onAccept,
    required this.onReject,
  });

  final bool isThai;
  final CallState call;
  final bool peerIsCustomer;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        const CallAvatar(),
        const SizedBox(height: PgTokens.space6),
        Text(_peerLabel(isThai),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: PgTokens.space2),
        CallRolePill(isThai: isThai, customer: peerIsCustomer),
        const SizedBox(height: PgTokens.space3),
        if (call.callType.isVideo) ...[
          CallTypeBadge(
            isThai: isThai,
            label: isThai ? 'สายวิดีโอ' : 'Video',
          ),
          const SizedBox(height: PgTokens.space2),
        ],
        Text(
          call.callType.isVideo
              ? (isThai ? 'สายวิดีโอเรียกเข้า · pguard' : 'Incoming video call · pguard')
              : (isThai ? 'สายเรียกเข้า · pguard' : 'Incoming call · pguard'),
          style: callStatusStyle(),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(left: 50, right: 50, bottom: 54),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CallLabeledButton(
                icon: Icons.call_end,
                label: isThai ? 'ปฏิเสธ' : 'Decline',
                color: PgTokens.colorDanger,
                size: 70,
                onPressed: onReject,
              ),
              CallLabeledButton(
                icon: Icons.call,
                label: isThai ? 'รับสาย' : 'Accept',
                color: PgTokens.colorPrimary,
                size: 70,
                onPressed: onAccept,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InCallView extends StatelessWidget {
  const _InCallView({
    required this.isThai,
    required this.call,
    required this.connectedAt,
    required this.localRenderer,
    required this.remoteRenderer,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onSwitchCamera,
    required this.onEnd,
  });

  final bool isThai;
  final CallState call;
  final DateTime? connectedAt;
  final RTCVideoRenderer? localRenderer;
  final RTCVideoRenderer? remoteRenderer;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onSwitchCamera;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final showRemoteVideo = call.callType.isVideo &&
        call.remoteVideoActive &&
        remoteRenderer != null;
    final connecting = call.phase == CallPhase.connecting;
    final active = call.phase == CallPhase.active;
    final since = connectedAt;

    return Stack(
      children: [
        // Remote video fills the screen (video calls); audio shows the avatar placeholder.
        Positioned.fill(
          child: showRemoteVideo
              ? RTCVideoView(remoteRenderer!,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CallAvatar(size: 130, ripple: false),
                      if (connecting) ...[
                        const SizedBox(height: PgTokens.space4),
                        Text(isThai ? 'กำลังเชื่อมต่อ…' : 'Connecting…',
                            style: callStatusStyle()),
                      ],
                    ],
                  ),
                ),
        ),
        // Floating top header: peer name + live MM:SS duration.
        Positioned(
          top: PgTokens.space4,
          left: PgTokens.space4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_peerLabel(isThai),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              if (active && since != null) ...[
                const SizedBox(height: PgTokens.space1),
                CallElapsedClock(since: since),
              ],
            ],
          ),
        ),
        // Local self-view PiP (video calls).
        if (call.callType.isVideo && localRenderer != null)
          Positioned(
            top: 64,
            right: PgTokens.space4,
            width: 96,
            height: 130,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PgTokens.radiusXl),
                border: Border.all(
                    color: Colors.white.withValues(alpha: .25), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .35),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(PgTokens.radiusXl - 2),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Cover (crop, not letterbox) so the front-camera self-view FILLS the small
                    // PiP frame — no grey gaps. mirror:true keeps the natural selfie orientation.
                    RTCVideoView(localRenderer!,
                        mirror: true,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                    Positioned(
                      bottom: 6,
                      left: 0,
                      right: 0,
                      child: Text(
                        isThai ? 'คุณ' : 'You',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .85),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Controls: glass rest state; an ACTIVE toggle inverts to white with green-900 icon.
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 50),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CallLabeledButton(
                  icon: call.muted ? Icons.mic_off : Icons.mic,
                  label: isThai ? 'ปิดเสียง' : 'Mute',
                  color: call.muted ? Colors.white : null,
                  foreground:
                      call.muted ? PgTokens.colorBrand : Colors.white,
                  onPressed: onToggleMute,
                ),
                const SizedBox(width: 22),
                CallLabeledButton(
                  icon: call.speakerOn ? Icons.volume_up : Icons.volume_down,
                  label: isThai ? 'ลำโพง' : 'Speaker',
                  color: call.speakerOn ? Colors.white : null,
                  foreground:
                      call.speakerOn ? PgTokens.colorBrand : Colors.white,
                  onPressed: onToggleSpeaker,
                ),
                if (call.callType.isVideo) ...[
                  const SizedBox(width: 22),
                  CallLabeledButton(
                    icon: Icons.cameraswitch,
                    label: isThai ? 'สลับกล้อง' : 'Flip',
                    onPressed: onSwitchCamera,
                  ),
                ],
                const SizedBox(width: 22),
                CallLabeledButton(
                  icon: Icons.call_end,
                  label: isThai ? 'วางสาย' : 'End',
                  color: PgTokens.colorDanger,
                  onPressed: onEnd,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The light call-ended summary: icon circle + avatar + duration line + "call again" /
/// "back to chat" CTAs (design state 4).
class _EndedView extends StatelessWidget {
  const _EndedView({
    required this.isThai,
    required this.call,
    required this.elapsed,
    required this.onCallAgain,
  });

  final bool isThai;
  final CallState call;
  final Duration? elapsed;
  final VoidCallback? onCallAgain;

  String _durationLine() {
    final secs = call.call?.durationSeconds ?? elapsed?.inSeconds;
    final ended = isThai ? 'การโทรสิ้นสุด' : 'Call ended';
    if (secs == null) return ended;
    final m = secs ~/ 60;
    final s = secs % 60;
    final duration = isThai
        ? (m > 0 ? '$m นาที $s วินาที' : '$s วินาที')
        : (m > 0 ? '$m min $s sec' : '$s sec');
    return '$ended · $duration';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(PgTokens.space6),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: PgTokens.colorSunken,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.call_end,
                size: 40, color: PgTokens.colorTextMuted),
          ),
          const SizedBox(height: PgTokens.space6),
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: PgTokens.colorGreen100,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person,
                size: 32, color: PgTokens.colorGreen800),
          ),
          const SizedBox(height: PgTokens.space3),
          Text(
            _peerLabel(isThai),
            style: const TextStyle(
              color: PgTokens.colorText,
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: PgTokens.space2),
          Text(
            call.error ?? _durationLine(),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: PgTokens.colorTextMuted, fontSize: 14),
          ),
          const Spacer(),
          if (onCallAgain != null) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCallAgain,
                style: FilledButton.styleFrom(
                  backgroundColor: PgTokens.colorPrimary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PgTokens.radiusXl),
                  ),
                ),
                icon: const Icon(Icons.call, size: 18),
                label: Text(isThai ? 'โทรอีกครั้ง' : 'Call again'),
              ),
            ),
            const SizedBox(height: PgTokens.space3),
          ],
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => context.pop(),
              style: TextButton.styleFrom(
                foregroundColor: PgTokens.colorPrimary,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text(isThai ? 'กลับไปแชต' : 'Back to chat'),
            ),
          ),
        ],
      ),
    );
  }
}
