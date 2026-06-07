// Admin login flow — run LOGGED OUT (override the shared admin storageState). Asserts the cookie
// contract from CLAUDE.md › Web: auth is a server-set httpOnly cookie, never readable from JS.
import { test, expect } from "@playwright/test";

import { ADMIN } from "./helpers/accounts";

test.use({ storageState: { cookies: [], origins: [] } });

test.describe("admin login", () => {
  test("rejects bad credentials and sets no session", async ({ page }) => {
    await page.goto("/login");
    await page.locator('input[autocomplete="username"]').fill(ADMIN.identifier);
    await page.locator('input[autocomplete="current-password"]').fill("definitely-wrong");
    await page.locator('button[type="submit"]').click();

    // Scope to <main> so the Next dev-tools overlay's role="alert" can't satisfy this for us.
    await expect(page.getByRole("main").getByRole("alert")).toBeVisible();
    expect(page.url()).toContain("/login");
    const accessToken = (await page.context().cookies()).find((c) => c.name === "access_token");
    expect(accessToken, "no session cookie on a failed login").toBeFalsy();
  });

  test("logs in → httpOnly cookie → redirects to dashboard", async ({ page }) => {
    await page.goto("/login");
    await page.locator('input[autocomplete="username"]').fill(ADMIN.identifier);
    await page.locator('input[autocomplete="current-password"]').fill(ADMIN.password);
    await page.locator('button[type="submit"]').click();

    await page.waitForURL("**/dashboard");
    await expect(page.getByRole("heading").first()).toBeVisible();

    const accessToken = (await page.context().cookies()).find((c) => c.name === "access_token");
    expect(accessToken, "access_token cookie present").toBeTruthy();
    expect(accessToken?.httpOnly, "access_token is httpOnly").toBe(true);
    // The token must never be exposed to page JS.
    const documentCookie = await page.evaluate(() => document.cookie);
    expect(documentCookie).not.toContain("access_token");
  });
});
