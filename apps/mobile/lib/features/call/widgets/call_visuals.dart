import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import 'call_controls.dart';

/// Pure presentational widgets for the call screen (no controller / network imports):
/// background, ripple avatar, role pill, labelled round button, and the live MM:SS clock.

/// Status-line text style shared by the dialing / incoming / connecting captions
/// (13px, white @ 75%, slight letter-spacing per the design).
TextStyle callStatusStyle() => TextStyle(
      color: Colors.white.withValues(alpha: .75),
      fontSize: 13,
      letterSpacing: 0.5,
    );

/// The dark call backdrop: the design's green-800 → green-950 gradient (exact tokens since
/// the full-ramp regen) with an optional 40px hairline grid mesh overlay.
class CallBackground extends StatelessWidget {
  const CallBackground({super.key, this.showGrid = true});

  final bool showGrid;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PgTokens.colorGreen800, PgTokens.colorGreen950],
        ),
      ),
      child: showGrid
          ? const CustomPaint(
              painter: _GridPainter(), child: SizedBox.expand())
          : const SizedBox.expand(),
    );
  }
}

/// 40px-spaced hairlines at 4% white — the design's grid mesh.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  static const double _spacing = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .04)
      ..strokeWidth = 1;
    for (var x = _spacing; x < size.width; x += _spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = _spacing; y < size.height; y += _spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

/// A translucent-white avatar circle placeholder (the call models carry no name/avatar in v2)
/// with two pulsing ripple rings while ringing (scale 0.85→1.4, fade 0.6→0, 2s loop, the second
/// ring phase-shifted by 1s).
class CallAvatar extends StatefulWidget {
  const CallAvatar({super.key, this.size = 120, this.ripple = true});

  final double size;
  final bool ripple;

  @override
  State<CallAvatar> createState() => _CallAvatarState();
}

class _CallAvatarState extends State<CallAvatar>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.ripple) {
      _controller = AnimationController(
          vsync: this, duration: const Duration(seconds: 2))
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _ring(double phase) {
    final controller = _controller!;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final p = (controller.value + phase) % 1.0;
        final scale = 0.85 + (1.4 - 0.85) * Curves.easeOut.transform(p);
        final opacity = (1 - p) * 0.6;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: .3), width: 2),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .15),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.person, size: widget.size * 0.47, color: Colors.white),
    );
    if (!widget.ripple) return circle;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [_ring(0), _ring(0.5), circle],
      ),
    );
  }
}

/// The role pill under the peer name: guard = white tint + shield, customer = amber tint + person.
class CallRolePill extends StatelessWidget {
  const CallRolePill({super.key, required this.isThai, required this.customer});

  final bool isThai;
  final bool customer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: customer
            ? PgTokens.colorAccent.withValues(alpha: .25)
            : Colors.white.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            customer ? Icons.account_circle_outlined : Icons.shield_outlined,
            size: 13,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            customer
                ? (isThai ? 'ลูกค้า' : 'Customer')
                : (isThai ? 'เจ้าหน้าที่ รปภ.' : 'Security Guard'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A round call button with its 11px label below (design: icon circle + caption column).
/// Reuses [CallRoundButton] for the circle; glass (white 18%) is the default rest style.
class CallLabeledButton extends StatelessWidget {
  const CallLabeledButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.foreground = Colors.white,
    this.size = 62,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CallRoundButton(
          icon: icon,
          tooltip: label,
          color: color ?? Colors.white.withValues(alpha: .18),
          foreground: foreground,
          size: size,
          onPressed: onPressed,
        ),
        const SizedBox(height: PgTokens.space2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .8),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// MM:SS, monospace-ish via tabular figures (IBM Plex Mono is not bundled).
String _formatClock(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Live MM:SS readout since [since]. A frame [Ticker] (NOT `Timer.periodic`) that rebuilds only
/// when the displayed second changes; purely presentational, dies with the widget.
class CallElapsedClock extends StatefulWidget {
  const CallElapsedClock({super.key, required this.since});

  final DateTime since;

  @override
  State<CallElapsedClock> createState() => _CallElapsedClockState();
}

class _CallElapsedClockState extends State<CallElapsedClock>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late int _seconds;

  @override
  void initState() {
    super.initState();
    _seconds = DateTime.now().difference(widget.since).inSeconds;
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    final s = DateTime.now().difference(widget.since).inSeconds;
    if (s != _seconds) setState(() => _seconds = s);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatClock(_seconds),
      style: TextStyle(
        color: Colors.white.withValues(alpha: .85),
        fontSize: 13,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
