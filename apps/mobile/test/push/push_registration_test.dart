import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/guard_jobs_controller.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/core/push/incoming_call_push.dart';
import 'package:pguard_mobile/core/push/new_job_push.dart';
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

  group('NewJobPush.tryParse', () {
    test('parses a new_job data map', () {
      final p = NewJobPush.tryParse({
        'type': 'new_job',
        'booking_id': 'b-42',
      });
      expect(p, isNotNull);
      expect(p!.bookingId, 'b-42');
    });

    test('returns null for a non new_job payload', () {
      expect(NewJobPush.tryParse({'type': 'incoming_call'}), isNull);
      expect(NewJobPush.tryParse({'type': 'chat'}), isNull);
      expect(NewJobPush.tryParse(const {}), isNull);
    });

    test('parses with an empty id (still "refresh the feed")', () {
      expect(NewJobPush.tryParse({'type': 'new_job'})!.bookingId, '');
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

  test('a new_job push refetches the guard jobs feed and surfaces a banner',
      () async {
    final push = FakePushService();
    final routes = <String>[];
    final banners = <String>[];
    // Count how many times the open-jobs discovery feed is fetched — invalidation on a new_job
    // push must trigger a SECOND fetch (the guard's open feed re-loads so the offer appears).
    var openFetches = 0;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/open') openFetches++;
        return <dynamic>[]; // both /bookings and /bookings/open return an empty list
      },
      onPost: (path, data) async => <String, dynamic>{},
    );
    final c = ProviderContainer(overrides: [
      pushServiceProvider.overrideWithValue(push),
      pguardApiProvider.overrideWithValue(api),
      pushNavigateProvider.overrideWithValue(routes.add),
      pushNotifyProvider.overrideWithValue(banners.add),
      appStoreProvider
          .overrideWithValue(InMemoryStore()..access = 't'..refresh = 'r'),
    ]);
    addTearDown(c.dispose);

    // Keep the (autoDispose) guard-jobs feed actively listened so invalidation REFETCHES rather
    // than just disposing — i.e. exercise the dashboard-mounted path.
    final sub = c.listen(guardJobsControllerProvider, (_, __) {});
    addTearDown(sub.close);

    c.read(pushRegistrationProvider);
    c.read(sessionProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // First load happened (open feed fetched once).
    expect(openFetches, 1);
    expect(banners, isEmpty);

    // A new_job push: invalidate → the open feed refetches, and the banner is shown.
    push.emitForeground({'type': 'new_job', 'booking_id': 'b-7'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(openFetches, 2);
    expect(banners, ['งานใหม่ใกล้คุณ']); // default locale is Thai

    // It did NOT navigate (new_job surfaces in-place; it never opens the call screen).
    expect(routes, isEmpty);
  });
}
