import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/active_job_controller.dart';
import 'package:pguard_mobile/core/controllers/guard_jobs_controller.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson(String id, String status) => {
      'id': id,
      'customer_id': 'c1',
      'guard_id': status == 'requested' ? null : 'g1',
      'status': status,
      'address': 'หมู่บ้านลัดดารมย์',
      'scheduled_at': '2026-06-05T14:00:00Z',
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'tip': '0',
      'created_at': '2026-06-05T10:00:00Z',
      'updated_at': '2026-06-05T10:00:00Z',
    };

// A guard session whose user_id matches the bookings' guard_id ('g1'), so the assigned-feed
// role filter (guard_id == me) keeps them.
String _guardJwt() => fakeJwt({
      'sub': 'g1',
      'role': 'guard',
      'exp':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
    });

/// A container whose SESSION is guard `g1` (matching the bookings' `guard_id`), so the assigned-feed
/// filter (`guard_id == me`) keeps them. The store still holds a guard JWT because the API client
/// attaches it, but the controller now reads identity from the SESSION, not the token — see the
/// on-device bug where a null token read emptied the guard's whole job list.
ProviderContainer _guardContainer(FakeApi api) {
  final c = ProviderContainer(overrides: [
    pguardApiProvider.overrideWithValue(api),
    appStoreProvider.overrideWithValue(InMemoryStore()..access = _guardJwt()),
    prefsStoreProvider.overrideWithValue(FakePrefsStore()),
  ]);
  c.read(sessionProvider.notifier).onLoggedIn(
        const AuthUser(userId: 'g1', role: 'guard', roles: ['guard']),
      );
  return c;
}

