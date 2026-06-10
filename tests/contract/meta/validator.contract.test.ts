// META / anti-tautology guard — runs WITHOUT the live stack.
//
// The whole suite is only worth anything if the validator actually FAILS on a non-conforming
// payload. These tests prove that: every response schema in the four target contracts compiles,
// every event envelope schema compiles, and a deliberately-broken payload is REJECTED while the
// correct one is ACCEPTED. If this file ever passes a malformed payload, the rest of the suite is
// a tautology and must not be trusted.
import { describe, expect, it } from "vitest";

import { getOperation, loadOpenApi, responseSchema, type ServiceKey } from "../src/specs.js";
import { assertEventMatchesSchema, validateSchema } from "../src/validate.js";

const SERVICES: ServiceKey[] = ["identity", "booking", "rating", "chat"];

describe("contract self-consistency (no stack required)", () => {
  for (const service of SERVICES) {
    it(`${service}: every documented JSON response schema compiles under Ajv`, async () => {
      const doc = await loadOpenApi(service);
      const paths = Object.keys(doc.paths ?? {});
      expect(paths.length).toBeGreaterThan(0);
      for (const p of paths) {
        for (const method of Object.keys(doc.paths[p])) {
          if (!["get", "post", "put", "patch", "delete"].includes(method)) continue;
          const contract = await getOperation(service, method, p);
          for (const status of Object.keys(contract.responses)) {
            const schema = responseSchema(contract, Number(status));
            if (!schema) continue;
            // compile + validate an empty object: must not THROW (a throw = malformed schema).
            expect(() => validateSchema(schema, {})).not.toThrow();
          }
        }
      }
    });
  }

  it("rejects a TokenPair response that is missing the required access_token", async () => {
    const contract = await getOperation("identity", "post", "/auth/login");
    const schema = responseSchema(contract, 200);
    expect(schema).toBeTruthy();
    // Correct shape ACCEPTED.
    const ok = validateSchema(schema, {
      success: true,
      error: null,
      data: { access_token: "a", refresh_token: "b", expires_in: 900, token_type: "Bearer" },
    });
    expect(ok.valid, ok.message).toBe(true);
    // access_token removed → REJECTED (proves provider-drift detection).
    const bad = validateSchema(schema, {
      success: true,
      error: null,
      data: { refresh_token: "b", expires_in: 900, token_type: "Bearer" },
    });
    expect(bad.valid).toBe(false);
  });

  it("rejects an ErrorBody whose error.code is the wrong type", async () => {
    const contract = await getOperation("identity", "post", "/auth/login");
    const schema = responseSchema(contract, 401);
    expect(schema).toBeTruthy();
    expect(validateSchema(schema, { error: { code: "UNAUTHORIZED", message: "no" } }).valid).toBe(true);
    expect(validateSchema(schema, { error: { code: 123, message: "no" } }).valid).toBe(false);
    expect(validateSchema(schema, { error: { message: "no" } }).valid).toBe(false);
  });

  it("event envelope validation accepts a well-formed job_accepted and rejects a broken one", async () => {
    const good = {
      event_id: "11111111-1111-1111-1111-111111111111",
      event_type: "pguard.events.booking.job_accepted",
      occurred_at: "2026-06-10T10:00:00Z",
      correlation_id: "22222222-2222-2222-2222-222222222222",
      // an extra envelope field (traceparent) must be tolerated, not rejected:
      traceparent: "00-abc-def-01",
      payload: {
        booking_id: "33333333-3333-3333-3333-333333333333",
        guard_id: "44444444-4444-4444-4444-444444444444",
        customer_id: "55555555-5555-5555-5555-555555555555",
      },
    };
    await expect(assertEventMatchesSchema("EnvelopeOf_JobAccepted", good)).resolves.toBeUndefined();

    // Missing guard_id in the payload → must throw.
    const bad = structuredClone(good);
    delete (bad.payload as Record<string, unknown>).guard_id;
    await expect(assertEventMatchesSchema("EnvelopeOf_JobAccepted", bad)).rejects.toThrow();

    // Missing the envelope correlation_id → must throw.
    const bad2 = structuredClone(good);
    delete (bad2 as Record<string, unknown>).correlation_id;
    await expect(assertEventMatchesSchema("EnvelopeOf_JobAccepted", bad2)).rejects.toThrow();
  });
});
