import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/live_status_screen.dart';

import '../support/fakes.dart';

void main() {
  testWidgets(
      'live-status screen renders the snapshot then updates from a WS push',
      (tester) async {
    final feed = FakeBookingFeed();
    final store = InMemoryStore()..access = 'token';
    final api = FakeApi(
        onGet: (_, __) async => {
              'id': 'b1',
              'customer_id': 'c1',
              'status': 'accepted',
              'guard_id': null
            });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(store),
        bookingStatusFeedBuilderProvider
            .overrideWithValue((id, tokenProvider) => feed),
      ],
      child: const MaterialApp(home: LiveStatusScreen(bookingId: 'b1')),
    ));

    // Resolve the initial REST snapshot.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.textContaining('Guard assigned'),
        findsOneWidget); // status = accepted

    // A WebSocket push advances the on-screen status — no polling, no rebuild trigger but the
    // pushed frame.
    feed.emit(BookingStatusEvent(
        bookingId: 'b1',
        status: BookingStatus.arrived,
        occurredAt: DateTime.utc(2026)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.textContaining('Arrived'), findsOneWidget);

    // Exactly one REST GET — proves the screen is push-driven, not polling.
    expect(api.getCount, 1);
  });
}
