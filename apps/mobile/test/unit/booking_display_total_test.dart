import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking.dart';

/// `Booking.displayTotalSatang` — the shared DISPLAY estimate the customer's live-status sheet AND
/// the guard's active-job details sheet (#122) both render, so the two never drift. Pure derivation
/// (`base_fee × hours × guard_count + tip`); `null` when the rate/hours aren't known yet.
Booking booking({
  String? baseFee = '500.00',
  int? hours = 8,
  int? guardCount = 1,
  String? tip = '0',
}) =>
    Booking(
      id: 'b1',
      customerId: 'c1',
      status: BookingStatus.accepted,
      baseFee: baseFee,
      hours: hours,
      guardCount: guardCount,
      tip: tip,
    );

void main() {
  group('Booking.displayTotalSatang', () {
    test('base_fee × hours × guard_count (+ tip)', () {
      // 500 × 8 × 1 = 4000 baht = 400000 satang.
      expect(booking().displayTotalSatang, 400000);
      // 2 guards doubles it.
      expect(booking(guardCount: 2).displayTotalSatang, 800000);
      // A tip is added on top (in full): 400000 + 5000 (50.00) = 405000.
      expect(booking(tip: '50.00').displayTotalSatang, 405000);
    });

    test('null guard_count defaults to 1', () {
      expect(booking(guardCount: null).displayTotalSatang, 400000);
    });

    test('null when the rate or hours are not known yet (fresh request)', () {
      expect(booking(baseFee: null).displayTotalSatang, isNull);
      expect(booking(baseFee: '0').displayTotalSatang, isNull);
      expect(booking(hours: null).displayTotalSatang, isNull);
      expect(booking(hours: 0).displayTotalSatang, isNull);
    });
  });
}
