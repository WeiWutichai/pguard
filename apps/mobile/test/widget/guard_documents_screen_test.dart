import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/media/document_picker.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/profile/guard_documents_screen.dart';

import '../support/fakes.dart';

void main() {
  // A real temp JPEG so the upload's MultipartFile.fromFile() (driven by the fake picker path)
  // can stat/read it.
  late File tempImage;
  setUp(() async {
    tempImage = File(
        '${Directory.systemTemp.path}/pg_doc_widget_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await tempImage.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
  });
  tearDown(() async {
    if (await tempImage.exists()) await tempImage.delete();
  });

  /// Every probe 404s (nothing uploaded yet); the upload POST succeeds but returns no
  /// download_url, so the uploaded thumbnail is the green check (no Image.network in the test).
  FakeApi freshGuardApi() => FakeApi(
        onGet: (path, query) async {
          if (path == '/auth/me') return {'user_id': 'g1'};
          throw const ApiException(message: 'not found', statusCode: 404);
        },
        onPost: (path, data) async => <String, dynamic>{},
      );

  // The upload chain mixes fake-clock animation (modal-sheet dismiss) with REAL file I/O
  // (_readFileHead + MultipartFile.fromFile). Neither pump-only nor runAsync-only drives both, so
  // interleave them: pump advances the animation + microtasks, runAsync lets the real I/O settle.
  // Stop as soon as [until] appears (or after a bounded number of rounds).
  Future<void> driveUntil(WidgetTester tester, Finder until) async {
    for (var i = 0; i < 30 && until.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    await tester.pump();
  }

  Widget host(FakeApi api, FakeDocumentPicker picker) => ProviderScope(
        overrides: [
          pguardApiProvider.overrideWithValue(api),
          documentPickerProvider.overrideWithValue(picker),
          prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        ],
        child: const MaterialApp(home: GuardDocumentsScreen()),
      );

  testWidgets('renders all six credential rows, each not-uploaded, with a 0-of-6 count',
      (tester) async {
    await tester.pumpWidget(host(freshGuardApi(), FakeDocumentPicker()));
    await tester.pumpAndSettle();

    for (final label in const [
      'บัตรประชาชน',
      'ใบอนุญาต รปภ.',
      'ใบรับรองการฝึก',
      'ใบตรวจประวัติ',
      'ใบขับขี่',
      'หน้าสมุดบัญชี',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('อัปโหลดแล้ว 0 จาก 6'), findsOneWidget);
    expect(find.text('ยังไม่อัปโหลด'), findsNWidgets(6));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping a row → camera/gallery sheet → pick → upload flips the row to uploaded',
      (tester) async {
    final picker = FakeDocumentPicker(path: tempImage.path);
    await tester.pumpWidget(host(freshGuardApi(), picker));
    await tester.pumpAndSettle();

    await tester.tap(find.text('บัตรประชาชน'));
    await tester.pumpAndSettle();
    // The source sheet is up.
    expect(find.text('ถ่ายรูป'), findsOneWidget);
    expect(find.text('เลือกจากคลัง'), findsOneWidget);

    await tester.tap(find.text('เลือกจากคลัง'));
    await driveUntil(tester, find.text('อัปโหลดแล้ว 1 จาก 6'));

    // The picker was asked for a gallery image, and exactly one credential is now uploaded.
    expect(picker.picks, [DocSource.gallery]);
    expect(find.text('อัปโหลดแล้ว 1 จาก 6'), findsOneWidget);
    expect(find.text('อัปโหลดแล้ว'), findsOneWidget); // the id_card row's status
    expect(find.text('ยังไม่อัปโหลด'), findsNWidgets(5));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a cancelled picker leaves everything not-uploaded (no upload fired)',
      (tester) async {
    final picker = FakeDocumentPicker(path: null); // user cancels the OS picker
    await tester.pumpWidget(host(freshGuardApi(), picker));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ใบขับขี่'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ถ่ายรูป'));
    await tester.pumpAndSettle();

    expect(picker.picks, [DocSource.camera]);
    expect(find.text('อัปโหลดแล้ว 0 จาก 6'), findsOneWidget);
    expect(find.text('ยังไม่อัปโหลด'), findsNWidgets(6));

    await tester.pumpWidget(const SizedBox());
  });
}
