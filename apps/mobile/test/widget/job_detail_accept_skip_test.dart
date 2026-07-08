import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/job_detail_screen.dart';

import '../support/fakes.dart';

Map<String, dynamic> bookingJson(String status) => {
      'id': 'b1',
      'customer_id': 'c1abcdef99',
      'guard_id': null,
      'status': status,
      'address': 'อาคารสำนักงาน สีลม',
      'hours': 8,
      'base_fee': '500.00',
      'guard_count': 1,
      'tip': '0',
    };

GoRouter buildRouter() => GoRouter(
      initialLocation: '/home/guard',
      routes: [
        GoRoute(
          path: '/home/guard',
          builder: (_, __) => const Scaffold(body: Text('GUARD HOME STUB')),
        ),
        GoRoute(
          path: '/guard/job/:id',
          builder: (_, s) =>
              JobDetailScreen(bookingId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/guard/active/:id',
          builder: (_, __) => const Scaffold(body: Text('ACTIVE JOB STUB')),
        ),
      ],
    );

/// The open-job detail reads the booking via [activeJobControllerProvider] (GET /bookings/{id})
/// and accepts via [guardJobsController] (GET /bookings + GET /bookings/open, then POST /accept).
FakeApi apiWith({
  Future<dynamic> Function(String, Object?)? onPost,
}) =>
    FakeApi(
      onGet: (path, _) async {
        if (path == '/bookings/b1') return bookingJson('requested');
        if (path == '/bookings') return <Map<String, dynamic>>[];
        if (path == '/bookings/open') return [bookingJson('requested')];
        return <Map<String, dynamic>>[];
      },
      onPost: onPost,
    );

Future<void> pumpFlow(WidgetTester tester, FakeApi api) async {
  final router = buildRouter();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  // Push the detail over the dashboard so the local SKIP can pop back to it (mirroring the real
  // dashboard → job-detail navigation).
  router.push('/guard/job/b1');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets(
      'Accept → confirm dialog gates POST /accept, then success snackbar + '
      'navigate to the active job', (tester) async {
    final api = apiWith(onPost: (path, _) async {
      expect(path, '/bookings/b1/accept');
      return bookingJson('accepted');
    });
    await pumpFlow(tester, api);

    await tester.tap(find.text('รับงานนี้'));
    await tester.pumpAndSettle();

    // Confirm dialog appears BEFORE any POST.
    expect(find.text('ยืนยันรับงานนี้?'), findsOneWidget);
    expect(api.calls.where((c) => c.startsWith('POST')), isEmpty);

    await tester.tap(find.text('รับงาน'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('POST /bookings/b1/accept'));
    expect(find.text('รับงานสำเร็จ'), findsOneWidget); // success snackbar
    expect(find.text('ACTIVE JOB STUB'), findsOneWidget); // navigated
  });

  testWidgets('Accept → cancel keeps the screen and fires no POST',
      (tester) async {
    final api = apiWith(onPost: (_, __) async => bookingJson('accepted'));
    await pumpFlow(tester, api);

    await tester.tap(find.text('รับงานนี้'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => c.startsWith('POST')), isEmpty);
    expect(find.byType(JobDetailScreen), findsOneWidget);
  });

  testWidgets(
      'Skip (ข้าม) → confirm → SERVER skip (POST /skip) + clarifying snackbar, '
      'pops back', (tester) async {
    final api = apiWith(onPost: (_, __) async => {'skipped': true});
    await pumpFlow(tester, api);

    // The local-skip button is now "ข้าม" (was the misleading "ปฏิเสธ").
    expect(find.text('ข้าม'), findsOneWidget);
    expect(find.text('ปฏิเสธ'), findsNothing);

    await tester.tap(find.text('ข้าม'));
    await tester.pumpAndSettle();

    expect(find.text('ข้ามงานนี้?'), findsOneWidget);

    // The dialog's confirm action is the "ข้าม" inside a TextButton (the footer button is a
    // PgPrimaryButton), so scoping to TextButton disambiguates from the footer trigger.
    await tester.tap(find.widgetWithText(TextButton, 'ข้าม'));
    await tester.pumpAndSettle();

    // Clarifying snackbar — and the skip is now SERVER-TRACKED (POST /bookings/{id}/skip) so it
    // can't reappear on refresh (was purely local before).
    expect(find.textContaining('งานยังเปิดให้เจ้าหน้าที่อื่น'), findsOneWidget);
    expect(api.calls.where((c) => c.contains('/skip')).length, 1);
    expect(find.text('GUARD HOME STUB'), findsOneWidget); // popped back
  });
}
