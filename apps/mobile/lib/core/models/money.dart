// Exact-money helpers for the booking flow.
//
// Server money fields cross the wire as decimal STRINGS (e.g. "500.00") — never floats — to
// avoid rounding drift (CLAUDE.md money rule). We work in integer **satang** (1 baht = 100
// satang) so all arithmetic is exact. Pure (no Flutter imports) → fully unit-testable.
//
// DISPLAY ONLY for any total the client shows. The AUTHORITATIVE charge total is re-computed
// and verified by the payment service against the booking's server-owned `base_fee`
// (`expected_total = base_fee × hours × guard_count + tip`); the client merely derives the
// `amount` it sends, which the server rejects if it undercuts the price.
class Money {
  const Money._();

  /// Parse a decimal baht string ("500", "500.5", "1,840.00", " -50 ") into integer satang.
  /// Tolerant: returns 0 for null/blank/garbage so callers can treat money defensively.
  static int satangFromString(String? decimal) {
    if (decimal == null) return 0;
    var s = decimal.trim().replaceAll(',', '');
    if (s.isEmpty) return 0;
    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }
    final dot = s.indexOf('.');
    String whole;
    String frac;
    if (dot < 0) {
      whole = s;
      frac = '';
    } else {
      whole = s.substring(0, dot);
      frac = s.substring(dot + 1);
    }
    if (whole.isEmpty) whole = '0';
    // Truncate/pad the fractional part to exactly two digits (satang precision).
    frac = '${frac}00'.substring(0, 2);
    final wholeVal = int.tryParse(whole);
    final fracVal = int.tryParse(frac);
    if (wholeVal == null || fracVal == null) return 0;
    final satang = wholeVal * 100 + fracVal;
    return negative ? -satang : satang;
  }

  /// satang → a plain 2dp decimal string ("8050.00") suitable for sending as a money field
  /// (e.g. the payment `amount`). No grouping, no currency symbol.
  static String amountString(int satang) {
    final negative = satang < 0;
    final v = satang.abs();
    final s = '${v ~/ 100}.${(v % 100).toString().padLeft(2, '0')}';
    return negative ? '-$s' : s;
  }

  /// satang → a localized display string. `฿1,840`; `฿1,840.00` when [decimals]; drop the symbol
  /// with `symbol: false`.
  ///
  /// Satang are shown WHENEVER dropping them would misstate the amount, [decimals] or not. A job
  /// worth ฿0.04 used to render as `฿0` — money on screen that reads as no money at all — while the
  /// receipt (which passes `decimals: true`) showed `฿0.04` for the same job. Round amounts stay
  /// clean: `฿1,840`, not `฿1,840.00`. [decimals] still forces the two places on a round number,
  /// which is what a receipt wants.
  static String format(int satang,
      {bool decimals = false, bool symbol = true}) {
    final negative = satang < 0;
    final v = satang.abs();
    final baht = _group(v ~/ 100);
    final body = decimals || v % 100 != 0
        ? '$baht.${(v % 100).toString().padLeft(2, '0')}'
        : baht;
    return '${negative ? '-' : ''}${symbol ? '฿' : ''}$body';
  }

  /// Charge total in satang: `base_fee × hours × guard_count + tip`. All operands are satang
  /// except the integer multipliers [hours] and [guardCount].
  static int total({
    required int baseFeeSatang,
    required int hours,
    required int guardCount,
    int tipSatang = 0,
  }) =>
      baseFeeSatang * hours * guardCount + tipSatang;

  /// Group the integer part with thousands separators ("1840" → "1,840").
  static String _group(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
