// HEADLINE e2e: the cross-service approve→login event loop.
//
//   admin approves a pending guard  (web-admin → profile: POST /v1/admin/guard-profiles/{id}/approve)
//     → profile flips approval + emits `user.approved` via the transactional outbox → NATS
//       → identity consumer flips identity.users.approval_status
//         → the guard, previously blocked, can now authenticate.
//
// We assert the WHOLE loop end-to-end: a guard that cannot log in while pending becomes loginable
// after the admin clicks Approve — proving the event actually propagated across services.
import { test, expect } from "@playwright/test";

import { createPendingGuard } from "./helpers/db";
import { loginStatus } from "./helpers/api";

test("approving a pending guard makes it loginable (user.approved event loop)", async ({ page }) => {
  const guard = createPendingGuard();

  // Precondition: identity blocks a non-approved account (masked as 401, anti-enumeration).
  expect(await loginStatus(guard.phone, guard.password), "pending guard cannot log in").not.toBe(
    200,
  );

  // Admin approves the guard from the pending applicants list.
  await page.goto("/applicants");
  const approveBtn = page.getByTestId(`applicant-approve-${guard.userId}`);
  await expect(approveBtn, "the seeded pending guard is listed").toBeVisible({ timeout: 15_000 });
  await approveBtn.click();
  // Optimistic removal; if the POST had failed the row would be restored — so it staying gone is
  // the first signal the approve persisted.
  await expect(approveBtn).toBeHidden();

  // Wait-for-condition (NO fixed sleep): poll the login through the proxy, spaced ≤1/s to respect
  // the 5 r/s auth limit, until the `user.approved` event has propagated and identity lets the
  // guard in. This is the actual cross-service assertion.
  await expect
    .poll(() => loginStatus(guard.phone, guard.password), {
      intervals: Array.from({ length: 30 }, () => 1000),
      timeout: 35_000,
      message: "guard becomes loginable once user.approved reaches identity",
    })
    .toBe(200);
});