void main() {
  test(
      'merges assigned (/bookings) + open discovery (/bookings/open) and partitions '
      'incoming from the open feed, active/completed from the assigned feed',
      () async {
    final api = FakeApi(
      onGet: (path, _) async {
        switch (path) {
          case '/bookings':
            return [
              bookingJson('b2', 'accepted'),
              bookingJson('b3', 'completed')
            ];
          case '/bookings/open':
            return [bookingJson('b1', 'requested')];
          default:
            throw StateError('unexpected GET $path');
        }
      },
    );
    final c = _guardContainer(api);
    addTearDown(c.dispose);

    final list = await c.read(guardJobsControllerProvider.future);
    expect(list, hasLength(3));
    expect(GuardJobsController.incoming(list).map((b) => b.id), ['b1'],
        reason: 'incoming = the open-discovery feed (requested, unassigned)');
    expect(GuardJobsController.active(list).map((b) => b.id), ['b2']);
    expect(GuardJobsController.completed(list).map((b) => b.id), ['b3']);
    // Assigned first, then open — both fetched.
    expect(api.calls, ['GET /bookings', 'GET /bookings/open']);
  });

  test(
      'REGRESSION: the guard id comes from the SESSION, not a re-read of the token — a job the '
      'guard is assigned to must still show even if the stored token is momentarily unreadable',
      () async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings'
          ? [bookingJson('b2', 'arrived'), bookingJson('b3', 'completed')]
          : const <Map<String, dynamic>>[],
    );
    // Store has NO token (the exact null-read that used to empty the whole list); the session is
    // still a valid guard `g1`. The assigned jobs must survive.
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ]);
    addTearDown(c.dispose);
    c.read(sessionProvider.notifier).onLoggedIn(
          const AuthUser(userId: 'g1', role: 'guard', roles: ['guard']),
        );

    final list = await c.read(guardJobsControllerProvider.future);
    expect(GuardJobsController.active(list).map((b) => b.id), ['b2'],
        reason: 'the arrived job the guard is working must appear');
    expect(GuardJobsController.completed(list).map((b) => b.id), ['b3'],
        reason: 'the completed job (feeds today-earnings) must appear');
  });

  test('no session user → assigned feed is empty (fail closed, no leak)',
      () async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings'
          ? [bookingJson('b2', 'arrived')]
          : const <Map<String, dynamic>>[],
    );
    // Authenticated-guard container but the session user is never set → me == null.
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = _guardJwt()),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ]);
    addTearDown(c.dispose);

    final list = await c.read(guardJobsControllerProvider.future);
    expect(list, isEmpty,
        reason:
            'no resolvable identity → never fall through to the unfiltered OR-list');
  });

  test(
      'a pending_completion job (guard requested completion) stays in the ACTIVE '
      'tab — not lost from in-progress and not yet in Done', () async {
    // After PUT /complete the booking is `pending_completion` in the guard's assigned feed; it must
    // remain visible in the Active tab (awaiting the customer) and NOT vanish, nor jump to Done.
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings'
          ? [bookingJson('b9', 'pending_completion')]
          : const <Map<String, dynamic>>[],
    );
    final c = _guardContainer(api);
    addTearDown(c.dispose);

    final list = await c.read(guardJobsControllerProvider.future);
    expect(GuardJobsController.active(list).map((b) => b.id), ['b9'],
        reason: 'pending_completion belongs to the in-progress (Active) tab');
    expect(GuardJobsController.completed(list), isEmpty,
        reason: 'not completed until the CUSTOMER confirms');
    expect(GuardJobsController.incoming(list), isEmpty);

    final b = list.single;
    expect(
        GuardJobsController.statusBadge(b, isThai: true), 'รอลูกค้ายืนยันจบงาน',
        reason: 'the card must label the awaiting-confirmation state');
    expect(GuardJobsController.statusBadge(b, isThai: false),
        'Awaiting customer confirmation');
    expect(GuardJobsController.opensReadOnly(b), isTrue,
        reason: 'the guard can\'t re-end it → opens the read-only status view');
  });

  test(
      'a normal in-progress job carries no status badge and opens the working '
      'active screen (not read-only)', () async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings'
          ? [bookingJson('b1', 'en_route')]
          : const <Map<String, dynamic>>[],
    );
    final c = _guardContainer(api);
    addTearDown(c.dispose);

    final b = (await c.read(guardJobsControllerProvider.future)).single;
    expect(GuardJobsController.statusBadge(b, isThai: true), isNull);
    expect(GuardJobsController.opensReadOnly(b), isFalse);
  });

  test(
      'the two feeds are fetched CONCURRENTLY (perf #2) — both fire before either resolves',
      () async {
    final order = <String>[];
    final api = FakeApi(onGet: (path, _) async {
      order.add('start $path');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      order.add('end $path');
      return path == '/bookings'
          ? [bookingJson('b2', 'accepted')]
          : [bookingJson('b1', 'requested')];
    });
    final c = _guardContainer(api);
    addTearDown(c.dispose);
    await c.read(guardJobsControllerProvider.future);
    // Both requests STARTED before either finished — proof they overlapped rather than serialized.
    expect(order.take(2).toSet(), {'start /bookings', 'start /bookings/open'},
        reason: 'assigned + open fire concurrently, not one-after-the-other');
  });

  test(
      'a malformed (non-list) open feed degrades to assigned-only, never errors',
      () async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings'
          ? [bookingJson('b2', 'accepted')]
          : <String, dynamic>{'unexpected': 'shape'}, // not a List
    );
    final c = _guardContainer(api);
    addTearDown(c.dispose);
    final list = await c.read(guardJobsControllerProvider.future);
    expect(list.map((b) => b.id), ['b2'],
        reason: 'a malformed open feed must not error the whole load');
    expect(GuardJobsController.incoming(list), isEmpty);
  });

  test('open-feed failure degrades to assigned-only (no throw, incoming empty)',
      () async {
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings') return [bookingJson('b2', 'accepted')];
        throw const ApiException(
            message: 'discovery down', code: 'UNAVAILABLE', statusCode: 503);
      },
    );
    final c = _guardContainer(api);
    addTearDown(c.dispose);

    final list = await c.read(guardJobsControllerProvider.future);
    expect(list.map((b) => b.id), ['b2'],
        reason: 'a discovery hiccup must NOT blank the guard\'s assigned jobs');
    expect(GuardJobsController.incoming(list), isEmpty);
  });

  test('accept POSTs the correct path (claiming an open job)', () async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/open'
          ? [bookingJson('b1', 'requested')]
          : const [],
      onPost: (path, _) async {
        expect(path, '/bookings/b1/accept');
        return bookingJson('b1', 'accepted');
      },
    );
    final c = _guardContainer(api);
    addTearDown(c.dispose);
    await c.read(guardJobsControllerProvider.future);

    expect(await c.read(guardJobsControllerProvider.notifier).accept('b1'),
        isNull); // null = success
    expect(api.calls, contains('POST /bookings/b1/accept'));
  });

  test(
      'dismiss SKIPS an offer server-side (POST /skip) → stays gone on refresh',
      () async {
    final skipped = <String>{}; // the server-side per-guard skip set
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/open'
          ? [bookingJson('b1', 'requested'), bookingJson('b2', 'requested')]
              .where((b) => !skipped.contains(b['id'] as String))
              .toList()
          : const [],
      // POST /bookings/{id}/skip — discovery excludes it for this guard thereafter.
      onPost: (path, _) async {
        skipped.add(path.split('/')[2]);
        return {'skipped': true};
      },
    );
    final c = _guardContainer(api);
    addTearDown(c.dispose);
    await c.read(guardJobsControllerProvider.future);

    final err =
        await c.read(guardJobsControllerProvider.notifier).dismiss('b1');
    expect(err, isNull);
    // The skip hit the server, and the re-fetch (which the fake now filters) keeps b1 gone.
    expect(api.calls, contains('POST /bookings/b1/skip'));
    expect(c.read(guardJobsControllerProvider).value!.map((b) => b.id), ['b2']);
  });

  test(
      'accept invalidates the booking\'s active-job provider → it re-fetches the '
      'fresh accepted snapshot (no stale "requested" on the active screen)',
      () async {
    // The server flips the booking requested → accepted at the moment of accept; the
    // active-job re-read after accept must see `accepted`.
    var accepted = false;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/open') {
          return accepted ? const [] : [bookingJson('b1', 'requested')];
        }
        if (path == '/bookings/b1') {
          return bookingJson('b1', accepted ? 'accepted' : 'requested');
        }
        // /bookings (assigned) + /bookings/b1/progress-reports
        return const [];
      },
      onPost: (path, _) async {
        expect(path, '/bookings/b1/accept');
        accepted = true;
        return bookingJson('b1', 'accepted');
      },
    );
    final c = _guardContainer(api);
    addTearDown(c.dispose);

    // The detail screen reads the active-job provider FIRST, while the booking is still
    // `requested` — mirror that by listening (so the value is cached/built before accept).
    final aSub = c.listen(activeJobControllerProvider('b1'), (_, __) {});
    addTearDown(aSub.close);
    final before = await c.read(activeJobControllerProvider('b1').future);
    expect(before.booking.status, BookingStatus.requested);

    await c.read(guardJobsControllerProvider.future);
    expect(await c.read(guardJobsControllerProvider.notifier).accept('b1'),
        isNull); // null = success

    // The accept invalidated activeJobControllerProvider('b1'); the still-listened instance
    // re-fetches and now reflects the accepted snapshot — NOT the cached `requested` one.
    final after = await c.read(activeJobControllerProvider('b1').future);
    expect(after.booking.status, BookingStatus.accepted,
        reason:
            'the active screen the guard navigates to builds fresh, not stale');
  });

  test(
      'active() EXCLUDES terminal jobs (cancelled/completed/declined) so a job the '
      'customer cancelled never lingers in the Active tab and traps the guard',
      () async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings'
          ? [
              bookingJson('b1', 'accepted'),
              bookingJson('b2', 'cancelled'),
              bookingJson('b3', 'declined'),
              bookingJson('b4', 'completed'),
            ]
          : const <Map<String, dynamic>>[],
    );
    final c = _guardContainer(api);
    addTearDown(c.dispose);

    final list = await c.read(guardJobsControllerProvider.future);
    expect(GuardJobsController.active(list).map((b) => b.id), ['b1'],
        reason:
            'only the in-progress job; cancelled/declined/completed are excluded');
    expect(GuardJobsController.completed(list).map((b) => b.id), ['b4']);
  });

  test(
      'refresh() SWALLOWS a rebuild failure — never rethrows into RefreshIndicator / '
      'onRetry (offline pull-to-refresh)', () async {
    var bookingsCalls = 0;
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings') {
          bookingsCalls++;
          // First build succeeds; the refresh re-fetch is offline (transport failure).
          if (bookingsCalls >= 2) {
            throw const ApiException(message: 'Network error');
          }
          return [bookingJson('b2', 'accepted')];
        }
        return const <Map<String, dynamic>>[];
      },
    );
    final c = _guardContainer(api);
    addTearDown(c.dispose);
    await c.read(guardJobsControllerProvider.future);

    // Must complete normally (null), NOT throw an unhandled async error.
    final result = await c.read(guardJobsControllerProvider.notifier).refresh();
    expect(result, isNull);
    expect(c.read(guardJobsControllerProvider).hasError, isTrue,
        reason: 'the error is carried in provider state for the UI to render');
  });

  test('accept surfaces the server error message (and does not throw)',
      () async {
    final api = FakeApi(
      onGet: (path, _) async => path == '/bookings/open'
          ? [bookingJson('b1', 'requested')]
          : const [],
      onPost: (_, __) async => throw const ApiException(
          message: 'Already taken', code: 'CONFLICT', statusCode: 409),
    );
    final c = _guardContainer(api);
    addTearDown(c.dispose);
    await c.read(guardJobsControllerProvider.future);
    final err = await c.read(guardJobsControllerProvider.notifier).accept('b1');
    expect(err, 'Already taken');
  });
}
