import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
import '../../core/models/money.dart';
import '../../core/models/payment.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';

/// Step 4 — payment. The total is the AUTHORITATIVE `base_fee × hours × guard_count` (from the
/// created booking) plus an optional tip; `POST /v1/payments` re-verifies it server-side. UI per
/// `Mobile Prototype.html` (payment). On success → success screen → live-status hand-off.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  PaymentMethod _method = PaymentMethod.promptpay;

  static const List<int> _tipPresets = [0, 5000, 10000]; // satang: ฿0 / ฿50 / ฿100

  Future<void> _pay() async {
    final ok = await ref.read(bookingFlowControllerProvider.notifier).pay(_method);
    if (ok && mounted) context.go('/book/success');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookingFlowControllerProvider);
    final ctrl = ref.read(bookingFlowControllerProvider.notifier);
    final subtotal = state.bookingSubtotalSatang;
    final total = state.payTotalSatang;

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: const PGuardHeader(
        title: 'ชำระเงิน',
        subtitle: 'Payment · ตัดจริงตามเวลางาน',
        showBack: true,
      ),
      body: SafeArea(
        child: subtotal == null || total == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(PgTokens.space6),
                  child: Text(
                    'ยังไม่พบการจอง\nBooking not ready',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: PgTokens.colorTextMuted),
                  ),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(PgTokens.space4),
                      children: [
                        _SummaryCard(state: state, subtotal: subtotal, total: total),
                        const SizedBox(height: PgTokens.space4),
                        const _Label('ทิปเจ้าหน้าที่ (ไม่บังคับ) / Tip (optional)'),
                        const SizedBox(height: PgTokens.space2),
                        _TipChips(
                          presets: _tipPresets,
                          selected: state.tipSatang,
                          onSelect: ctrl.setTipSatang,
                        ),
                        const SizedBox(height: PgTokens.space4),
                        const _Label('วิธีชำระเงิน / Payment method'),
                        const SizedBox(height: PgTokens.space2),
                        for (final method in PaymentMethod.values)
                          _MethodRow(
                            method: method,
                            selected: method == _method,
                            onTap: () => setState(() => _method = method),
                          ),
                        if (state.error != null) ...[
                          const SizedBox(height: PgTokens.space3),
                          Text(state.error!,
                              style: const TextStyle(
                                  color: PgTokens.colorDanger)),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(PgTokens.space4),
                    decoration: const BoxDecoration(
                      color: PgTokens.colorSurface,
                      border:
                          Border(top: BorderSide(color: PgTokens.colorBorder)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: PgPrimaryButton(
                        label:
                            'ชำระเงิน · ${Money.format(total)} / Pay',
                        busy: state.busy,
                        onPressed: state.busy ? null : _pay,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: PgTokens.colorTextMuted),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.state,
    required this.subtotal,
    required this.total,
  });

  final BookingFlowState state;
  final int subtotal;
  final int total;

  @override
  Widget build(BuildContext context) {
    final baseFeeSatang = Money.satangFromString(state.booking?.baseFee);
    // Mirror the multipliers used by bookingSubtotalSatang (server values when present) so the
    // line-item label and the computed subtotal can never disagree.
    final hours = state.booking?.hours ?? state.hours;
    final guards = state.booking?.guardCount ?? state.guardCount;
    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Column(
        children: [
          _Line(
            label:
                'ค่าบริการ ${Money.format(baseFeeSatang)} × $hours ชม. × $guards คน',
            value: Money.format(subtotal, decimals: true),
          ),
          if (state.tipSatang > 0) ...[
            const SizedBox(height: PgTokens.space2),
            _Line(
              label: 'ทิปเจ้าหน้าที่ / Tip',
              value: Money.format(state.tipSatang, decimals: true),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: PgTokens.space3),
            child: Divider(height: 1, color: PgTokens.colorBorder),
          ),
          _Line(
            label: 'ยอดชำระ / Total',
            value: Money.format(total, decimals: true),
            emphasize: true,
          ),
          const SizedBox(height: PgTokens.space2),
          const Text(
            'ยอดสุทธิคำนวณโดยระบบ — ตัดจริงตามเวลางาน',
            style: TextStyle(fontSize: 11, color: PgTokens.colorTextFaint),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: emphasize ? 16 : 13.5,
      fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
      color: emphasize ? PgTokens.colorText : PgTokens.colorTextMuted,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}

class _TipChips extends StatelessWidget {
  const _TipChips({
    required this.presets,
    required this.selected,
    required this.onSelect,
  });

  final List<int> presets;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: PgTokens.space2,
      children: [
        for (final tip in presets)
          ChoiceChip(
            label: Text(tip == 0 ? 'ไม่มี' : Money.format(tip)),
            selected: tip == selected,
            onSelected: (_) => onSelect(tip),
            selectedColor: PgTokens.colorGreen50,
            labelStyle: TextStyle(
              fontWeight: FontWeight.w600,
              color: tip == selected
                  ? PgTokens.colorGreen800
                  : PgTokens.colorText,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PgTokens.radiusFull),
              side: BorderSide(
                color: tip == selected
                    ? PgTokens.colorPrimary
                    : PgTokens.colorBorder,
              ),
            ),
            backgroundColor: PgTokens.colorSurface,
            showCheckmark: false,
          ),
      ],
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon {
    switch (method) {
      case PaymentMethod.promptpay:
        return Icons.qr_code_2;
      case PaymentMethod.creditCard:
        return Icons.credit_card;
      case PaymentMethod.debitCard:
        return Icons.credit_card_outlined;
      case PaymentMethod.mobileBanking:
        return Icons.account_balance_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PgTokens.space2),
      child: Material(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PgTokens.radiusLg),
          child: Container(
            padding: const EdgeInsets.all(PgTokens.space3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PgTokens.radiusLg),
              border: Border.all(
                  color: selected
                      ? PgTokens.colorPrimary
                      : PgTokens.colorBorder),
            ),
            child: Row(
              children: [
                Icon(_icon, size: 20, color: PgTokens.colorPrimary),
                const SizedBox(width: PgTokens.space3),
                Expanded(
                  child: Text(
                    '${method.labelTh} · ${method.labelEn}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? PgTokens.colorPrimary
                      : PgTokens.colorBorderStrong,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
