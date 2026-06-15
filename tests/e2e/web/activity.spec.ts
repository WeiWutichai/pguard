// The activity admin data-access audit log (profile GET /admin/access-audit) renders without
// crashing — a real screen now (was the last ApiGapPage). Data-tolerant smoke: the page mounts +
// resolves (heading, no load-error banner, no uncaught errors), not a specific row count.
import { test, expect } from "@playwright/test";

test("activity page renders the data-access audit log without crashing", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/activity");
  await expect(page.getByRole("heading").first(), "page mounted").toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole("main").getByRole("alert"), "no load error").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
