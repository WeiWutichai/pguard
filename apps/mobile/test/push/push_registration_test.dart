import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/active_job_controller.dart';
import 'package:pguard_mobile/core/controllers/booking_status_controller.dart';
import 'package:pguard_mobile/core/controllers/customer_home_controller.dart';
import 'package:pguard_mobile/core/controllers/guard_jobs_controller.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/core/push/booking_push.dart';
import 'package:pguard_mobile/core/push/in_app_banner_type.dart';
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
    final banners = <String>[];
    final posts = <String, Object?>{};
    final api = FakeApi(onPost: (path, data) async {
      posts[path] = data;
      return <String, dynamic>{};
    });
    final c = ProviderContainer(overrides: [
      pushServiceProvider.overrideWithValue(push),
      pguardApiProvider.overrideWithValue(api),
      pushNavigateProvider.overrideWithValue(routes.add),
      pushNotifyProvider.overrideWithValue(
        (message, {title, type = InAppBannerType.info, onTap}) =>
            banners.add(message),
      ),
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

    // An incoming-call push routes to the call screen AND shows the in-app banner.
    push.emitForeground({'type': 'incoming_call', 'call_id': 'call-123'});
    await Future<void>.delayed(Duration.zero);
    expect(routes, contains('/call?incoming=call-123'));
    expect(banners, contains('สายเรียกเข้า')); // Thai default
  });

  test('foreground chat + booking pushes surface an in-app banner (no nav)',
      () async {
    final push = FakePushService();
    final routes = <String>[];
    final banners = <String>[];
    final api = FakeApi(
      onGet: (_, __) async => <dynamic>[],
      onPost: (_, __) async => <String, dynamic>{},
    );
    final c = ProviderContainer(overrides: [
      pushServiceProvider.overrideWithValue(push),
      pguardApiProvider.overrideWithValue(api),
      pushNavigateProvider.overrideWithValue(routes.add),
      pushNotifyProvider.overrideWithValue(
        (message, {title, type = InAppBannerType.info, onTap}) =>
            banners.add(message),
      ),
      appStoreProvider
          .overrideWithValue(InMemoryStore()..access = 't'..refresh = 'r'),
    ]);
    addTearDown(c.dispose);

    c.read(pushRegistrationProvider);
    c.read(sessionProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // A chat push (no `type`, classified by event_type) → banner, no navigation.
    push.emitForeground({
      'event_type': 'pguard.events.chat.message_sent',
      'conversation_id': 'conv-1',
    });
    await Future<void>.delayed(Duration.zero);

    // A booking-status push → banner, no navigation.
    push.emitForeground({
      'event_type': 'pguard.events.booking.guard_en_route',
      'booking_id': 'b-1',
    });
    await Future<void>.delayed(Duration.zero);

    expect(banners, ['ข้อความใหม่', 'อัปเดตงานของคุณ']);
    expect(routes, isEmpty); // foreground status/chat pushes don't navigate
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
      pushNotifyProvider.overrideWithValue(
        (message, {title, type = InAppBannerType.info, onTap}) =>
            banners.add(message),
      ),
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
    expect(banners, ['มีงานใหม่ใกล้คุณ แตะเพื่อดู']); // default locale is Thai

    // It did NOT navigate (new_job surfaces in-place; it never opens the call screen).
    expect(routes, isEmpty);
  });

  test(
      'a booking.* push (guard accepted) re-fetches the customer home bookings '
      'list so the ongoing-job card advances', () async {
    final push = FakePushService();
    // Count re-fetches of the customer dashboard's /bookings list. NOTE: the booking push now ALSO
    // invalidates guardJobsController (#128), which shares `/bookings` — so we assert this count
    // INCREASED after the push (the customer home re-pulled) rather than an exact figure that would
    // couple to the unrelated guard-jobs (re)build.
    var homeFetches = 0;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings') homeFetches++;
        return <dynamic>[];
      },
      onPost: (_, __) async => <String, dynamic>{},
    );
    final c = ProviderContainer(overrides: [
      pushServiceProvider.overrideWithValue(push),
      pguardApiProvider.overrideWithValue(api),
      pushNavigateProvider.overrideWithValue((_) {}),
      pushNotifyProvider.overrideWithValue(
        (message, {title, type = InAppBannerType.info, onTap}) {},
      ),
      appStoreProvider
          .overrideWithValue(InMemoryStore()..access = 't'..refresh = 'r'),
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tp) => FakeBookingFeed()),
    ]);
    addTearDown(c.dispose);

    // Keep the customer home feed actively listened so an invalidate REFETCHES (dashboard mounted).
    final sub = c.listen(customerHomeControllerProvider, (_, __) {});
    addTearDown(sub.close);

    c.read(pushRegistrationProvider);
    c.read(sessionProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(homeFetches, 1); // initial load
    final before = homeFetches;

    // The guard-accepted push fires (booking.* event, carries the booking id).
    push.emitForeground({
      'event_type': 'pguard.events.booking.job_accepted',
      'booking_id': 'b-1',
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(homeFetches, greaterThan(before),
        reason: 'the booking push invalidated customerHomeController → it re-pulled');
  });

  test(
      '#128 a booking.completed push (customer confirmed) re-fetches the guard '
      'jobs list so the just-completed job leaves "กำลังทำ"', () async {
    final push = FakePushService();
    // Count fetches of `/bookings/open` — this path is UNIQUE to guardJobsController's build
    // (customerHomeController, which the push also invalidates, only hits `/bookings`), so it
    // isolates the guard-jobs (re)build count cleanly without coupling to the shared `/bookings`.
    var openFetches = 0;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/open') openFetches++;
        return <dynamic>[]; // /bookings + /bookings/open both empty
      },
      onPost: (_, __) async => <String, dynamic>{},
    );
    final c = ProviderContainer(overrides: [
      pushServiceProvider.overrideWithValue(push),
      pguardApiProvider.overrideWithValue(api),
      pushNavigateProvider.overrideWithValue((_) {}),
      pushNotifyProvider.overrideWithValue(
        (message, {title, type = InAppBannerType.info, onTap}) {},
      ),
      appStoreProvider
          .overrideWithValue(InMemoryStore()..access = 't'..refresh = 'r'),
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tp) => FakeBookingFeed()),
    ]);
    addTearDown(c.dispose);

    // Keep the (autoDispose) guard-jobs feed actively listened so the invalidate REFETCHES rather
    // than just disposing — i.e. exercise the guard-dashboard-mounted path.
    final sub = c.listen(guardJobsControllerProvider, (_, __) {});
    addTearDown(sub.close);

    c.read(pushRegistrationProvider);
    c.read(sessionProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(openFetches, 1); // initial load

    // The customer-confirmed push fires: booking.completed carries this booking id and (per the
    // notification mapper) is delivered TO THE GUARD.
    push.emitForeground({
      'event_type': 'pguard.events.booking.completed',
      'booking_id': 'b-1',
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(openFetches, greaterThan(1),
        reason: 'the booking.completed push invalidated guardJobsController → it re-pulled, so the '
            'completed job leaves "กำลังทำ"');
  });

  group('BookingPush.tryParse', () {
    test('parses a payment.completed push (isPayment) + its booking_id', () {
      final p = BookingPush.tryParse({
        'event_type': 'pguard.events.payment.completed',
        'booking_id': 'b-9',
        'payment_id': 'p-1',
      });
      expect(p, isNotNull);
      expect(p!.bookingId, 'b-9');
      expect(p.isPayment, isTrue);
    });

    test('parses a booking.* status push (not isPayment)', () {
      final p = BookingPush.tryParse({
        'event_type': 'pguard.events.booking.guard_en_route',
        'booking_id': 'b-9',
      });
      expect(p, isNotNull);
      expect(p!.isPayment, isFalse);
      expect(p.bookingId, 'b-9');
    });

    test('returns null for new_job / incoming_call / chat / unknown', () {
      // new_job & incoming_call carry `type` → owned by their own handlers.
      expect(BookingPush.tryParse({'type': 'new_job', 'booking_id': 'b'}),
          isNull);
      expect(BookingPush.tryParse({'type': 'incoming_call', 'call_id': 'c'}),
          isNull);
      expect(
          BookingPush.tryParse(
              {'event_type': 'pguard.events.chat.message_sent'}),
          isNull);
      expect(BookingPush.tryParse(const {}), isNull);
    });
  });

  test(
      'a payment.completed push invalidates the booking-status AND active-job '
      'controllers for that booking (guard un-gates, customer banner clears)',
      () async {
    final push = FakePushService();
    // Count re-fetches of THIS booking. `paid_at` is set ASYNC by the booking service AFTER the
    // push, so it only becomes visible once [paidVisible] flips (the test flips it only once the
    // push has fired AND the retry lag has elapsed — proving the single bounded retry is what
    // finally picks up `paid_at`).
    var bookingFetches = 0;
    var paidVisible = false;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') {
          bookingFetches++;
          return {
            'id': 'b1',
            'customer_id': 'c1',
            'guard_id': 'g1',
            'status': 'accepted',
            'hours': 4,
            'base_fee': '500.00',
            'guard_count': 1,
            'tip': '0',
            if (paidVisible) 'paid_at': '2026-06-05T10:05:00Z',
          };
        }
        return <dynamic>[]; // progress-reports trail
      },
      onPost: (_, __) async => <String, dynamic>{},
    );
    final c = ProviderContainer(overrides: [
      pushServiceProvider.overrideWithValue(push),
      pguardApiProvider.overrideWithValue(api),
      pushNavigateProvider.overrideWithValue((_) {}),
      pushNotifyProvider.overrideWithValue(
        (message, {title, type = InAppBannerType.info, onTap}) {},
      ),
      appStoreProvider
          .overrideWithValue(InMemoryStore()..access = 't'..refresh = 'r'),
      bookingStatusFeedBuilderProvider
          .overrideWithValue((id, tp) => FakeBookingFeed()),
    ]);
    addTearDown(c.dispose);

    // Keep both of the booking's controllers actively listened so an invalidate REFETCHES.
    final bSub =
        c.listen(bookingStatusControllerProvider('b1'), (_, __) {});
    addTearDown(bSub.close);
    final aSub = c.listen(activeJobControllerProvider('b1'), (_, __) {});
    addTearDown(aSub.close);

    // Shrink the post-payment retry delay so the test doesn't wait ~1.5s.
    final reg = c.read(pushRegistrationProvider.notifier);
    reg.payRefetchDelayForTest = const Duration(milliseconds: 20);

    c.read(pushRegistrationProvider);
    c.read(sessionProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Both controllers loaded; the guard is NOT yet paid (gate closed — paid_at still lagging).
    final job0 = await c.read(activeJobControllerProvider('b1').future);
    expect(job0.booking.isPaid, isFalse);
    final fetchesBefore = bookingFetches;

    // `paid_at` lands ~12ms later (just after the 10ms retry delay) — the immediate post-push
    // refetch still sees it absent, only the bounded retry picks it up.
    Future<void>.delayed(const Duration(milliseconds: 12), () => paidVisible = true);

    // The payment push fires: invalidate both controllers, and (paid_at still lagging) retry the
    // active job once after the (shrunk) delay.
    push.emitForeground({
      'event_type': 'pguard.events.payment.completed',
      'booking_id': 'b1',
      'payment_id': 'p1',
    });
    // Let the invalidations refetch + the bounded retry elapse.
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(bookingFetches, greaterThan(fetchesBefore),
        reason: 'the booking-status + active-job controllers re-fetched on the push');
    // The retry re-fetch picked up the now-present paid_at → the guard un-gates.
    final jobAfter = c.read(activeJobControllerProvider('b1')).valueOrNull;
    expect(jobAfter?.booking.isPaid, isTrue,
        reason: 'active-job re-fetch (with one retry) saw paid_at → en_route enabled');
  });
}
