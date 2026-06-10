// Provider verification — rating service. Rating is reachable two ways in the e2e stack: via the
// gateway (:3000 /v1) AND on a direct host port (:3007, the documented gateway-gap accommodation).
// We deliberately use BOTH, because auth for rating lives in different places:
//
//  - getGuardRatings (GET /guards/{id}/ratings) — the CANONICAL DRIFT this suite must catch. The
//    contract declares `security: [{bearerAuth: []}]` and its description states auth is enforced
//    AT THE EDGE ("the api-gateway enforces edge auth on every /guards/… route; 'public' means
//    visible-to-customers, not unauthenticated"). And indeed the SERVICE handler is intentionally
//    public — services/rating/src/api/mod.rs:100 `guard_ratings` takes NO AuthUser extractor. So
//    the faithful test of "auth is required" hits the GATEWAY (the client-facing surface where the
//    contract promises enforcement): an unauthenticated GET must be REJECTED (401). If the route is
//    ever made edge-public (the historical drift), this turns green→200 and the test fails. Hitting
//    :3007 here would prove nothing (the service ignores auth by design).
//
//  - submitReview / admin endpoints — these DO take AuthUser at the service (mod.rs:41,119,154), so
//    the service itself enforces auth+role. We test those DIRECTLY on :3007 to verify the service's
//    own enforcement and response shapes.
import { describe, expect, it } from "vitest";

import { ADMIN, CUSTOMER } from "../src/accounts.js";
import { RATING_DIRECT, accessToken, bearer, gatewayUrl, http } from "../src/http.js";
import { assertResponseMatchesSpec, requiresUserBearer } from "../src/validate.js";

// Seed guard #1 has 3 visible reviews (seed-v2.sql) → getGuardRatings returns a populated summary.
const SEED_GUARD_WITH_REVIEWS = "99999999-0000-0000-0000-000000000001";
// A seed booking owned by the test customer, status 'accepted' (NOT 'completed') → review → 409.
const SEED_BOOKING_ID = "11111111-0000-0000-0000-000000000001";

const ratingDirect = (path: string, init?: RequestInit) => http(`${RATING_DIRECT}${path}`, init);

describe("rating contract", () => {
  it("GET /guards/{id}/ratings (happy, via gateway) is contract-shaped", async () => {
    const token = await accessToken(CUSTOMER);
    const res = await http(gatewayUrl(`/guards/${SEED_GUARD_WITH_REVIEWS}/ratings`), {
      headers: bearer(token),
    });
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("rating", "get", "/guards/{id}/ratings", res);
    expect((res.body as { data?: { guard_id?: string } }).data?.guard_id).toBe(SEED_GUARD_WITH_REVIEWS);
  });

  it("DRIFT GUARD: GET /guards/{id}/ratings requires auth at the edge (unauthenticated → 401)", async () => {
    // The contract declares this endpoint requires a bearer token (edge-enforced).
    expect(await requiresUserBearer("rating", "get", "/guards/{id}/ratings")).toBe(true);
    // Unauthenticated request to the client-facing (gateway) surface MUST be rejected — NOT 200.
    const res = await http(gatewayUrl(`/guards/${SEED_GUARD_WITH_REVIEWS}/ratings`));
    expect(res.status, "getGuardRatings must not be publicly accessible (historical drift)").toBe(401);
  });

  it("POST /assignments/{id}/review without a token → 401 (service-enforced, ErrorBody)", async () => {
    const res = await ratingDirect(`/assignments/${SEED_BOOKING_ID}/review`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ overall_rating: 5 }),
    });
    expect(res.status).toBe(401);
    await assertResponseMatchesSpec("rating", "post", "/assignments/{id}/review", res);
  });

  it("POST /assignments/{id}/review on a non-completed booking → 409 (completed-gate, ErrorBody)", async () => {
    const token = await accessToken(CUSTOMER);
    const res = await ratingDirect(`/assignments/${SEED_BOOKING_ID}/review`, {
      method: "POST",
      headers: { ...bearer(token), "content-type": "application/json" },
      body: JSON.stringify({ overall_rating: 5 }),
    });
    expect(res.status).toBe(409);
    await assertResponseMatchesSpec("rating", "post", "/assignments/{id}/review", res);
  });

  it("GET /admin/reviews (admin) is contract-shaped; stats computed on the unfiltered set", async () => {
    const token = await accessToken(ADMIN);
    const res = await ratingDirect(`/admin/reviews`, { headers: bearer(token) });
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("rating", "get", "/admin/reviews", res);
  });

  it("GET /admin/reviews is admin-only → 403 for a customer (service ErrorBody)", async () => {
    const token = await accessToken(CUSTOMER);
    const res = await ratingDirect(`/admin/reviews`, { headers: bearer(token) });
    expect(res.status).toBe(403);
    await assertResponseMatchesSpec("rating", "get", "/admin/reviews", res);
  });

  it("PUT /admin/reviews/{id}/visibility (admin) returns the updated visibility (contract-shaped)", async () => {
    const token = await accessToken(ADMIN);
    const list = await ratingDirect(`/admin/reviews`, { headers: bearer(token) });
    expect(list.status).toBe(200);
    const first = (list.body as { data?: { data?: Array<{ id: string; is_visible: boolean }> } }).data
      ?.data?.[0];
    expect(first, "seed data should contain at least one review").toBeTruthy();

    // Set is_visible to its CURRENT value — idempotent no-op, but exercises the endpoint + shape.
    const res = await ratingDirect(`/admin/reviews/${first!.id}/visibility`, {
      method: "PUT",
      headers: { ...bearer(token), "content-type": "application/json" },
      body: JSON.stringify({ is_visible: first!.is_visible }),
    });
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("rating", "put", "/admin/reviews/{id}/visibility", res);
    expect((res.body as { data?: { id?: string } }).data?.id).toBe(first!.id);
  });
});
