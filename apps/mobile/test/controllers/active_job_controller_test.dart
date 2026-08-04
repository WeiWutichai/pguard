import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/active_job_controller.dart';
import 'package:pguard_mobile/core/controllers/locale_controller.dart';
import 'package:pguard_mobile/core/media/photo_capture.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson(String id, String status,
        {String? workStartedAt}) =>
    {
      'id': id,
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': status,
      'address': 'หมู่บ้านลัดดารมย์',
      'scheduled_at': '2026-06-05T14:00:00Z',
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'tip': '0',
      if (workStartedAt != null) 'work_started_at': workStartedAt,
      'created_at': '2026-06-05T10:00:00Z',
      'updated_at': '2026-06-05T10:00:00Z',
    };

void main() {
  test('drives transitions to the correct PUT paths; start records startedAt',
      () async {
    final api = FakeApi(
      // build() now also reads the check-in trail; no trail yet → empty list (startedAt stays null).
      onGet: (path, _) async => path == '/bookings/b1'
          ? bookingJson('b1', 'accepted')
          : <Map<String, dynamic>>[],
      onPut: (path, _) async {
        switch (path) {
          case '/bookings/b1/en-route':
            return bookingJson('b1', 'en_route');
          case '/bookings/b1/arrived':
            return bookingJson('b1', 'arrived');
          case '/bookings/b1/start':
            return bookingJson('b1', 'arrived'); // start keeps status = arrived
          case '/bookings/b1/complete':
            return bookingJson('b1', 'pending_completion');
          default:
            throw StateError('unexpected PUT $path');
        }
      },
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    final s0 = await c.read(activeJobControllerProvider('b1').future);
    expect(s0.booking.status, BookingStatus.accepted);
    expect(s0.startedAt, isNull);
    expect(s0.clock, isNull); // no countdown until started

    final ctrl = c.read(activeJobControllerProvider('b1').notifier);
    ActiveJobState state() => c.read(activeJobControllerProvider('b1')).value!;

    expect(await ctrl.enRoute(), isTrue);
    expect(state().booking.status, BookingStatus.enRoute);

    expect(await ctrl.arrived(), isTrue);
    expect(state().booking.status, BookingStatus.arrived);

    expect(await ctrl.start(), isTrue);
    expect(state().startedAt,
        isNotNull); // client-recorded (API doesn't expose it)
    expect(state().clock, isNotNull);
    expect(state().booking.status, BookingStatus.arrived);

    expect(await ctrl.complete(), isTrue);
    expect(state().booking.status, BookingStatus.pendingCompletion);

    expect(
        api.calls,
        containsAllInOrder([
          'PUT /bookings/b1/en-route',
          'PUT /bookings/b1/arrived',
          'PUT /bookings/b1/start',
          'PUT /bookings/b1/complete',
        ]));
  });

  test(
      'submitCheckIn maps the 0-based UI slot to the 1-based server hour_number '
      '(slot N → hour N+1) and marks the slot (not the hour) done', () async {
    final checkIn = FakeCheckInService();
    final api = FakeApi(
        onGet: (path, _) async => path == '/bookings/b1'
            ? bookingJson('b1', 'arrived')
            : const <Map<String, dynamic>>[]);
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      checkInServiceProvider.overrideWithValue(checkIn),
    ]);
    addTearDown(c.dispose);

    await c.read(activeJobControllerProvider('b1').future); // hours: 8
    final ctrl = c.read(activeJobControllerProvider('b1').notifier);
    Set<int> done() =>
        c.read(activeJobControllerProvider('b1')).value!.completedCheckIns;

    // slot 0 (the start-of-work check-in) → server hour_number 1 (never the invalid 0).
    expect(
      await ctrl.submitCheckIn(
        slot: 0,
        photo: const CapturedPhoto(path: '/tmp/p.jpg', sizeBytes: 10),
      ),
      isTrue,
    );
    // slot 1 → server hour_number 2.
    expect(
      await ctrl.submitCheckIn(
        slot: 1,
        photo: const CapturedPhoto(path: '/tmp/p.jpg', sizeBytes: 10),
      ),
      isTrue,
    );
    expect(checkIn.submitted, [1, 2], reason: 'slots 0,1 → hours 1,2');
    expect(done(), containsAll(<int>[0, 1]),
        reason: 'completedCheckIns stays slot-indexed for the schedule UI');
  });

  test(
      'submitCheckIn maps the last slot (hours-1) 1:1 to hour=hours — no clamp',
      () async {
    final checkIn = FakeCheckInService();
    // hours: 8 → the schedule has slots 0..7; the last slot (7) maps to hour 8 directly.
    final api = FakeApi(
        onGet: (path, _) async => path == '/bookings/b1'
            ? bookingJson('b1', 'arrived')
            : const <Map<String, dynamic>>[]);
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      checkInServiceProvider.overrideWithValue(checkIn),
    ]);
    addTearDown(c.dispose);

    await c.read(activeJobControllerProvider('b1').future);
    final ctrl = c.read(activeJobControllerProvider('b1').notifier);
    await ctrl.submitCheckIn(
      slot: 7,
      photo: const CapturedPhoto(path: '/tmp/p.jpg', sizeBytes: 10),
    );
    expect(checkIn.submitted, [8],
        reason:
            'slot 7 → hour 8 (slot+1, 1:1); the defensive clamp does not trip');
  });

  test('submitCheckIn surfaces failure and does not mark the slot done',
      () async {
    final checkIn = FakeCheckInService(fail: true);
    final api = FakeApi(
        onGet: (path, _) async => path == '/bookings/b1'
            ? bookingJson('b1', 'arrived')
            : const <Map<String, dynamic>>[]);
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      checkInServiceProvider.overrideWithValue(checkIn),
    ]);
    addTearDown(c.dispose);

    await c.read(activeJobControllerProvider('b1').future);
    final ctrl = c.read(activeJobControllerProvider('b1').notifier);
    final ok = await ctrl.submitCheckIn(
      slot: 1,
      photo: const CapturedPhoto(path: '/tmp/p.jpg', sizeBytes: 10),
    );
    expect(ok, isFalse);
    final s = c.read(activeJobControllerProvider('b1')).value!;
    expect(s.completedCheckIns, isEmpty);
    expect(s.error, isNotNull);
  });

  test(
      'startedAt SURVIVES an invalidate with an EMPTY trail (the resumed re-fetch '
      'after the check-in camera backgrounds the app — round 1 not yet submitted)',
      () async {
    // The progress-reports trail stays EMPTY (no check-in has landed yet) — this is the exact
    // first-check-in scenario: the guard tapped Start, opened the camera (which backgrounds the
    // app), and the `resumed` re-fetch fires before the round-1 POST. Without the keep-alive
    // WorkSessionStore fallback, the rebuild would lose `startedAt` (the API never returns
    // work_started_at) → schedule/clock null → working panel collapses → "Start job" re-prompts.
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? bookingJson('b1', 'arrived')
          : const <Map<String, dynamic>>[],
      onPut: (path, _) async => bookingJson('b1', 'arrived'),
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    await c.read(activeJobControllerProvider('b1').future);
    expect(await c.read(activeJobControllerProvider('b1').notifier).start(),
        isTrue);
    final started = c.read(activeJobControllerProvider('b1')).value!.startedAt;
    expect(started, isNotNull); // start stamped the client time

    // Simulate the resumed re-fetch: invalidate → rebuild from the (still empty) server trail.
    c.invalidate(activeJobControllerProvider('b1'));
    final s = await c.read(activeJobControllerProvider('b1').future);
    expect(s.startedAt, started,
        reason: 'the client start is restored from the keep-alive store');
    expect(s.clock, isNotNull); // working panel stays up (schedule available)
    expect(s.schedule, isNotNull);
  });

  test(
      'applyExternalStatus folds a WS-pushed cancellation into state (the customer '
      'cancels while the guard is on the active-job screen) — idempotent',
      () async {
    // The active-job controller has no WS of its own; the screen pumps a terminal transition it
    // observes on the booking-status feed (chiefly the customer cancelling) into this method so the
    // screen flips to the cancelled terminal live, not only after a background+resume re-fetch.
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? bookingJson('b1', 'en_route')
          : const <Map<String, dynamic>>[],
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    await c.read(activeJobControllerProvider('b1').future);
    final ctrl = c.read(activeJobControllerProvider('b1').notifier);
    BookingStatus status() =>
        c.read(activeJobControllerProvider('b1')).value!.booking.status;
    expect(status(), BookingStatus.enRoute);

    ctrl.applyExternalStatus(BookingStatus.cancelled);
    expect(status(), BookingStatus.cancelled,
        reason:
            'the screen now renders the cancelled terminal banner + back-to-jobs');

    // Idempotent: a duplicate WS frame for the same status doesn't churn / re-emit a change.
    final before = c.read(activeJobControllerProvider('b1')).value;
    ctrl.applyExternalStatus(BookingStatus.cancelled);
    expect(identical(c.read(activeJobControllerProvider('b1')).value, before),
        isTrue);
    // No mutating API call was made — folding a status is purely local.
    expect(api.calls.where((s) => s.startsWith('PUT')), isEmpty);
  });

  test(
      'build hydrates completedCheckIns + startedAt from the check-in trail '
      '(resumes the working panel after an app restart)', () async {
    final api = FakeApi(
      onGet: (path, _) async {
        switch (path) {
          case '/bookings/b1':
            return bookingJson(
                'b1', 'arrived'); // started server-side, in progress
          case '/bookings/b1/progress-reports':
            return [
              {'hour_number': 1, 'created_at': '2026-06-05T14:00:00Z'},
              {'hour_number': 2, 'created_at': '2026-06-05T15:00:00Z'},
            ];
          default:
            throw StateError('unexpected GET $path');
        }
      },
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    final s = await c.read(activeJobControllerProvider('b1').future);
    // hours 1,2 reported → slots 0,1 (slot = hour_number − 1).
    expect(s.completedCheckIns, {0, 1});
    // startedAt = earliest anchor: r1 (14:00 − 0h) and r2 (15:00 − 1h) both → 14:00Z.
    expect(s.startedAt, DateTime.utc(2026, 6, 5, 14, 0, 0));
    // With status=arrived + startedAt set, the working panel resumes (clock available).
    expect(s.clock, isNotNull);
  });

  test(
      'server work_started_at anchors the clock across a rebuild (no check-in trail needed)',
      () async {
    // A job STARTED but with ZERO check-ins yet — the only anchor is the server stamp. This is
    // the app-restart / re-login case that used to collapse to "Start job".
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? bookingJson('b1', 'arrived', workStartedAt: '2026-06-05T14:00:00Z')
          : const <Map<String, dynamic>>[],
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    final s = await c.read(activeJobControllerProvider('b1').future);
    expect(s.startedAt, DateTime.utc(2026, 6, 5, 14, 0, 0));
    expect(s.clock, isNotNull); // working panel survives restart, no re-prompt
  });

  test(
      'start() sends the guard GPS fix in the PUT body (feeds the 50m geofence)',
      () async {
    Object? startBody;
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? bookingJson('b1', 'arrived')
          : const <Map<String, dynamic>>[],
      onPut: (path, data) async {
        if (path == '/bookings/b1/start') {
          startBody = data;
          return bookingJson('b1', 'arrived',
              workStartedAt: '2026-06-05T14:00:00Z');
        }
        throw StateError('unexpected PUT $path');
      },
    );
    // FakeLocationService default sample = lat 13.7/lng 100.5/acc 8.
    final loc = FakeLocationService();
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      locationServiceProvider.overrideWithValue(loc),
    ]);
    addTearDown(c.dispose);
    await c.read(activeJobControllerProvider('b1').future);

    expect(await c.read(activeJobControllerProvider('b1').notifier).start(),
        isTrue);
    expect(startBody, isA<Map<String, dynamic>>());
    final body = startBody as Map<String, dynamic>;
    expect(body['lat'], 13.7);
    expect(body['lng'], 100.5);
    expect(body['accuracy_m'], 8);
    // The server stamp (not now()) anchors the clock.
    expect(c.read(activeJobControllerProvider('b1')).value!.startedAt,
        DateTime.utc(2026, 6, 5, 14, 0, 0));
  });

  test(
      'a 409 NOT_AT_SITE start error is localized to Thai with the distance, and '
      'the booking snapshot is re-pulled', () async {
    var getCount = 0;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') {
          getCount++;
          return bookingJson('b1', 'arrived');
        }
        return const <Map<String, dynamic>>[];
      },
      onPut: (path, _) async {
        throw const ApiException(
          message: 'You are 128 m from the job site (max 50 m)',
          code: 'NOT_AT_SITE',
          statusCode: 409,
        );
      },
    );
    final loc = FakeLocationService();
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      locationServiceProvider.overrideWithValue(loc),
      // Thai default → the localized copy path.
      localeControllerProvider.overrideWith(() => _ThaiLocale()),
    ]);
    addTearDown(c.dispose);
    await c.read(activeJobControllerProvider('b1').future);
    final buildGets =
        getCount; // GETs during build (booking + progress-reports)

    expect(await c.read(activeJobControllerProvider('b1').notifier).start(),
        isFalse);
    final err = c.read(activeJobControllerProvider('b1')).value!.error!;
    expect(err, contains('128'));
    expect(err, contains('50 ม.'));
    expect(err, isNot(contains('job site'))); // not the raw English
    // The 409 handler re-pulled the booking snapshot (best-effort catch-up).
    await Future<void>.delayed(Duration.zero);
    expect(getCount, greaterThan(buildGets));
  });

  test(
      'applyExternalStatus folds ONLY terminals and never over an already-terminal state',
      () async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/b1'
          ? bookingJson('b1', 'en_route')
          : const <Map<String, dynamic>>[],
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);
    await c.read(activeJobControllerProvider('b1').future);
    final ctrl = c.read(activeJobControllerProvider('b1').notifier);
    BookingStatus status() =>
        c.read(activeJobControllerProvider('b1')).value!.booking.status;

    // A non-terminal frame is NOT folded (ordering hazard — corrected by the 409 re-pull instead).
    ctrl.applyExternalStatus(BookingStatus.accepted);
    expect(status(), BookingStatus.enRoute);
    ctrl.applyExternalStatus(BookingStatus.arrived);
    expect(status(), BookingStatus.enRoute);

    // A terminal cancel always folds.
    ctrl.applyExternalStatus(BookingStatus.cancelled);
    expect(status(), BookingStatus.cancelled);

    // Once terminal, a late non-terminal frame (at-least-once redelivery) CANNOT resurrect it.
    ctrl.applyExternalStatus(BookingStatus.arrived);
    expect(status(), BookingStatus.cancelled);
  });

  test(
      'BUG3.2 resumeFromRejectedCompletion: a pending_completion→arrived bounce re-fetches and '
      'lands back in working with startedAt + check-ins preserved', () async {
    // The customer tapped "ให้ทำงานต่อ" (reject completion). The booking-status WS pushes `arrived`;
    // the screen forwards it here. The controller re-pulls the authoritative snapshot (now arrived,
    // work_started_at preserved by the backend) and keeps the client startedAt + completedCheckIns.
    var bookingStatus = 'pending_completion';
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') {
          return bookingJson('b1', bookingStatus,
              workStartedAt: '2026-06-05T14:00:00Z');
        }
        // The start check-in trail (hour 1) → slot 0 done, so on `arrived` the guard is WORKING.
        return [
          {'hour_number': 1, 'created_at': '2026-06-05T14:00:00Z'}
        ];
      },
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
    ]);
    addTearDown(c.dispose);

    final s0 = await c.read(activeJobControllerProvider('b1').future);
    expect(s0.booking.status, BookingStatus.pendingCompletion);
    expect(s0.completedCheckIns, contains(0));
    final startedAt0 = s0.startedAt;
    expect(startedAt0, isNotNull);

    final ctrl = c.read(activeJobControllerProvider('b1').notifier);
    ActiveJobState state() => c.read(activeJobControllerProvider('b1')).value!;

    // The reject bounce: the server now reports `arrived`.
    bookingStatus = 'arrived';
    await ctrl.resumeFromRejectedCompletion();

    // Back in working: status arrived, the anchor + check-ins are intact (timer continues).
    expect(state().booking.status, BookingStatus.arrived);
    expect(state().completedCheckIns, contains(0));
    expect(state().startedAt, startedAt0,
        reason: 'work_started_at is preserved across the reject (never reset)');

    // The booked-duration auto-complete is now SUPPRESSED for this booking: the customer asked the
    // guard to keep working, so the remounted working panel must not instantly re-request
    // completion at the (already-elapsed) booked boundary.
    expect(c.read(workSessionStoreProvider).isAutoCompleteSuppressed('b1'),
        isTrue);

    // Self-gated: called when NOT pending_completion, it is a no-op (no extra re-fetch).
    final getsBefore = api.calls.where((s) => s == 'GET /bookings/b1').length;
    await ctrl.resumeFromRejectedCompletion();
    final getsAfter = api.calls.where((s) => s == 'GET /bookings/b1').length;
    expect(getsAfter, getsBefore, reason: 'no re-fetch once already arrived');
  });
}

/// Forces the Thai locale for the localized-error test.
class _ThaiLocale extends LocaleController {
  @override
  AppLocale build() => AppLocale.th;
}
