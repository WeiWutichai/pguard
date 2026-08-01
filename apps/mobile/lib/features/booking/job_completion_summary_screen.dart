import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_payment_controller.dart';
import '../../core/controllers/booking_status_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/money.dart';
import '../../core/models/payment.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import 'widgets/job_receipt_sheet.dart';

/// THE job-completion summary, reached when the customer APPROVES the guard's completion request
/// (`pending_completion → completed`). Approval triggers the server-side RECONCILE on
/// `pguard.events.booking.completed`: the pre-pay charge is settled to the hours actually worked
/// and any overpay is recorded as a refund. This screen surfaces that settle — booked vs actual
/// hours, the base charge, the reconciled `final_amount` + `refund_amount` (with the admin-handled
/// note) and the tip — then sends the customer on to RATE the guard.
///
/// The order summary → rating is FORCED: the screen wraps in `PopScope(canPop: false)` so a back
/// gesture cannot skip the summary, and the only forward action is "ให้คะแนน/Rate".
///
/// Payment-read used: [bookingPaymentControllerProvider] → `GET /v1/payments` (the caller's own
/// payments), picking the row for this booking. When the settle hasn't propagated yet (no row),
/// the cost is DERIVED from the booking (pre-pay estimate) and the screen notes the backend gap.
class JobCompletionSummaryScreen extends ConsumerWidget {
  const JobCompletionSummaryScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final bookingAsync = ref.watch(bookingStatusControllerProvider(bookingId));

    // Force summary → rating: back is disabled so the customer cannot pop back to the live
    // screen and skip the summary on the way to the review.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: PgTokens.colorBg,
        appBar: PGuardHeader(
          title: isThai ? 'สรุปงาน' : 'Job summary',
          subtitle: isThai ? 'งานเสร็จสมบูรณ์' : 'Job completed',
          // No back button — the only way forward is to rate the guard.
          showBack: false,
          background: PgTokens.colorGreen800,
        ),
        body: SafeArea(
          child: bookingAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => PgErrorState(
              title: isThai ? 'โหลดสรุปงานไม่สำเร็จ' : 'Could not load summary',
              onRetry: () =>
                  ref.invalidate(bookingStatusControllerProvider(bookingId)),
            ),
            data: (booking) => _Body(bookingId: bookingId, booking: booking),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.bookingId, required this.booking});

  final String bookingId;
  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    // The reconciled payment may not have propagated yet (the completed→settle event chain is
    // async). Loading/error degrade to the booking-derived estimate so the customer is never
    // blocked from rating; a refresh re-pulls when the settle lands.
    final payment =
        ref.watch(bookingPaymentControllerProvider(bookingId)).valueOrNull;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(PgTokens.space4),
            children: [
              const _CompletedHero(),
              const SizedBox(height: PgTokens.space4),
              _BreakdownCard(booking: booking, payment: payment),
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: PgTokens.colorSurface,
            border: Border(top: BorderSide(color: PgTokens.colorBorder)),
          ),
          padding: const EdgeInsets.fromLTRB(
              20, PgTokens.space4, 20, PgTokens.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // "ดูใบเสร็จ" HERE, on the summary itself — the summary IS the receipt, but rating
              // pushReplaces it off the stack, so a customer who taps Rate (or later returns) had no
              // way back to their settled bill (the reported "หลังจบงานไม่มีปุ่มดูใบเสร็จ"). This
              // opens the same receipt sheet the live-status "View receipt" uses, with the owner's
              // reconciled payment when it has propagated (else booking-derived).
              PgGhostButton(
                label: isThai ? 'ดูใบเสร็จ' : 'View receipt',
                onPressed: () => showJobReceiptSheet(
                  context,
                  booking: booking,
                  payment: payment,
                  isThai: isThai,
                ),
              ),
              const SizedBox(height: PgTokens.space2),
              PgPrimaryButton(
                label: isThai ? 'ให้คะแนนเจ้าหน้าที่' : 'Rate the guard',
                color: PgTokens.colorAmber500,
                foreground: PgTokens.colorOnAmber,
                // Replace so the user can never come back to the summary AFTER rating (and the
                // PopScope above blocks skipping it BEFORE rating).
                onPressed: () =>
                    context.pushReplacement('/booking/$bookingId/review'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompletedHero extends ConsumerWidget {
  const _CompletedHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Column(
      children: [
        const Icon(Icons.check_circle, size: 56, color: PgTokens.colorSuccess),
        const SizedBox(height: PgTokens.space2),
        Text(
          isThai ? 'งานเสร็จสมบูรณ์' : 'Job completed',
          style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: PgTokens.colorGreen900),
        ),
        const SizedBox(height: 2),
        Text(
          isThai ? 'ขอบคุณที่ใช้บริการ' : 'Thanks for using pguard',
          style: const TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
        ),
      ],
    );
  }
}

/// The cost breakdown: booked vs actual hours, the base charge, the reconciled final amount +
/// refund (admin-handled note) and the tip. Reads the authoritative figures from the customer's
/// settled [payment] when present; otherwise derives them from the [booking] and flags the gap.
class _BreakdownCard extends ConsumerWidget {
  const _BreakdownCard({required this.booking, required this.payment});

  final Booking booking;
  final Payment? payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;

    final bookedHours = booking.hours ?? 0;
    final baseFeeSatang = Money.satangFromString(booking.baseFee);
    final guardCount = booking.guardCount ?? 1;
    final tipSatang = Money.satangFromString(booking.tip);

    // Actual hours come from the settle (`actual_hours`); null until the reconcile lands.
    final actualHours = payment?.actualHours;

    // Base charge: the pre-pay estimate of the base (base_fee × booked-hours × guards) shown for
    // context. The authoritative settled bill is `final_amount` (below).
    final baseChargeSatang = baseFeeSatang > 0 && bookedHours > 0
        ? baseFeeSatang * bookedHours * guardCount
        : 0;

    // The reconciled figures, authoritative when the settle has run.
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

    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isThai ? 'สรุปค่าบริการ' : 'Cost breakdown',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: PgTokens.space3),
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
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
                  ? 'กำลังประมวลผลยอดสุทธิ — ตัวเลขด้านบนเป็นยอดประมาณจากการจอง'
                  : 'Final settlement is still processing — the figures above are '
                      'estimated from your booking.',
              style: const TextStyle(
                  fontSize: 11.5, color: PgTokens.colorTextMuted),
            ),
          ],
        ],
      ),
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
