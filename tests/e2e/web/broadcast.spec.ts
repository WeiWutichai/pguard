// The broadcast admin bulk-send screen (notification `/admin/broadcasts` + `/admin/audience-
// counts`) renders without crashing — a real screen now, no longer a ComingSoon stub. Data-
// tolerant: the seed may have no broadcast history (audience counts may be 0), so we assert the
// page mounts + the composer is present, not specific rows. Audience-count failure is non-fatal
// (the page shows "—"), so only a broadcasts-list error trips the alert banner.
import { test, expect } from "@playwright/test";

test("broadcast page renders the composer without crashing", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/broadcast");
  await expect(page.getByRole("heading").first(), "page mounted").toBeVisible({
    timeout: 15_000,
  });
  // The composer's title input is always present (real screen, not a stub).
  await expect(page.getByRole("textbox").first(), "composer present").toBeVisible();
  await expect(page.getByRole("main").getByRole("alert"), "no load error").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
