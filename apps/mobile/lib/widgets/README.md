<!-- pguard v2 scaffold stub. See ../../../CLAUDE.md "Flutter (mobile)". -->

# widgets

**Shared, reusable widgets — single source of truth for common UI.**

Per CLAUDE.md ("Flutter (mobile)" Do/Don't):

- Use the shared `PGuardHeader` widget — **do not copy-paste header markup** into
  screens.
- Keep shared, presentational widgets here so screens stay thin and consistent.
- Widgets render; they hold no business logic (that lives in core/controllers).
- Keep god-screens out: extract widgets + controllers; no screen > 800 LOC.

## TODO

- [ ] `PGuardHeader` — shared app header (bilingual TH/EN aware).
- [ ] Pull visuals/tokens from `apps/design-tokens/` (tokens.dart).
