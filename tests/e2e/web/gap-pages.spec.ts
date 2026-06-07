// Documented-gap admin pages (no v2 backend endpoint yet) must render an honest gap notice that
// names the missing endpoint — NOT a crash or blank screen. The endpoint strings are literal props
// (not translated), so they double as language-independent, stable assertions.
import { test, expect } from "@playwright/test";

const GAP_PAGES = [
  { path: "/customers", endpoint: "/v1/admin/customer-profiles" },
  { path: "/pricing", endpoint: "/v1/pricing/services" },
  { path: "/wallet", endpoint: "/v1/admin/payments" },
] as const;

for (const { path, endpoint } of GAP_PAGES) {
  test(`gap page ${path} renders the gap notice without crashing`, async ({ page }) => {
    const pageErrors: string[] = [];
    page.on("pageerror", (e) => pageErrors.push(e.message));

    await page.goto(path);
    await expect(page.getByRole("heading").first()).toBeVisible();
    await expect(
      page.getByText(endpoint, { exact: false }),
      "the missing endpoint is named",
    ).toBeVisible();
    expect(pageErrors, "no uncaught page errors").toEqual([]);
  });
}
