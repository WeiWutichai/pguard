import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import 'pg_logo_mark.dart';

/// The hi-fi `.auth-head`: a centered hero used by every auth/onboarding screen —
/// optional mark (pguard logo by default, or a custom icon tile such as the PIN lock
/// circle), 23px/600 title, 14px muted subtitle (line-height 1.55), all centered.
class AuthHead extends StatelessWidget {
  const AuthHead({
    super.key,
    required this.title,
    this.subtitle,
    this.showLogo = false,
    this.icon,
  });

  final String title;
  final String? subtitle;

  /// Show the 48px pguard mark above the title (design screen ① welcome hero).
  final bool showLogo;

  /// Custom hero widget instead of the logo (e.g. the 64px bio-circle lock tile).
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          icon!,
          const SizedBox(height: 18),
        ] else if (showLogo) ...[
          const PgLogoMark(size: 48),
          const SizedBox(height: 18),
        ],
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            color: PgTokens.colorText,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.55,
              color: PgTokens.colorTextMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// The hi-fi `.bio-circle` icon tile (64px rounded square, green-50 fill, brand-int
/// icon) used as the [AuthHead.icon] on PIN setup / biometric screens.
class AuthHeadIconTile extends StatelessWidget {
  const AuthHeadIconTile({super.key, required this.icon, this.size = 64});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: PgTokens.colorGreen50,
        borderRadius: BorderRadius.circular(size * 20 / 64),
      ),
      child: Icon(icon, size: size * 30 / 64, color: PgTokens.colorPrimary),
    );
  }
}
