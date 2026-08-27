import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/guard/guard_jobs_screen.dart';
import 'package:pguard_mobile/features/guard/widgets/job_card.dart';
import 'package:pguard_mobile/widgets/pg_skeleton.dart';

import '../support/fakes.dart';

Map<String, dynamic> _bookingJson(String id, String status) => {
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

void main() {
  testWidgets(
      'PgSkeletonList renders the requested number of placeholder cards',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PgSkeletonList(count: 4)),
    ));
    expect(find.byType(PgSkeletonCard), findsNWidgets(4));
    // The skeleton is deliberately static — never a spinner.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'guard jobs screen shows a SKELETON (not a full-screen spinner) while loading, '
      'then the last-known data (perf-review #1)', (tester) async {
    final gate = Completer<List<Map<String, dynamic>>>();
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/bookings') return gate.future;
      return const <Map<String, dynamic>>[]; // /bookings/open (best-effort)
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        // The jobs controller scopes by the SESSION user id.
        seededGuardSession(),
      ],
      child: const MaterialApp(home: GuardJobsScreen()),
    ));
    await tester.pump(); // build starts; the controller is loading (feed gated)

    // LOADING → the screen's SHAPE renders (skeleton list), never a bare centered spinner.
    expect(find.byType(PgSkeletonList), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Feed resolves → the skeleton is replaced by the real job card.
    gate.complete([_bookingJson('b1', 'accepted')]);
    await tester.pump();
    await tester.pump();

    expect(find.byType(PgSkeletonList), findsNothing);
    expect(find.byType(GuardJobCard), findsOneWidget);
  });
}
