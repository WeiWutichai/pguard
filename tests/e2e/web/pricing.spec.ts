// The pricing admin service-catalog (booking `GET /admin/pricing/services`) renders without
// crashing — a real CRUD screen now, no longer a gap page. Data-tolerant: the seed may have no
// catalog rows, so we assert the page mounts + resolves (heading, no load-error banner, no
// uncaught errors), not a specific row count.
import { test, expect } from "@playwright/test";

test("pricing page renders the service catalog without crashing", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/pricing");
  await expect(page.getByRole("heading").first(), "page mounted").toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByRole("main").getByRole("alert"), "no load error").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
