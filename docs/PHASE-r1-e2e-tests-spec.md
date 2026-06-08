# Round 1 · e2e tests — Playwright (web-admin) + Patrol (mobile) — work spec

> For Claude Code (Terminal A). The `tests/e2e/` dir is an empty scaffold. Add happy-path
> end-to-end tests that exercise the real merged stack — they double as a demo safety-net and run
> in CI. Branch off freshly synced main. Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # 2a40357
git worktree add ../pguard-e2e -b feat/r1-e2e-tests main
cd ../pguard-e2e
```

## Scope

### A. Web-admin — Playwright (`tests/e2e/web/`)
- Spin the prod stack (reuse the perf harness: `tooling/scripts/migrate.sh` + the v2 seed) OR a CI service stack; point Playwright at the gateway.
- Flows: **login** (cookie set, redirect to dashboard) · **applicants → approve a pending guard** (the approve fires `user.approved` → the guard becomes loginable — assert via the API) · **reviews visibility toggle** (optimistic + persists) · **guards/map list renders live data** · **documented-gap pages show the gap notice** (not a crash).
- Assert cookie auth (httpOnly), CSRF header present on writes, no console errors.

### B. Mobile — Patrol (`tests/e2e/mobile/`)
- Flows against the running backend: **phone → OTP → PIN → role → register (202 pending)** · **admin approves (via API/seed) → login succeeds** · **customer: book-a-guard happy path** (service → map → discovery → payment → live status via WS) · **guard: go online (GPS) → accept job → active job**. Use the OTP test-bypass / seed where SMS is disabled.
- Keep flows deterministic (seeded data, fixed phones); no reliance on real SMS.

### C. CI wiring
- Add an `e2e` job (or extend CI) that brings up the stack (service containers + migrate + seed), runs Playwright headless, and (if feasible in CI) a Patrol smoke subset. Gate it so a stack-up failure is a clear red, not a flake. Document how to run both locally.

## Definition of Done
- Playwright suite green against the live stack (the approve→login loop asserted end-to-end). Patrol suite green locally (+ a CI smoke subset if the runner allows; otherwise document the local-run + wire the harness).
- Deterministic (seeded), no real-SMS dependency, no hard-coded sleeps where a wait-for-condition works.
- CI job added + documented; `docker compose config` / harness reused (don't reinvent seeding).
- Update `PROGRESS.md` (tick e2e tests + Completed-log row) · run the review agents (code-reviewer + architecture-guardian) · own PR off main · **don't merge**.

## Reference (read-only)
- Stack + seed: `v1-audit/perf-baseline/scripts/seed-v2.sql`, `tooling/scripts/migrate.sh`, `infra/docker/docker-compose.prod.yml`. CI: `.github/workflows/ci.yml`. Web flows: `apps/web-admin/app/(dashboard)/*`. Mobile flows: `apps/mobile/lib/features/*` + the controllers. Contracts: `contracts/openapi/*`.
