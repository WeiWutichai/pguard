// The two live-data read pages render real seeded data without crashing: guards (approved guard
// profiles via the gateway) and the live map (presence locations via the env-gated rewrite).
import { test, expect } from "@playwright/test";

test("guards page lists approved guards (live data via the gateway)", async ({ page }) => {
  await page.goto("/guards");
  const rows = page.locator("table tbody tr");
  await expect(rows.first(), "approved guards rendered").toBeVisible({ timeout: 15_000 });
  expect(await rows.count()).toBeGreaterThan(0);
});

test("map page mounts the live guard map (presence via rewrite)", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/map");
  // Once locations load the Leaflet map mounts (it only renders when there are guards to plot).
  await expect(page.locator(".leaflet-container"), "Leaflet map mounted with data").toBeVisible({
    timeout: 20_000,
  });
  // Scope to <main> — the page's own error banner — so the Next dev-tools overlay (which also
  // carries role="alert") doesn't register as a presence-load failure.
  await expect(page.getByRole("main").getByRole("alert"), "no presence load error").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
