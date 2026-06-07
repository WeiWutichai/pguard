import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'call_engine.dart';

/// Production [CallEngine] over `flutter_webrtc`: a P2P `RTCPeerConnection` whose SDP/ICE is
/// relayed by the controller through the calling `/ws/call` socket (no SFU client — the mediasoup
/// SFU control plane is service-JWT internal-only). Requests mic (+camera for video) up front.
///
/// NEVER constructed in unit/widget tests (the controller's engine provider is overridden with a
/// fake) — so the platform plugin is not touched under `flutter test`. Renderers stay in the view.
class WebRtcCallEngine implements CallEngine {
  RTCPeerConnection? _pc;
  MediaStream? _local;
  MediaStream? _remote;
  bool _disposed = false;

  final _localCand = StreamController<SignalCandidate>.broadcast();
  final _mediaEvent = StreamController<CallMediaEvent>.broadcast();
  final _remoteChanged = StreamController<void>.broadcast();

  /// Map the SERVED ICE list (STUN + short-lived TURN credentials from `GET /v1/calls/ice`) into
  /// the WebRTC `RTCConfiguration`. Nothing is hard-coded: the controller fetches the list per call
  /// and the relay credentials it carries are minted server-side + short-lived. TURN is what lets a
  /// call connect behind symmetric / carrier-grade NAT (common on Thai mobile networks).
  static Map<String, dynamic> _rtcConfig(List<IceServer> iceServers) => {
        'iceServers': [
          for (final s in iceServers)
            {
              'urls': s.urls,
              if (s.username != null) 'username': s.username,
              if (s.credential != null) 'credential': s.credential,
            },
        ],
        'sdpSemantics': 'unified-plan',
      };

  @override
  Stream<SignalCandidate> get onLocalCandidate => _localCand.stream;
  @override
  Stream<CallMediaEvent> get onMediaEvent => _mediaEvent.stream;
  @override
  Stream<void> get onRemoteStreamChanged => _remoteChanged.stream;
  @override
  Object? get localStream => _local;
  @override
  Object? get remoteStream => _remote;

  @override
  Future<void> initialize({
    required bool video,
    required List<IceServer> iceServers,
  }) async {
    // Permissions FIRST (Android + iOS) — a denied mic/camera is a friendly, generic failure.
    if (!await Permission.microphone.request().isGranted) {
      throw const CallException('Microphone permission is required for calls');
    }
    if (video && !await Permission.camera.request().isGranted) {
      throw const CallException('Camera permission is required for video calls');
    }

    try {
      _local = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': video ? {'facingMode': 'user'} : false,
      });
    } catch (_) {
      throw const CallException('Could not access the microphone/camera');
    }

    final pc = await createPeerConnection(_rtcConfig(iceServers));
    _pc = pc;
    pc.onIceCandidate = (candidate) {
      final c = candidate.candidate;
      if (c != null && !_localCand.isClosed) {
        _localCand.add(SignalCandidate(
          candidate: c,
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
        ));
      }
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remote = event.streams.first;
        if (!_remoteChanged.isClosed) _remoteChanged.add(null);
      }
    };
    pc.onConnectionState = (s) {
      if (_mediaEvent.isClosed) return;
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _mediaEvent.add(CallMediaEvent.connected);
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          _mediaEvent.add(CallMediaEvent.connecting);
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _mediaEvent.add(CallMediaEvent.failed);
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _mediaEvent.add(CallMediaEvent.closed);
        default:
          break;
      }
    };

    for (final track in _local!.getTracks()) {
      await pc.addTrack(track, _local!);
    }
  }

  @override
  Future<SignalDescription> createOffer() async {
    final pc = _requirePc();
    final offer = await pc.createOffer({});
    await pc.setLocalDescription(offer);
    return SignalDescription(type: offer.type ?? 'offer', sdp: offer.sdp ?? '');
  }

  @override
  Future<SignalDescription> createAnswer() async {
    final pc = _requirePc();
    final answer = await pc.createAnswer({});
    await pc.setLocalDescription(answer);
    return SignalDescription(type: answer.type ?? 'answer', sdp: answer.sdp ?? '');
  }

  @override
  Future<void> setRemoteDescription(SignalDescription description) async {
    await _requirePc().setRemoteDescription(
      RTCSessionDescription(description.sdp, description.type),
    );
  }

  @override
  Future<void> addIceCandidate(SignalCandidate candidate) async {
    await _requirePc().addCandidate(RTCIceCandidate(
      candidate.candidate,
      candidate.sdpMid,
      candidate.sdpMLineIndex,
    ));
  }

  @override
  Future<void> setMuted(bool muted) async {
    for (final track in _local?.getAudioTracks() ?? const []) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> setSpeaker(bool on) async {
    await Helper.setSpeakerphoneOn(on);
  }

  @override
  Future<void> switchCamera() async {
    final tracks = _local?.getVideoTracks() ?? const [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  RTCPeerConnection _requirePc() {
    final pc = _pc;
    if (pc == null) throw const CallException('Call media is not initialised');
    return pc;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Close the stream controllers FIRST so a late onIceCandidate/onTrack/onConnectionState
    // callback (fired between pc.close() and here) has nowhere to add — then tear down the pc.
    await _localCand.close();
    await _mediaEvent.close();
    await _remoteChanged.close();
    for (final track in _local?.getTracks() ?? const []) {
      await track.stop();
    }
    await _local?.dispose();
    await _remote?.dispose();
    await _pc?.close();
    await _pc?.dispose();
    _pc = null;
    _local = null;
    _remote = null;
  }
}
