import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// The shared pguard header (CLAUDE.md: use this widget, don't copy-paste header markup).
/// Usable as a [Scaffold.appBar] (implements [PreferredSizeWidget]). Supports an optional back
/// button, a subtitle, a trailing widget, and a pulsing LIVE indicator (used by the real-time
/// booking-status screen).
///
/// Two variants:
///  - default = the brand-green app bar (white text), for shells/marketing-adjacent surfaces;
///  - [light] = the hi-fi `.hd` in-body header (transparent surface, dark 19px title, a circular
///    "sunken" chevron back button) used by most in-app screens in the mockups.
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
    this.light = false,
  });

  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool live;
  final Color? background;

  /// Render the light in-body `.hd` variant (dark text on a transparent surface, circular sunken
  /// back) instead of the brand-green app bar. Matches the mockup's per-screen header.
  final bool light;

  static const double _barHeight = 64;

  @override
  Size get preferredSize => const Size.fromHeight(_barHeight);

  @override
  Widget build(BuildContext context) {
    final bg = background ?? (light ? Colors.transparent : PgTokens.colorBrand);
    final titleColor = light ? PgTokens.colorTextStrong : Colors.white;
    final subColor =
        light ? PgTokens.colorTextMuted : Colors.white.withValues(alpha: 0.82);
    final bar = Material(
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
                  light
                      ? _SunkenBack(onBack: onBack)
                      : IconButton(
                          onPressed:
                              onBack ?? () => Navigator.of(context).maybePop(),
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
                        style: TextStyle(
                          color: titleColor,
                          fontSize: light ? 19 : 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: subColor, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (live) _LiveBadge(light: light),
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
    // The light variant is transparent over the light screen surface, so the status bar shows a
    // light background — force DARK status-bar icons (the app's global default suits the green
    // bar's dark surface). Mirrors the per-screen AnnotatedRegion the auth screens use.
    return light
        ? AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.dark,
            child: bar,
          )
        : bar;
  }
}

/// The mockup `.iconbtn`: a 40×40 circular "sunken" back button with a dark chevron (light header).
class _SunkenBack extends StatelessWidget {
  const _SunkenBack({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: PgTokens.space2),
      child: Material(
        color: PgTokens.colorSunken,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onBack ?? () => Navigator.of(context).maybePop(),
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.chevron_left,
                size: 22, color: PgTokens.colorTextStrong),
          ),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({this.light = false});

  final bool light;

  @override
  Widget build(BuildContext context) {
    final color = light ? PgTokens.colorBrand : Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: PgTokens.space1),
        Text(
          'LIVE',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
