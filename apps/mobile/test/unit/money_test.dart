import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/money.dart';

void main() {
  group('Money.satangFromString', () {
    test('parses plain and decimal baht strings', () {
      expect(Money.satangFromString('500.00'), 50000);
      expect(Money.satangFromString('500'), 50000);
      expect(Money.satangFromString('500.5'), 50050);
      expect(Money.satangFromString('0'), 0);
      expect(Money.satangFromString('1840.00'), 184000);
    });

    test('tolerates grouping, whitespace, and sign', () {
      expect(Money.satangFromString(' 1,840.00 '), 184000);
      expect(Money.satangFromString('-50'), -5000);
      expect(Money.satangFromString('+50'), 5000);
    });

    test('returns 0 for null/blank/garbage', () {
      expect(Money.satangFromString(null), 0);
      expect(Money.satangFromString(''), 0);
      expect(Money.satangFromString('abc'), 0);
    });

    test('truncates beyond two fractional digits', () {
      expect(Money.satangFromString('1.999'), 199);
    });
  });

  group('Money.amountString', () {
    test('renders exactly two decimals, no grouping/symbol', () {
      expect(Money.amountString(50000), '500.00');
      expect(Money.amountString(805000), '8050.00');
      expect(Money.amountString(184050), '1840.50');
      expect(Money.amountString(0), '0.00');
    });

    test('round-trips with satangFromString', () {
      for (final s in ['500.00', '8050.00', '1840.50', '0.00']) {
        expect(Money.amountString(Money.satangFromString(s)), s);
      }
    });
  });

  group('Money.format', () {
    test('groups thousands and prefixes ฿', () {
      expect(Money.format(184000), '฿1,840');
      expect(Money.format(184000, decimals: true), '฿1,840.00');
      expect(Money.format(50000, symbol: false), '500');
      // Satang appear on their own when they carry value — a ฿0.04 job must never read as ฿0,
      // which is what the guard earnings row was doing.
      expect(Money.format(4), '฿0.04');
      expect(Money.format(3), '฿0.03');
      expect(Money.format(184050), '฿1,840.50');
      expect(Money.format(-4), '-฿0.04');
    });
  });

  group('Money.total', () {
    test('computes base_fee × hours × guards + tip in satang', () {
      // ฿500 × 8 × 2 + ฿50 tip = ฿8,050.00 — the VAT-EXCLUSIVE subtotal.
      final total = Money.total(
        baseFeeSatang: 50000,
        hours: 8,
        guardCount: 2,
        tipSatang: 5000,
      );
      expect(total, 805000);
      expect(Money.amountString(total), '8050.00');
    });
  });

  group('Money.vat / grandTotal', () {
    test('VAT is 7% of the VAT-exclusive subtotal', () {
      expect(Money.vatPercent, 7);
      expect(Money.vat(805000), 56350); // ฿8,050.00 → ฿563.50
      expect(Money.vat(100000), 7000); // ฿1,000.00 → ฿70.00
      expect(Money.vat(0), 0);
    });

    test('rounds halves AWAY FROM ZERO, like the server rust_decimal', () {
      // 10050 × 7% = 703.5 satang → 704 (never 703, which would undercharge vs the server).
      expect(Money.vat(10050), 704);
      // 12345 × 7% = 864.15 → 864.
      expect(Money.vat(12345), 864);
      expect(Money.vat(-10050), -704);
    });

    test('the grand total is what the customer actually pays', () {
      expect(Money.grandTotal(805000), 805000 + 56350);
      expect(Money.grandTotal(0), 0);
    });
  });

  group('Money.percentHundredths / percentOf', () {
    test('a NUMERIC(5,2) percent parses to exact hundredths', () {
      expect(Money.percentHundredths('12.50'), 1250);
      expect(Money.percentHundredths('10'), 1000);
      expect(Money.percentHundredths('0.00'), 0);
      expect(Money.percentHundredths(null), 0);
      expect(Money.percentHundredths('100.00'), 10000);
    });

    test('percentOf applies a commission exactly', () {
      // ฿1,840.00 gross at 10% = ฿184.00 commission.
      expect(Money.percentOf(184000, 1000), 18400);
      // 12.5% of ฿1,840.00 = ฿230.00.
      expect(Money.percentOf(184000, 1250), 23000);
      // 0% takes nothing; 100% takes everything.
      expect(Money.percentOf(184000, 0), 0);
      expect(Money.percentOf(184000, 10000), 184000);
    });

    test('percentOf rounds halves away from zero, to the satang', () {
      // ฿1.00 at 12.5% = 12.5 satang → 13.
      expect(Money.percentOf(100, 1250), 13);
      // ฿0.07 at 7.5% = 0.525 satang → 1.
      expect(Money.percentOf(7, 750), 1);
    });
  });
}
