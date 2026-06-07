// Project dependency: log in as the seeded admin once and persist the session (httpOnly cookies)
// for the dashboard specs to reuse. Selectors are by input attribute (autocomplete) so they're
// language-independent (the admin UI is TH/EN bilingual).
import { test as setup, expect } from "@playwright/test";
import path from "node:path";

import { ADMIN } from "./helpers/accounts";

const ADMIN_STATE = path.join(__dirname, "..", ".auth", "admin.json");

setup("authenticate as admin", async ({ page }) => {
  await page.goto("/login");
  await page.locator('input[autocomplete="username"]').fill(ADMIN.identifier);
  await page.locator('input[autocomplete="current-password"]').fill(ADMIN.password);
  await page.locator('button[type="submit"]').click();

  // On success identity sets the httpOnly cookies and the app soft-navigates to the dashboard.
  await page.waitForURL("**/dashboard");

  const cookies = await page.context().cookies();
  const accessToken = cookies.find((c) => c.name === "access_token");
  expect(accessToken, "access_token cookie set on login").toBeTruthy();
  expect(accessToken?.httpOnly, "access_token is httpOnly").toBe(true);

  await page.context().storageState({ path: ADMIN_STATE });
});
