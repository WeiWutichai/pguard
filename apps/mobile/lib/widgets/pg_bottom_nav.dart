import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// One of the four tab slots of [PgBottomNav].
class PgNavTab {
  const PgNavTab({
    required this.icon,
    required this.label,
    this.active = false,
    this.badgeCount = 0,
    this.onTap,
  });

  final IconData icon;

  /// Single-language label (locale-resolved by the caller), 10px.
  final String label;

  /// Active renders colorPrimary; inactive colorTextFaint.
  final bool active;

  /// Red count pill over the icon when > 0 (e.g. incoming jobs on "งาน / Jobs").
  final int badgeCount;

  /// Null = no-op (the already-active tab).
  final VoidCallback? onTap;
}

/// Visual config of [PgBottomNav]'s floating 62px centre action. The three design variants
/// are exposed as named constructors so screens never restate colors.
class PgNavFab {
  PgNavFab._({
    required this.icon,
    required this.label,
    required this.labelColor,
    required this.iconColor,
    required this.onTap,
    this.color,
    this.gradient,
    this.border,
  });

  /// Customer "เรียก รปภ. / Book" (design `.fab.amber`): solid amber (`--accent`) circle,
  /// shield icon on amber-950, amber-700 label.
  PgNavFab.book({required String label, required VoidCallback onTap})
      : this._(
          icon: Icons.shield_outlined,
          label: label,
          labelColor: PgTokens.colorAmber700,
          iconColor: PgTokens.colorOnAmber,
          color: PgTokens.colorAccent,
          onTap: onTap,
        );

  /// Guard duty toggle, on-duty (design `.fab.toggle-on`): shield+check on the amber
  /// gradient. Label color is the design's `--amber-600` (exact since the full-ramp regen).
  PgNavFab.onDuty({required String label, required VoidCallback onTap})
      : this._(
          icon: Icons.verified_user_outlined, // shield with checkmark
          label: label,
          labelColor: PgTokens.colorAmber600,
          iconColor: PgTokens.colorOnAmber,
          gradient: _dutyGradient,
          onTap: onTap,
        );

  /// Guard duty toggle, offline (design `.fab` default): sunken circle, 2px colorBorder
  /// ring, muted shield, faint label.
  PgNavFab.offline({required String label, required VoidCallback onTap})
      : this._(
          icon: Icons.shield_outlined,
          label: label,
          labelColor: PgTokens.colorTextFaint,
          iconColor: PgTokens.colorTextMuted,
          color: PgTokens.colorSunken,
          border: _offlineBorder,
          onTap: onTap,
        );

  final IconData icon;

  /// 9px w600 caption under the circle.
  final String label;
  final Color labelColor;
  final Color iconColor;
  final Color? color;
  final Gradient? gradient;
  final BoxBorder? border;
  final VoidCallback onTap;

  /// Design `linear-gradient(150deg, --amber-400, --amber-600)` — exact tokens since the
  /// full-ramp regen. Alignment pair = the CSS 150deg axis (unit vector (sin 150°, -cos 150°)).
  static const Gradient _dutyGradient = LinearGradient(
    begin: Alignment(-0.5, -0.866),
    end: Alignment(0.5, 0.866),
    colors: [PgTokens.colorAmber400, PgTokens.colorAmber600],
  );

  static const BoxBorder _offlineBorder =
      Border.fromBorderSide(BorderSide(color: PgTokens.colorBorder, width: 2));
}

/// Hi-fi bottom navigation per the design's nav states (Cancellation.md build spec, states
/// 4–5): a colorSurface bar with a 1px colorBorder top hairline, 8px vertical padding plus
/// the bottom safe-area, four 22px-icon tabs and a 62px centre FAB that floats
/// [fabOverhang] above the bar (Stack with `clipBehavior: Clip.none`).
///
/// Additive chrome only — mount via `Scaffold.bottomNavigationBar`; screens keep their
/// body/controllers untouched.
class PgBottomNav extends StatelessWidget {
  const PgBottomNav({super.key, required this.tabs, required this.fab})
      : assert(tabs.length == 4,
            'PgBottomNav takes exactly 4 tabs + the centre FAB');

  /// How far the centre FAB overhangs the bar's top edge (design `top: -30px`). Screens
  /// add this to their scroll-view bottom padding so the last row stays reachable.
  static const double fabOverhang = 30;

  final List<PgNavTab> tabs;
  final PgNavFab fab;

  /// SnackBar for tabs whose destination doesn't exist yet —
  /// no dead navigation, no fake routes. (No current tab uses it: การจอง / กระเป๋า /
  /// รายได้ now route to /bookings-history, /wallet and /earnings.)
  static void comingSoon(BuildContext context, {required bool isThai}) =>
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isThai ? 'เร็วๆ นี้' : 'Coming soon')));

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          decoration: const BoxDecoration(
            color: PgTokens.colorSurface,
            border: Border(top: BorderSide(color: PgTokens.colorBorder)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: PgTokens.space2),
              child: Row(
                children: [
                  Expanded(child: _NavTabItem(tab: tabs[0])),
                  Expanded(child: _NavTabItem(tab: tabs[1])),
                  // Centre slot — the FAB floats over it from the outer Stack.
                  const Expanded(child: SizedBox()),
                  Expanded(child: _NavTabItem(tab: tabs[2])),
                  Expanded(child: _NavTabItem(tab: tabs[3])),
                ],
              ),
            ),
          ),
        ),
        // Floats -30 over the bar. Standard Stack overflow: only the part inside the
        // bar's bounds is hit-testable — the lower (thumb-zone) half, per the design.
        Positioned(top: -fabOverhang, child: _FabCircle(fab: fab)),
        Positioned(
          top: 36, // design `.fab-label` top:36px from the bar's top edge
          child: Text(
            fab.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: fab.labelColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _NavTabItem extends StatelessWidget {
  const _NavTabItem({required this.tab});

  final PgNavTab tab;

  @override
  Widget build(BuildContext context) {
    final color = tab.active ? PgTokens.colorPrimary : PgTokens.colorTextFaint;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: tab.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(tab.icon, size: 22, color: color),
              if (tab.badgeCount > 0)
                // Design `.nbadge`: top -3, right edge 18px right of the item's centre
                // (icon is 22 wide ⇒ right: -7 off the icon box).
                Positioned(
                  top: -3,
                  right: -7,
                  child: _NavBadge(count: tab.badgeCount),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            tab.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }
}

/// Red count pill: min-w 16, h 16, radiusFull, 9px w700 white on colorDanger.
class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PgTokens.colorDanger,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

class _FabCircle extends StatelessWidget {
  const _FabCircle({required this.fab});

  final PgNavFab fab;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: fab.onTap,
      child: Container(
        width: 62,
        height: 62,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fab.color,
          gradient: fab.gradient,
          border: fab.border,
          // Design `--sh-lg` (0 8px 20px rgba(8,38,25,.10)) — PgTokens has no shadow
          // token; approximated as 10% black per the build brief.
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              offset: const Offset(0, 8),
              blurRadius: 20,
            ),
          ],
        ),
        child: Icon(fab.icon, size: 26, color: fab.iconColor),
      ),
    );
  }
}
