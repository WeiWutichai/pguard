import { defineConfig } from "vitest/config";

// Contract tests hit ONE shared live stack and authenticate against the gateway, whose auth tier
// rate-limits to ~5 req/s/IP. So we run strictly SEQUENTIALLY (single fork, no file parallelism, no
// in-file concurrency) — parallel logins would trip 429s and make the suite flaky for the wrong
// reason. Tokens are cached per-account in src/http.ts to keep login traffic minimal.
export default defineConfig({
  test: {
    include: ["**/*.contract.test.ts"],
    testTimeout: 60_000,
    hookTimeout: 60_000,
    fileParallelism: false,
    pool: "forks",
    poolOptions: { forks: { singleFork: true } },
    sequence: { concurrent: false },
    reporters: process.env.CI ? ["default", "junit"] : ["default"],
    outputFile: { junit: "./contract-results.xml" },
  },
});
