/// App-wide configuration, resolved from `--dart-define` with dev defaults.
///
/// All REST traffic goes through the api-gateway `/v1` edge (JWT-at-edge, rate limit,
/// route). The booking-status WebSocket points at the same edge — see [wsBaseUrl] and the
/// note in `core/network/sockets/booking_status_socket.dart` about the gateway not yet
/// proxying WS upgrades (the one backend dependency for this slice).
class AppConfig {
  const AppConfig._();

  /// HTTP base for the gateway, e.g. `http://localhost:3000`. Android emulators reach the
  /// host loopback via `10.0.2.2`; override per-platform with `--dart-define=PGUARD_API_HOST`.
  static const String _apiHost = String.fromEnvironment('PGUARD_API_HOST',
      defaultValue: 'http://localhost:3000');

  /// WS base, e.g. `ws://localhost:3000`. Defaults derived from the API host scheme.
  static const String _wsHostOverride =
      String.fromEnvironment('PGUARD_WS_HOST', defaultValue: '');

  /// Public host for presigned media (chat attachments). MinIO/S3 presigned URLs carry the
  /// storage host as the SERVER sees it (e.g. `minio:9000`), which a device can't reach; when set
  /// (`--dart-define=PGUARD_MEDIA_HOST=https://media.pguard.app`) the scheme+authority is swapped
  /// to this, preserving the signed path/query. Empty (default) → no rewrite. See [MediaHost].
  static const String mediaHost =
      String.fromEnvironment('PGUARD_MEDIA_HOST', defaultValue: '');

  /// REST base URL including the `/v1` version prefix the gateway expects.
  static String get apiBaseUrl => '$_apiHost/v1';

  /// WebSocket base URL including `/v1`. If not overridden, swap the http(s) scheme to ws(s).
  static String get wsBaseUrl {
    if (_wsHostOverride.isNotEmpty) return '$_wsHostOverride/v1';
    final ws = _apiHost.replaceFirst(RegExp(r'^http'), 'ws');
    return '$ws/v1';
  }

  /// Refresh the access token proactively when it expires within this window (mirrors v1's
  /// 2-minute buffer) so requests rarely hit a reactive 401.
  static const Duration proactiveRefreshLeeway = Duration(minutes: 2);

  /// Network timeouts for REST calls.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 20);
}
