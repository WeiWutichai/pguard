#!/usr/bin/env node
/**
 * pguard — design-token extractor.
 *
 * Reads the COMMITTED snapshot of the hi-fi design's token sheet
 * (`source/tokens.css` — copied verbatim from
 * `redesign-pguard/project/pguard/tokens.css`, which is a gitignored local
 * design artifact, so CI regenerates from this snapshot, not from the design
 * folder) and emits the three consumer outputs, byte-deterministically:
 *
 *   tokens.css                      → web-admin (CSS custom properties, light + dark)
 *   tokens.ts                       → TS consumers (typed object; superset of the old stub)
 *   lib/pguard_design_tokens.dart   → Flutter mobile (class PgTokens — every member the
 *                                     old stub had keeps its NAME and VALUE; new tokens
 *                                     are additive, so apps/mobile cannot break)
 *
 * Every `--var` in source/tokens.css MUST be claimed by the mapping below and
 * vice-versa — an unmapped or missing var fails the run (that is the drift
 * alarm: when the design adds/renames a token, this script forces the mapping
 * to be updated consciously instead of silently dropping the token).
 *
 * Run: node apps/design-tokens/extract.mjs   (no deps; pinned in
 * tooling/codegen/generate.sh and stale-checked in CI — regen must produce an
 * empty git diff).
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = dirname(fileURLToPath(import.meta.url));
const SRC = join(ROOT, 'source', 'tokens.css');

// ---------------------------------------------------------------------------
// Parse
// ---------------------------------------------------------------------------

const css = readFileSync(SRC, 'utf8');

/** Extract `--name: value;` pairs from the body of a CSS block. */
function parseBlock(selectorRe) {
  const m = css.match(selectorRe);
  if (!m) throw new Error(`block not found: ${selectorRe}`);
  const vars = new Map();
  for (const line of m[1].matchAll(/--([A-Za-z0-9-]+)\s*:\s*([^;]+);/g)) {
    vars.set(line[1], line[2].trim());
  }
  return vars;
}

const light = parseBlock(/:root\s*\{([\s\S]*?)\n\}/);
const dark = parseBlock(/\[data-theme="dark"\]\s*\{([\s\S]*?)\n\}/);

/** Resolve var(--x) references against a scope (dark falls back to light). */
function resolve(value, scope) {
  let out = value;
  for (let i = 0; i < 10; i++) {
    const next = out.replace(/var\(--([A-Za-z0-9-]+)\)/g, (_, name) => {
      const v = scope.get(name) ?? light.get(name);
      if (v === undefined) throw new Error(`unresolvable var(--${name}) in "${value}"`);
      return v;
    });
    if (next === out) return out;
    out = next;
  }
  throw new Error(`var() resolution too deep for "${value}"`);
}

// ---------------------------------------------------------------------------
// Mapping (CSS var → TS path + Dart member). EVERY :root var must appear here.
// dart:null = web-only token (shadows/fonts handled separately or N/A in Flutter).
// ---------------------------------------------------------------------------

/** [cssVar, tsPath, dartMember] — ramps. */
const RAMPS = [];
for (const [prefix, tsKey, dartKey] of [
  ['green', 'green', 'Green'],
  ['amber', 'amber', 'Amber'],
]) {
  for (const name of light.keys()) {
    const m = name.match(new RegExp(`^${prefix}-(\\d+)$`));
    if (m) RAMPS.push([name, `color.${tsKey}.${m[1]}`, `color${dartKey}${m[1]}`]);
  }
}
for (const name of light.keys()) {
  const m = name.match(/^n-(\d+)$/);
  if (m) RAMPS.push([name, `color.n.${m[1]}`, `colorN${m[1]}`]);
}

