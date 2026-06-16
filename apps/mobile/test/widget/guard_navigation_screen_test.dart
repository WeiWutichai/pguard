import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/models/geo.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/guard_navigation_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> _bookingJson(String status) => {
      'id': 'b1',
      'customer_id': 'c1',
      'guard_id': 'g1',
      'status': status,
      'address': 'หมู่บ้านลัดดารมย์ ซ.5',
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'lat': 13.7501,
      'lng': 100.5001,
      'tip': '0',
      'created_at': '2026-06-16T00:00:00Z',
      'updated_at': '2026-06-16T00:00:00Z',
    };

Future<void> _pump(WidgetTester tester, FakeApi api, GeoPoint? self) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      guardSelfLocationProvider.overrideWith((ref) async => self),
    ],
    child: const MaterialApp(home: GuardNavigationScreen(bookingId: 'b1')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows approximate distance·ETA + address + the combined CTA',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => _bookingJson('en_route'));
    // ~1.1 km north of the destination.
    await _pump(tester, api, const GeoPoint(13.7600, 100.5001));

    expect(find.textContaining('นาที'), findsOneWidget); // the ~ETA on the sheet
    expect(find.textContaining('หมู่บ้านลัดดารมย์'), findsOneWidget);
    expect(find.text('ถึงจุดนัดแล้ว — เริ่มงาน'), findsOneWidget);
  });

  testWidgets('degrades to address-only when there is no GPS fix (no distance)',
      (tester) async {
    final api = FakeApi(onGet: (_, __) async => _bookingJson('en_route'));
    await _pump(tester, api, null); // no self position

    expect(find.textContaining('นาที'), findsNothing); // no fabricated ETA
    expect(find.text('ถึงจุดนัดแล้ว — เริ่มงาน'), findsOneWidget);
    expect(find.textContaining('หมู่บ้านลัดดารมย์'), findsOneWidget);
  });

  testWidgets('the combined CTA marks arrived then starts the job',
      (tester) async {
    final api = FakeApi(
      onGet: (_, __) async => _bookingJson('en_route'),
      onPut: (path, _) async {
        if (path == '/bookings/b1/arrived') return _bookingJson('arrived');
        if (path == '/bookings/b1/start') return _bookingJson('arrived');
        throw StateError('unexpected PUT $path');
      },
    );
    final router = GoRouter(initialLocation: '/start', routes: [
      GoRoute(
        path: '/start',
        builder: (context, __) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => context.push('/nav'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/nav',
        builder: (_, __) => const GuardNavigationScreen(bookingId: 'b1'),
      ),
    ]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        guardSelfLocationProvider
            .overrideWith((ref) async => const GeoPoint(13.76, 100.50)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ถึงจุดนัดแล้ว — เริ่มงาน'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('PUT /bookings/b1/arrived'));
    expect(api.calls, contains('PUT /bookings/b1/start'));
    // Returned to the previous screen after arrive+start.
    expect(find.text('go'), findsOneWidget);
  });
}
