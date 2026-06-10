// Provider verification — booking service via the api-gateway (:3000 /v1). Covers read shapes,
// the create happy/400 paths, and role enforcement (the booking handlers — not the edge — own the
// 403s, so those carry the service ErrorBody and are validated against the contract).
//
// The multipart check-in (progress-reports) happy path + its 409 are exercised in
// events/events.contract.test.ts, which builds the arrived+work-started precondition and asserts
// the HTTP ProgressReport shape AND the emitted progress_reported event in one flow.
import { describe, expect, it } from "vitest";

import { CUSTOMER, GUARD } from "../src/accounts.js";
import { accessToken, bearer, gatewayUrl, http } from "../src/http.js";
import { assertResponseMatchesSpec } from "../src/validate.js";

// A deterministic seed booking owned by the test customer (seed-v2.sql: ids 11111111-0000-…-00000000000<i>).
const SEED_BOOKING_ID = "11111111-0000-0000-0000-000000000001";

describe("booking contract (gateway /v1)", () => {
  it("GET /bookings returns the caller's bookings as contract-shaped list", async () => {
    const token = await accessToken(CUSTOMER);
    const res = await http(gatewayUrl("/bookings"), { headers: bearer(token) });
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("booking", "get", "/bookings", res);
  });

  it("GET /bookings/{id} returns a single contract-shaped Booking", async () => {
    const token = await accessToken(CUSTOMER);
    const res = await http(gatewayUrl(`/bookings/${SEED_BOOKING_ID}`), { headers: bearer(token) });
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("booking", "get", "/bookings/{id}", res);
  });

  it("GET /bookings/{id} without a token → 401 at the edge", async () => {
    const res = await http(gatewayUrl(`/bookings/${SEED_BOOKING_ID}`));
    expect(res.status).toBe(401);
  });

  it("POST /bookings (happy, customer) creates a contract-shaped Booking", async () => {
    const token = await accessToken(CUSTOMER);
    const res = await http(gatewayUrl("/bookings"), {
      method: "POST",
      headers: { ...bearer(token), "content-type": "application/json" },
      body: JSON.stringify({
        address: "1 Contract Test Rd, Bangkok",
        scheduled_at: "2026-06-15T09:00:00Z",
        hours: 4,
      }),
    });
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("booking", "post", "/bookings", res);
    expect((res.body as { data?: { status?: string } }).data?.status).toBe("requested");
  });

  it("POST /bookings with an out-of-range field → 400 service ErrorBody", async () => {
    const token = await accessToken(CUSTOMER);
    // Body that DESERIALIZES (all required fields present, right types) but fails the handler's
    // business validation (hours <= 0) → the documented 400 ErrorBody. NOTE: a body that fails
    // DESERIALIZATION (e.g. a missing required field) is rejected by Axum's Json extractor with 422
    // BEFORE the handler — an undocumented status the contract lists only as 400. We target the
    // documented handler-400 path here; the 422 extractor gap is called out in the PR.
    const res = await http(gatewayUrl("/bookings"), {
      method: "POST",
      headers: { ...bearer(token), "content-type": "application/json" },
      body: JSON.stringify({ address: "1 Bad Rd", scheduled_at: "2026-06-15T09:00:00Z", hours: 0 }),
    });
    expect(res.status).toBe(400);
    await assertResponseMatchesSpec("booking", "post", "/bookings", res);
  });

  it("GET /available-guards returns a contract-shaped discovery list", async () => {
    const token = await accessToken(CUSTOMER);
    const res = await http(gatewayUrl("/available-guards"), { headers: bearer(token) });
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("booking", "get", "/available-guards", res);
  });

  it("GET /bookings/open is guard/admin-only → 403 for a customer (service ErrorBody)", async () => {
    const token = await accessToken(CUSTOMER);
    const res = await http(gatewayUrl("/bookings/open"), { headers: bearer(token) });
    expect(res.status).toBe(403);
    await assertResponseMatchesSpec("booking", "get", "/bookings/open", res);
  });

  it("POST /bookings/{id}/accept is guard-only → 403 for a customer (service ErrorBody)", async () => {
    const token = await accessToken(CUSTOMER);
    const res = await http(gatewayUrl(`/bookings/${SEED_BOOKING_ID}/accept`), {
      method: "POST",
      headers: bearer(token),
    });
    expect(res.status).toBe(403);
    await assertResponseMatchesSpec("booking", "post", "/bookings/{id}/accept", res);
  });

  it("guard can list open bookings (positive role check, contract-shaped)", async () => {
    const token = await accessToken(GUARD);
    const res = await http(gatewayUrl("/bookings/open"), { headers: bearer(token) });
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("booking", "get", "/bookings/open", res);
  });
});
