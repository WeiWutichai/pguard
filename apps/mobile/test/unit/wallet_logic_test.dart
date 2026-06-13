import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/wallet_controller.dart';
import 'package:pguard_mobile/core/models/payment.dart';

Payment payment({
  String id = 'p1',
  String bookingId = '3f2a9b1c-0000-4000-8000-000000000001',
  String amount = '2000.00',
  PaymentStatus status = PaymentStatus.completed,
  String? finalAmount,
  String? refundAmount,
  DateTime? createdAt,
}) =>
    Payment(
      id: id,
      bookingId: bookingId,
      customerId: 'c1',
      amount: amount,
      status: status,
      finalAmount: finalAmount,
      refundAmount: refundAmount,
      createdAt: createdAt,
    );

void main() {
  group('WalletController.spentSatang', () {
    test('a plain completed payment costs its amount', () {
      expect(WalletController.spentSatang(payment()), 200000);
    });

    test('a refunded payment costs 0', () {
      expect(
        WalletController.spentSatang(payment(status: PaymentStatus.refunded)),
        0,
      );
    });

    test('final_amount (prorated post-completion figure) wins when set', () {
      expect(
        WalletController.spentSatang(
            payment(finalAmount: '1725.00', refundAmount: '275.00')),
        172500,
      );
    });

    test('without final_amount, refund_amount subtracts (clamped at 0)', () {
      expect(
        WalletController.spentSatang(payment(refundAmount: '275.00')),
        172500,
      );
      expect(
        WalletController.spentSatang(payment(refundAmount: '9999.00')),
        0,
      );
    });
  });

  group('WalletController.rowAmountSatang (receipt-row display figure)', () {
    test(
        'a prorated completed payment shows final_amount — coherent with the hero',
        () {
      final p = payment(finalAmount: '1725.00', refundAmount: '275.00');
      expect(WalletController.rowAmountSatang(p), 172500);
      // Row figure == hero contribution → rows sum to the header for non-refunded items.
      expect(
          WalletController.rowAmountSatang(p), WalletController.spentSatang(p));
    });

    test(
        'a refunded payment keeps the ORIGINAL charge on the row (badge explains ฿0)',
        () {
      final p = payment(status: PaymentStatus.refunded);
      expect(WalletController.rowAmountSatang(p), 200000);
      expect(WalletController.spentSatang(p), 0);
    });

    test('a plain completed payment shows its amount', () {
      expect(WalletController.rowAmountSatang(payment()), 200000);
    });
  });

  test('totalSpentSatang sums the effective spends', () {
    final payments = [
      payment(id: 'p1'), // ฿2,000
      payment(id: 'p2', status: PaymentStatus.refunded), // ฿0
      payment(id: 'p3', finalAmount: '1725.00'), // ฿1,725
    ];
    expect(WalletController.totalSpentSatang(payments), 200000 + 172500);
  });

  test('paymentRef derives the mono PG- reference from the booking id', () {
    expect(WalletController.paymentRef(payment()), 'PG-3F2A9B1C');
    // Short/odd ids degrade gracefully instead of throwing.
    expect(WalletController.paymentRef(payment(bookingId: 'ab-12')), 'PG-AB12');
  });

  test('statusLabel renders the Thai label per status (default locale)', () {
    expect(WalletController.statusLabel(PaymentStatus.pending, isThai: true),
        'รอดำเนินการ');
    expect(WalletController.statusLabel(PaymentStatus.completed, isThai: true),
        'ชำระแล้ว');
    expect(WalletController.statusLabel(PaymentStatus.refunded, isThai: true),
        'คืนเงินแล้ว');
  });

  test('statusLabel renders the English label when isThai is false', () {
    expect(WalletController.statusLabel(PaymentStatus.pending, isThai: false),
        'Pending');
    expect(WalletController.statusLabel(PaymentStatus.completed, isThai: false),
        'Paid');
    expect(WalletController.statusLabel(PaymentStatus.refunded, isThai: false),
        'Refunded');
  });

  test('thaiShortDateYear renders the design receipt date (3 มิ.ย. 2026)', () {
    expect(thaiShortDateYear(DateTime.utc(2026, 6, 3, 12), isThai: true),
        '3 มิ.ย. 2026');
  });

  test('thaiShortDateYear renders an English month when isThai is false', () {
    expect(thaiShortDateYear(DateTime.utc(2026, 6, 3, 12), isThai: false),
        '3 Jun 2026');
  });

  test('Payment.fromJson parses the list fields (created_at, proration)', () {
    final p = Payment.fromJson({
      'id': 'p1',
      'booking_id': 'b1',
      'customer_id': 'c1',
      'amount': '2000.00',
      'status': 'completed',
      'final_amount': '1725.00',
      'refund_amount': '275.00',
      'created_at': '2026-06-03T05:00:00Z',
      'updated_at': '2026-06-03T05:00:00Z',
    });
    expect(p.finalAmount, '1725.00');
    expect(p.refundAmount, '275.00');
    expect(p.createdAt, DateTime.utc(2026, 6, 3, 5));
  });
}
