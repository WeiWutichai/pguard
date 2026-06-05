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
    });
  });

  group('Money.total', () {
    test('computes base_fee × hours × guards + tip in satang', () {
      // ฿500 × 8 × 2 + ฿50 tip = ฿8,050.00
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
}
