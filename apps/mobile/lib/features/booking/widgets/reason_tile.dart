import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// The design's `.reason-opt` radio tile (Mobile - Cancellation.html), shared by the
/// customer cancellation screen and the guard withdraw screen: 15/16 padding, 1.5px
/// border ([PgTokens.colorBorder] → [PgTokens.colorPrimary] when selected), radius 14
/// ([PgTokens.radiusXl]), selected fill [PgTokens.colorGreen50], a 22px radio circle
/// with an 11px inner dot, and a 14.5px w600 label.
class PgReasonTile extends StatelessWidget {
  const PgReasonTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? PgTokens.colorGreen50 : Colors.transparent,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PgTokens.radiusXl),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PgTokens.radiusXl),
              border: Border.all(
                color:
                    selected ? PgTokens.colorPrimary : PgTokens.colorBorder,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                _RadioCircle(selected: selected),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: PgTokens.colorText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Design `.rd`: 22px circle, 2px border ([PgTokens.colorBorderStrong] at rest); when
/// selected the border turns brand and an 11px [PgTokens.colorPrimary] dot fills in.
class _RadioCircle extends StatelessWidget {
  const _RadioCircle({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color:
              selected ? PgTokens.colorPrimary : PgTokens.colorBorderStrong,
          width: 2,
        ),
      ),
      child: selected
          ? Container(
              width: 11,
              height: 11,
              decoration: const BoxDecoration(
                color: PgTokens.colorPrimary,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}
