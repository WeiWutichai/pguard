import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// A tappable 1–5 star input (design `.stars` / `.ministars`). `value` is 0 (none) … 5; tapping a
/// star sets that score. Pure presentation — the screen owns the state. Used for the customer
/// review's overall rating (large) and the optional per-category ministars (small).
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 38,
    this.semanticPrefix,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  /// Prefixed onto each star's semantic label (e.g. "Punctuality" → "Punctuality 4 stars").
  final String? semanticPrefix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            button: true,
            label: semanticPrefix == null ? '$i' : '$semanticPrefix $i',
            selected: i <= value,
            child: InkResponse(
              onTap: () => onChanged(i),
              radius: size * 0.7,
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: Icon(
                  i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size,
                  color:
                      i <= value ? PgTokens.colorAccent : PgTokens.colorBorderStrong,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Read-only filled stars for a whole-star [value] (design `.stars-x`). Rounds to the nearest
/// whole star; the precise average is shown numerically alongside (never faked).
class StarRatingDisplay extends StatelessWidget {
  const StarRatingDisplay({super.key, required this.value, this.size = 13});

  final int value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i <= value ? PgTokens.colorAccent : PgTokens.colorBorderStrong,
          ),
      ],
    );
  }
}
