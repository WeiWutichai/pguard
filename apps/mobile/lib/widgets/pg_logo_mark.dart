import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// The pguard mark — shield + location pin on the brand gradient, drawn from the same
/// paths as the hi-fi SVG (admin-shell.js MARK, viewBox 0 0 100 106) so the app and the
/// design share one piece of artwork. Tokens only (gradient colorPrimary → colorBrand).
class PgLogoMark extends StatelessWidget {
  const PgLogoMark({super.key, this.size = 48});

  /// Width in logical px (height follows the 100:106 viewBox ratio).
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 1.06),
      painter: _MarkPainter(),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 100;
    final sy = size.height / 106;

    // Shield: M50 4 L88 18 V50 C88 78 72 95 50 104 C28 95 12 78 12 50 V18 Z
    final shield = Path()
      ..moveTo(50 * sx, 4 * sy)
      ..lineTo(88 * sx, 18 * sy)
      ..lineTo(88 * sx, 50 * sy)
      ..cubicTo(88 * sx, 78 * sy, 72 * sx, 95 * sy, 50 * sx, 104 * sy)
      ..cubicTo(28 * sx, 95 * sy, 12 * sx, 78 * sy, 12 * sx, 50 * sy)
      ..lineTo(12 * sx, 18 * sy)
      ..close();
    canvas.drawPath(
      shield,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [PgTokens.colorPrimary, PgTokens.colorBrand],
        ).createShader(Offset.zero & size),
    );

    // Pin: M50 30 C41 30 34 37 34 46 C34 58 50 74 50 74 C50 74 66 58 66 46 C66 37 59 30 50 30 Z
    final pin = Path()
      ..moveTo(50 * sx, 30 * sy)
      ..cubicTo(41 * sx, 30 * sy, 34 * sx, 37 * sy, 34 * sx, 46 * sy)
      ..cubicTo(34 * sx, 58 * sy, 50 * sx, 74 * sy, 50 * sx, 74 * sy)
      ..cubicTo(50 * sx, 74 * sy, 66 * sx, 58 * sy, 66 * sx, 46 * sy)
      ..cubicTo(66 * sx, 37 * sy, 59 * sx, 30 * sy, 50 * sx, 30 * sy)
      ..close();
    canvas.drawPath(pin, Paint()..color = PgTokens.colorSurface);

    canvas.drawCircle(
      Offset(50 * sx, 46 * sy),
      7.5 * sx,
      Paint()..color = PgTokens.colorPrimary,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
