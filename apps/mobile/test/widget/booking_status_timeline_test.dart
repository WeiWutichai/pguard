import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/widgets/booking_status_timeline.dart';

/// #123 shared status timeline: verifies the step set renders and that the
/// done/current logic ticks the right number of steps for each status.
Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// Count of rendered check ticks (a step is "done" when ticked).
int _ticks(WidgetTester tester) => tester
    .widgetList<Icon>(find.byType(Icon))
    .where((i) => i.icon == Icons.check)
    .length;

void main() {
  testWidgets('renders all five EN steps once a guard is assigned (accepted)',
      (tester) async {
    await tester.pumpWidget(_host(const BookingStatusTimeline(
        status: BookingStatus.accepted, isThai: false)));

    for (final label in ['Accepted', 'En route', 'Arrived', 'Working', 'Completed']) {
      expect(find.text(label), findsOneWidget);
    }
    // On "accepted" the first step is CURRENT (not done) → zero ticks yet.
    expect(_ticks(tester), 0);
  });

  testWidgets('en_route ticks the Accepted step, highlights En route',
      (tester) async {
    await tester.pumpWidget(_host(const BookingStatusTimeline(
        status: BookingStatus.enRoute, isThai: false)));
    // Accepted is behind the current step → 1 tick.
    expect(_ticks(tester), 1);
  });

  testWidgets('arrived without started keeps Working pending (2 ticks)',
      (tester) async {
    await tester.pumpWidget(_host(const BookingStatusTimeline(
        status: BookingStatus.arrived, isThai: false)));
    // Accepted + En route done; Arrived is current; Working/Completed pending.
    expect(_ticks(tester), 2);
  });

  testWidgets('arrived WITH started advances the current step to Working',
      (tester) async {
    await tester.pumpWidget(_host(const BookingStatusTimeline(
        status: BookingStatus.arrived, isThai: false, started: true)));
    // Accepted + En route + Arrived done; Working is current.
    expect(_ticks(tester), 3);
  });

  testWidgets('completed ticks every step', (tester) async {
    await tester.pumpWidget(_host(const BookingStatusTimeline(
        status: BookingStatus.completed, isThai: false)));
    expect(_ticks(tester), 5);
  });

  testWidgets('cancelled collapses to one red terminal row (a close icon)',
      (tester) async {
    await tester.pumpWidget(_host(const BookingStatusTimeline(
        status: BookingStatus.cancelled, isThai: false)));
    // Not the happy path: a single close-marked terminal row, no step checks.
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(_ticks(tester), 0);
    expect(find.text('Accepted'), findsNothing);
  });

  testWidgets('renders Thai step labels when isThai', (tester) async {
    await tester.pumpWidget(_host(const BookingStatusTimeline(
        status: BookingStatus.accepted, isThai: true)));
    for (final label in ['เริ่มรับงาน', 'กำลังเดินทาง', 'ถึงจุดนัด', 'กำลังปฏิบัติงาน', 'เสร็จงาน']) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
