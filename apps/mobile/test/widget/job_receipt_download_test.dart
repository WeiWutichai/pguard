import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/models/payment.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/widgets/job_receipt_sheet.dart';

import '../support/fakes.dart';
import '../support/pdf_text.dart';

/// "ใบเสร็จยังไม่สามารถดาวโหลดได้จาก app หลังจบงาน" — the customer could read the receipt but
/// never keep it. These tests hold the download honest:
///   • the action is THERE on a completed job's receipt,
///   • tapping it really builds the PDF (not a stub) and the file that reaches the OS carries the
///     same grand total the sheet is showing,
///   • the file is named after the document number, and
///   • a failure is reported in the reader's language instead of silently doing nothing.
Booking _booking() => const Booking(
      id: '3f2a9b1c-0000-4000-8000-000000000001',
      customerId: 'c1',
      status: BookingStatus.completed,
      address: 'หมู่บ้านลัดดารมย์ 88/1',
      baseFee: '230.00',
      hours: 8,
      guardCount: 1,
    );

Payment _payment() => Payment(
      id: 'aa11bb22-3333-4444-8888-999999999999',
      bookingId: '3f2a9b1c-0000-4000-8000-000000000001',
      customerId: 'c1',
      amount: '1968.80',
      status: PaymentStatus.completed,
      subtotal: '1840.00',
      vatAmount: '128.80',
      grandTotal: '1968.80',
      paymentMethod: 'promptpay',
      paidAt: DateTime.utc(2026, 8, 10, 5),
    );

FakeApi _api() => FakeApi(
      onGet: (path, _) async {
        switch (path) {
          case '/auth/me':
            return {'user_id': 'c1', 'role': 'customer'};
          case '/profile/me':
            return {
              'kind': 'customer',
              'full_name': 'สมชาย ใจดี',
              'address': '99/9 ถนนสุขุมวิท กรุงเทพฯ 10110',
            };
          case '/org-settings':
            return {
              'company_name': 'บริษัท พีการ์ด จำกัด',
              'tax_id': '0105558001234',
              'address': '1 อาคารพีการ์ด ถนนพระราม 9 กรุงเทพฯ 10310',
            };
        }
        return <String, dynamic>{};
      },
    );

Future<void> _pump(
  WidgetTester tester, {
  required FakeDocumentSharer sharer,
  bool isThai = true,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(_api()),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      documentSharerProvider.overrideWithValue(sharer),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: JobReceiptBody(
            booking: _booking(),
            payment: _payment(),
            isThai: isThai,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

/// Pump until [done] — never `pumpAndSettle`, which would hang on the button's progress spinner.
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The receipt is a long document; the action sits under it. Scroll it into view, as a customer
/// would, before tapping.
Future<void> _tapDownload(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
}

void main() {
  testWidgets('the receipt offers a download, and it produces the real PDF',
      (tester) async {
    // Hold the hand-off open so the in-progress state can be inspected without racing it.
    final sharer = FakeDocumentSharer()..hold = Completer<void>();
    await _pump(tester, sharer: sharer);

    final button = find.widgetWithText(OutlinedButton, 'ดาวน์โหลดใบเสร็จ');
    expect(button, findsOneWidget);

    await _tapDownload(tester, button);
    await _pumpUntil(tester, () => sharer.calls > 0);
    // One more frame: the loop stops the instant the share is reached, before the in-flight state
    // has been painted.
    await tester.pump();
    expect(sharer.calls, 1);

    // The work is visible while it runs — and the button cannot be fired twice into it.
    expect(find.text('กำลังสร้างไฟล์ PDF…'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'กำลังสร้างไฟล์ PDF…'))
          .onPressed,
      isNull,
    );

    // A real PDF reached the OS…
    final bytes = sharer.bytes!;
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(sharer.mimeType, 'application/pdf');

    // …named after the document number, not a temp name.
    expect(sharer.fileName, 'pguard-RCP-AA11BB22.pdf');
    expect(sharer.subject, contains('RCP-AA11BB22'));

    // …and it says what the sheet says. The grand total on screen is ฿1,968.80; so is the one in
    // the file the customer just saved.
    expect(find.text('฿1,968.80'), findsOneWidget);
    final text = extractPdfText(bytes);
    expect(text, containsPdfText('฿1,968.80'));
    expect(text, containsPdfText('ต้นฉบับ ใบเสร็จรับเงิน / ใบกำกับภาษี'));
    expect(text, containsPdfText('บริษัท พีการ์ด จำกัด'));
    expect(text, containsPdfText('สมชาย ใจดี'));

    // Back to an idle, tappable button once the share sheet has been handed the file.
    sharer.release();
    await _pumpUntil(
        tester, () => find.text('ดาวน์โหลดใบเสร็จ').evaluate().isNotEmpty);
    expect(find.text('ดาวน์โหลดใบเสร็จ'), findsOneWidget);
    expect(find.text('กำลังสร้างไฟล์ PDF…'), findsNothing);
  });

  testWidgets('the English receipt offers the same action in English',
      (tester) async {
    final sharer = FakeDocumentSharer();
    await _pump(tester, sharer: sharer, isThai: false);

    expect(find.widgetWithText(OutlinedButton, 'Download receipt'),
        findsOneWidget);
  });

  testWidgets('a failed download says so, in the reader’s language',
      (tester) async {
    final sharer = FakeDocumentSharer()..throwOnShare = true;
    await _pump(tester, sharer: sharer);

    await _tapDownload(
        tester, find.widgetWithText(OutlinedButton, 'ดาวน์โหลดใบเสร็จ'));
    await _pumpUntil(tester, () => sharer.calls > 0);
    await tester.pump();

    expect(find.text('สร้างไฟล์ใบเสร็จไม่สำเร็จ — ลองใหม่อีกครั้ง'),
        findsOneWidget);
    // …and the customer can try again rather than being left on a dead button.
    expect(
      tester
          .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'ดาวน์โหลดใบเสร็จ'))
          .onPressed,
      isNotNull,
    );
  });
}
