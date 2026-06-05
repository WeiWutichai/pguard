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

  Future<void> close();
}

/// Guard GPS uplink over [ReconnectingWebSocket] (Bearer-on-upgrade + backoff).
///
/// BACKEND DEPENDENCY (documented — does not exist yet): the presence service is purge-only and
/// the api-gateway exposes no presence route. This client codes against the agreed contract so
/// the guard tracking works the moment the ingress lands, with no client change:
///
///   URL  : `{wsBaseUrl}/ws/track`                 (token scopes the guard)
///   Auth : `Authorization: Bearer <access>`        on the HTTP upgrade (never URL query)
///   Frame: `{ "type":"location", "lat", "lng", "accuracy"?, "recorded_at" }`  (client → server)
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
    });
  }

  final ReconnectingWebSocket _ws;
  final StreamController<PresenceLink> _link =
      StreamController<PresenceLink>.broadcast();
  StreamSubscription<bool>? _sub;

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
  Future<void> close() async {
    if (!_link.isClosed) _link.add(PresenceLink.offline);
    await _sub?.cancel();
    await _ws.close();
    if (!_link.isClosed) await _link.close();
  }
}
