// Pure derivation of a Thai TAX INVOICE (ใบเสร็จรับเงิน / ใบกำกับภาษี) from a booking + its
// settled payment. No Flutter/HTTP imports → 100% unit-testable (CLAUDE.md: money math lives in
// core/controllers, screens only render).
//
// TAX MODEL (locked 2026-08): catalog prices are VAT-EXCLUSIVE.
//   subtotal    = base_fee × hours × guard_count + tip     ← the "ราคาสินค้า" the lines add up to
//   vat         = subtotal × 7%
//   grand_total = subtotal + vat                           ← what the customer is charged
// The payment service owns those figures; when the settled payment carries them
// (`subtotal`/`vat_amount`/`grand_total`) they are used VERBATIM — a tax document must state what
// was actually charged, never a client recomputation. Only when they are absent (a guard-side
// receipt with no readable payment, or a payment predating the tax split) does this fall back to
// deriving them from the booking, and the UI then labels the document an ESTIMATE.

import '../models/booking.dart';
import '../models/money.dart';
import '../models/payment.dart';
import 'customer_home_controller.dart' show thaiShortDate;

/// One line of the invoice's item table: `รายการ / จำนวนเงิน / ภาษีมูลค่าเพิ่ม / รวมเงิน`.
class ReceiptLine {
  const ReceiptLine({
    required this.labelTh,
    required this.labelEn,
    required this.amountSatang,
    required this.vatSatang,
    this.noteTh,
    this.noteEn,
  });

  final String labelTh;
  final String labelEn;

  /// The sub-label under the item name (e.g. the rate × hours × guards it came from).
  final String? noteTh;
  final String? noteEn;

  /// VAT-EXCLUSIVE line amount.
  final int amountSatang;

  /// This line's share of the VAT (see [ReceiptData.allocateVat] — the shares always add up to
  /// the document's VAT total, so the columns foot exactly).
  final int vatSatang;

  /// The line's `รวมเงิน` column.
  int get totalSatang => amountSatang + vatSatang;

  String label(bool isThai) => isThai ? labelTh : labelEn;
  String? note(bool isThai) => isThai ? noteTh : noteEn;
}

/// What KIND of document this is — a receipt must not claim to be something it isn't.
enum ReceiptKind {
  /// A settled charge WITH a VAT split: a full Thai tax invoice (ใบเสร็จรับเงิน/ใบกำกับภาษี).
  taxInvoice,

  /// A settled charge taken BEFORE VAT was itemized: a real receipt, but no tax was charged, so
  /// it is titled as a plain receipt and its VAT line is a truthful ฿0.00.
  receiptNoVat,

  /// No readable payment (the guard's side of a job): figures derived from the booking. An
  /// estimate — never presented as a tax document.
  estimate,
}

/// Everything the tax invoice prints, derived once so the widget only lays it out.
class ReceiptData {
  const ReceiptData({
    required this.lines,
    required this.subtotalSatang,
    required this.vatSatang,
    required this.grandTotalSatang,
    required this.kind,
    required this.documentNumber,
    this.issuedAt,
    this.paymentMethod,
    this.cancellationFeeSatang = 0,
    this.refundSatang = 0,
    this.bookedHours,
    this.actualHours,
  });

  final List<ReceiptLine> lines;

  /// VAT-EXCLUSIVE total of [lines].
  final int subtotalSatang;

  /// The document's VAT (7%).
  final int vatSatang;

  /// จำนวนเงินรวมทั้งสิ้น — what the customer was charged.
  final int grandTotalSatang;

  /// Which document this is (see [ReceiptKind]) — drives the title and the honesty notice.
  final ReceiptKind kind;

  /// True when no settled payment was readable and the figures were derived from the booking, so
  /// the document is an estimate, not a record of a charge. The header says so.
  bool get isEstimate => kind == ReceiptKind.estimate;

  /// เลขที่ — stable, derived from the payment (or booking) id so re-opening prints the same number.
  final String documentNumber;

  /// วันที่ — when the money moved (`paid_at`), falling back to the payment's creation and then to
  /// the job's schedule. `null` when nothing is known (an unpaid, unscheduled booking).
  final DateTime? issuedAt;

