import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_status_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/payment_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/money.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import 'widgets/promptpay_slip_panel.dart';

/// THE PRE-PAY step. The instant a guard ACCEPTS, the customer lands here to pay the ESTIMATE
/// (`base_fee × booked-hours × guard_count + tip`) — the figure is READ from the authoritative
/// booking (the client never sends an amount; it posts only `{ booking_id }` and the payment
/// service computes + charges server-side). On success the screen flips to a PaymentSuccess
/// state and WAITS — over the booking-status WebSocket (no polling) — for the guard to proceed
/// once the booking un-gates (`paid_at` set via the `payment.completed` event).
///
/// The booking is read through [BookingStatusController] so the screen sits on the SAME live WS
/// the rest of the flow uses: status + `paid_at` advance by push, and a booking that is already
/// paid (e.g. re-entered) shows the success state straight away.
class PaymentScreen extends ConsumerWidget {
  const PaymentScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(bookingStatusControllerProvider(bookingId));

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: isThai ? 'ชำระเงิน' : 'Payment',
        subtitle: isThai ? 'ยืนยันการชำระเงิน' : 'Confirm payment',
        showBack: true,
        background: PgTokens.colorGreen800,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => PgErrorState(
            title: isThai ? 'โหลดยอดชำระไม่สำเร็จ' : 'Could not load payment',
            message: e is ApiException
                ? e.message
                : (isThai
                    ? 'ไม่สามารถโหลดยอดที่ต้องชำระได้ในขณะนี้'
                    : 'Payment details are unavailable right now'),
            onRetry: () =>
                ref.invalidate(bookingStatusControllerProvider(bookingId)),
          ),
          data: (booking) => _Body(bookingId: bookingId, booking: booking),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.bookingId, required this.booking});

  final String bookingId;
  final Booking booking;

  /// The PRE-PAY estimate in satang: `base_fee × booked-hours × guard_count + tip`, all from the
  /// authoritative booking. DISPLAY only — the server re-computes and charges this; the client
  /// sends only the booking id.
  int? get _estimateSatang {
    final baseFeeSatang = Money.satangFromString(booking.baseFee);
    final hours = booking.hours ?? 0;
    if (baseFeeSatang <= 0 || hours <= 0) return null;
    return Money.total(
      baseFeeSatang: baseFeeSatang,
      hours: hours,
      guardCount: booking.guardCount ?? 1,
      tipSatang: Money.satangFromString(booking.tip),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final payState = ref.watch(paymentControllerProvider(bookingId));

    // Paid is true once EITHER the booking already carries `paid_at` (re-entry / a WS snapshot
    // after the payment.completed event un-gated it) OR this session's POST /payments succeeded.
    final paid = booking.isPaid || payState.isPaid;

    return ListView(
      padding: const EdgeInsets.all(PgTokens.space4),
      children: [
        _SummaryCard(booking: booking, estimateSatang: _estimateSatang),
        const SizedBox(height: PgTokens.space4),
        if (paid)
          _PaidPanel(booking: booking)
        else if (payState.slipRequired)
          // The provider requires a transfer slip (PAYMENT_PROVIDER=slip2go): `POST /payments`
          // came back 409 SLIP_REQUIRED, so there is no auto-charge — render the PromptPay QR +
          // slip-upload flow. (The simulated default never sets this; the one-tap path is below.)
          PromptPaySlipPanel(bookingId: bookingId, booking: booking)
        else
          _PayPanel(
            bookingId: bookingId,
            estimateSatang: _estimateSatang,
            busy: payState.busy,
            error: payState.error,
            isThai: isThai,
          ),
      ],
    );
  }
}

