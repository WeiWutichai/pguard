// The location-replay screen (presence GET /guards/{id}/history) renders without crashing — a
// real screen now, no longer a ComingSoon stub. No guard is selected on load, so it shows the
// "pick a guard" prompt; we assert the page mounts (heading + the guard picker) and raises no
// uncaught errors. Replaying an actual route needs seeded GPS history (covered in staging).
import { test, expect } from "@playwright/test";

test("replay page renders the guard picker without crashing", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/replay");
  await expect(page.getByRole("heading").first(), "page mounted").toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole("combobox"), "guard picker present").toBeVisible();
  await expect(page.getByRole("main").getByRole("alert"), "no load error").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
