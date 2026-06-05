import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pguard_mobile/core/network/sockets/ws_client.dart';

/// Minimal fake channel — only `stream` + `sink.close()` are used by ReconnectingWebSocket.
class _FakeWsSink implements WebSocketSink {
  bool closed = false;
  @override
  Future<void> close([int? code, String? reason]) async => closed = true;
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// A sink that records what was written (to assert outbound frames).
class _RecordingSink implements WebSocketSink {
  final List<dynamic> added = [];
  bool closed = false;
  @override
  void add(dynamic data) => added.add(data);
  @override
  Future<void> close([int? code, String? reason]) async => closed = true;
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakeWsChannel implements WebSocketChannel {
  _FakeWsChannel(this._stream, this._sink);
  final Stream<dynamic> _stream;
  final WebSocketSink _sink;
  @override
  Stream<dynamic> get stream => _stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  test('decodes JSON frames to the messages stream', () async {
    final ctrl = StreamController<dynamic>.broadcast();
    final ws = ReconnectingWebSocket(
      url: Uri.parse('ws://x/v1/ws/bookings/b1'),
      tokenProvider: () async => 'tok',
      factory: (_, __) => _FakeWsChannel(ctrl.stream, _FakeWsSink()),
    );
    final got = <Map<String, dynamic>>[];
    ws.messages.listen(got.add);
    await ws.connect();
    ctrl.add('{"type":"booking_status","status":"arrived"}');
    await Future<void>.delayed(Duration.zero);
    expect(got.single['status'], 'arrived');
    await ws.close();
  });

  test(
      'close() during the connect await tears down the raced channel (no leak/throw)',
      () async {
    final ctrl = StreamController<dynamic>.broadcast();
    final sink = _FakeWsSink();
    final tokenGate = Completer<String?>();
    var factoryCalls = 0;

    final ws = ReconnectingWebSocket(
      url: Uri.parse('ws://x/v1/ws/bookings/b1'),
      tokenProvider: () => tokenGate.future, // hangs until completed
      factory: (_, __) {
        factoryCalls++;
        return _FakeWsChannel(ctrl.stream, sink);
      },
    );
    final got = <Map<String, dynamic>>[];
    ws.messages.listen(got.add, onError: (_) {});

    final connecting = ws.connect(); // enters, awaits tokenProvider
    await ws.close(); // close races in during the await
    tokenGate.complete('tok'); // resume connect()
    await connecting; // must not throw

    // The post-await `_closed` check returns before opening a channel → no orphan.
    expect(factoryCalls, 0);
    expect(got, isEmpty);
  });

  test('send() forwards a JSON frame when connected, drops otherwise', () async {
    final ctrl = StreamController<dynamic>.broadcast();
    final sink = _RecordingSink();
    final ws = ReconnectingWebSocket(
      url: Uri.parse('ws://x/v1/ws/track'),
      tokenProvider: () async => 'tok',
      factory: (_, __) => _FakeWsChannel(ctrl.stream, sink),
    );

    // Before connect → dropped (ephemeral GPS frames are never queued).
    ws.send({'type': 'location', 'lat': 1});
    expect(sink.added, isEmpty);

    await ws.connect();
    ws.send({'type': 'location', 'lat': 13.7});
    expect(sink.added.single, '{"type":"location","lat":13.7}'); // JSON-encoded
    ws.send('raw');
    expect(sink.added.last, 'raw'); // strings pass through unchanged

    await ws.close();
    ws.send({'x': 1}); // after close → dropped
    expect(sink.added.length, 2);
  });

  test('connectionChanges emits true on open and false on drop', () async {
    final ctrl = StreamController<dynamic>.broadcast();
    final ws = ReconnectingWebSocket(
      url: Uri.parse('ws://x/v1/ws/track'),
      tokenProvider: () async => 'tok',
      factory: (_, __) => _FakeWsChannel(ctrl.stream, _FakeWsSink()),
    );
    final events = <bool>[];
    ws.connectionChanges.listen(events.add);

    await ws.connect();
    await Future<void>.delayed(Duration.zero);
    expect(events, [true]);

    await ctrl.close(); // stream done → _onClosed emits false (then schedules reconnect)
    await Future<void>.delayed(Duration.zero);
    expect(events, [true, false]);

    await ws.close(); // cancels the pending reconnect timer
  });
}
