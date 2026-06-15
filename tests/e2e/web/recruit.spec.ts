// The recruitment pipeline admin screen (profile `GET /admin/recruitment/candidates`) renders
// without crashing — a real kanban now, no longer a ComingSoon stub. Data-tolerant: the seed may
// have no guard profiles, so we assert the page mounts + resolves (heading, no load-error
// banner, no uncaught errors), not specific cards.
import { test, expect } from "@playwright/test";

test("recruit page renders the recruitment pipeline without crashing", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/recruit");
  await expect(page.getByRole("heading").first(), "page mounted").toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByRole("main").getByRole("alert"), "no load error").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
