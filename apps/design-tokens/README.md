# Design tokens

Single source of design primitives, **extracted from the hi-fi design**:
`redesign-pguard/project/pguard/tokens.css` (brand: Deep Forest green `#0E3B2E` +
interactive `#1FA971` + Amber accent · IBM Plex Sans Thai). Bilingual TH/EN platform
per CLAUDE.md.

## Layout

| File | Role |
|---|---|
| `source/tokens.css` | **Committed snapshot** of the design's token sheet (the in-repo source of truth — `redesign-pguard/` is a gitignored local artifact, so CI regenerates from this snapshot) |
| `extract.mjs` | The extractor (node-only, no deps, byte-deterministic) |
| `tokens.css` | GENERATED → web-admin (CSS custom properties, light + `[data-theme="dark"]`) |
| `tokens.ts` | GENERATED → TS consumers (typed object incl. dark overrides) |
| `lib/pguard_design_tokens.dart` | GENERATED → Flutter mobile (`PgTokens` + `PgTokensDark`) |

## Regenerating

```bash
node apps/design-tokens/extract.mjs     # or: ./tooling/codegen/generate.sh
```

Do not hand-edit the generated trio. To change a value: update the hi-fi design,
re-copy `redesign-pguard/project/pguard/tokens.css` → `source/tokens.css`, regenerate,
commit all four. CI (`codegen-stale` job → `tests/contract/check-generated-codegen.sh`)
fails if the committed outputs drift from the snapshot.

## Guarantees

- **Every `--var` in the snapshot must be claimed by the extractor's mapping** (and
  vice-versa) — an unmapped token fails the run, so a design-side token change can't be
  silently dropped.
- **Dart API is an additive superset**: every member the original stub exposed keeps its
  name and value (the 36 members `apps/mobile` consumes are pinned by that contract), so
  regeneration cannot break mobile.
- `color.onAmber` (`#2A1500`) is carried from the design's component sheet
  (`admin.css` `.btn.accent` text) — the one token not in tokens.css.
