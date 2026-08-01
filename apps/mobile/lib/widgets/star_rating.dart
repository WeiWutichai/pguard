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
                  color: i <= value
                      ? PgTokens.colorAccent
                      : PgTokens.colorBorderStrong,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Read-only stars for a FRACTIONAL [value] (e.g. a 4.25 average): full / half / empty per star,
/// rounded to the nearest half. Used for the customer review's OVERALL star, which is the AVERAGE of
/// the per-category ministars (not a separate tap) — the precise number is shown alongside so the
/// half-star rounding is never mistaken for the exact figure.
class StarRatingAverage extends StatelessWidget {
  const StarRatingAverage({super.key, required this.value, this.size = 38});

  /// The average, 0.0 … 5.0.
  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Round to the nearest HALF star for the icons (the numeric label carries the precise value).
    final halves = (value.clamp(0, 5) * 2).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            halves >= i * 2
                ? Icons.star_rounded
                : (halves == i * 2 - 1
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded),
            size: size,
            color: halves >= i * 2 - 1
                ? PgTokens.colorAccent
                : PgTokens.colorBorderStrong,
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
            color:
                i <= value ? PgTokens.colorAccent : PgTokens.colorBorderStrong,
          ),
      ],
    );
  }
}
