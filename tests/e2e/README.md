<!-- pguard v2 scaffold stub — e2e test harness. See CLAUDE.md "tests/e2e". -->
# E2E tests — Playwright (web) + Patrol (mobile)

End-to-end flows across the running stack (`./tooling/scripts/dev-up.sh` first).

| Surface | Tool | Notes |
|---|---|---|
| Web admin (Next.js 16) | **Playwright** | config: `playwright.config.ts`; specs under `web/` |
| Mobile (Flutter) | **Patrol** | native integration driving the Flutter app; specs under `mobile/` |

## Web (Playwright)

- Tests live in `tests/e2e/web/**/*.spec.ts` (create as flows are built).
- Cover auth (cookie-based, httpOnly per CLAUDE.md), booking lifecycle, refunds, role gating.
- Run: `pnpm --filter e2e test` (wire scripts when the workspace exists).

## Mobile (Patrol)

- Tests live in `apps/mobile/integration_test/**` driven by Patrol; this folder holds
  the shared scenarios/fixtures and CI orchestration notes.
- Cover: OTP login, accept job, en-route → arrived → hourly check-in (photo+GPS), complete.
- Validate **WebSocket** booking-status updates replace the old polling path (no `Timer.periodic`).

## Conventions

- Drive only through public surfaces (UI / API gateway), never direct DB writes.
- Seed via service APIs or dedicated test fixtures, not cross-schema inserts.
- Bilingual TH/EN: assert key flows render in both locales where relevant.
