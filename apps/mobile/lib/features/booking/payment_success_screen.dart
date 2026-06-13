import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/money.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';

/// Step 5 — payment success, then hand off to the existing WS-driven live-status screen. The
/// amount shown is the server's charged value (`payment.amount`). UI per
/// `Mobile - Customer App.html` (payment success).
class PaymentSuccessScreen extends ConsumerWidget {
  const PaymentSuccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bookingFlowControllerProvider);
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final payment = state.payment;
    final booking = state.booking;

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: isThai ? 'ชำระเงินสำเร็จ' : 'Payment success',
        subtitle: isThai ? 'การจองได้รับการยืนยันแล้ว' : 'Booking confirmed',
        background: PgTokens.colorGreen800,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Design success hero: a bare 48px success-stroke checkmark (no tinted circle)
              // with ~56px top breathing room (space7 + the page's space6 padding).
              const SizedBox(height: PgTokens.space7),
              const Center(
                child: Icon(Icons.check_rounded,
                    size: 48, color: PgTokens.colorSuccess),
              ),
              const SizedBox(height: PgTokens.space4),
              Text(
                isThai ? 'ยืนยันการจองแล้ว!' : 'Booking confirmed!',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              if (payment != null) ...[
                const SizedBox(height: PgTokens.space2),
                Text(
                  isThai
                      ? 'ชำระแล้ว ${Money.format(Money.satangFromString(payment.amount), decimals: true)} · ตัดจริงตามเวลางาน'
                      : 'Paid ${Money.format(Money.satangFromString(payment.amount), decimals: true)} · charged by actual hours',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: PgTokens.colorTextMuted),
                ),
              ],
              const SizedBox(height: PgTokens.space6),
              _SummaryCard(state: state, isThai: isThai),
              const Spacer(),
              PgPrimaryButton(
                label: isThai ? 'ติดตามเจ้าหน้าที่' : 'Track guard',
                onPressed: booking != null
                    ? () => context.go('/booking/${booking.id}/live')
                    : null,
              ),
              const SizedBox(height: PgTokens.space2),
              PgGhostButton(
                label: isThai ? 'กลับหน้าหลัก' : 'Back home',
                onPressed: () => context.go('/home/customer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state, required this.isThai});

  final BookingFlowState state;
  final bool isThai;

  /// The booked time RANGE per the design ("วันนี้ 14:00 – 22:00"): date + start – end.
  /// The end instant is the pure [BookingFlowState.scheduledEndAt] (start + booked hours).
  String _formatRange(DateTime? start, DateTime? end) {
    if (start == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    final s = start.toLocal();
    final date = '${two(s.day)}/${two(s.month)}/${s.year}';
    final from = '${two(s.hour)}:${two(s.minute)}';
    if (end == null) return '$date  $from น.';
    final e = end.toLocal();
    return '$date  $from – ${two(e.hour)}:${two(e.minute)} น.';
  }

  @override
  Widget build(BuildContext context) {
    final method = state.payment?.paymentMethod;
    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Column(
        children: [
          _Row(
            icon: Icons.event_outlined,
            label: isThai ? 'เวลา' : 'Time',
            value: _formatRange(state.scheduledAt, state.scheduledEndAt),
          ),
          const SizedBox(height: PgTokens.space3),
          _Row(
            icon: Icons.location_on_outlined,
            label: isThai ? 'สถานที่' : 'Location',
            value: state.address.isEmpty ? '—' : state.address,
          ),
          if (method != null) ...[
            const SizedBox(height: PgTokens.space3),
            _Row(
              icon: Icons.payments_outlined,
              label: isThai ? 'ชำระโดย' : 'Paid via',
              value: method,
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: PgTokens.colorPrimary),
        const SizedBox(width: PgTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: PgTokens.colorTextMuted)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
