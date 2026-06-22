import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/controllers/services_controller.dart';
import 'package:pguard_mobile/core/models/service_catalog.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/widgets/service_package_card.dart';
import 'package:pguard_mobile/features/home/customer_home_screen.dart';

import '../support/fakes.dart';

const _catalog = [
  ServiceOption(
    id: 'svc-1',
    nameTh: 'หมู่บ้าน',
    nameEn: 'Village',
    baseFeeSatang: 23000, // ฿230/hr
    minHours: 4,
    description: 'เหมาะกับหมู่บ้านจัดสรร',
  ),
  ServiceOption(
    id: 'svc-2',
    nameTh: 'คอนโด',
    nameEn: 'Condo',
    baseFeeSatang: 25000, // ฿250/hr
    minHours: 6,
  ),
];

/// A [FakeApi] that quietly satisfies the home's incidental fetches (bookings, the notification
/// bell, the chat badge, the profile avatar) so the screen pumps without exploding. The service
/// catalog is supplied via a `servicesProvider` override (below), not through this fake.
FakeApi _quietApi() => FakeApi(
      onGet: (path, _) async {
        switch (path) {
          case '/bookings':
            return <dynamic>[];
          case '/notifications/unread-count':
            return {'count': 0};
          case '/conversations':
            return <dynamic>[];
          case '/auth/me':
            return {'id': 'c1', 'role': 'customer'};
          case '/profile/me':
            return null;
          default:
            return <dynamic>[];
        }
      },
    );

/// The captured `ServiceOption` a `/book/detail` push carried — proves the home card opens the
/// SAME detail destination as the picker, with the tapped package as `extra`.
ServiceOption? _pushedToDetail;

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const CustomerHomeScreen()),
        GoRoute(
          path: '/book/detail',
          builder: (_, s) {
            _pushedToDetail = s.extra as ServiceOption?;
            return const Scaffold(
                body: Text('DETAIL', textDirection: TextDirection.ltr));
          },
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  required Override servicesOverride,
}) async {
  _pushedToDetail = null;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(_quietApi()),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      servicesOverride,
    ],
    child: MaterialApp.router(routerConfig: _router()),
  ));
  // Resolve the async providers (services / bookings / profile / counts).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets(
      'the home "บริการ" section lists a ServicePackageCard per catalog service',
      (tester) async {
    await _pump(tester,
        servicesOverride:
            servicesProvider.overrideWith((ref) async => _catalog));

    // Section title stays "บริการ".
    expect(find.text('บริการ'), findsOneWidget);

    // One package card per fetched service (not the old capped-4 compact tiles).
    expect(find.byType(ServicePackageCard), findsNWidgets(_catalog.length));
    expect(find.text('หมู่บ้าน'), findsOneWidget);
    expect(find.text('คอนโด'), findsOneWidget);
    // The card keeps the picker's ฿/hr + min-hours + description visuals.
    expect(find.text('฿230 /ชม.'), findsOneWidget);
    expect(find.text('เหมาะกับหมู่บ้านจัดสรร'), findsOneWidget);
  });

  testWidgets('tapping a package card pushes /book/detail with that service',
      (tester) async {
    await _pump(tester,
        servicesOverride:
            servicesProvider.overrideWith((ref) async => _catalog));

    await tester.tap(find.text('คอนโด'));
    await tester.pumpAndSettle();

    // Same destination as the two-screen picker, carrying the tapped package.
    expect(find.text('DETAIL'), findsOneWidget);
    expect(_pushedToDetail?.id, 'svc-2');
  });
}
