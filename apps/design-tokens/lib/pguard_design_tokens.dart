// GENERATED PLACEHOLDER — regenerate from Design System.html
// pguard v2 design tokens (subset). Keep tokens.css / lib/pguard_design_tokens.dart /
// tokens.ts in sync. Canonical Flutter import:
//   import 'package:pguard_design_tokens/pguard_design_tokens.dart';
import 'dart:ui' show Color;

/// pguard design tokens. Values mirror tokens.css / tokens.ts exactly.
class PgTokens {
  PgTokens._();

  // Brand
  static const Color colorBrand = Color(0xFF0E3B2E); // Deep Forest — green-900
  static const Color colorPrimary =
      Color(0xFF1FA971); // interactive base — green-500
  static const Color colorPrimaryHover = Color(0xFF15885B); // green-int hover
  static const Color colorAccent = Color(0xFFF59E0B); // amber-500

  // Semantic
  static const Color colorSuccess = Color(0xFF16A34A);
  static const Color colorWarning = Color(0xFFF59E0B);
  static const Color colorDanger = Color(0xFFE5484D);
  static const Color colorInfo = Color(0xFF2A6FDB);

  // Surface / text (light)
  static const Color colorBg = Color(0xFFF6F8F7); // n-50
  static const Color colorSurface = Color(0xFFFFFFFF); // n-0
  static const Color colorSunken = Color(0xFFEDF1EF); // n-75 — keypad/slot rest
  static const Color colorText = Color(0xFF222B27); // n-800
  static const Color colorTextMuted = Color(0xFF69776F); // n-500
  static const Color colorTextFaint = Color(0xFF94A29D); // n-400
  static const Color colorBorder = Color(0xFFDEE5E2); // n-200
  static const Color colorBorderStrong =
      Color(0xFFC6D0CC); // n-300 — input outline

  // Green ramp (cards, avatars, header tints)
  static const Color colorGreen50 = Color(0xFFE9F8F1);
  static const Color colorGreen100 = Color(0xFFC9EEDD);
  static const Color colorGreen200 = Color(0xFF97E0C2);
  static const Color colorGreen800 = Color(0xFF0E5238); // live-status header

  // Amber ramp (customer accents)
  static const Color colorAmber100 = Color(0xFFFDE9C2);
  static const Color colorAmber700 = Color(0xFFB45F09);
  static const Color colorOnAmber =
      Color(0xFF2A1500); // text on amber CTAs — amber-950

  // Tinted backgrounds for status banners
  static const Color colorSuccessBg = Color(0xFFE7F6ED);
  static const Color colorWarningBg = Color(0xFFFEF3E0);
  static const Color colorDangerBg = Color(0xFFFCEAEA);

  // Focus ring (primary @ 45% — outline glow on inputs/OTP/PIN)
  static const Color colorFocusRing = Color(0x731FA971);

  // Spacing scale (4px base)
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space6 = 24;
  static const double space7 = 32;

  // Radius
  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLg = 11;
  static const double radiusXl = 14; // OTP/PIN/input fields
  static const double radius2xl = 18; // keypad keys / cards
  static const double radiusFull = 999;
}
