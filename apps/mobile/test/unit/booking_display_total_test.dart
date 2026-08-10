import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking.dart';

/// `Booking.displaySubtotalSatang` / `displayVatSatang` / `displayGrandTotalSatang` — the shared
/// DISPLAY figures the customer's live-status sheet AND the guard's active-job details sheet (#122)
/// both render, so the two never drift.
///
/// Catalog prices are VAT-EXCLUSIVE, so the SUBTOTAL is `base_fee × hours × guard_count + tip` and
/// the customer is charged that plus 7% VAT. `displayTotalSatang` — what every "the total" call
/// site reads — is therefore the VAT-INCLUSIVE grand total.
Booking booking({
  String? baseFee = '500.00',
  int? hours = 8,
  int? guardCount = 1,
  String? tip = '0',
  String? commissionPercent,
  String? cancellationFee,
}) =>
    Booking(
      id: 'b1',
      customerId: 'c1',
      status: BookingStatus.accepted,
      baseFee: baseFee,
      hours: hours,
      guardCount: guardCount,
      tip: tip,
      commissionPercent: commissionPercent,
      cancellationFee: cancellationFee,
    );

void main() {
  group('Booking.displaySubtotalSatang (VAT-exclusive)', () {
    test('base_fee × hours × guard_count (+ tip)', () {
      // 500 × 8 × 1 = 4000 baht = 400000 satang.
      expect(booking().displaySubtotalSatang, 400000);
      // 2 guards doubles it.
      expect(booking(guardCount: 2).displaySubtotalSatang, 800000);
      // A tip is added on top (in full): 400000 + 5000 (50.00) = 405000.
      expect(booking(tip: '50.00').displaySubtotalSatang, 405000);
    });

    test('null guard_count defaults to 1', () {
      expect(booking(guardCount: null).displaySubtotalSatang, 400000);
    });
  });

  group('Booking VAT', () {
    test('VAT is 7% of the subtotal', () {
      // 4000.00 × 7% = 280.00.
      expect(booking().displayVatSatang, 28000);
      // Tips are taxable too: 4050.00 × 7% = 283.50.
      expect(booking(tip: '50.00').displayVatSatang, 28350);
    });

    test('the grand total is subtotal + VAT — what the customer is charged',
        () {
      expect(booking().displayGrandTotalSatang, 428000);
      expect(booking(tip: '50.00').displayGrandTotalSatang, 405000 + 28350);
    });

    test('displayTotalSatang IS the VAT-inclusive grand total', () {
      // Every "the total" call site (live-status sheet, guard job sheet, cancellation refund copy)
      // reads this, so it must never quote the pre-tax subtotal the customer is not charged.
      expect(booking().displayTotalSatang, booking().displayGrandTotalSatang);
      expect(booking().displayTotalSatang, 428000);
    });

    test('VAT rounds half away from zero, to the satang', () {
      // 1 hr × ฿123.45 = 12345 satang; 7% = 864.15 satang → 864.
      expect(booking(baseFee: '123.45', hours: 1).displayVatSatang, 864);
      // 1 hr × ฿100.50 = 10050 satang; 7% = 703.5 satang → 704 (away from zero).
      expect(booking(baseFee: '100.50', hours: 1).displayVatSatang, 704);
    });
  });

  group('null when the rate or hours are not known yet (fresh request)', () {
    test('every derived figure degrades together', () {
      for (final b in [
        booking(baseFee: null),
        booking(baseFee: '0'),
        booking(hours: null),
        booking(hours: 0),
      ]) {
        expect(b.displaySubtotalSatang, isNull);
        expect(b.displayVatSatang, isNull);
        expect(b.displayGrandTotalSatang, isNull);
        expect(b.displayTotalSatang, isNull);
      }
    });
  });

  group('commission + cancellation-fee snapshots', () {
    test('parsed from the wire and exposed in exact units', () {
      final b = Booking.fromJson(const {
        'id': 'b1',
        'customer_id': 'c1',
        'status': 'accepted',
        'base_fee': '500.00',
        'hours': 8,
        'guard_count': 1,
        'tip': '0',
        'commission_percent': '12.50',
        'cancellation_fee': '200.00',
      });
      expect(b.commissionPercent, '12.50');
      expect(b.commissionPercentHundredths, 1250); // 12.50%
      expect(b.cancellationFee, '200.00');
      expect(b.cancellationFeeSatang, 20000);
    });

    test('a pre-migration booking carries neither → both read as zero', () {
      final b = Booking.fromJson(const {
        'id': 'b1',
        'customer_id': 'c1',
        'status': 'accepted',
      });
      expect(b.commissionPercent, isNull);
      expect(b.commissionPercentHundredths, 0);
      expect(b.cancellationFeeSatang, 0);
    });

    test('the snapshots survive a WS status fold and a paid stamp', () {
      // The money terms a job was SOLD at must not be dropped when a live frame advances it.
      final b = booking(commissionPercent: '10.00', cancellationFee: '150.00');
      final advanced = b.applyEvent(BookingStatusEvent(
        bookingId: 'b1',
        status: BookingStatus.enRoute,
        occurredAt: DateTime.utc(2026, 8, 10),
      ));
      expect(advanced.commissionPercentHundredths, 1000);
      expect(advanced.cancellationFeeSatang, 15000);

      final paid = b.withPaidAt(DateTime.utc(2026, 8, 10));
      expect(paid.commissionPercentHundredths, 1000);
      expect(paid.cancellationFeeSatang, 15000);
    });
  });
}
