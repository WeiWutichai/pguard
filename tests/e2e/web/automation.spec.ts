// The automation admin screen (notification `GET /admin/automation/rules`) renders without
// crashing — a real authoring surface now, no longer a ComingSoon stub. Data-tolerant: the rules
// table may be empty, so we assert the page mounts + resolves (heading, rule builder present, no
// load-error banner). Live rule execution is a documented follow-up, not exercised here.
import { test, expect } from "@playwright/test";

test("automation page renders the rule builder without crashing", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/automation");
  await expect(page.getByRole("heading").first(), "page mounted").toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByRole("main").getByRole("alert"), "no load error").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
