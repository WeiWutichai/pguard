// The admin profile screen renders without crashing — a real screen now, no longer a
// ComingSoon stub. The identity card (role + user_id) comes from the server-resolved session
// (useAuth, no fetch), so it mounts deterministically; the only live action is "sign out
// everywhere" (POST /auth/revoke-all), not exercised here. No load-error banner on mount.
import { test, expect } from "@playwright/test";

test("admin profile page renders account + session security without crashing", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/profile");
  await expect(page.getByRole("heading").first(), "page mounted").toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByRole("main").getByRole("alert"), "no error on mount").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
