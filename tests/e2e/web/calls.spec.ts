// The calls admin call log (calling `GET /admin/calls`) renders without crashing — a real
// read-only screen now, no longer a ComingSoon stub. Data-tolerant: the seed may have no call
// rows, so we assert the page mounts + resolves (heading, no load-error banner, no uncaught
// errors), not a specific row count.
import { test, expect } from "@playwright/test";

test("calls page renders the admin call log without crashing", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/calls");
  await expect(page.getByRole("heading").first(), "page mounted").toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByRole("main").getByRole("alert"), "no load error").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
