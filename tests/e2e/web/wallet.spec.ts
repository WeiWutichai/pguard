// The wallet admin payment ledger (payment `GET /admin/payments`) renders without crashing —
// a real read-only screen now, no longer a gap page. Data-tolerant: the e2e seed may or may
// not include payments, so we assert the page mounts + resolves (heading, no load-error
// banner, no uncaught errors), not a specific row count.
import { test, expect } from "@playwright/test";

test("wallet page renders the admin payment ledger without crashing", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/wallet");
  await expect(page.getByRole("heading").first(), "page mounted").toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByRole("main").getByRole("alert"), "no load error").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