/// The booking + price breakdown card: the per-hour rate, the booked hours, the guard count, the
/// tip and the server-computed total — the ESTIMATE the customer is about to pay.
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.booking, required this.estimateSatang});

  final Booking booking;
  final int? estimateSatang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final baseFeeSatang = Money.satangFromString(booking.baseFee);
    final hours = booking.hours ?? 0;
    final guardCount = booking.guardCount ?? 1;
    final tipSatang = Money.satangFromString(booking.tip);

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
          Row(
            children: [
              const Icon(Icons.shield_outlined,
                  size: 20, color: PgTokens.colorGreen800),
              const SizedBox(width: PgTokens.space2),
              Expanded(
                child: Text(
                  booking.address ?? (isThai ? 'การจอง' : 'Booking'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: PgTokens.space3),
            child: Divider(height: 1, color: PgTokens.colorBorder),
          ),
          _Line(
            label: isThai ? 'ค่าบริการ/ชม./คน' : 'Rate / hr / guard',
            value: baseFeeSatang > 0
                ? Money.format(baseFeeSatang, decimals: true)
                : '—',
          ),
          const SizedBox(height: PgTokens.space2),
          _Line(
            label: isThai ? 'จำนวนชั่วโมง' : 'Hours',
            value: '$hours',
          ),
          const SizedBox(height: PgTokens.space2),
          _Line(
            label: isThai ? 'จำนวนเจ้าหน้าที่' : 'Guards',
            value: '$guardCount',
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
                isThai ? 'ยอดชำระ (ประมาณ)' : 'Total (estimate)',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                estimateSatang != null
                    ? Money.format(estimateSatang!, decimals: true)
                    : '—',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: PgTokens.colorGreen800,
                ),
              ),
            ],
          ),
          const SizedBox(height: PgTokens.space2),
          Text(
            isThai
                ? 'คิดตามชั่วโมงที่จองไว้ — เมื่อจบงานจะปรับตามเวลาจริง และคืนเงินส่วนต่างหากใช้น้อยกว่า'
                : 'Charged for the booked hours — settled to the actual hours at completion '
                    '(any over-charge is refunded).',
            style:
                const TextStyle(fontSize: 11.5, color: PgTokens.colorTextMuted),
          ),
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

/// The pay action: the CTA + any error. Tapping it posts `{ booking_id }`; loading shows the
/// button spinner; an error renders inline (the customer can retry).
class _PayPanel extends ConsumerWidget {
  const _PayPanel({
    required this.bookingId,
    required this.estimateSatang,
    required this.busy,
    required this.error,
    required this.isThai,
  });

  final String bookingId;
  final int? estimateSatang;
  final bool busy;
  final String? error;
  final bool isThai;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          Container(
            padding: const EdgeInsets.all(PgTokens.space3),
            decoration: BoxDecoration(
              color: PgTokens.colorDangerBg,
              borderRadius: BorderRadius.circular(PgTokens.radiusLg),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 16, color: PgTokens.colorDanger),
                const SizedBox(width: PgTokens.space2),
                Expanded(
                  child: Text(error!,
                      style: const TextStyle(
                          fontSize: 12.5, color: PgTokens.colorDanger)),
                ),
              ],
            ),
          ),
          const SizedBox(height: PgTokens.space3),
        ],
        PgPrimaryButton(
          label: estimateSatang != null
              ? (isThai
                  ? 'ชำระเงิน ${Money.format(estimateSatang!)}'
                  : 'Pay ${Money.format(estimateSatang!)}')
              : (isThai ? 'ชำระเงิน' : 'Pay'),
          busy: busy,
          onPressed: busy
              ? null
              : () =>
                  ref.read(paymentControllerProvider(bookingId).notifier)
                      .createPayment(),
        ),
      ],
    );
  }
}

/// The PaymentSuccess state: "ชำระเงินสำเร็จ" + the customer now WAITS over the booking-status WS
/// for the guard to proceed. Offers a jump to the live-status screen.
class _PaidPanel extends ConsumerWidget {
  const _PaidPanel({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Container(
      padding: const EdgeInsets.all(PgTokens.space5),
      decoration: BoxDecoration(
        color: PgTokens.colorSuccessBg,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Icon(Icons.check_circle,
                size: 48, color: PgTokens.colorSuccess),
          ),
          const SizedBox(height: PgTokens.space3),
          Text(
            isThai ? 'ชำระเงินสำเร็จ' : 'Payment successful',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: PgTokens.colorGreen900),
          ),
          const SizedBox(height: PgTokens.space2),
          Text(
            isThai
                ? 'รอเจ้าหน้าที่เริ่มเดินทาง'
                : 'Waiting for the guard to set off',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: PgTokens.colorText),
          ),
          const SizedBox(height: PgTokens.space4),
          PgPrimaryButton(
            label: isThai ? 'ดูสถานะงาน' : 'View live status',
            onPressed: () => context.go('/booking/${booking.id}/live'),
          ),
        ],
      ),
    );
  }
}
