import '../../config/app_config.dart';
import '../../models/call.dart';
import 'ws_client.dart';

/// A decoded inbound `/ws/call` signal frame (`{ type:"signal", from, call_id, signal }`).
class CallSignalFrame {
  const CallSignalFrame({
    required this.callId,
    required this.signal,
    this.from,
  });

  /// The sender (the other participant) — informational; routing is by call id, never trusted.
  final String? from;
  final String callId;
  final CallSignal signal;

  /// Parse a decoded WS frame into a signal frame, or `null` if it is not a `signal` frame
  /// (e.g. a `{ type:"error", ... }` frame, or one with an unrecognised `signal`).
  static CallSignalFrame? tryParse(Map<String, dynamic> json) {
    if (json['type'] != 'signal') return null;
    final callId = json['call_id'];
    if (callId is! String) return null;
    final signal = CallSignal.tryParse(json['signal']);
    if (signal == null) return null;
    return CallSignalFrame(
      callId: callId,
      signal: signal,
      from: json['from'] as String?,
    );
  }
}

/// The call-signaling feed the [CallController] depends on. An interface so the controller is
/// unit-testable against a fake (no real WebSocket); [CallSocket] is the production implementation.
abstract class CallSignalFeed {
  /// Inbound signal frames relayed from the other participant (offer/answer/candidate/ready/bye).
  Stream<CallSignalFrame> get signals;
  Future<void> connect();

  /// Send a signal to the call's other participant. `callId` rides IN the frame (NEVER the URL).
  void send({required String callId, required CallSignal signal});

  Future<void> close();
}

/// Typed `/ws/call` signaling over [ReconnectingWebSocket] (Bearer-on-upgrade, auto-reconnect).
///
/// Protocol (per `contracts/openapi/calling.yaml` + the merged backend `services/calling/src/api/ws.rs`):
///  - Connect to `{wsBaseUrl}/ws/call` — **`call_id` is NOT in the URL** (it rides in each frame).
///  - Send `{ type:"signal", call_id, signal:<opaque SDP/ICE> }`; the server verifies the sender is
///    a participant and relays `{ type:"signal", from, call_id, signal }` to the OTHER party only
///    (IDOR-safe on the wire). The `signal` payload is the [CallSignal] envelope.
///  - The relay has NO lifecycle/presence push — the controller bootstraps the SDP exchange with a
///    `ready` signal (see [CallSignalKind]).
///
/// BACKEND DEPENDENCY (documented, mirrors `chat_socket.dart`): the api-gateway does not yet proxy
/// the `/v1/ws/call` upgrade. This client codes against the contract so it works unchanged once a
/// WS-aware ingress lands. NO polling — signals are push.
class CallSocket implements CallSignalFeed {
  CallSocket({
    required Future<String?> Function() tokenProvider,
    WsChannelFactory? factory,
  }) : _ws = factory != null
            ? ReconnectingWebSocket(
                url: _url, tokenProvider: tokenProvider, factory: factory)
            : ReconnectingWebSocket(url: _url, tokenProvider: tokenProvider);

  final ReconnectingWebSocket _ws;

  static Uri get _url => Uri.parse('${AppConfig.wsBaseUrl}/ws/call');

  @override
  Stream<CallSignalFrame> get signals => _ws.messages
      .map(CallSignalFrame.tryParse)
      .where((f) => f != null)
      .cast<CallSignalFrame>();

  @override
  Future<void> connect() => _ws.connect();

  @override
  void send({required String callId, required CallSignal signal}) {
    _ws.send({
      'type': 'signal',
      'call_id': callId,
      'signal': signal.toJson(),
    });
  }

  @override
  Future<void> close() => _ws.close();
}