/** Semantic + status + alias colors. TS paths keep the OLD stub's key names. */
const COLORS = [
  ...RAMPS,
  ['success', 'color.success', 'colorSuccess'],
  ['success-bg', 'color.successBg', 'colorSuccessBg'],
  ['warning', 'color.warning', 'colorWarning'],
  ['warning-bg', 'color.warningBg', 'colorWarningBg'],
  ['danger', 'color.danger', 'colorDanger'],
  ['danger-bg', 'color.dangerBg', 'colorDangerBg'],
  ['info', 'color.info', 'colorInfo'],
  ['info-bg', 'color.infoBg', 'colorInfoBg'],
  ['status-active', 'color.statusActive', 'colorStatusActive'],
  ['status-working', 'color.statusWorking', 'colorStatusWorking'],
  ['status-offline', 'color.statusOffline', 'colorStatusOffline'],
  ['status-active-ring', 'color.statusActiveRing', 'colorStatusActiveRing'],
  ['status-working-ring', 'color.statusWorkingRing', 'colorStatusWorkingRing'],
  ['status-offline-ring', 'color.statusOfflineRing', 'colorStatusOfflineRing'],
  ['bg-app', 'color.bg', 'colorBg'],
  ['bg-surface', 'color.surface', 'colorSurface'],
  ['bg-raised', 'color.raised', 'colorRaised'],
  ['bg-sunken', 'color.sunken', 'colorSunken'],
  ['bg-inverse', 'color.inverse', 'colorInverse'],
  ['border', 'color.border', 'colorBorder'],
  ['border-strong', 'color.borderStrong', 'colorBorderStrong'],
  ['text-strong', 'color.textStrong', 'colorTextStrong'],
  ['text', 'color.text', 'colorText'],
  ['text-muted', 'color.textMuted', 'colorTextMuted'],
  ['text-faint', 'color.textFaint', 'colorTextFaint'],
  ['text-on-brand', 'color.textOnBrand', 'colorTextOnBrand'],
  ['brand', 'color.brand', 'colorBrand'],
  ['brand-int', 'color.primary', 'colorPrimary'],
  ['brand-int-hover', 'color.primaryHover', 'colorPrimaryHover'],
  ['accent', 'color.accent', 'colorAccent'],
  ['accent-hover', 'color.accentHover', 'colorAccentHover'],
  ['focus-ring', 'color.focusRing', 'colorFocusRing'],
];

/** Non-color scales: [cssVar, tsPath, dartMember, kind] (kind: px | unitless | em | string). */
const SCALES = [
  ['t-display', 'text.display', 'fontSizeDisplay', 'px'],
  ['t-h1', 'text.h1', 'fontSizeH1', 'px'],
  ['t-h2', 'text.h2', 'fontSizeH2', 'px'],
  ['t-h3', 'text.h3', 'fontSizeH3', 'px'],
  ['t-lg', 'text.lg', 'fontSizeLg', 'px'],
  ['t-base', 'text.base', 'fontSizeBase', 'px'],
  ['t-sm', 'text.sm', 'fontSizeSm', 'px'],
  ['t-xs', 'text.xs', 'fontSizeXs', 'px'],
  ['t-2xs', 'text.2xs', 'fontSize2xs', 'px'],
  ['lh-tight', 'lineHeight.tight', 'lineHeightTight', 'unitless'],
  ['lh-snug', 'lineHeight.snug', 'lineHeightSnug', 'unitless'],
  ['lh-base', 'lineHeight.base', 'lineHeightBase', 'unitless'],
  ['lh-relaxed', 'lineHeight.relaxed', 'lineHeightRelaxed', 'unitless'],
  ['ls-thai', 'letterSpacing.thai', null, 'em'], // em-relative — Flutter letterSpacing is px; web-only
  ['sp-1', 'space.1', 'space1', 'px'],
  ['sp-2', 'space.2', 'space2', 'px'],
  ['sp-3', 'space.3', 'space3', 'px'],
  ['sp-4', 'space.4', 'space4', 'px'],
  ['sp-5', 'space.5', 'space5', 'px'],
  ['sp-6', 'space.6', 'space6', 'px'],
  ['sp-7', 'space.7', 'space7', 'px'],
  ['sp-8', 'space.8', 'space8', 'px'],
  ['sp-9', 'space.9', 'space9', 'px'],
  ['sp-10', 'space.10', 'space10', 'px'],
  ['sp-11', 'space.11', 'space11', 'px'],
  ['sp-12', 'space.12', 'space12', 'px'],
  ['r-xs', 'radius.xs', 'radiusXs', 'px'],
  ['r-sm', 'radius.sm', 'radiusSm', 'px'],
  ['r-md', 'radius.md', 'radiusMd', 'px'],
  ['r-lg', 'radius.lg', 'radiusLg', 'px'],
  ['r-xl', 'radius.xl', 'radiusXl', 'px'],
  ['r-2xl', 'radius.2xl', 'radius2xl', 'px'],
  ['r-full', 'radius.full', 'radiusFull', 'px'],
  ['tap', 'tap', 'tapTarget', 'px'],
];

