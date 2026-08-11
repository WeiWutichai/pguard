import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/receipt.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/models/org_settings.dart';
import 'package:pguard_mobile/core/models/payment.dart';
import 'package:pguard_mobile/core/pdf/receipt_pdf.dart';

import '../support/pdf_text.dart';

/// The downloadable tax invoice (`core/pdf/receipt_pdf.dart`).
///
/// The two things this file exists to protect:
///   1. THAI RENDERS. A pdf built with the package's default face prints every Thai word as a
///      blank box — a "download" that produces an unreadable document is worse than no download.
///      So the test asserts the IBM Plex Sans Thai face is really embedded AND reads Thai back out
///      of the finished bytes.
///   2. THE NUMBERS ARE [ReceiptData]'s. Every figure is read back out of the PDF and compared to
///      the derivation the on-screen sheet lays out — the PDF may never quietly say something else
///      about what the customer paid.
Booking _booking() => const Booking(
      id: '3f2a9b1c-0000-4000-8000-000000000001',
      customerId: 'c1',
      status: BookingStatus.completed,
      address: 'หมู่บ้านลัดดารมย์ 88/1',
      baseFee: '230.00',
      hours: 8,
      guardCount: 1,
      tip: '100.00',
    );

Payment _payment({String? refundAmount, String? cancellationFeeCharged}) =>
    Payment(
      id: 'aa11bb22-3333-4444-8888-999999999999',
      bookingId: '3f2a9b1c-0000-4000-8000-000000000001',
      customerId: 'c1',
      amount: '2075.80',
      status: PaymentStatus.completed,
      subtotal: '1940.00',
      vatAmount: '135.80',
      grandTotal: '2075.80',
      refundAmount: refundAmount,
      cancellationFeeCharged: cancellationFeeCharged,
      paymentMethod: 'promptpay',
      paidAt: DateTime.utc(2026, 8, 10, 5),
    );

const _org = OrgSettings(
  companyName: 'บริษัท พีการ์ด จำกัด',
  taxId: '0105558001234',
  address: '1 อาคารพีการ์ด ถนนพระราม 9 กรุงเทพฯ 10310',
);

ReceiptPdfDocument _full({Payment? payment}) => ReceiptPdfDocument(
      data: ReceiptData.from(
        booking: _booking(),
        payment: payment ?? _payment(),
      ),
      isThai: true,
      org: _org,
      buyerName: 'สมชาย ใจดี',
      buyerAddress: '99/9 ถนนสุขุมวิท กรุงเทพฯ 10110',
      siteAddress: 'หมู่บ้านลัดดารมย์ 88/1',
    );

/// The barest document the app can be asked to print: no company profile, no buyer, no settled
/// payment, no schedule — a guard-side estimate. It must still produce a real, readable file.
ReceiptPdfDocument _minimal() => ReceiptPdfDocument(
      data: ReceiptData.from(
        booking: const Booking(
          id: '0000aaaa-0000-4000-8000-00000000000f',
          customerId: 'c9',
          status: BookingStatus.completed,
        ),
        payment: null,
      ),
      isThai: false,
    );

