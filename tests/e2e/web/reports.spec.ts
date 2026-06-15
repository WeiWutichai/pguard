// The reports analytics screen (payment `GET /admin/reports/revenue` + booking
// `GET /admin/reports/bookings`) renders without crashing — a real screen now, no longer a
// ComingSoon stub. Data-tolerant: the seed may have no payments/bookings (empty series), so we
// assert the page mounts + resolves (heading, no load-error banner, no uncaught errors).
import { test, expect } from "@playwright/test";

test("reports page renders the analytics dashboard without crashing", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/reports");
  await expect(page.getByRole("heading").first(), "page mounted").toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByRole("main").getByRole("alert"), "no load error").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
