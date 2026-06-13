import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';
import 'package:pguard_mobile/widgets/pg_bottom_nav.dart';

Widget _host(PgBottomNav nav) => MaterialApp(
      home: Scaffold(body: const SizedBox.expand(), bottomNavigationBar: nav),
    );

List<PgNavTab> _tabs({
  VoidCallback? onSecond,
  VoidCallback? onFourth,
  int secondBadge = 0,
}) =>
    [
      const PgNavTab(
          icon: Icons.home_outlined, label: 'หน้าหลัก', active: true),
      PgNavTab(
          icon: Icons.inbox_outlined,
          label: 'งาน',
          badgeCount: secondBadge,
          onTap: onSecond),
      const PgNavTab(icon: Icons.payments_outlined, label: 'รายได้'),
      PgNavTab(icon: Icons.person_outline, label: 'โปรไฟล์', onTap: onFourth),
    ];

Container _fabCircle(WidgetTester tester, IconData icon) =>
    tester.widget<Container>(find
        .ancestor(of: find.byIcon(icon), matching: find.byType(Container))
        .first);

void main() {
  testWidgets('renders 4 tab labels + FAB label with active/inactive colors',
      (tester) async {
    await tester.pumpWidget(_host(PgBottomNav(
      tabs: _tabs(),
      fab: PgNavFab.book(label: 'เรียก รปภ.', onTap: () {}),
    )));

    for (final label in [
      'หน้าหลัก',
      'งาน',
      'รายได้',
      'โปรไฟล์',
      'เรียก รปภ.',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    final active = tester.widget<Text>(find.text('หน้าหลัก'));
    expect(active.style?.color, PgTokens.colorPrimary);
    final inactive = tester.widget<Text>(find.text('งาน'));
    expect(inactive.style?.color, PgTokens.colorTextFaint);
    // FAB label: 9px w600 amber-700.
    final fabLabel = tester.widget<Text>(find.text('เรียก รปภ.'));
    expect(fabLabel.style?.color, PgTokens.colorAmber700);
    expect(fabLabel.style?.fontSize, 9);
  });

  testWidgets('badge shows the count when > 0 and is absent at 0',
      (tester) async {
    await tester.pumpWidget(_host(PgBottomNav(
      tabs: _tabs(secondBadge: 2),
      fab: PgNavFab.book(label: 'เรียก รปภ.', onTap: () {}),
    )));
    expect(find.text('2'), findsOneWidget);

    await tester.pumpWidget(_host(PgBottomNav(
      tabs: _tabs(),
      fab: PgNavFab.book(label: 'เรียก รปภ.', onTap: () {}),
    )));
    expect(find.text('2'), findsNothing);
  });

  testWidgets('tab taps and FAB tap fire their callbacks', (tester) async {
    var jobs = 0;
    var profile = 0;
    var booked = 0;
    await tester.pumpWidget(_host(PgBottomNav(
      tabs: _tabs(onSecond: () => jobs++, onFourth: () => profile++),
      fab: PgNavFab.book(label: 'เรียก รปภ.', onTap: () => booked++),
    )));

    await tester.tap(find.text('งาน'));
    await tester.tap(find.text('โปรไฟล์'));
    // The FAB centre sits just inside the bar's bounds (62px circle, -30 overhang).
    await tester.tap(find.byIcon(Icons.shield_outlined));
    expect(jobs, 1);
    expect(profile, 1);
    expect(booked, 1);
  });

  testWidgets('duty FAB states: on-duty amber gradient · offline sunken+border',
      (tester) async {
    await tester.pumpWidget(_host(PgBottomNav(
      tabs: _tabs(),
      fab: PgNavFab.onDuty(label: 'พร้อมรับงาน', onTap: () {}),
    )));
    final onDuty = _fabCircle(tester, Icons.verified_user_outlined).decoration!
        as BoxDecoration;
    expect(onDuty.gradient, isA<LinearGradient>());
    // Design 150deg amber-400 → amber-600 (exact tokens since the full-ramp regen).
    expect((onDuty.gradient! as LinearGradient).colors,
        [PgTokens.colorAmber400, PgTokens.colorAmber600]);
    expect(find.text('พร้อมรับงาน'), findsOneWidget);

    await tester.pumpWidget(_host(PgBottomNav(
      tabs: _tabs(),
      fab: PgNavFab.offline(label: 'ออฟไลน์', onTap: () {}),
    )));
    final offline =
        _fabCircle(tester, Icons.shield_outlined).decoration! as BoxDecoration;
    expect(offline.color, PgTokens.colorSunken);
    expect(
        offline.border,
        const Border.fromBorderSide(
            BorderSide(color: PgTokens.colorBorder, width: 2)));
    expect(find.text('ออฟไลน์'), findsOneWidget);
  });

  testWidgets('coming-soon helper shows the SnackBar', (tester) async {
    await tester.pumpWidget(_host(PgBottomNav(
      tabs: _tabs(),
      fab: PgNavFab.book(label: 'เรียก รปภ.', onTap: () {}),
    )));
    final context = tester.element(find.text('งาน'));
    PgBottomNav.comingSoon(context, isThai: true);
    await tester.pump();
    expect(find.text('เร็วๆ นี้'), findsOneWidget);
  });
}
