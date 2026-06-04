<!-- pguard v2 scaffold stub — design tokens package. See CLAUDE.md "apps/design-tokens". -->
# Design tokens

Single source of design primitives, **generated from the hi-fi design system**:
`redesign-pguard/project/pguard/Design System.html` (brand: Deep Forest green + Amber
accent, IBM Plex Sans Thai). Bilingual TH/EN platform per CLAUDE.md.

This package holds three outputs that **must stay in sync** (same token names + values):

| File | Consumer |
|---|---|
| `tokens.css` | Next.js web admin (`apps/web-admin`) |
| `tokens.dart` | Flutter mobile (`apps/mobile`) |
| `tokens.ts`  | TS-side theming / Storybook / shared web utilities |

## Status

The current files are **PLACEHOLDER** subsets (a handful of color/spacing/radius tokens)
carrying the real brand values, marked `GENERATED PLACEHOLDER`. They exist so consumers
can import token names now.

## Regeneration

Regenerate all three from `Design System.html` (full palette, semantic aliases, dark
theme, typography, spacing scale, radii). Do not hand-edit — change the design source,
then re-export so CSS/Dart/TS remain identical in name and value.

> TODO: wire the extraction step (Design System.html → tokens.{css,dart,ts}) and pin it
> in `tooling/codegen/` or a dedicated token build script.
