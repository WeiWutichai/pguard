import 'dart:async';

import '../../config/app_config.dart';
import '../../models/tracking.dart';
import 'ws_client.dart';

/// Link state of the guard's presence connection (drives the dashboard online/standby UI).
enum PresenceLink { offline, connecting, online }

/// The presence GPS feed the [TrackingController] depends on. An interface so the controller is
/// unit-testable against a fake (no real WebSocket, no GPS); [PresenceSocket] is production.
abstract class PresenceFeed {
  /// Connection-link transitions (offline → connecting → online → …).
  Stream<PresenceLink> get link;

  /// Open the connection (idempotent).
  Future<void> connect();

  /// Stream one GPS sample up to the server (dropped if not connected — the next sample wins).
  void sendLocation(GpsSample sample);

  /// Declare whether the guard has switched "พร้อมรับงาน" ON. This — NOT the mere existence of
  /// this connection — is what makes the guard appear in the customer's guard-selection list.
  ///
  /// The distinction is the whole point: the app also opens this socket to stream GPS during an
  /// ACTIVE JOB with the toggle off, and the server used to read any incoming fix as "available",
  /// putting guards who never opted in in front of customers. The declaration is remembered and
  /// RE-SENT on every reconnect, because the server scopes it to the connection (a dropped socket
  /// means "not available", so a silent reconnect must re-assert intent or the guard would
  /// quietly vanish from discovery).
  void setAvailability(bool available);

  Future<void> close();
}

/// Guard GPS uplink over [ReconnectingWebSocket] (Bearer-on-upgrade + backoff).
///
///   URL  : `{wsBaseUrl}/ws/track`                 (token scopes the guard)
///   Auth : `Authorization: Bearer <access>`        on the HTTP upgrade (never URL query)
///   Frame: `{ "type":"location", "lat", "lng", "accuracy"?, "recorded_at" }`  (client → server)
///          `{ "type":"availability", "available": bool }`                     (client → server)
///
/// mirrors the booking-status WS auth (Bearer-on-upgrade). NO `Timer.periodic`: the cadence is
/// the OS position stream; reconnect is event-driven backoff.
class PresenceSocket implements PresenceFeed {
  PresenceSocket({
    required Future<String?> Function() tokenProvider,
    WsChannelFactory? factory,
  }) : _ws = factory != null
            ? ReconnectingWebSocket(
                url: _url(), tokenProvider: tokenProvider, factory: factory)
            : ReconnectingWebSocket(url: _url(), tokenProvider: tokenProvider) {
    _sub = _ws.connectionChanges.listen((connected) {
      _link.add(connected ? PresenceLink.online : PresenceLink.connecting);
      // Availability is SESSION-scoped server-side, so a fresh socket starts out "not available".
      // Re-assert the guard's standing declaration the moment a connection comes up — otherwise a
      // backoff reconnect (or the very first connect, which races the caller's setAvailability)
      // would silently drop an online guard out of the customer's list until their next toggle.
      if (connected && _available) _sendAvailability(true);
    });
  }

  final ReconnectingWebSocket _ws;
  final StreamController<PresenceLink> _link =
      StreamController<PresenceLink>.broadcast();
  StreamSubscription<bool>? _sub;

  /// The guard's standing "พร้อมรับงาน" declaration, kept so it survives reconnects.
  bool _available = false;

  static Uri _url() => Uri.parse('${AppConfig.wsBaseUrl}/ws/track');

  @override
  Stream<PresenceLink> get link => _link.stream;

  @override
  Future<void> connect() {
    if (!_link.isClosed) _link.add(PresenceLink.connecting);
    return _ws.connect();
  }

  @override
  void sendLocation(GpsSample sample) => _ws.send(sample.toFrame());

  @override
  void setAvailability(bool available) {
    _available = available;
    // Send even when the socket is down: the frame is dropped, but the remembered value is
    // re-sent on connect. Never queue — a stale declaration must not replay later.
    _sendAvailability(available);
  }

  void _sendAvailability(bool available) => _ws
      .send(<String, dynamic>{'type': 'availability', 'available': available});

  @override
  Future<void> close() async {
    if (!_link.isClosed) _link.add(PresenceLink.offline);
    await _sub?.cancel();
    await _ws.close();
    if (!_link.isClosed) await _link.close();
  }
}
