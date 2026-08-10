import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/models/payment.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/booking/widgets/job_receipt_sheet.dart';
import 'package:pguard_mobile/widgets/pg_logo_mark.dart';

import '../support/fakes.dart';

/// The receipt rebuilt as a Thai TAX INVOICE (ต้นฉบับ ใบเสร็จรับเงิน / ใบกำกับภาษี): the issuer
/// block, the document title/number/date, the buyer block, the
/// `รายการ / จำนวนเงิน / ภาษีมูลค่าเพิ่ม / รวมเงิน` table and the grand total.
///
/// The two facts this file exists to protect: the VAT the customer paid is VISIBLE as its own
/// line, and a missing company profile is STATED rather than printed as a blank letterhead.
Booking _booking() => const Booking(
      id: '3f2a9b1c-0000-4000-8000-000000000001',
      customerId: 'c1',
      status: BookingStatus.completed,
      address: 'หมู่บ้านลัดดารมย์ 88/1',
      baseFee: '230.00',
      hours: 8,
      guardCount: 1,
    );

Payment _payment({String? refundAmount, String? cancellationFeeCharged}) =>
    Payment(
      id: 'aa11bb22-3333-4444-8888-999999999999',
      bookingId: '3f2a9b1c-0000-4000-8000-000000000001',
      customerId: 'c1',
      amount: '1968.80',
      status: PaymentStatus.completed,
      subtotal: '1840.00',
      vatAmount: '128.80',
      grandTotal: '1968.80',
      refundAmount: refundAmount,
      cancellationFeeCharged: cancellationFeeCharged,
      paymentMethod: 'promptpay',
      paidAt: DateTime.utc(2026, 8, 10, 5),
    );