void main() {
  // Fonts are read from the bundled assets, so the binding (and its asset bundle) must exist.
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReceiptPdfFonts fonts;

  setUpAll(() async {
    fonts = await ReceiptPdfFonts.load(bundle: rootBundle);
  });

  test('a full receipt produces real PDF bytes', () async {
    final bytes = await buildReceiptPdf(_full(), fonts: fonts);

    expect(bytes, isNotEmpty);
    expect(bytes.length, greaterThan(1000),
        reason: 'an embedded-font tax invoice is never a few hundred bytes');
    // A PDF, not "some bytes": the header and the trailer are both there.
    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(latin1.decode(bytes.sublist(bytes.length - 8)), contains('%%EOF'));
  });

  test('the minimal receipt — no company, no buyer, no payment — still builds',
      () async {
    final bytes = await buildReceiptPdf(_minimal(), fonts: fonts);

    expect(bytes, isNotEmpty);
    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    final text = extractPdfText(bytes);
    // It refuses to call itself a tax invoice, and it names the missing company block.
    expect(text, containsPdfText('Estimated statement'));
    expect(text, isNot(containsPdfText('Tax Invoice')));
    expect(text, containsPdfText('Company details not set up'));
  });

  test('the Thai typeface is embedded (Thai would be blank boxes without it)',
      () async {
    final bytes = await buildReceiptPdf(_full(), fonts: fonts);
    final raw = latin1.decode(bytes, allowInvalid: true);

    expect(raw, contains('IBMPlexSansThai'),
        reason: 'the font program must be IN the file, not referenced');
    expect(raw, contains('/FontFile2'),
        reason: 'a TrueType program, i.e. really embedded');
    expect(raw, isNot(contains('/BaseFont /Helvetica')),
        reason:
            'Helvetica has no Thai glyphs — it must not be the document face');
  });

  test('Thai text is readable back out of the finished document', () async {
    final text = extractPdfText(await buildReceiptPdf(_full(), fonts: fonts));

    // Title, issuer, buyer, and a table column — all Thai, all round-tripped through the PDF's
    // own glyph → unicode map, which is exactly what a reader/printer will do.
    expect(text, containsPdfText('ต้นฉบับ ใบเสร็จรับเงิน / ใบกำกับภาษี'));
    expect(text, containsPdfText('บริษัท พีการ์ด จำกัด'));
    expect(text, containsPdfText('สมชาย ใจดี'));
    expect(text, containsPdfText('ค่าบริการรักษาความปลอดภัย'));
    expect(text, containsPdfText('ภาษีมูลค่าเพิ่ม'));
  });

  test('every printed figure comes from ReceiptData', () async {
    final doc = _full();
    final data = doc.data;
    final text = extractPdfText(await buildReceiptPdf(doc, fonts: fonts));

    // THE number a receipt exists for.
    expect(data.grandTotalSatang, 207580);
    expect(text, containsPdfText('฿2,075.80'));

    // …and the split that has to foot to it: subtotal + VAT, plus the two line amounts.
    expect(text, containsPdfText('฿1,940.00')); // subtotal
    expect(text, containsPdfText('฿135.80')); // VAT 7%
    expect(text, containsPdfText('1,840.00')); // service line, VAT-exclusive
    expect(text, containsPdfText('100.00')); // tip line

    // The document's own identity, derived (not invented) from the payment id + paid_at.
    expect(text, containsPdfText(data.documentNumber));
    expect(text, containsPdfText('RCP-AA11BB22'));
    expect(text, containsPdfText('10 ส.ค. 2569'));
    expect(text, containsPdfText('พร้อมเพย์ / โอนเงิน'));
  });

  test('a refund and a withheld cancellation fee are printed too', () async {
    final doc = _full(
      payment:
          _payment(refundAmount: '1875.80', cancellationFeeCharged: '200.00'),
    );
    final text = extractPdfText(await buildReceiptPdf(doc, fonts: fonts));

    expect(text, containsPdfText('ค่าธรรมเนียมการยกเลิก'));
    expect(text, containsPdfText('ยอดคืนเงิน'));
    expect(text, containsPdfText('฿1,875.80'));
    expect(text, containsPdfText('ยอดชำระสุทธิ'));
    expect(text, containsPdfText('฿200.00'));
  });

  test('the file is named after the document number, not a temp name', () {
    expect(_full().fileName, 'pguard-RCP-AA11BB22.pdf');
    // Whatever the number turns out to be, the name stays filesystem/mail-client safe.
    expect(_minimal().fileName, matches(RegExp(r'^[A-Za-z0-9._-]+\.pdf$')));
  });

  test('fonts are loaded on demand when the caller passes none', () async {
    final bytes = await buildReceiptPdf(_full(), bundle: rootBundle);
    expect(
        latin1.decode(bytes, allowInvalid: true), contains('IBMPlexSansThai'));
  });
}
