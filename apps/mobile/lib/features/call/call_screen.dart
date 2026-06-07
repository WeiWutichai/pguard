import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/call_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/call.dart';
import 'widgets/call_controls.dart';

/// The full-screen call UI. It renders by [CallState.phase] (dialing / incoming / connecting /
/// active / ended) and owns ONLY the `RTCVideoRenderer` view objects (for video). ALL call +
/// WebRTC lifecycle lives in [CallController]; this screen binds renderers to the controller's
/// engine streams and forwards control taps. No `Timer.periodic`.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, this.incomingCallId});

  /// When set, this is an INCOMING call (the id arrived via a notification/push) — the screen
  /// drives [CallController.startIncoming] on first frame. For OUTGOING the entry button has
  /// already called [CallController.startOutgoing] before navigating here.
  final String? incomingCallId;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  bool _initializingRenderers = false;

  @override
  void initState() {
    super.initState();
    final incoming = widget.incomingCallId;
    if (incoming != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(callControllerProvider.notifier).startIncoming(callId: incoming);
      });
    }
  }

  @override
  void dispose() {
    _localRenderer?.dispose();
    _remoteRenderer?.dispose();
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
  // controller transitions to `ended`, which auto-pops) so a REMOTE hangup dismisses the screen too.
  void _end() => ref.read(callControllerProvider.notifier).end();
  void _reject() => ref.read(callControllerProvider.notifier).reject();

  /// React to controller state changes: renderer sync for video + auto-dismiss on a clean end.
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
    // Auto-dismiss when a call ENDS cleanly (hangup by either side). An error end keeps the
    // _EndedView so the user can read the reason and close it manually.
    if (next.phase == CallPhase.ended &&
        prev?.phase != CallPhase.ended &&
        next.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callControllerProvider);
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final notifier = ref.read(callControllerProvider.notifier);

    ref.listen(callControllerProvider, _onCallStateChanged);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1F17), // dark call backdrop
      body: SafeArea(
        child: switch (call.phase) {
          CallPhase.idle => const Center(
              child: CircularProgressIndicator(color: Colors.white)),
          CallPhase.dialing => _RingingView(
              isThai: isThai,
              outgoing: true,
              call: call,
              onCancel: _end,
            ),
          CallPhase.incoming => _IncomingView(
              isThai: isThai,
              call: call,
              onAccept: notifier.accept,
              onReject: _reject,
            ),
          CallPhase.connecting || CallPhase.active => _InCallView(
              isThai: isThai,
              call: call,
              localRenderer: _localRenderer,
              remoteRenderer: _remoteRenderer,
              onToggleMute: notifier.toggleMute,
              onToggleSpeaker: notifier.toggleSpeaker,
              onSwitchCamera: notifier.switchCamera,
              onEnd: _end,
            ),
          CallPhase.ended => _EndedView(isThai: isThai, call: call),
        },
      ),
    );
  }
}

String _peerLabel(bool isThai) => isThai ? 'คู่สนทนา' : 'Contact';

/// A round avatar placeholder (the call models carry no name/avatar in v2).
class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: const BoxDecoration(
        color: PgTokens.colorGreen800,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person, size: 53, color: Colors.white),
    );
  }
}

class _RingingView extends StatelessWidget {
  const _RingingView({
    required this.isThai,
    required this.outgoing,
    required this.call,
    required this.onCancel,
  });

  final bool isThai;
  final bool outgoing;
  final CallState call;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        const _Avatar(),
        const SizedBox(height: PgTokens.space4),
        Text(_peerLabel(isThai),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: PgTokens.space2),
        Text(
          (isThai ? 'กำลังโทร' : 'Calling') +
              (call.callType.isVideo
                  ? (isThai ? ' · วิดีโอ' : ' · video')
                  : ''),
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: PgTokens.space7),
          child: CallRoundButton(
            icon: Icons.call_end,
            color: PgTokens.colorDanger,
            tooltip: isThai ? 'ยกเลิก' : 'Cancel',
            onPressed: onCancel,
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
    required this.onAccept,
    required this.onReject,
  });

  final bool isThai;
  final CallState call;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        const _Avatar(),
        const SizedBox(height: PgTokens.space4),
        Text(_peerLabel(isThai),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: PgTokens.space2),
        Text(
          (isThai ? 'สายเรียกเข้า' : 'Incoming call') +
              (call.callType.isVideo
                  ? (isThai ? ' · วิดีโอ' : ' · video')
                  : ''),
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: PgTokens.space7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CallRoundButton(
                icon: Icons.call_end,
                color: PgTokens.colorDanger,
                tooltip: isThai ? 'ปฏิเสธ' : 'Reject',
                onPressed: onReject,
              ),
              CallRoundButton(
                icon: Icons.call,
                color: PgTokens.colorPrimary,
                tooltip: isThai ? 'รับสาย' : 'Accept',
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
    required this.localRenderer,
    required this.remoteRenderer,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onSwitchCamera,
    required this.onEnd,
  });

  final bool isThai;
  final CallState call;
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

    return Stack(
      children: [
        // Remote video fills the screen (video calls); audio shows the avatar.
        Positioned.fill(
          child: showRemoteVideo
              ? RTCVideoView(remoteRenderer!,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _Avatar(),
                      const SizedBox(height: PgTokens.space4),
                      Text(_peerLabel(isThai),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: PgTokens.space2),
                      Text(
                        connecting
                            ? (isThai ? 'กำลังเชื่อมต่อ…' : 'Connecting…')
                            : (isThai ? 'กำลังสนทนา' : 'In call'),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
        ),
        // Local self-view (video calls).
        if (call.callType.isVideo && localRenderer != null)
          Positioned(
            top: PgTokens.space4,
            right: PgTokens.space4,
            width: 96,
            height: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PgTokens.radiusLg),
              child: RTCVideoView(localRenderer!, mirror: true),
            ),
          ),
        // Controls.
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: PgTokens.space7),
            child: CallControls(
              isThai: isThai,
              muted: call.muted,
              speakerOn: call.speakerOn,
              showCamera: call.callType.isVideo,
              onToggleMute: onToggleMute,
              onToggleSpeaker: onToggleSpeaker,
              onSwitchCamera: onSwitchCamera,
              onEnd: onEnd,
            ),
          ),
        ),
      ],
    );
  }
}

class _EndedView extends StatelessWidget {
  const _EndedView({required this.isThai, required this.call});

  final bool isThai;
  final CallState call;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.call_end, color: Colors.white70, size: 40),
          const SizedBox(height: PgTokens.space3),
          Text(
            call.error ?? (isThai ? 'วางสายแล้ว' : 'Call ended'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: PgTokens.space4),
          TextButton(
            onPressed: () => context.pop(),
            child: Text(isThai ? 'ปิด' : 'Close',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
