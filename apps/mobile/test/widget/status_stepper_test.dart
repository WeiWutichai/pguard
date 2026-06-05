import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/widgets/pin_dots.dart';
import 'package:pguard_mobile/widgets/status_stepper.dart';

void main() {
  testWidgets('BookingStatusStepper shows the current status label (TH · EN)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BookingStatusStepper(status: BookingStatus.enRoute)),
    ));
    expect(find.textContaining('On the way'), findsOneWidget);
    expect(find.textContaining(BookingLifecycle.labelTh(BookingStatus.enRoute)),
        findsOneWidget);
  });

  testWidgets('PinDots renders one dot per slot', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PinDots(length: 6, filled: 3)),
    ));
    // 6 dot containers inside the row.
    expect(find.byType(Container), findsNWidgets(6));
  });
}
