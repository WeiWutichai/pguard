import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/controllers/booking_flow_controller.dart';
import 'package:pguard_mobile/core/models/available_guard.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/guard_discovery_screen.dart';
import 'package:pguard_mobile/widgets/primary_button.dart';

import '../support/fakes.dart';

/// Sub-item 3: the "ยืนยันการจอง / Confirm booking" button must be GATED on a guard selection —
/// disabled until the customer radio-selects a guard (the first-come preference). These tests
/// drive the real screen against a FakeApi that returns two guards, then assert the confirm
/// button's enabled state flips only after a selection.
void main() {
  List<Map<String, dynamic>> guardsJson() => [
        {
          'guard_id': 'guard-aaaa-1111',
          'display_name': 'สมชาย มั่นคง',
          'years_of_experience': 6,
          'average_rating': '4.90',
          'review_count': 188,
        },
        {
          'guard_id': 'guard-bbbb-2222',
          'years_of_experience': null,
          'average_rating': null,
          'review_count': 0,
        },
      ];

  Future<ProviderContainer> pumpScreen(WidgetTester tester, FakeApi api) async {
    final container = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      // C2: loadGuards now resolves a meetup coordinate — falling back to the DEVICE location when no
      // pin was dropped. This screen never pins one, so give it a fake with NO fix (deterministic: no
      // native geolocator channel in a widget test); the fake API returns the list + distance_m
      // regardless of the query.
      locationServiceProvider
          .overrideWithValue(FakeLocationService()..current = null),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GuardDiscoveryScreen()),
    ));
    // Let initState's loadGuards() microtask + the fake GET resolve.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    return container;
  }

  PgPrimaryButton confirmButton(WidgetTester tester) =>
      tester.widget<PgPrimaryButton>(find.byType(PgPrimaryButton));

  testWidgets('confirm is DISABLED until a guard is selected, then ENABLED',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      expect(path, '/available-guards');
      return guardsJson();
    });
    final container = await pumpScreen(tester, api);

    // Guards loaded, none selected → confirm disabled (onPressed == null) + the hint is shown.
    expect(container.read(bookingFlowControllerProvider).guards.length, 2);
    expect(confirmButton(tester).onPressed, isNull);
    expect(find.text('เลือกเจ้าหน้าที่ที่ต้องการก่อน'), findsOneWidget);

    // Select a guard (first-come preference) → confirm enabled + the hint clears.
    container
        .read(bookingFlowControllerProvider.notifier)
        .selectGuard('guard-aaaa-1111');
    await tester.pump();

    expect(confirmButton(tester).onPressed, isNotNull);
    expect(find.text('เลือกเจ้าหน้าที่ที่ต้องการก่อน'), findsNothing);
  });

  testWidgets('selecting via the radio card enables confirm', (tester) async {
    final api = FakeApi(onGet: (_, __) async => guardsJson());
    final container = await pumpScreen(tester, api);

    expect(confirmButton(tester).onPressed, isNull);

    // Tap the first guard's name (card body radio-selects).
    await tester.tap(find.text('สมชาย มั่นคง'));
    await tester.pump();

    expect(
      container.read(bookingFlowControllerProvider).selectedGuardId,
      'guard-aaaa-1111',
    );
    expect(confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets(
      'C2: renders the nearest-first distance caption when the server sends distance_m',
      (tester) async {
    final api = FakeApi(onGet: (path, _) async {
      expect(path, '/available-guards');
      // Server returns the list already sorted nearest-first, each with a distance.
      return [
        {
          'guard_id': 'near',
          'display_name': 'ก ใกล้',
          'review_count': 2,
          'distance_m': 350.0,
        },
        {
          'guard_id': 'far',
          'display_name': 'ข ไกล',
          'review_count': 1,
          'distance_m': 4200.0,
        },
      ];
    });
    await pumpScreen(tester, api);
    // Each guard shows an approximate distance caption (the `~`) with localized units.
    expect(find.textContaining('ห่าง ~350 ม.'), findsOneWidget);
    expect(find.textContaining('ห่าง ~4.2 กม.'), findsOneWidget);
  });

  testWidgets('C2: no distance caption when the server omits distance_m',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => guardsJson()); // no distance_m
    await pumpScreen(tester, api);
    expect(find.textContaining('ห่าง'), findsNothing);
  });

  testWidgets(
      'DIRECTED OFFER: confirming after picking a guard sends it as target_guard_id',
      (tester) async {
    Map<String, dynamic>? postBody;
    final api = FakeApi(
      onGet: (_, __) async => guardsJson(),
      onPost: (path, data) async {
        expect(path, '/bookings');
        postBody = data as Map<String, dynamic>;
        return {
          'id': 'bk-directed-1',
          'customer_id': 'c1',
          'guard_id': null,
          'status': 'requested',
          'address': postBody!['address'],
          'scheduled_at': postBody!['scheduled_at'],
          'hours': postBody!['hours'],
          'base_fee': '500.00',
          'guard_count': postBody!['guard_count'],
          'tip': postBody!['tip'] ?? '0',
          'target_guard_id': postBody!['target_guard_id'],
          'created_at': '2026-06-05T10:00:00Z',
          'updated_at': '2026-06-05T10:00:00Z',
        };
      },
    );

    final container = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      // C2: loadGuards now resolves a meetup coordinate — falling back to the DEVICE location when no
      // pin was dropped. This screen never pins one, so give it a fake with NO fix (deterministic: no
      // native geolocator channel in a widget test); the fake API returns the list + distance_m
      // regardless of the query.
      locationServiceProvider
          .overrideWithValue(FakeLocationService()..current = null),
    ]);
    addTearDown(container.dispose);

    // The screen's confirm navigates (go home → push live); give it a real router with stub
    // destinations so the tap-through doesn't throw on `context.go`/`context.push`.
    final router = GoRouter(
      initialLocation: '/discovery',
      routes: [
        GoRoute(
            path: '/discovery',
            builder: (_, __) => const GuardDiscoveryScreen()),
        GoRoute(
            path: '/home/customer',
            builder: (_, __) => const Scaffold(body: Text('home'))),
        GoRoute(
            path: '/booking/:id/live',
            builder: (_, __) => const Scaffold(body: Text('live'))),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // An address + start/end must exist for a valid create (the form step normally sets these).
    container.read(bookingFlowControllerProvider.notifier)
      ..setAddress('123 ลัดดารมย์ ซ.5')
      ..setStart(DateTime.utc(2026, 6, 6, 14))
      ..setEnd(DateTime.utc(2026, 6, 6, 22));

    // Pick the first guard via its card, then confirm.
    await tester.tap(find.text('สมชาย มั่นคง'));
    await tester.pump();
    await tester.tap(find.byType(PgPrimaryButton));
    await tester.pumpAndSettle();

    // The create call carried the picked guard as the directed-offer target.
    expect(postBody, isNotNull);
    expect(postBody!['target_guard_id'], 'guard-aaaa-1111');
  });

  testWidgets(
      'a guard who comes online APPEARS via the light periodic refresh — no app '
      'restart (deep-review: keepAlive discovery state was stale)',
      (tester) async {
    var guards = <Map<String, dynamic>>[]; // none online at first
    final api = FakeApi(onGet: (path, _) async {
      expect(path, '/available-guards');
      return guards;
    });
    await pumpScreen(tester, api);
    // Empty state: the just-arrived guard is not shown yet.
    expect(find.text('สมชาย มั่นคง'), findsNothing);

    // A guard comes online. The screen's ~25s visibility refresh must surface them WITHOUT a
    // manual pull or an app restart (the keepAlive flow controller otherwise kept a stale list).
    guards = guardsJson();
    await tester.pump(const Duration(seconds: 25)); // fire the periodic refresh
    await tester.pump(); // resolve refreshGuards
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('สมชาย มั่นคง'), findsOneWidget,
        reason: 'the discovery list refreshes while the screen is visible');
  });

  testWidgets('pull-to-refresh re-pulls available-guards from the empty state',
      (tester) async {
    var guards = <Map<String, dynamic>>[];
    final api = FakeApi(onGet: (_, __) async => guards);
    await pumpScreen(tester, api);
    expect(find.text('สมชาย มั่นคง'), findsNothing);

    guards = guardsJson();
    // Drag down on the scrollable empty state to trigger the RefreshIndicator.
    await tester.fling(find.text('ยังไม่มีเจ้าหน้าที่ว่างในขณะนี้'),
        const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(find.text('สมชาย มั่นคง'), findsOneWidget,
        reason: 'pull-to-refresh brings in the newly-available guard');
  });

  test('AvailableGuard.displayLabel prefers the real name, else the id handle',
      () {
    const named = AvailableGuard(
      guardId: 'guard-aaaa-1111',
      displayName: 'สมหญิง ใจดี',
      reviewCount: 3,
    );
    const anon = AvailableGuard(guardId: 'guard-bbbb-2222', reviewCount: 0);
    expect(named.displayLabel(true), 'สมหญิง ใจดี');
    expect(anon.displayLabel(true), 'เจ้าหน้าที่ #GUAR');
    expect(anon.displayLabel(false), 'Guard #GUAR');
    // Initials: first grapheme of the name; id handle when anonymous.
    expect(named.avatarInitials, 'ส');
    expect(anon.avatarInitials, 'GUAR');
  });
}
