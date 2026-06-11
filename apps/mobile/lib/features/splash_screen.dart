import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../widgets/pg_logo_mark.dart';

/// Shown while the session state loads from secure storage (router redirects away once known).
/// Hi-fi System state 1: brand gradient + faint 40px grid, logo mark above the two-tone
/// wordmark and tagline, 34px spinner anchored near the bottom.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Design: linear-gradient(165deg, --green-700, --green-950). Those two stops have
        // no exact tokens — nearest are colorGreen800 → colorBrand (flag for token regen).
        // 165deg CSS angle → unit vector (sin165°, −cos165°) = (0.259, 0.966 downward),
        // mirrored for begin (same exact-axis pattern as PgNavFab's 150deg gradient).
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.259, -0.966),
            end: Alignment(0.259, 0.966),
            colors: [PgTokens.colorGreen800, PgTokens.colorBrand],
          ),
        ),
        child: CustomPaint(
          // Grid decoration overlay: transparent white lines, 40px spacing.
          painter: _GridPainter(),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PgLogoMark(size: 72),
                    // Design: wordmark margin-top 18px (non-token design metric).
                    const SizedBox(height: 18),
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'p',
                            style: TextStyle(color: PgTokens.colorPrimary),
                          ),
                          TextSpan(
                            text: 'guard',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1, // -0.03em × 34px
                      ),
                    ),
                    const SizedBox(height: PgTokens.space2),
                    Text(
                      'ความปลอดภัย ณ ตำแหน่งจริง / Safety, at a real location',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              // Spinner: 34×34, 3px ring, white on 25% white, ~70px above the bottom.
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 70),
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Faint white grid lines every 40px (design's splash background decoration).
class _GridPainter extends CustomPainter {
  static const double _spacing = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double x = _spacing; x < size.width; x += _spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = _spacing; y < size.height; y += _spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