  /// Raw wire value of `payment_method` (e.g. `promptpay`); `null` for a booking-derived receipt.
  final String? paymentMethod;

  /// What was KEPT when the customer cancelled pre-arrival (`min(fee, paid)`), 0 when none.
  final int cancellationFeeSatang;

  /// What is being returned to the customer, 0 when none.
  final int refundSatang;

  /// The booked hours and — when the settle recorded them — the hours actually worked, so the
  /// document can show a reconciliation that changed the bill instead of silently restating it.
  final int? bookedHours;
  final String? actualHours;

  /// True when a cancellation fee was withheld or a refund is owed — the invoice then prints an
  /// after-the-fact adjustment block under the grand total.
  bool get hasAdjustments => cancellationFeeSatang > 0 || refundSatang > 0;

  /// What the customer ultimately keeps out of pocket after any refund.
  int get netPaidSatang => grandTotalSatang - refundSatang;

  /// Split [totalVat] across [lineSubtotals] IN PROPORTION to each line, with the last line
  /// absorbing the rounding remainder. Guarantees `Σ line VAT == totalVat`, so the VAT column can
  /// never fail to add up to the VAT the customer was actually charged — the one arithmetic error
  /// a tax document must not contain.
  static List<int> allocateVat(List<int> lineSubtotals, int totalVat) {
    if (lineSubtotals.isEmpty) return const [];
    final base = lineSubtotals.fold<int>(0, (a, b) => a + b);
    if (base == 0) {
      return [
        for (var i = 0; i < lineSubtotals.length; i++)
          i == lineSubtotals.length - 1 ? totalVat : 0,
      ];
    }
    final out = <int>[];
    var used = 0;
    for (var i = 0; i < lineSubtotals.length; i++) {
      if (i == lineSubtotals.length - 1) {
        out.add(totalVat - used);
      } else {
        final share = (totalVat * lineSubtotals[i] / base).round();
        out.add(share);
        used += share;
      }
    }
    return out;
  }

