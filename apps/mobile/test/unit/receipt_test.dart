import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/receipt.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/models/payment.dart';

/// `ReceiptData` — the derivation behind the Thai tax invoice (ใบเสร็จรับเงิน/ใบกำกับภาษี).
///
/// The rules under test are the ones a tax document cannot get wrong: the VAT column adds up to
/// the VAT charged, the lines add up to the subtotal, the grand total is what the customer was
/// actually charged (never a client recomputation), and the document never claims to be a tax
/// invoice for tax that was not charged.
Booking booking({
  String? baseFee = '230.00',
  int? hours = 8,
  int? guardCount = 1,
  String? tip,
  DateTime? scheduledAt,
}) =>
    Booking(
      id: '3f2a9b1c-0000-4000-8000-000000000001',
      customerId: 'c1',
      status: BookingStatus.completed,
      address: 'หมู่บ้านลัดดารมย์',
      baseFee: baseFee,
      hours: hours,
      guardCount: guardCount,
      tip: tip,
      scheduledAt: scheduledAt,
    );

Payment payment({
  String amount = '1968.80',
  String? subtotal = '1840.00',
  String? vatAmount = '128.80',
  String? grandTotal = '1968.80',
  String? refundAmount,
  String? cancellationFeeCharged,
  String? actualHours,
  String? paymentMethod = 'promptpay',
  DateTime? paidAt,
}) =>
    Payment(
      id: 'aa11bb22-3333-4444-8888-999999999999',
      bookingId: '3f2a9b1c-0000-4000-8000-000000000001',
      customerId: 'c1',
      amount: amount,
      status: PaymentStatus.completed,
      subtotal: subtotal,
      vatAmount: vatAmount,
      grandTotal: grandTotal,
      refundAmount: refundAmount,
      cancellationFeeCharged: cancellationFeeCharged,
      actualHours: actualHours,
      paymentMethod: paymentMethod,
      paidAt: paidAt ?? DateTime.utc(2026, 8, 10, 5),
    );

