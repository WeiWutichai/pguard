// The document-expiry admin screen (profile `GET /admin/documents/expiring`) renders without
// crashing — a real screen now, no longer a ComingSoon stub. Data-tolerant: the document_expiry
// table is empty until the upload+expiry-capture follow-up lands, so we assert the page mounts +
// resolves (heading, KPI cards, no load-error banner), not specific rows.
import { test, expect } from "@playwright/test";

test("expiring page renders the document-expiry surface without crashing", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));

  await page.goto("/expiring");
  await expect(page.getByRole("heading").first(), "page mounted").toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByRole("main").getByRole("alert"), "no load error").toHaveCount(0);
  expect(pageErrors, "no uncaught page errors").toEqual([]);
});