  /// Build the document.
  ///
  /// The AUTHORITATIVE figures are the settled [payment]'s (`subtotal` / `vat_amount` /
  /// `grand_total`). Without them the money is derived from the booking's own server-owned fields
  /// and [isEstimate] is set. The item split (service vs tip) always comes from the booking, with
  /// the service line taking `subtotal − tip` so the lines foot to the authoritative subtotal even
  /// after a reconcile changed the hours.
  factory ReceiptData.from({
    required Booking booking,
    required Payment? payment,
  }) {
    final tipSatang = Money.satangFromString(booking.tip);
    final baseFeeSatang = Money.satangFromString(booking.baseFee);
    final bookedHours = booking.hours ?? 0;
    final guardCount = booking.guardCount ?? 1;

    // Booking-derived base: base_fee × booked-hours × guards.
    final derivedBase = baseFeeSatang > 0 && bookedHours > 0
        ? baseFeeSatang * bookedHours * guardCount
        : 0;

    // WHICH DOCUMENT: a payment carrying a VAT split is a tax invoice; a payment without one is a
    // real (pre-VAT) receipt whose `amount` was the whole charge — inventing 7% on top of it would
    // overstate what the customer actually paid; no payment at all is an estimate.
    final settledVat = payment?.vatSatang;
    final ReceiptKind kind;
    if (payment == null) {
      kind = ReceiptKind.estimate;
    } else if (settledVat == null) {
      kind = ReceiptKind.receiptNoVat;
    } else {
      kind = ReceiptKind.taxInvoice;
    }

    final int subtotal;
    final int vat;
    final int grandTotal;
    switch (kind) {
      case ReceiptKind.taxInvoice:
        // Verbatim from the settle: a tax document states what was charged, not a recomputation.
        subtotal =
            payment!.subtotalSatang ?? (payment.grandTotalSatang - settledVat!);
        vat = settledVat!;
        grandTotal = payment.grandTotalSatang;
      case ReceiptKind.receiptNoVat:
        // The whole `amount` was the charge and no tax was taken.
        grandTotal = payment!.grandTotalSatang;
        subtotal = grandTotal;
        vat = 0;
      case ReceiptKind.estimate:
        subtotal = derivedBase + tipSatang;
        vat = Money.vat(subtotal);
        grandTotal = subtotal + vat;
    }

    // The service line takes whatever the subtotal is, minus the tip — so tip + service == subtotal
    // exactly, whichever side the subtotal came from. Clamped at 0 for a tip-only edge case.
    final serviceAmount = (subtotal - tipSatang) < 0 ? 0 : subtotal - tipSatang;

    final actualHours = payment?.actualHours;
    final hoursLabel = actualHours ?? (bookedHours > 0 ? '$bookedHours' : null);
    final rate =
        baseFeeSatang > 0 ? Money.format(baseFeeSatang, decimals: true) : null;
    final noteTh = rate != null && hoursLabel != null
        ? '$rate × $hoursLabel ชม.${guardCount > 1 ? ' × $guardCount คน' : ''}'
        : null;
    final noteEn = rate != null && hoursLabel != null
        ? '$rate × $hoursLabel hr${guardCount > 1 ? ' × $guardCount guards' : ''}'
        : null;

    final amounts = <int>[
      serviceAmount,
      if (tipSatang > 0) tipSatang,
    ];
    final vatShares = allocateVat(amounts, vat);

    final lines = <ReceiptLine>[
      ReceiptLine(
        labelTh: 'ค่าบริการรักษาความปลอดภัย',
        labelEn: 'Security guard service',
        noteTh: noteTh,
        noteEn: noteEn,
        amountSatang: serviceAmount,
        vatSatang: vatShares.first,
      ),
      if (tipSatang > 0)
        ReceiptLine(
          labelTh: 'ทิป',
          labelEn: 'Tip',
          amountSatang: tipSatang,
          vatSatang: vatShares.last,
        ),
    ];

    return ReceiptData(
      lines: lines,
      subtotalSatang: subtotal,
      vatSatang: vat,
      grandTotalSatang: grandTotal,
      kind: kind,
      documentNumber: documentNumberFor(payment?.id ?? booking.id),
      issuedAt: payment?.paidAt ?? payment?.createdAt ?? booking.scheduledAt,
      paymentMethod: payment?.paymentMethod,
      cancellationFeeSatang: payment?.cancellationFeeChargedSatang ?? 0,
      refundSatang: Money.satangFromString(payment?.refundAmount),
      bookedHours: bookedHours > 0 ? bookedHours : null,
      actualHours: actualHours,
    );
  }

  /// `RCP-` + the first 8 hex digits of the source id, uppercased — a stable, human-quotable
  /// document number (a receipt re-opened tomorrow must carry the number it carried today).
  static String documentNumberFor(String id) {
    final compact = id.replaceAll('-', '').toUpperCase();
    final head = compact.length >= 8 ? compact.substring(0, 8) : compact;
    return 'RCP-$head';
  }

  /// วันที่ on the document: `10 ส.ค. 2569` (Buddhist era) / `10 Aug 2026`. Reuses the app's one
  /// month-name table ([thaiShortDate]) and adds the year a tax document needs.
  static String formatIssuedDate(DateTime when, {required bool isThai}) {
    final local = when.toLocal();
    final year = isThai ? local.year + 543 : local.year;
    return '${thaiShortDate(local, isThai: isThai)} $year';
  }

  /// A human label for the wire `payment_method`; unknown values are shown as-is rather than
  /// hidden — a receipt should never invent how the money was taken.
  static String paymentMethodLabel(String? method, {required bool isThai}) {
    switch (method) {
      case null:
      case '':
        return '—';
      case 'promptpay':
      case 'slip2go':
        return isThai ? 'พร้อมเพย์ / โอนเงิน' : 'PromptPay / bank transfer';
      case 'simulated':
        return isThai ? 'ชำระผ่านระบบ (ทดสอบ)' : 'In-app (simulated)';
      case 'post_paid':
        return isThai ? 'ชำระปลายทาง' : 'Post-paid';
      default:
        return method;
    }
  }
}
