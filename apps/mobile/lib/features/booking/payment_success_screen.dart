import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
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
    final payment = state.payment;
    final booking = state.booking;

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: const PGuardHeader(
        title: 'ชำระเงินสำเร็จ',
        subtitle: 'Payment success',
        background: PgTokens.colorGreen800,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: PgTokens.space6),
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(
                    color: PgTokens.colorSuccessBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 44, color: PgTokens.colorSuccess),
                ),
              ),
              const SizedBox(height: PgTokens.space4),
              const Text(
                'ยืนยันการจองแล้ว!\nBooking confirmed!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              if (payment != null) ...[
                const SizedBox(height: PgTokens.space2),
                Text(
                  'ชำระแล้ว ${Money.format(Money.satangFromString(payment.amount), decimals: true)} · ตัดจริงตามเวลางาน',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: PgTokens.colorTextMuted),
                ),
              ],
              const SizedBox(height: PgTokens.space6),
              _SummaryCard(state: state),
              const Spacer(),
              PgPrimaryButton(
                label: 'ติดตามเจ้าหน้าที่ / Track guard',
                onPressed: booking != null
                    ? () => context.go('/booking/${booking.id}/live')
                    : null,
              ),
              const SizedBox(height: PgTokens.space2),
              PgGhostButton(
                label: 'กลับหน้าหลัก / Back home',
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
  const _SummaryCard({required this.state});

  final BookingFlowState state;

  String _formatWhen(DateTime? when) {
    if (when == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    final l = when.toLocal();
    return '${two(l.day)}/${two(l.month)}/${l.year}  ${two(l.hour)}:${two(l.minute)} น.';
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
            label: 'เวลา / Time',
            value: _formatWhen(state.scheduledAt),
          ),
          const SizedBox(height: PgTokens.space3),
          _Row(
            icon: Icons.location_on_outlined,
            label: 'สถานที่ / Location',
            value: state.address.isEmpty ? '—' : state.address,
          ),
          if (method != null) ...[
            const SizedBox(height: PgTokens.space3),
            _Row(
              icon: Icons.payments_outlined,
              label: 'ชำระโดย / Paid via',
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
