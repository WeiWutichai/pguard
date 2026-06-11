import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// Builds the app [ThemeData] from the design tokens — the single source of color/radius/
/// spacing. Screens/widgets must reference [PgTokens] (or this theme), never hardcoded hex.
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: PgTokens.colorPrimary,
      onPrimary: Colors.white,
      secondary: PgTokens.colorAccent,
      onSecondary: PgTokens.colorOnAmber,
      surface: PgTokens.colorSurface,
      onSurface: PgTokens.colorText,
      error: PgTokens.colorDanger,
      onError: Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: PgTokens.colorBg,
      splashFactory: InkRipple.splashFactory,
      // Brand typeface (design --font-thai): bundled IBM Plex Sans Thai — covers Thai +
      // Latin; mono accents opt in per-widget with fontFamily 'IBMPlexMono'.
      fontFamily: 'IBMPlexSansThai',
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: PgTokens.colorText,
        displayColor: PgTokens.colorText,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PgTokens.colorSurface,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: PgTokens.space4, vertical: PgTokens.space3),
        border: _inputBorder(PgTokens.colorBorderStrong),
        enabledBorder: _inputBorder(PgTokens.colorBorderStrong),
        focusedBorder: _inputBorder(PgTokens.colorPrimary, width: 1.5),
        hintStyle: const TextStyle(color: PgTokens.colorTextFaint),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1.5}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
        borderSide: BorderSide(color: color, width: width),
      );
}
