import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// A static, muted placeholder box — the building block for the app's stale-while-revalidate
/// skeletons (perf-review #1). Rendered instead of a full-screen spinner so a screen shows its
/// SHAPE (chrome + skeleton rows) on a cold open / re-entry rather than blanking. Deliberately
/// NON-animated (no Ticker) so it never leaves a pending timer in a widget test.
class PgSkeletonBox extends StatelessWidget {
  const PgSkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = PgTokens.radiusMd,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: PgTokens.colorSunken,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A skeleton "card" — a bordered surface panel of [height] used to stand in for a list row / stat
/// card while its data loads.
class PgSkeletonCard extends StatelessWidget {
  const PgSkeletonCard({super.key, this.height = 72, this.child});

  final double height;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: child == null ? height : null,
      width: double.infinity,
      padding: child == null ? null : const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: child,
    );
  }
}

/// A vertical stack of [count] skeleton cards separated by [gap] — the common "list is loading"
/// placeholder body.
class PgSkeletonList extends StatelessWidget {
  const PgSkeletonList({
    super.key,
    this.count = 3,
    this.itemHeight = 72,
    this.gap = PgTokens.space3,
  });

  final int count;
  final double itemHeight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i != 0) SizedBox(height: gap),
          PgSkeletonCard(height: itemHeight),
        ],
      ],
    );
  }
}
