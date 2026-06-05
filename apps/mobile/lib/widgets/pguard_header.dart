import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// The shared pguard green header (CLAUDE.md: use this widget, don't copy-paste header
/// markup). Usable as a [Scaffold.appBar] (implements [PreferredSizeWidget]). Supports an
/// optional back button, a subtitle, a trailing widget, and a pulsing LIVE indicator (used by
/// the real-time booking-status screen).
class PGuardHeader extends StatelessWidget implements PreferredSizeWidget {
  const PGuardHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = false,
    this.onBack,
    this.trailing,
    this.live = false,
    this.background,
  });

  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool live;
  final Color? background;

  static const double _barHeight = 64;

  @override
  Size get preferredSize => const Size.fromHeight(_barHeight);

  @override
  Widget build(BuildContext context) {
    final bg = background ?? PgTokens.colorBrand;
    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: _barHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: PgTokens.space3),
            child: Row(
              children: [
                if (showBack)
                  IconButton(
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    color: Colors.white,
                    tooltip: 'Back',
                  )
                else
                  const SizedBox(width: PgTokens.space2),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (live) const _LiveBadge(),
                if (trailing != null) ...[
                  const SizedBox(width: PgTokens.space2),
                  trailing!
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
        const SizedBox(width: PgTokens.space1),
        const Text(
          'LIVE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
