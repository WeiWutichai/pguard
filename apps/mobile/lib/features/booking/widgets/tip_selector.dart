import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/booking_flow_controller.dart';
import '../../../core/controllers/locale_controller.dart';
import '../../../core/models/money.dart';

/// Flat-tip selector on the booking form. v2 is POST-PAY: the tip rides the booking (sent by
/// `createBooking`) and is billed in FULL on completion (never prorated). Preset pills
/// ฿0/฿50/฿100 + a custom-amount option, wired to [BookingFlowController.setTipSatang].
/// (Ported from the removed up-front payment screen.)
class TipSelector extends ConsumerWidget {
  const TipSelector({super.key});

  static const List<int> _presets = [0, 5000, 10000]; // satang: ฿0 / ฿50 / ฿100

  /// Custom-amount dialog feeding [setTipSatang] (parsing via the pure [Money] helper).
  Future<void> _promptCustom(
      BuildContext context, WidgetRef ref, bool isThai) async {
    final input = TextEditingController();
    final satang = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isThai ? 'ระบุทิป' : 'Custom tip'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            prefixText: '฿ ',
            labelText: isThai ? 'จำนวนเงิน (บาท)' : 'Amount (THB)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, Money.satangFromString(input.text)),
            child: Text(isThai ? 'ตกลง' : 'OK'),
          ),
        ],
      ),
    );
    input.dispose();
    if (satang != null) {
      ref.read(bookingFlowControllerProvider.notifier).setTipSatang(satang);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final selected =
        ref.watch(bookingFlowControllerProvider.select((s) => s.tipSatang));
    final ctrl = ref.read(bookingFlowControllerProvider.notifier);
    // A tip outside the presets means the "ระบุ" (custom) option is active.
    final customActive = !_presets.contains(selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isThai ? 'ทิป (ไม่บังคับ)' : 'Tip (optional)',
          style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: PgTokens.colorText),
        ),
        const SizedBox(height: PgTokens.space2),
        Wrap(
          spacing: PgTokens.space2,
          children: [
            for (final tip in _presets)
              _TipChip(
                label: Money.format(tip),
                selected: tip == selected,
                onTap: () => ctrl.setTipSatang(tip),
              ),
            _TipChip(
              label: isThai ? 'ระบุ' : 'Custom',
              selected: customActive,
              onTap: () => _promptCustom(context, ref, isThai),
            ),
          ],
        ),
      ],
    );
  }
}

class _TipChip extends StatelessWidget {
  const _TipChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: selected ? PgTokens.colorPrimary : PgTokens.colorText,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
        side: BorderSide(
            color: selected ? PgTokens.colorPrimary : PgTokens.colorBorder),
      ),
      backgroundColor: PgTokens.colorSurface,
      selectedColor: PgTokens.colorSurface,
      showCheckmark: false,
    );
  }
}