/** Shadows + font stacks: CSS/TS only (Flutter elevation + TextTheme differ by design). */
const STRINGS = [
  ['font-thai', 'font.thai'],
  ['font-latin', 'font.latin'],
  ['font-mono', 'font.mono'],
  ['sh-xs', 'shadow.xs'],
  ['sh-sm', 'shadow.sm'],
  ['sh-md', 'shadow.md'],
  ['sh-lg', 'shadow.lg'],
  ['sh-xl', 'shadow.xl'],
  ['sh-brand', 'shadow.brand'],
  ['sh-accent', 'shadow.accent'],
];

/**
 * Extra derived tokens that live in the design's component sheet (admin.css),
 * not tokens.css — carried so the old stub's API keeps working.
 */
const EXTRAS = [
  // admin.css `.btn.accent { color:#2A1500 }` — text on amber CTAs.
  ['#2A1500', 'color.onAmber', 'colorOnAmber'],
];

// ---- completeness check: every :root var is claimed exactly once ----------
{
  const claimed = new Set([
    ...COLORS.map(([v]) => v),
    ...SCALES.map(([v]) => v),
    ...STRINGS.map(([v]) => v),
  ]);
  const unmapped = [...light.keys()].filter((v) => !claimed.has(v));
  const missing = [...claimed].filter((v) => !light.has(v));
  if (unmapped.length || missing.length) {
    throw new Error(
      `token map drift — unmapped vars: [${unmapped.join(', ')}], mapped-but-absent: [${missing.join(', ')}]`,
    );
  }
}

// ---------------------------------------------------------------------------
// Value converters
// ---------------------------------------------------------------------------

/** '#RRGGBB' | '#RGB' | 'rgba(r,g,b,a)' → Flutter Color literal. */
function dartColor(raw) {
  const v = raw.trim();
  let m = v.match(/^#([0-9a-fA-F]{6})$/);
  if (m) return `Color(0xFF${m[1].toUpperCase()})`;
  m = v.match(/^rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\.?[\d.]+)\s*\)$/);
  if (m) {
    const [r, g, b] = [m[1], m[2], m[3]].map(Number);
    const a = Math.round(parseFloat(m[4]) * 255);
    const hex = (n) => n.toString(16).padStart(2, '0').toUpperCase();
    return `Color(0x${hex(a)}${hex(r)}${hex(g)}${hex(b)})`;
  }
  throw new Error(`not a color: "${raw}"`);
}

function pxNumber(raw, cssVar) {
  const m = raw.trim().match(/^([\d.]+)(px)?$/);
  if (!m) throw new Error(`not a number: --${cssVar}: ${raw}`);
  return parseFloat(m[1]);
}

function setPath(obj, path, value) {
  const parts = path.split('.');
  let cur = obj;
  for (const p of parts.slice(0, -1)) cur = cur[p] ??= {};
  cur[parts.at(-1)] = value;
}

// ---------------------------------------------------------------------------
// Emit tokens.css — the full custom-property sheet (light + dark), values
// passed through RESOLVED so the file stands alone (no alias chains).
// ---------------------------------------------------------------------------

const GEN = `/* GENERATED by apps/design-tokens/extract.mjs from source/tokens.css — DO NOT EDIT.
 * source/tokens.css is the committed snapshot of redesign-pguard/project/pguard/tokens.css
 * (the hi-fi design source of truth). To change a value: update the design, re-copy the
 * snapshot, then \`node apps/design-tokens/extract.mjs\`. CI stale-checks this file. */`;

function cssBlock(selector, vars, scope, extraLines = []) {
  const lines = [
    ...[...vars.entries()].map(([k, v]) => `  --${k}: ${resolve(v, scope)};`),
    ...extraLines,
  ];
  return `${selector} {\n${lines.join('\n')}\n}`;
}

const cssExtras = EXTRAS.map(
  ([value, path]) => `  --${path.split('.').at(-1).replace(/([A-Z])/g, '-$1').toLowerCase()}: ${value}; /* admin.css .btn.accent text */`,
);
const outCss = `${GEN}\n\n${cssBlock(':root', light, light, cssExtras)}\n\n${cssBlock('[data-theme="dark"]', dark, dark)}\n`;

// ---------------------------------------------------------------------------
// Emit tokens.ts
// ---------------------------------------------------------------------------

