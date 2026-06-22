import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/core/push/incoming_call_push.dart';
import 'package:pguard_mobile/core/push/push_registration_controller.dart';
import 'package:pguard_mobile/core/push/push_service.dart';

import '../support/fakes.dart';

/// In-memory [PushService] — no Firebase. [emitForeground] simulates an FCM data message.
class FakePushService implements PushService {
  FakePushService({this.token = 'fcm-tok'});

  final String? token;
  final _fg = StreamController<Map<String, dynamic>>.broadcast();
  int permissionRequests = 0;

  @override
  Future<void> requestPermission() async => permissionRequests++;

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get foregroundMessages => _fg.stream;

  @override
  Stream<Map<String, dynamic>> get openedMessages => const Stream.empty();

  @override
  Future<Map<String, dynamic>?> initialMessageData() async => null;

  void emitForeground(Map<String, dynamic> data) => _fg.add(data);
}

void main() {
  group('IncomingCallPush.tryParse', () {
    test('parses an incoming_call data map', () {
      final p = IncomingCallPush.tryParse({
        'type': 'incoming_call',
        'call_id': 'c1',
        'call_type': 'audio',
        'caller_id': 'u9',
      });
      expect(p, isNotNull);
      expect(p!.callId, 'c1');
      expect(p.callType, 'audio');
      expect(p.callerId, 'u9');
    });

    test('returns null for a non-call or id-less payload', () {
      expect(IncomingCallPush.tryParse({'type': 'chat'}), isNull);
      expect(IncomingCallPush.tryParse({'type': 'incoming_call'}), isNull);
      expect(
          IncomingCallPush.tryParse(
              {'type': 'incoming_call', 'call_id': ''}),
          isNull);
    });
  });

  test('registers the FCM token on auth and routes an incoming-call push', () async {
    final push = FakePushService();
    final routes = <String>[];
    final posts = <String, Object?>{};
    final api = FakeApi(onPost: (path, data) async {
      posts[path] = data;
      return <String, dynamic>{};
    });
    final c = ProviderContainer(overrides: [
      pushServiceProvider.overrideWithValue(push),
      pguardApiProvider.overrideWithValue(api),
      pushNavigateProvider.overrideWithValue(routes.add),
      appStoreProvider
          .overrideWithValue(InMemoryStore()..access = 't'..refresh = 'r'),
    ]);
    addTearDown(c.dispose);

    c.read(pushRegistrationProvider); // instantiate → listens to the session
    c.read(sessionProvider); // instantiate → schedules the async _load
    // Let _load resolve to authenticated, the listener fire, and _start run.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // The device token was registered with the backend.
    expect(posts['/tokens'], {'token': 'fcm-tok', 'device_type': 'android'});
    expect(push.permissionRequests, 1);

    // An incoming-call push routes to the call screen.
    push.emitForeground({'type': 'incoming_call', 'call_id': 'call-123'});
    await Future<void>.delayed(Duration.zero);
    expect(routes, contains('/call?incoming=call-123'));

    // A non-call push is ignored (no navigation).
    push.emitForeground({'type': 'chat', 'conversation_id': 'x'});
    await Future<void>.delayed(Duration.zero);
    expect(routes.where((r) => r.contains('chat')), isEmpty);
  });
}
