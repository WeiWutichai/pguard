import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/models/booking.dart';
import '../../../core/models/money.dart';
import '../../../core/models/payment.dart';

/// A simple, shared job RECEIPT for a paid + completed booking — the cost breakdown both the
/// customer and the guard can reach from the completed view (#99c). Reuses the SAME figures the
/// job-completion summary derives.
///
/// RECEIPT SOURCE (a deliberate, flagged limitation):
///   • The CUSTOMER passes their settled [payment] (from owner-scoped `GET /v1/payments`) so the
///     authoritative reconciled `final_amount` / `refund_amount` / `actual_hours` show.
///   • The GUARD has NO readable payment: `GET /v1/payments` is owner-scoped (returns the guard's
///     OWN customer payments — empty for a guard's job), and `GET /v1/payments/{id}` is owner-or-
///     admin only — a guard cannot read the customer's payment row. So the guard passes
///     `payment: null` and the receipt is DERIVED from the booking (base_fee × booked-hours ×
///     guards + tip), with a note that the settled figures aren't available on this side.
///
/// BACKEND FOLLOW-UP (flagged): there is no receipt endpoint in `contracts/openapi/payment.yaml`
/// (only owner-scoped `GET /payments`, owner/admin `GET /payments/{id}`, and admin ledgers). A
/// participants-scoped `GET /v1/payments/by-booking/{booking_id}/receipt` (readable by the
/// booking's customer AND its assigned guard) would let the guard show the real settled bill +
/// any refund. Until then the guard side is booking-derived only.
Future<void> showJobReceiptSheet(
  BuildContext context, {
  required Booking booking,
  required Payment? payment,
  required bool isThai,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: PgTokens.colorSurface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(PgTokens.radius2xl)),
    ),
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              PgTokens.space5, 0, PgTokens.space5, PgTokens.space5),
          child: JobReceiptBody(
            booking: booking,
            payment: payment,
            isThai: isThai,
          ),
        ),
      ),
    ),
  );
}

/// The receipt body (header + cost breakdown). Pulled out of the sheet so it can also be embedded
/// inline (e.g. on the customer's completion summary). Read-only; DISPLAY figures only — the
/// authoritative bill is the payment service's.
class JobReceiptBody extends StatelessWidget {
  const JobReceiptBody({
    super.key,
    required this.booking,
    required this.payment,
    required this.isThai,
  });

  final Booking booking;
  final Payment? payment;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final bookedHours = booking.hours ?? 0;
    final baseFeeSatang = Money.satangFromString(booking.baseFee);
    final guardCount = booking.guardCount ?? 1;
    final tipSatang = Money.satangFromString(booking.tip);

    // Actual hours come from the settle (`actual_hours`); null until the reconcile lands / for
    // the booking-derived (guard) receipt.
    final actualHours = payment?.actualHours;

    // Base charge: pre-pay estimate of the base (base_fee × booked-hours × guards) for context.
    final baseChargeSatang = baseFeeSatang > 0 && bookedHours > 0
        ? baseFeeSatang * bookedHours * guardCount
        : 0;

    final finalAmount = payment?.finalAmount;
    final refundAmount = payment?.refundAmount;
    final refundSatang = Money.satangFromString(refundAmount);
    final hasRefund = refundAmount != null && refundSatang > 0;

    // Final the customer effectively pays: the server's prorated `final_amount` when set, else the
    // pre-pay `amount`, else the booking-derived estimate (base + tip). DISPLAY only.
    final int? finalSatang = finalAmount != null
        ? Money.satangFromString(finalAmount)
        : (payment != null
            ? Money.satangFromString(payment!.amount)
            : (baseChargeSatang > 0 ? baseChargeSatang + tipSatang : null));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 20, color: PgTokens.colorGreen800),
            const SizedBox(width: PgTokens.space2),
            Text(
              isThai ? 'ใบสรุปค่าบริการ' : 'Receipt',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: PgTokens.space4),
        _Line(
          label: isThai ? 'ชั่วโมงที่จอง' : 'Booked hours',
          value: bookedHours > 0 ? '$bookedHours' : '—',
        ),
        const SizedBox(height: PgTokens.space2),
        _Line(
          label: isThai ? 'ชั่วโมงจริง' : 'Actual hours',
          value: actualHours ?? (bookedHours > 0 ? '$bookedHours' : '—'),
        ),
        if (guardCount > 1) ...[
          const SizedBox(height: PgTokens.space2),
          _Line(
            label: isThai ? 'จำนวนเจ้าหน้าที่' : 'Guards',
            value: '$guardCount',
          ),
        ],
        const SizedBox(height: PgTokens.space2),
        _Line(
          label: isThai ? 'ค่าบริการ (ตามจอง)' : 'Base charge (booked)',
          value: baseChargeSatang > 0
              ? Money.format(baseChargeSatang, decimals: true)
              : '—',
        ),
        if (tipSatang > 0) ...[
          const SizedBox(height: PgTokens.space2),
          _Line(
            label: isThai ? 'ทิป' : 'Tip',
            value: Money.format(tipSatang, decimals: true),
          ),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: PgTokens.space3),
          child: Divider(height: 1, color: PgTokens.colorBorder),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isThai ? 'ยอดสุทธิ' : 'Final amount',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            Text(
              finalSatang != null
                  ? Money.format(finalSatang, decimals: true)
                  : '—',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: PgTokens.colorGreen800,
              ),
            ),
          ],
        ),
        if (hasRefund) ...[
          const SizedBox(height: PgTokens.space3),
          Container(
            padding: const EdgeInsets.all(PgTokens.space3),
            decoration: BoxDecoration(
              color: PgTokens.colorAmber50,
              borderRadius: BorderRadius.circular(PgTokens.radiusLg),
              border: Border.all(color: PgTokens.colorAmber200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.replay_outlined,
                            size: 16, color: PgTokens.colorAmber700),
                        const SizedBox(width: PgTokens.space2),
                        Text(
                          isThai ? 'ยอดคืนเงิน' : 'Refund',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Text(
                      Money.format(refundSatang, decimals: true),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: PgTokens.colorAmber700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: PgTokens.space2),
                Text(
                  isThai
                      ? 'ยอดคืนเงินจะถูกดำเนินการโดยทีมแอดมินภายหลัง'
                      : 'Refund handled by admin',
                  style: const TextStyle(
                      fontSize: 11.5, color: PgTokens.colorTextMuted),
                ),
              ],
            ),
          ),
        ],
        if (payment == null) ...[
          const SizedBox(height: PgTokens.space3),
          Text(
            isThai
                ? 'ยอดสุทธิเป็นยอดประมาณจากการจอง — ยอดที่เรียกเก็บจริงดูได้จากฝั่งลูกค้า'
                : 'Figures are estimated from the booking — the settled bill is on the '
                    "customer's side.",
            style: const TextStyle(
                fontSize: 11.5, color: PgTokens.colorTextMuted),
          ),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 13, color: PgTokens.colorTextMuted)),
        Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
