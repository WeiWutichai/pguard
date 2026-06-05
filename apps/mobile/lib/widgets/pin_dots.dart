import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// The PIN progress dots (per design: 16px circles, 15px gap). Filled = primary green,
/// error = danger red, empty = strong border outline.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.length,
    required this.filled,
    this.error = false,
  });

  final int length;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final fill = error ? PgTokens.colorDanger : PgTokens.colorPrimary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final isFilled = i < filled;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7.5),
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled ? fill : Colors.transparent,
              border: Border.all(
                color: isFilled ? fill : PgTokens.colorBorderStrong,
                width: 2,
              ),
            ),
          ),
        );
      }),
    );
  }
}
