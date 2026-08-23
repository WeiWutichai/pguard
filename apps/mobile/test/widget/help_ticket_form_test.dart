import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/help/help_screen.dart';

import '../support/fakes.dart';

/// The Help page is now a single support-ticket form (H1): a problem/feedback toggle + a message
/// field + Send → `POST /support/tickets`. These tests drive the form through a [FakeApi] and
/// assert the exact posted body, plus the success + error states.
void main() {
  /// Pump the Help screen with [api] wired in. A plain MaterialApp is enough — the header's back
  /// button uses `Navigator.maybePop()` (no router needed).
  Future<void> pumpHelp(WidgetTester tester, FakeApi api) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      ],
      child: const MaterialApp(home: HelpScreen()),
    ));
    await tester.pump();
  }

  testWidgets(
      'submit posts the right body { kind: problem, message } and shows success',
      (tester) async {
    Object? postedBody;
    final api = FakeApi(
      onPost: (path, data) async {
        postedBody = data;
        return {
          'id': 't1',
          'user_id': 'u1',
          'kind': 'problem',
          'message': 'แอปค้าง',
          'status': 'open',
          'created_at': '2026-08-23T00:00:00Z',
        };
      },
    );
    await pumpHelp(tester, api);

    // Default toggle is "problem"; type a message and Send.
    await tester.enterText(find.byType(TextField), 'แอปค้าง');
    await tester.tap(find.text('ส่ง'));
    await tester.pump(); // kick the async submit
    await tester.pump(); // settle the setState → success panel

    // Exactly one POST, to the tickets endpoint, with the wire body.
    expect(api.calls, ['POST /support/tickets']);
    expect(postedBody, {'kind': 'problem', 'message': 'แอปค้าง'});

    // The success panel replaced the form (no double-file).
    expect(find.text('ส่งเรียบร้อยแล้ว'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('choosing the feedback toggle posts kind: feedback',
      (tester) async {
    Object? postedBody;
    final api = FakeApi(
      onPost: (path, data) async {
        postedBody = data;
        return {
          'id': 't2',
          'user_id': 'u1',
          'kind': 'feedback',
          'message': 'ปุ่มเล็กไป',
          'status': 'open',
          'created_at': '2026-08-23T00:00:00Z',
        };
      },
    );
    await pumpHelp(tester, api);

    await tester
        .tap(find.text('ส่งความคิดเห็น')); // switch the segmented toggle
    await tester.pump();
    await tester.enterText(find.byType(TextField), '  ปุ่มเล็กไป  ');
    await tester.tap(find.text('ส่ง'));
    await tester.pump();
    await tester.pump();

    // The controller trims before sending; the toggle carries the feedback kind.
    expect(postedBody, {'kind': 'feedback', 'message': 'ปุ่มเล็กไป'});
  });

  testWidgets('an empty message never posts — inline error, no round-trip',
      (tester) async {
    final api =
        FakeApi(onPost: (_, __) async => throw StateError('must not post'));
    await pumpHelp(tester, api);

    await tester.tap(find.text('ส่ง'));
    await tester.pump();

    expect(api.calls, isEmpty, reason: 'an empty body must not cost a request');
    expect(find.text('กรุณากรอกข้อความ'), findsOneWidget);
    // Still on the form (not the success panel).
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a server error surfaces inline and keeps the form',
      (tester) async {
    final api = FakeApi(
      onPost: (_, __) async => throw const ApiException(
          message: 'ข้อมูลไม่ถูกต้อง', statusCode: 400),
    );
    await pumpHelp(tester, api);

    await tester.enterText(find.byType(TextField), 'test');
    await tester.tap(find.text('ส่ง'));
    await tester.pump();
    await tester.pump();

    expect(find.text('ข้อมูลไม่ถูกต้อง'), findsOneWidget);
    // The form is still there (not the success panel) so the user can retry.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('ส่งเรียบร้อยแล้ว'), findsNothing);
  });
}