const ts = {};
for (const [v, path] of COLORS) setPath(ts, path, resolve(light.get(v), light));
for (const [v, path, , kind] of SCALES) {
  const raw = resolve(light.get(v), light);
  setPath(ts, path, kind === 'px' ? pxNumber(raw, v) : kind === 'unitless' ? parseFloat(raw) : raw);
}
for (const [v, path] of STRINGS) setPath(ts, path, resolve(light.get(v), light));
for (const [value, path] of EXTRAS) setPath(ts, path, value);
// dark overrides (resolved): only vars the dark block actually overrides.
for (const [v, path] of [...COLORS, ...STRINGS]) {
  if (dark.has(v)) setPath(ts, `dark.${path}`, resolve(dark.get(v), dark));
}

const outTs = `// GENERATED by apps/design-tokens/extract.mjs from source/tokens.css — DO NOT EDIT.
// Superset of the old placeholder: flat semantic keys keep their names + values; the
// ramps were RESTRUCTURED to nested objects (green50 → green["50"]) — no repo consumer
// existed at restructure time. The Dart output keeps every old member name (mobile uses it).

export const pgTokens = ${JSON.stringify(ts, null, 2).replace(/"([A-Za-z_][A-Za-z0-9_]*)":/g, '$1:')} as const;

export type PgTokens = typeof pgTokens;
`;

// ---------------------------------------------------------------------------
// Emit lib/pguard_design_tokens.dart
// ---------------------------------------------------------------------------

const dartColorLines = [];
for (const [v, , member] of COLORS) {
  if (!member) continue;
  dartColorLines.push(`  static const Color ${member} = ${dartColor(resolve(light.get(v), light))}; // --${v}`);
}
for (const [value, , member] of EXTRAS) {
  dartColorLines.push(`  static const Color ${member} = ${dartColor(value)}; // admin.css .btn.accent text`);
}

const dartScaleLines = [];
for (const [v, , member, kind] of SCALES) {
  if (!member) continue;
  const raw = resolve(light.get(v), light);
  const num = kind === 'px' ? pxNumber(raw, v) : parseFloat(raw);
  dartScaleLines.push(`  static const double ${member} = ${num}; // --${v}`);
}

const dartFontLines = [
  `  static const String fontFamilyThai = 'IBM Plex Sans Thai'; // --font-thai (primary)`,
  `  static const String fontFamilyLatin = 'IBM Plex Sans'; // --font-latin (primary)`,
  `  static const String fontFamilyMono = 'IBM Plex Mono'; // --font-mono (primary)`,
];

const dartDarkLines = [];
for (const [v, , member] of COLORS) {
  if (!member || !dark.has(v)) continue;
  dartDarkLines.push(`  static const Color ${member} = ${dartColor(resolve(dark.get(v), dark))}; // --${v} (dark)`);
}

const outDart = `// GENERATED by apps/design-tokens/extract.mjs from source/tokens.css — DO NOT EDIT.
// Full token set extracted from the hi-fi design (redesign-pguard tokens.css snapshot).
// Every member of the old placeholder keeps its NAME and VALUE (additive superset),
// so existing apps/mobile usage is source-compatible. Canonical import:
//   import 'package:pguard_design_tokens/pguard_design_tokens.dart';
import 'dart:ui' show Color;

/// pguard design tokens (LIGHT theme values + theme-independent scales).
class PgTokens {
  PgTokens._();

${dartColorLines.join('\n')}

${dartScaleLines.join('\n')}

${dartFontLines.join('\n')}
}

/// Dark-theme overrides (same member names as [PgTokens] where the design's
/// \`[data-theme="dark"]\` block overrides them; scales are theme-independent).
class PgTokensDark {
  PgTokensDark._();

${dartDarkLines.join('\n')}
}
`;

// ---------------------------------------------------------------------------
// Write
// ---------------------------------------------------------------------------

writeFileSync(join(ROOT, 'tokens.css'), outCss);
writeFileSync(join(ROOT, 'tokens.ts'), outTs);
writeFileSync(join(ROOT, 'lib', 'pguard_design_tokens.dart'), outDart);
// web-admin gets its own committed copy: its Docker build copies ONLY apps/web-admin/
// (infra/docker/web-admin.Dockerfile), so a ../../design-tokens import would break the
// image build — same precedent as the committed TS client.
writeFileSync(join(ROOT, '..', 'web-admin', 'app', 'tokens.css'), outCss);
console.log(
  `extracted ${light.size} light + ${dark.size} dark vars → tokens.css (+ web-admin copy), tokens.ts, lib/pguard_design_tokens.dart`,
);
