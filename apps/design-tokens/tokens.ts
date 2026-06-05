// GENERATED PLACEHOLDER — regenerate from Design System.html
// pguard v2 design tokens (subset). Keep tokens.css / lib/pguard_design_tokens.dart /
// tokens.ts in sync (the Dart tokens are a Flutter path package — see pubspec.yaml).

export const pgTokens = {
  color: {
    // Brand
    brand: "#0E3B2E", // Deep Forest — green-900
    primary: "#1FA971", // interactive base — green-500
    primaryHover: "#15885B", // green-int hover
    accent: "#F59E0B", // amber-500
    // Semantic
    success: "#16A34A",
    warning: "#F59E0B",
    danger: "#E5484D",
    info: "#2A6FDB",
    // Surface / text (light)
    bg: "#F6F8F7", // n-50
    surface: "#FFFFFF", // n-0
    sunken: "#EDF1EF", // n-75 — keypad/slot rest
    text: "#222B27", // n-800
    textMuted: "#69776F", // n-500
    textFaint: "#94A29D", // n-400
    border: "#DEE5E2", // n-200
    borderStrong: "#C6D0CC", // n-300 — input outline
    // Green ramp
    green50: "#E9F8F1",
    green100: "#C9EEDD",
    green200: "#97E0C2",
    green800: "#0E5238", // live-status header
    // Amber ramp
    amber100: "#FDE9C2",
    amber700: "#B45F09",
    onAmber: "#2A1500", // text on amber CTAs — amber-950
    // Tinted status backgrounds
    successBg: "#E7F6ED",
    warningBg: "#FEF3E0",
    dangerBg: "#FCEAEA",
    // Focus ring (primary @ 45%)
    focusRing: "rgba(31, 169, 113, .45)",
  },
  // Spacing scale (4px base), px
  space: {
    1: 4,
    2: 8,
    3: 12,
    4: 16,
    6: 24,
    7: 32,
  },
  radius: {
    sm: 6,
    md: 8,
    lg: 11,
    xl: 14, // OTP/PIN/input fields
    "2xl": 18, // keypad keys / cards
    full: 999,
  },
} as const;

export type PgTokens = typeof pgTokens;
