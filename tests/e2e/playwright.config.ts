// pguard v2 — Playwright config for the web-admin happy-path e2e (runs against the REAL stack).
// See tests/e2e/README.md + docs/PHASE-r1-e2e-tests-spec.md. The backend is brought up by the perf
// harness (tooling/scripts/migrate.sh + seed-v2.sql) via the e2e compose override; web-admin runs
// on :3100 with the same-origin `/v1` proxy pointed at the gateway (:3000), which routes EVERY
// service (PR #25) — so the suite exercises the same gateway path as prod (no per-service bypass).
import { defineConfig, devices } from "@playwright/test";
import path from "node:path";

// Web-admin host origin for the run (the browser origin the gateway is told to allow). Override via
// PGUARD_WEB_URL when web-admin is served elsewhere.
const BASE_URL = process.env.PGUARD_WEB_URL ?? "http://localhost:3100";

// Saved admin session (httpOnly cookies) produced by auth.setup.ts and reused by the dashboard
// specs so each one doesn't re-login (and doesn't burn the 5 r/s auth rate-limit).
const ADMIN_STATE = path.join(__dirname, ".auth", "admin.json");

export default defineConfig({
  testDir: "./web",
  testMatch: "**/*.spec.ts",
  // The specs mutate shared backend state (approve a guard, toggle a review) — keep them serial and
  // single-worker so the run is deterministic and stays well under the per-IP auth rate-limit.
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI
    ? [["github"], ["html", { open: "never" }]]
    : [["list"]],
  timeout: 60_000,
  expect: { timeout: 10_000 },
  use: {
    baseURL: BASE_URL,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    // `next dev` compiles each route on first hit — give navigations room for the cold compile.
    navigationTimeout: 60_000,
    // Cookie-based auth (httpOnly) per CLAUDE.md — never read tokens from localStorage.
  },
  projects: [
    // Logs in as admin once and saves the storage state.
    { name: "setup", testMatch: /auth\.setup\.ts/ },
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"], storageState: ADMIN_STATE },
      dependencies: ["setup"],
      testIgnore: /auth\.setup\.ts/,
    },
  ],
  // Auto-start web-admin (next dev on :3100). In CI (CI=true → reuseExistingServer=false) Playwright
  // owns the web-admin lifecycle; locally it reuses an already-running :3100 if present. The
  // env-gated rewrites (rating/presence) are switched on here for the e2e run only.
  webServer: {
    command: "pnpm dev",
    cwd: path.join(__dirname, "..", "..", "apps", "web-admin"),
    // Probe a route that actually renders (the bare `/` may 404 under the App Router groups).
    url: `${BASE_URL}/login`,
    timeout: 240_000,
    reuseExistingServer: !process.env.CI,
    stdout: "pipe",
    stderr: "pipe",
    env: {
      PORT: "3100",
      // Server-side proxy target (next.config rewrite): everything goes through the gateway, which
      // now routes every service (PR #25) — so no per-service bypass (PGUARD_RATING_URL/
      // PGUARD_PRESENCE_URL) is needed; the e2e suite exercises the SAME gateway path as prod.
      PGUARD_API_BASE_URL: process.env.PGUARD_API_BASE_URL ?? "http://localhost:3000",
    },
  },
});