/// A FakeApi answering everything the receipt reads: the caller's identity + customer profile
/// (the buyer block) and the org company profile (the issuer block).
FakeApi _api({bool orgConfigured = true}) => FakeApi(
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
            if (!orgConfigured) return <String, dynamic>{};
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
  required FakeApi api,
  required Payment? payment,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      prefsStoreProvider.overrideWithValue(FakePrefsStore()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: JobReceiptBody(
            booking: _booking(),
            payment: payment,
            isThai: true,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('a settled, VAT-charged payment renders a full tax invoice',
      (tester) async {
    await _pump(tester, api: _api(), payment: _payment());

    // Issuer block: the brand mark is DRAWN from tokens (no image asset), plus the legal name,
    // the TIN and the registered address.
    expect(find.byType(PgLogoMark), findsOneWidget);
    expect(find.text('บริษัท พีการ์ด จำกัด'), findsOneWidget);
    expect(find.text('เลขประจำตัวผู้เสียภาษี 0105558001234'), findsOneWidget);
    expect(find.textContaining('อาคารพีการ์ด'), findsOneWidget);

    // Document title — this copy IS a tax invoice, and says so in both languages.
    expect(find.text('ต้นฉบับ ใบเสร็จรับเงิน / ใบกำกับภาษี'), findsOneWidget);
    expect(find.text('Original Receipt / Tax Invoice'), findsOneWidget);

    // Number + date (Buddhist year).
    expect(find.text('RCP-AA11BB22'), findsOneWidget);
    expect(find.text('10 ส.ค. 2569'), findsOneWidget);

    // Buyer block from the caller's own customer profile.
    expect(find.text('สมชาย ใจดี'), findsOneWidget);
    expect(find.textContaining('ถนนสุขุมวิท'), findsOneWidget);

    // The item table's four columns.
    expect(find.text('รายการ'), findsOneWidget);
    expect(find.text('จำนวนเงิน'), findsOneWidget);
    expect(find.text('ภาษีมูลค่าเพิ่ม'), findsOneWidget);
    expect(find.text('รวมเงิน'), findsOneWidget);
    expect(find.text('ค่าบริการรักษาความปลอดภัย'), findsOneWidget);
    expect(find.text('฿230.00 × 8 ชม.'), findsOneWidget);

    // THE VAT LINE — its own row, never folded into the total.
    expect(find.text('ภาษีมูลค่าเพิ่ม 7%'), findsOneWidget);
    expect(find.text('฿128.80'), findsOneWidget);
    expect(find.text('รวมเป็นเงิน'), findsOneWidget);
    expect(find.text('฿1,840.00'), findsOneWidget);

    // Grand total = what was charged, and the payment method at the foot.
    expect(find.text('จำนวนเงินรวมทั้งสิ้น'), findsOneWidget);
    expect(find.text('฿1,968.80'), findsOneWidget);
    expect(find.text('พร้อมเพย์ / โอนเงิน'), findsOneWidget);

    // Two decimals everywhere in the money columns — a tax document does not round.
    expect(find.text('1,840.00'), findsOneWidget); // amount column
    expect(find.text('128.80'), findsOneWidget); // VAT column
    expect(find.text('1,968.80'), findsOneWidget); // line total column
  });

  testWidgets('an unconfigured company profile is STATED, not left blank',
      (tester) async {
    await _pump(tester, api: _api(orgConfigured: false), payment: _payment());

    expect(find.text('ยังไม่ได้ตั้งค่าข้อมูลบริษัท'), findsOneWidget);
    expect(find.textContaining('ยังไม่สมบูรณ์ตามข้อกำหนดของใบกำกับภาษี'),
        findsOneWidget,
        reason: 'a blank letterhead would hide that the document is not valid');
    // The money is still correct and complete — the gap is in the header, not the figures.
    expect(find.text('฿1,968.80'), findsOneWidget);
    expect(find.text('ภาษีมูลค่าเพิ่ม 7%'), findsOneWidget);
  });

  testWidgets('an unreadable org route degrades to the same honest header',
      (tester) async {
    // The only org-settings route that exists today is admin-only, so a customer's read can fail
    // outright. That must never break the receipt.
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/org-settings') throw Exception('404');
      if (path == '/auth/me') return {'user_id': 'c1', 'role': 'customer'};
      if (path == '/profile/me') {
        return {'kind': 'customer', 'full_name': 'สมชาย ใจดี'};
      }
      return <String, dynamic>{};
    });
    await _pump(tester, api: api, payment: _payment());

    expect(find.text('ยังไม่ได้ตั้งค่าข้อมูลบริษัท'), findsOneWidget);
    expect(find.text('฿1,968.80'), findsOneWidget);
  });

  testWidgets('a refund + withheld cancellation fee print under the total',
      (tester) async {
    await _pump(
      tester,
      api: _api(),
      payment:
          _payment(refundAmount: '1768.80', cancellationFeeCharged: '200.00'),
    );

    expect(find.text('ค่าธรรมเนียมการยกเลิก'), findsOneWidget);
    expect(find.text('ยอดคืนเงิน'), findsOneWidget);
    expect(find.text('฿1,768.80'), findsOneWidget);
    expect(find.text('ยอดชำระสุทธิ'), findsOneWidget);
    // The fee kept (฿200.00) and what the customer is left paying (1,968.80 − 1,768.80) are the
    // same figure by construction — the settlement reconciles, which is the point.
    expect(find.text('฿200.00'), findsNWidgets(2));
    expect(find.textContaining('หักค่าธรรมเนียมไม่เกินยอดที่ชำระไว้'),
        findsOneWidget);
  });

  testWidgets(
      'the guard side (no readable payment) is an ESTIMATE, not a tax invoice',
      (tester) async {
    await _pump(tester, api: _api(), payment: null);

    expect(find.text('ใบสรุปค่าบริการ (ประมาณการ)'), findsOneWidget);
    expect(find.text('ต้นฉบับ ใบเสร็จรับเงิน / ใบกำกับภาษี'), findsNothing,
        reason: 'a booking-derived copy must not claim to be a tax invoice');
    expect(find.textContaining('ไม่ใช่ใบกำกับภาษีที่ออกจากยอดที่เรียกเก็บจริง'),
        findsOneWidget);
    // Still shows the estimated tax the customer will be charged: ฿1,840 + 7% = ฿1,968.80.
    expect(find.text('ภาษีมูลค่าเพิ่ม 7%'), findsOneWidget);
    expect(find.text('฿1,968.80'), findsOneWidget);
  });
}