void main() {
  group('a settled, VAT-charged payment', () {
    test('is a TAX INVOICE and states the settle verbatim', () {
      final r = ReceiptData.from(booking: booking(), payment: payment());
      expect(r.kind, ReceiptKind.taxInvoice);
      expect(r.isEstimate, isFalse);
      expect(r.subtotalSatang, 184000);
      expect(
          r.vatSatang, 12880); // ฿128.80 — the charged VAT, not a recomputation
      expect(r.grandTotalSatang, 196880);
    });

    test('the item lines foot to the subtotal and the VAT column to the VAT',
        () {
      final r = ReceiptData.from(
          booking: booking(tip: '100.00'),
          payment: payment(
            subtotal: '1940.00', // 1,840 service + 100 tip
            vatAmount: '135.80',
            grandTotal: '2075.80',
          ));
      expect(r.lines.length, 2);
      expect(r.lines.map((l) => l.amountSatang).reduce((a, b) => a + b),
          r.subtotalSatang);
      expect(
          r.lines.map((l) => l.vatSatang).reduce((a, b) => a + b), r.vatSatang,
          reason: 'the VAT column must add up to the VAT actually charged');
      expect(r.lines.map((l) => l.totalSatang).reduce((a, b) => a + b),
          r.grandTotalSatang);
      // The tip is its own taxable line.
      expect(r.lines.last.labelTh, 'ทิป');
      expect(r.lines.last.amountSatang, 10000);
    });

    test('the service line absorbs a reconcile that changed the hours', () {
      // Booked 8h but only 2h worked: the settle's subtotal is ฿460, and the line must say so
      // rather than restating the booked ฿1,840.
      final r = ReceiptData.from(
        booking: booking(),
        payment: payment(
          subtotal: '460.00',
          vatAmount: '32.20',
          grandTotal: '492.20',
          actualHours: '2.00',
        ),
      );
      expect(r.lines.first.amountSatang, 46000);
      expect(r.lines.first.noteTh, contains('2.00'));
      expect(r.actualHours, '2.00');
      expect(r.bookedHours, 8);
    });

    test('a refund and a withheld cancellation fee print as adjustments', () {
      final r = ReceiptData.from(
        booking: booking(),
        payment: payment(
          refundAmount: '1768.80',
          cancellationFeeCharged: '200.00',
        ),
      );
      expect(r.hasAdjustments, isTrue);
      expect(r.cancellationFeeSatang, 20000);
      expect(r.refundSatang, 176880);
      // What the customer is really out of pocket.
      expect(r.netPaidSatang, 196880 - 176880);
      // Adjustments stay OUT of the taxable lines.
      expect(r.lines.map((l) => l.amountSatang).reduce((a, b) => a + b),
          r.subtotalSatang);
    });

    test('the document number and date come from the payment', () {
      final r = ReceiptData.from(booking: booking(), payment: payment());
      expect(r.documentNumber, 'RCP-AA11BB22');
      expect(r.issuedAt, DateTime.utc(2026, 8, 10, 5));
      expect(r.paymentMethod, 'promptpay');
    });
  });

  group('a payment taken BEFORE VAT was itemized', () {
    test('is a plain receipt: the amount is the whole charge, VAT is 0', () {
      final r = ReceiptData.from(
        booking: booking(),
        payment: payment(
            amount: '1840.00',
            subtotal: null,
            vatAmount: null,
            grandTotal: null),
      );
      expect(r.kind, ReceiptKind.receiptNoVat,
          reason: 'it must not claim to be a ใบกำกับภาษี for uncharged tax');
      expect(r.grandTotalSatang, 184000, reason: 'exactly what was charged');
      expect(r.vatSatang, 0);
      expect(r.subtotalSatang, 184000);
    });
  });

  group('no readable payment (the guard side)', () {
    test('is an ESTIMATE derived from the booking, VAT included', () {
      final r = ReceiptData.from(booking: booking(tip: '60.00'), payment: null);
      expect(r.kind, ReceiptKind.estimate);
      expect(r.isEstimate, isTrue);
      expect(r.subtotalSatang, 184000 + 6000);
      expect(r.vatSatang, 13300); // ฿1,900.00 × 7%
      expect(r.grandTotalSatang, 190000 + 13300);
      // Numbered off the BOOKING id (there is no payment to number it from).
      expect(r.documentNumber, 'RCP-3F2A9B1C');
      expect(r.paymentMethod, isNull);
    });

    test('degrades to zero — never throws — on a booking with no price yet',
        () {
      final r = ReceiptData.from(
          booking: booking(baseFee: null, hours: null), payment: null);
      expect(r.subtotalSatang, 0);
      expect(r.vatSatang, 0);
      expect(r.grandTotalSatang, 0);
    });
  });

  group('ReceiptData.allocateVat', () {
    test('shares always sum to the total VAT (last line takes the remainder)',
        () {
      // 3 equal lines against a VAT that does not divide evenly.
      final shares = ReceiptData.allocateVat([100, 100, 100], 7);
      expect(shares.reduce((a, b) => a + b), 7);
      // Proportional, not arbitrary.
      expect(shares.first, 2);
    });

    test('a zero subtotal still accounts for every satang of VAT', () {
      expect(ReceiptData.allocateVat([0, 0], 5), [0, 5]);
    });

    test('an empty table allocates nothing', () {
      expect(ReceiptData.allocateVat(const [], 100), isEmpty);
    });
  });

  group('formatting helpers', () {
    test('the Thai date carries the Buddhist year', () {
      expect(
        ReceiptData.formatIssuedDate(DateTime(2026, 8, 10), isThai: true),
        '10 ส.ค. 2569',
      );
      expect(
        ReceiptData.formatIssuedDate(DateTime(2026, 8, 10), isThai: false),
        '10 Aug 2026',
      );
    });

    test('the document number is stable and quotable', () {
      expect(
          ReceiptData.documentNumberFor('aa11bb22-3333-4444'), 'RCP-AA11BB22');
      // Short/odd ids degrade instead of crashing.
      expect(ReceiptData.documentNumberFor('ab'), 'RCP-AB');
    });

    test('an unknown payment method is shown as-is, never invented', () {
      expect(ReceiptData.paymentMethodLabel(null, isThai: true), '—');
      expect(ReceiptData.paymentMethodLabel('promptpay', isThai: false),
          'PromptPay / bank transfer');
      expect(ReceiptData.paymentMethodLabel('crypto', isThai: true), 'crypto');
    });
  });
}
