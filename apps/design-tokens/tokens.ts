// GENERATED PLACEHOLDER — regenerate from Design System.html
// pguard v2 design tokens (subset). Keep tokens.css / tokens.dart / tokens.ts in sync.

export const pgTokens = {
  color: {
    // Brand
    brand: "#0E3B2E", // Deep Forest — green-900
    primary: "#1FA971", // interactive base — green-500
    accent: "#F59E0B", // amber-500
    // Semantic
    success: "#16A34A",
    warning: "#F59E0B",
    danger: "#E5484D",
    info: "#2A6FDB",
    // Surface / text (light)
    bg: "#F6F8F7", // n-50
    surface: "#FFFFFF", // n-0
    text: "#222B27", // n-800
    textMuted: "#69776F", // n-500
    border: "#DEE5E2", // n-200
  },
  // Spacing scale (4px base), px
  space: {
    1: 4,
    2: 8,
    3: 12,
    4: 16,
    6: 24,
  },
  radius: {
    sm: 6,
    md: 8,
    lg: 11,
    full: 999,
  },
} as const;

export type PgTokens = typeof pgTokens;
