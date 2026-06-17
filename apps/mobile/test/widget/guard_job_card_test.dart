import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/features/guard/widgets/job_card.dart';

Booking _booking() => const Booking(
      id: 'b1',
      customerId: 'c1',
      status: BookingStatus.requested,
      address: 'บ้านสีลม',
      hours: 8,
      baseFee: '230.00',
      guardCount: 1,
    );

void main() {
  testWidgets('renders the infoLine slot (e.g. the incoming distance line)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GuardJobCard(
          booking: _booking(),
          isThai: true,
          highlight: true,
          infoLine: const Text('0.8 กม. · ~4 นาที'),
          actions: const Text('ACTIONS'),
        ),
      ),
    ));

    expect(find.text('0.8 กม. · ~4 นาที'), findsOneWidget);
    expect(find.text('บ้านสีลม'), findsOneWidget);
    expect(find.text('ACTIONS'), findsOneWidget);
  });

  testWidgets('no infoLine → the card shows no distance line (omitted)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GuardJobCard(booking: _booking(), isThai: true, highlight: true),
      ),
    ));

    expect(find.textContaining('กม.'), findsNothing);
    expect(find.textContaining('นาที'), findsNothing);
  });
}
