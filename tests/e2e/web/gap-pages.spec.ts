// Documented-gap admin pages (no v2 backend endpoint yet) must render an honest gap notice that
// names the missing endpoint — NOT a crash or blank screen. The endpoint strings are literal props
// (not translated), so they double as language-independent, stable assertions.
import { test, expect } from "@playwright/test";

// /customers + /wallet are no longer gaps — they became real admin screens once their endpoints
// landed (GET /admin/customer-profiles, GET /admin/payments; see customers.spec.ts /
// wallet.spec.ts). /pricing remains a documented gap until its catalog endpoint exists.
const GAP_PAGES = [{ path: "/pricing", endpoint: "/v1/pricing/services" }] as const;

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
