# E2E tests — Playwright (web) + Patrol (mobile)

End-to-end happy-path flows against the **real** Dockerized stack (the prod compose + an e2e
override), reusing the perf harness (`migrate.sh` + `seed-v2.sql`).

| Surface | Tool | Specs | Status |
|---|---|---|---|
| Web admin (Next.js 16) | **Playwright** | `web/*.spec.ts` | ✅ green vs the live stack |
| Mobile (Flutter) | **Patrol** | `apps/mobile/integration_test/*` | wired + documented (needs an emulator) |

## Quick start (web)

```bash
# 1. bring the stack up + migrate + seed (builds the service images the first time)
tooling/scripts/e2e-stack-up.sh

# 2. run Playwright (it starts web-admin on :3100 itself, with the env-gated rewrites)
cd tests/e2e
pnpm install
npx playwright install chromium
pnpm test:web
```

Tear down: `docker compose --env-file infra/.env.e2e -f infra/docker/docker-compose.prod.yml -f infra/docker/docker-compose.e2e.yml down -v`

## What the web suite covers (`web/`)

| Spec | Asserts |
|---|---|
| `auth.setup.ts` | logs in admin once → saves the httpOnly session for the other specs |
| `login.spec.ts` | bad creds → no session; good creds → **httpOnly** `access_token` cookie + redirect, token not in `document.cookie` |
| `applicants-approve.spec.ts` | **headline:** admin approves a pending guard → the `user.approved` event crosses profile→NATS→identity → the guard, blocked while pending, becomes loginable (asserted via the API, wait-for-condition poll) |
| `reviews.spec.ts` | hide a review → the global visible-count drops by one and **persists across reload** (pagination-immune stat) |
| `guards-map.spec.ts` | guards list renders live data (gateway); the map mounts Leaflet over live presence locations |
| `gap-pages.spec.ts` | customers/pricing/wallet render an honest gap notice (named missing endpoint) — no crash |

### How it reaches the backend

web-admin proxies a same-origin `/v1` to the gateway (`:3000`). Two services the gateway does **not
yet route** — rating (reviews) and presence (map) — are reached directly via **env-gated**
`next.config` rewrites (`PGUARD_RATING_URL` / `PGUARD_PRESENCE_URL`, set only for e2e; prod keeps the
single `/v1`→gateway rule). Both services validate the same httpOnly cookie. The `infra/.env.e2e`
override also disables SMS so the OTP path is deterministic (no real SMS).

### Determinism

- **No fixed sleeps** — the approve→login propagation uses an `expect.poll` wait-for-condition,
  spaced ≤1/s to respect the gateway's 5 r/s auth limit.
- The approve spec **creates its own** unique pending guard (`web/helpers/db.ts`) each run, so it's
  re-runnable without a reset. Locally that runs `psql` inside the compose `postgres` container; set
  `PGUARD_E2E_PSQL` to a direct psql invocation for a non-docker DB.
- Stable selectors: a few `data-testid` / `aria-pressed` affordances were added to the admin pages
  so selectors don't depend on the TH/EN locale.

## Mobile (Patrol)

See [`mobile/README.md`](./mobile/README.md). Wired (`apps/mobile/integration_test/` + `patrol.yaml`
+ pubspec deps) and documented; a green run needs the native platform projects, an emulator/simulator
(Patrol has no headless mode), and a deterministic-OTP hook. The cross-service approve→login loop the
mobile flow depends on is already proven by `web/applicants-approve.spec.ts`.

## CI

`.github/workflows/ci.yml` → job **`e2e-web`** brings the stack up, migrates + seeds, and runs the
Playwright suite headless. Mobile Patrol is local-only (emulator) and documented above.
