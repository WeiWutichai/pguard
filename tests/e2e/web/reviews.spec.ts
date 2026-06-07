// Reviews visibility moderation — hide a visible review and prove it PERSISTS server-side.
//
// The seeded reviews all share one created_at, so the paginated (LIMIT 50 of 150) list order is
// unstable — "find this exact row again" would be flaky. The UNFILTERED "visible" stat card, by
// contrast, is a global DB count and is pagination-immune, so it's the reliable persistence signal:
// hiding one review drops the visible count by exactly 1, and that survives a full reload.
import { test, expect } from "@playwright/test";

// INVARIANT: `stats.visible` is the rating contract's global UNFILTERED visible count. Keep this
// keyed off the stat card — do NOT switch it to a row-derived count (the paginated list is
// order-unstable over the tied-timestamp seed and would reintroduce flakiness).
/** Read the integer shown on the "visible" stat card. */
async function visibleCount(page: import("@playwright/test").Page): Promise<number> {
  const text = (await page.getByTestId("reviews-stat-visible").textContent())?.trim() ?? "";
  return Number.parseInt(text, 10);
}

test("hiding a review decrements the visible count and persists across reload", async ({ page }) => {
  await page.goto("/reviews");

  // Reviews load from the rating service (env-gated direct rewrite).
  await expect(page.getByTestId("reviews-stat-visible")).not.toHaveText("—", { timeout: 15_000 });
  const before = await visibleCount(page);
  expect(before).toBeGreaterThan(0);

  // Hide the first currently-visible review (any one — we assert the global count, not the row).
  const visibleToggle = page
    .locator('[data-testid^="review-toggle-"][aria-pressed="true"]')
    .first();
  await expect(visibleToggle).toBeVisible();
  const toggleId = await visibleToggle.getAttribute("data-testid");
  await visibleToggle.click();

  // After the PUT succeeds the page refetches the unfiltered stats → visible count drops by one.
  await expect
    .poll(() => visibleCount(page), { message: "visible count decremented", timeout: 15_000 })
    .toBe(before - 1);

  // Persisted: a fresh load re-fetches from rating and still shows the lower count.
  await page.reload();
  await expect
    .poll(() => visibleCount(page), { message: "decrement survives reload", timeout: 15_000 })
    .toBe(before - 1);

  // Restore via the (small, stable) hidden filter so re-runs start from the same count.
  await page.getByTestId("reviews-filter-hidden").click();
  const restore = page.locator(`[data-testid="${toggleId}"]`);
  await expect(restore).toBeVisible({ timeout: 15_000 });
  await restore.click();
  await expect
    .poll(() => visibleCount(page), { message: "visible count restored", timeout: 15_000 })
    .toBe(before);
});
