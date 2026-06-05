import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'backoff.dart';

/// Factory for the underlying channel — injectable so tests supply a fake transport.
/// The default uses [IOWebSocketChannel] which (on iOS/Android, dart:io) sends the
/// `Authorization` header on the HTTP upgrade — the token is NEVER put in the URL query.
typedef WsChannelFactory = WebSocketChannel Function(
    Uri url, Map<String, String> headers);

WebSocketChannel _defaultChannelFactory(Uri url, Map<String, String> headers) =>
    IOWebSocketChannel.connect(url, headers: headers);

/// A self-healing WebSocket: connects with a fresh Bearer on every (re)connect, decodes JSON
/// frames to a broadcast stream, and auto-reconnects with exponential backoff (cap 60s) using
/// a SINGLE one-shot timer per attempt — this is push delivery, NOT `Timer.periodic` polling.
///
/// Reconnecting re-runs [tokenProvider] (so a rotated/refreshed token is used) and re-opens
/// the same URL, which re-establishes the subscription (the booking id is in the path).
class ReconnectingWebSocket {
  ReconnectingWebSocket({
    required this.url,
    required this.tokenProvider,
    this.backoff = const BackoffPolicy(),
    WsChannelFactory factory = _defaultChannelFactory,
  }) : _factory = factory;

  /// e.g. `ws://host/v1/ws/bookings/{id}` — the subscription scope is the path.
  final Uri url;

  /// Supplies a fresh access token for the upgrade header on each (re)connect.
  final Future<String?> Function() tokenProvider;

  final BackoffPolicy backoff;
  final WsChannelFactory _factory;

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _closed = false;
  bool _connecting = false;

  /// Decoded JSON frames (object frames only; non-JSON heartbeats are dropped).
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  /// Open the connection (idempotent; no-op after [close]).
  Future<void> connect() async {
    if (_closed || _connecting) return;
    _connecting = true;
    _reconnectTimer?.cancel();
    try {
      final token = await tokenProvider();
      // close() may have fired during the await — don't open an orphan channel.
      if (_closed) return;
      final headers = <String, String>{
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final channel = _factory(url, headers);
      // Re-check after creating: if close() raced in, tear the channel down here
      // (nothing else holds a reference to it).
      if (_closed) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _sub = channel.stream.listen(
        _onData,
        onDone: _onClosed,
        onError: (Object _) => _onClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _onData(dynamic raw) {
    if (_controller.isClosed) return; // closed mid-flight — drop late frames
    _attempt =
        0; // a live frame proves the connection is healthy → reset backoff
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        _controller.add(decoded);
      }
    } catch (_) {
      // Ignore non-JSON / partial frames (e.g. ping/pong heartbeats).
    }
  }

  void _onClosed() {
    _sub?.cancel();
    _sub = null;
    _channel = null;
    if (!_closed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed) return;
    final delay = backoff.delayFor(_attempt);
    _attempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer =
        Timer(delay, connect); // one-shot per attempt — not periodic
  }

  /// Permanently close: stop reconnecting, tear down the channel + stream.
  Future<void> close() async {
    _closed = true;
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    if (!_controller.isClosed) await _controller.close();
  }
}
