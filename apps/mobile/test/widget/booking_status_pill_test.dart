import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/widgets/booking_status_pill.dart';

/// #127 shared coloured status pill: the right label + a status-driven palette, with the
/// awaiting-confirmation (`pending_completion`) state emphasised in AMBER so it stands out.
Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

/// The pill's chip background colour (the [Container] decoration fill).
Color _bg(WidgetTester tester) {
  final box = tester.widget<Container>(
    find.descendant(
      of: find.byType(BookingStatusPill),
      matching: find.byType(Container),
    ).first,
  );
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('pending_completion renders the awaiting label in AMBER', (tester) async {
    await tester.pumpWidget(_host(const BookingStatusPill(
        status: BookingStatus.pendingCompletion, isThai: true)));
    expect(find.text('รอยืนยันจบงาน'), findsOneWidget);
    // The case #127 most needs to emphasise → amber chip fill.
    expect(_bg(tester), PgTokens.colorAmber50);
  });

  testWidgets('completed renders green; cancelled renders danger', (tester) async {
    await tester.pumpWidget(_host(const BookingStatusPill(
        status: BookingStatus.completed, isThai: false)));
    expect(find.text('Completed'), findsOneWidget);
    expect(_bg(tester), PgTokens.colorSuccessBg);

    await tester.pumpWidget(_host(const BookingStatusPill(
        status: BookingStatus.cancelled, isThai: false)));
    expect(find.text('Cancelled'), findsOneWidget);
    expect(_bg(tester), PgTokens.colorDangerBg);
  });

  testWidgets('in-flight states render in INFO blue', (tester) async {
    await tester.pumpWidget(_host(const BookingStatusPill(
        status: BookingStatus.enRoute, isThai: false)));
    expect(find.text('On the way'), findsOneWidget);
    expect(_bg(tester), PgTokens.colorInfoBg);
  });
}
