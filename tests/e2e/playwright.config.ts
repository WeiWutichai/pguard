// pguard v2 scaffold stub — Playwright config skeleton.
// See CLAUDE.md "tests/e2e" + Web (Next.js) rules. Specs land under tests/e2e/web/.
import { defineConfig, devices } from "@playwright/test";

// TODO: point baseURL at the running web-admin (default Next.js dev port).
const BASE_URL = process.env.PGUARD_WEB_URL ?? "http://localhost:3000";

export default defineConfig({
  testDir: "./web",
  testMatch: "**/*.spec.ts",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: BASE_URL,
    trace: "on-first-retry",
    // Cookie-based auth (httpOnly) per CLAUDE.md — never read tokens from localStorage.
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    // TODO: add mobile-web viewport + firefox/webkit as coverage grows.
  ],
  // TODO: wire webServer to auto-start web-admin, or rely on ./tooling/scripts/dev-up.sh.
  // webServer: { command: "pnpm --filter web-admin dev", url: BASE_URL, reuseExistingServer: !process.env.CI },
});
