import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/money.dart';
import '../models/payment.dart';
import '../providers.dart';
import 'customer_home_controller.dart' show thaiShortDate;

part 'wallet_controller.g.dart';

/// The customer "กระเป๋า" tab data: the caller's payments from `GET /v1/payments` (payments
/// where the caller is the paying customer, newest first — contracts/openapi/payment.yaml
/// `listPayments`). One fetch per controller lifetime; re-pulls are gesture-driven
/// (pull-to-refresh) — never a `Timer.periodic`. The money derivations are pure statics so
/// they unit-test without a container.
@riverpod
class WalletController extends _$WalletController {
  @override
  Future<List<Payment>> build() async {
    final data = await ref.read(pguardApiProvider).get('/payments');
    final raw = data is List ? data : const [];
    return raw.whereType<Map<String, dynamic>>().map(Payment.fromJson).toList();
  }

  /// Gesture-driven re-pull — never rethrows; the provider state carries any error.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // state is AsyncError — the screen shows PgErrorState with retry.
    }
  }

  /// What this payment actually cost the customer, in satang:
  ///  - `refunded`  → 0 (the whole charge came back);
  ///  - `final_amount` set → the server's prorated post-completion figure (authoritative);
  ///  - else `amount − refund_amount` (refund_amount null-safe → 0), clamped at 0.
  static int spentSatang(Payment p) {
    if (p.status == PaymentStatus.refunded) return 0;
    if (p.finalAmount != null) return Money.satangFromString(p.finalAmount);
    final net = Money.satangFromString(p.amount) -
        Money.satangFromString(p.refundAmount);
    return net < 0 ? 0 : net;
  }

  /// The figure a receipt ROW displays, in satang. Differs from [spentSatang] only for
  /// `refunded`: the row keeps the ORIGINAL charge (the badge explains the ฿0
  /// contribution to the hero); a prorated completed payment shows its effective
  /// `final_amount` so the rows always sum to the hero total for non-refunded items —
  /// no silent ฿-disagreement between a "Paid" row and the header (review-gate fold).
  static int rowAmountSatang(Payment p) {
    if (p.status == PaymentStatus.refunded) {
      return Money.satangFromString(p.amount);
    }
    return spentSatang(p);
  }

  /// Σ [spentSatang] — the "รวมจ่ายแล้ว / Total spent" header figure.
  static int totalSpentSatang(List<Payment> payments) {
    var sum = 0;
    for (final p in payments) {
      sum += spentSatang(p);
    }
    return sum;
  }

  /// The mono receipt reference for a row (design Screen 13 shows "PG-284910"). v2 has NO
  /// receipt-number field — this is a DISPLAY-ONLY derivation of the payment's booking id
  /// (first 8 hex chars), so the customer can correlate a receipt with its booking.
  static String paymentRef(Payment p) {
    final hex = p.bookingId.replaceAll('-', '').toUpperCase();
    return 'PG-${hex.length > 8 ? hex.substring(0, 8) : hex}';
  }

  /// Single-language status label for the row badge (locale-driven). "คืนเงินแล้ว" is the
  /// design's refunded wording (More_Screens.md Screen 5, cancelled row).
  static String statusLabel(PaymentStatus status, {required bool isThai}) {
    switch (status) {
      case PaymentStatus.pending:
        return isThai ? 'รอดำเนินการ' : 'Pending';
      case PaymentStatus.completed:
        return isThai ? 'ชำระแล้ว' : 'Paid';
      case PaymentStatus.refunded:
        return isThai ? 'คืนเงินแล้ว' : 'Refunded';
    }
  }
}

/// Thai short date WITH year for receipt rows, e.g. `3 มิ.ย. 2026` (design Screen 13 shows
/// the Gregorian year). Pure.
String thaiShortDateYear(DateTime when) =>
    '${thaiShortDate(when)} ${when.toLocal().year}';
