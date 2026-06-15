// The chat admin conversation list (chat `GET /admin/conversations`) renders without crashing
// — a real read-only moderation screen now, no longer a ComingSoon stub. Data-tolerant: the
// seed may have no conversations, so we assert the page mounts + resolves (heading, no
// load-error banner, no uncaught errors), not a specific row count.
import { test, expect } from "@playwright/test";

test("chat page renders the admin conversation list without crashing", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/chat");
  await expect(page.getByRole("heading").first(), "page mounted").toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByRole("main").getByRole("alert"), "no load error").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
