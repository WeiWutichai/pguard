import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/help/help_screen.dart';

import '../support/fakes.dart';

Widget _host() => ProviderScope(
      overrides: [prefsStoreProvider.overrideWithValue(FakePrefsStore())],
      child: const MaterialApp(home: HelpScreen()),
    );

void main() {
  testWidgets('renders all 3 FAQ questions, the open first answer + contact rows',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('จองเจ้าหน้าที่อย่างไร?'), findsOneWidget);
    expect(find.text('การชำระเงินและคืนเงิน'), findsOneWidget);
    expect(find.text('ความปลอดภัยและความเป็นส่วนตัว'), findsOneWidget);
    // First item open by default → its answer is visible.
    expect(find.textContaining('เลือกบริการ → ปักหมุดตำแหน่ง'), findsOneWidget);
    // Contact rows + the (config) support phone, shown as honest text.
    expect(find.text('โทรหาฝ่ายสนับสนุน'), findsOneWidget);
    expect(find.textContaining('02-123-4567'), findsOneWidget);
    expect(find.text('แชตกับแอดมิน'), findsOneWidget);
    expect(find.text('แจ้งปัญหา / ส่งความเห็น'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('search filters the FAQ list to matching questions only',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ชำระ');
    await tester.pump();

    expect(find.text('การชำระเงินและคืนเงิน'), findsOneWidget);
    expect(find.text('จองเจ้าหน้าที่อย่างไร?'), findsNothing);
    expect(find.text('ความปลอดภัยและความเป็นส่วนตัว'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
