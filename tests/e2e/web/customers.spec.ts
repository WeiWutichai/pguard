// The customers admin list (profile `GET /admin/customer-profiles`, landed with the keystone
// endpoints) renders without crashing. Data-tolerant: the e2e seed may or may not include
// customer profiles, so we assert the page MOUNTS + resolves (heading, no load-error banner,
// no uncaught errors) rather than a specific row count — a real screen, no longer a gap page.
import { test, expect } from "@playwright/test";

test("customers page renders the admin customer list without crashing", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/customers");
  await expect(page.getByRole("heading").first(), "page mounted").toBeVisible({
    timeout: 15_000,
  });
  // The admin list resolves to rows or the empty-state — never a page-level error banner.
  // Scope to <main> so the Next dev-tools overlay (also role="alert") isn't counted.
  await expect(page.getByRole("main").getByRole("alert"), "no load error").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
