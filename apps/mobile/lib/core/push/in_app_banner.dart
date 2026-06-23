import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import 'in_app_banner_type.dart';

export 'in_app_banner_type.dart';

/// Global [OverlayState] key so a context-free layer (the push controller) can drop an in-app
/// banner — e.g. "New job nearby" — down from the top, over whatever screen is showing, without
/// holding a widget BuildContext. The overlay is installed by [inAppBannerBuilder] on the root
/// `MaterialApp.router` in `app.dart`. The production [showInAppBanner] reads this key; tests
/// override the `pushNotify` provider with a recorder, so this key is never touched under test.
final GlobalKey<OverlayState> inAppBannerKey = GlobalKey<OverlayState>();

/// Wraps the routed app in an [Overlay] (keyed by [inAppBannerKey]) so [showInAppBanner] has a
/// context-free surface to insert top toasts into, independent of the current route. Pass as the
/// `builder:` of `MaterialApp.router`.
Widget inAppBannerBuilder(BuildContext context, Widget? child) {
  return Overlay(
    key: inAppBannerKey,
    initialEntries: [
      OverlayEntry(builder: (_) => child ?? const SizedBox.shrink()),
    ],
  );
}

/// Drop an in-app banner down from the TOP of the screen (design #82): a rounded card with a
/// coloured left border + icon chip, a bold [title] and [message] body, an optional [onTap] action
/// and a close affordance. Auto-dismisses after ~4s; swipe-up or tap-✕ dismisses early; tapping the
/// card invokes [onTap] (and dismisses). Best-effort: a null overlay (before the first frame / under
/// test) is a no-op, never a crash.
void showInAppBanner(
  String message, {
  String? title,
  InAppBannerType type = InAppBannerType.info,
  VoidCallback? onTap,
}) {
  final overlay = inAppBannerKey.currentState;
  if (overlay == null) return;

  late final OverlayEntry entry;
  var removed = false;
  // Idempotent: the auto-dismiss timer, a tap, the close button and a swipe can all race to
  // remove the same entry. The toast only calls this after its exit animation (between frames),
  // so a synchronous remove is safe.
  void remove() {
    if (removed || !entry.mounted) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _TopToast(
      message: message,
      title: title,
      type: type,
      onTap: onTap,
      onDismiss: remove,
    ),
  );
  overlay.insert(entry);
}

class _ToastStyle {
  const _ToastStyle(this.color, this.bg, this.icon);
  final Color color;
  final Color bg;
  final IconData icon;
}

_ToastStyle _styleFor(InAppBannerType type) {
  switch (type) {
    case InAppBannerType.success:
      return const _ToastStyle(PgTokens.colorSuccess, PgTokens.colorSuccessBg,
          Icons.check_circle_outline);
    case InAppBannerType.error:
      return const _ToastStyle(
          PgTokens.colorDanger, PgTokens.colorDangerBg, Icons.error_outline);
    case InAppBannerType.warning:
      return const _ToastStyle(PgTokens.colorWarning, PgTokens.colorWarningBg,
          Icons.warning_amber_outlined);
    case InAppBannerType.info:
      return const _ToastStyle(
          PgTokens.colorInfo, PgTokens.colorInfoBg, Icons.info_outline);
  }
}

/// The animated card itself: slides down + fades in on mount, auto-dismisses after [_visible],
/// and exits (slide up + fade) before removing its overlay entry. Self-contained so the
/// context-free [showInAppBanner] never has to drive animation from outside the tree.
class _TopToast extends StatefulWidget {
  const _TopToast({
    required this.message,
    required this.title,
    required this.type,
    required this.onTap,
    required this.onDismiss,
  });

  final String message;
  final String? title;
  final InAppBannerType type;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  static const _visible = Duration(seconds: 4);
  static const _motion = Duration(milliseconds: 280);

  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: _motion);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    _timer = Timer(_visible, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    // Play the exit (slide up + fade), then ask the owner to remove the overlay entry. If the
    // widget was torn down mid-animation (e.g. a swipe already removed it), skip the removal.
    if (!mounted) return;
    await _ctrl.reverse();
    if (mounted) widget.onDismiss();
  }

  void _tapCard() {
    widget.onTap?.call();
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(widget.type);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: PgTokens.space3, vertical: PgTokens.space2),
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              // Swipe up to dismiss.
              child: Dismissible(
                key: const ValueKey('in_app_banner'),
                direction: DismissDirection.up,
                onDismissed: (_) {
                  _timer?.cancel();
                  widget.onDismiss();
                },
                child: Material(
                  color: Colors.transparent,
                  child: _card(style),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(_ToastStyle style) {
    // A rounded surface with a hairline border, plus a thick coloured LEFT accent strip (design
    // #82). The strip is a separate full-height child rather than a Border side, because Flutter
    // forbids a borderRadius on a non-uniform-colour Border.
    final radius = BorderRadius.circular(PgTokens.radiusXl);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: radius,
        border: Border.all(color: PgTokens.colorBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: InkWell(
          onTap: _tapCard,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The coloured left accent edge.
                Container(width: 4, color: style.color),
                Expanded(child: _body(style)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(_ToastStyle style) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          PgTokens.space3, PgTokens.space3, PgTokens.space2, PgTokens.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: style.bg,
              borderRadius: BorderRadius.circular(PgTokens.radiusLg),
            ),
            child: Icon(style.icon, color: style.color, size: 20),
          ),
          const SizedBox(width: PgTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.title != null && widget.title!.isNotEmpty) ...[
                  Text(
                    widget.title!,
                    style: const TextStyle(
                      fontSize: PgTokens.fontSizeSm,
                      fontWeight: FontWeight.w700,
                      color: PgTokens.colorTextStrong,
                      height: PgTokens.lineHeightSnug,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  widget.message,
                  style: const TextStyle(
                    fontSize: PgTokens.fontSizeSm,
                    color: PgTokens.colorTextMuted,
                    height: PgTokens.lineHeightSnug,
                  ),
                ),
              ],
            ),
          ),
          // Close affordance.
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 18,
              splashRadius: 18,
              color: PgTokens.colorTextFaint,
              onPressed: _dismiss,
              icon: const Icon(Icons.close),
              tooltip: 'Dismiss',
            ),
          ),
        ],
      ),
    );
  }
}
