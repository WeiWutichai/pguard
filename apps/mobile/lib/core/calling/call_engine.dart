// The WebRTC media-plane seam. PLUGIN-FREE (no flutter_webrtc import) so the [CallController]
// and its tests run against a fake engine without the platform plugin — the production
// implementation ([WebRtcCallEngine]) wraps `flutter_webrtc` + `permission_handler`.

/// A neutral SDP description (no plugin types). [type] is `offer` or `answer`.
class SignalDescription {
  const SignalDescription({required this.type, required this.sdp});

  final String type;
  final String sdp;
}

/// A neutral ICE server (no plugin types) — one entry of what the calling service serves at
/// `GET /v1/calls/ice`. A STUN entry carries [urls] only; a TURN entry adds a SHORT-LIVED,
/// per-caller [username]/[credential] (the coturn REST scheme). The engine maps these straight
/// into the WebRTC `RTCIceServer` shape — nothing here is hard-coded in the client.
class IceServer {
  const IceServer({required this.urls, this.username, this.credential});

  /// Parse one served `ice_servers[]` entry (field names match the calling OpenAPI contract).
  /// Tolerant of a malformed entry — a non-list `urls` or non-string members are dropped rather
  /// than throwing, so one bad entry can't fail the whole call (the engine just skips a dud server).
  factory IceServer.fromJson(Map<String, dynamic> json) {
    final rawUrls = json['urls'];
    return IceServer(
      urls: rawUrls is List ? rawUrls.whereType<String>().toList() : const <String>[],
      username: json['username'] is String ? json['username'] as String : null,
      credential: json['credential'] is String ? json['credential'] as String : null,
    );
  }

  final List<String> urls;
  final String? username;
  final String? credential;
}

/// A neutral trickle-ICE candidate (no plugin types).
class SignalCandidate {
  const SignalCandidate({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
}

/// Media / peer-connection lifecycle the engine surfaces to the controller.
enum CallMediaEvent { connecting, connected, failed, closed }

/// A user-facing failure in the media plane (e.g. a denied mic/camera permission). The message
/// is already friendly + generic (no internal/plugin detail).
class CallException implements Exception {
  const CallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The WebRTC peer the [CallController] drives. Owns the `RTCPeerConnection`, the local media
/// (mic, +camera for video), and the remote stream — but exposes them through neutral types so
/// the controller never touches the plugin and is unit-testable with a fake.
abstract class CallEngine {
  /// Acquire mic (+camera for [video]) — requesting OS permission first — and create the peer
  /// connection using [iceServers] (the STUN/TURN list served by the calling service; NOT
  /// hard-coded). Throws [CallException] if a required permission is denied or media is unavailable.
  Future<void> initialize({
    required bool video,
    required List<IceServer> iceServers,
  });

  /// Create the local offer (sets the local description) and return it for relaying to the peer.
  Future<SignalDescription> createOffer();

  /// Create the local answer (sets the local description) and return it for relaying to the peer.
  Future<SignalDescription> createAnswer();

  /// Apply the peer's offer/answer.
  Future<void> setRemoteDescription(SignalDescription description);

  /// Add a remote trickle-ICE candidate.
  Future<void> addIceCandidate(SignalCandidate candidate);

  /// Local ICE candidates as they are gathered (the controller relays each to the peer).
  Stream<SignalCandidate> get onLocalCandidate;

  /// Peer-connection lifecycle transitions.
  Stream<CallMediaEvent> get onMediaEvent;

  /// Emits when [remoteStream] becomes available / changes, so the view can rebind its renderer.
  Stream<void> get onRemoteStreamChanged;

  /// Toggle the local audio track.
  Future<void> setMuted(bool muted);

  /// Route audio to the loudspeaker (`true`) or the earpiece (`false`).
  Future<void> setSpeaker(bool on);

  /// Flip the front/back camera (video calls).
  Future<void> switchCamera();

  /// The local media stream as an opaque handle (the screen casts to `MediaStream` to render).
  /// `Object?` keeps this seam — and the controller + tests — free of plugin types.
  Object? get localStream;

  /// The remote media stream as an opaque handle (or `null` until the peer's media arrives).
  Object? get remoteStream;

  /// Tear down: close the peer connection, stop + release all tracks, free renderers.
  Future<void> dispose();
}
