import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/locale_controller.dart';

/// A compact TH | EN segmented control (the active segment is a raised pill). Per the design's
/// `.seg-sm` language control.
class LangSegmented extends StatelessWidget {
  const LangSegmented({super.key, required this.value, required this.onChanged});

  final AppLocale value;
  final ValueChanged<AppLocale> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: PgTokens.colorSunken,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in AppLocale.values)
            _Segment(
              label: l.label,
              selected: l == value,
              onTap: () => onChanged(l),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? PgTokens.colorSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(PgTokens.radiusFull),
          // Design `.seg-sm .on` elevation: --sh-xs (0 1px 2px rgba(8,38,25,.06)
          // ≈ colorText at 6% — nearest token to the design's shadow ink).
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: PgTokens.colorText.withValues(alpha: 0.06),
                    offset: const Offset(0, 1),
                    blurRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? PgTokens.colorText : PgTokens.colorTextMuted,
          ),
        ),
      ),
    );
  }
}
