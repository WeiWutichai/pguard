// Provider verification — identity service via the api-gateway (:3000 /v1). Anchors the auth flow
// every other contract test reuses: login → token, /auth/me, logout (+ token revocation), refresh.
//
// Envelope nuance this file pins:
//  - SERVICE-originated errors (e.g. a wrong-password 401 on the PUBLIC /auth/login route) pass
//    through the gateway and carry the documented ErrorBody {error:{code,message}} → validated
//    against the contract.
//  - EDGE-originated 401s (a tokenless call to a PROTECTED route, rejected by the gateway before it
//    reaches identity) carry the gateway's own envelope {success:false,error:"<string>"} — a known
//    divergence from the service ErrorBody. We assert the status + rejection, not the service schema.
import { describe, expect, it } from "vitest";

import { ADMIN, CUSTOMER, GUARD } from "../src/accounts.js";
import { bearer, gatewayUrl, http, loginRaw } from "../src/http.js";
import { assertResponseMatchesSpec, requiresUserBearer } from "../src/validate.js";

describe("identity contract (gateway /v1)", () => {
  it("POST /auth/login (happy) returns a contract-shaped TokenPair", async () => {
    const res = await loginRaw(CUSTOMER.identifier, CUSTOMER.password);
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("identity", "post", "/auth/login", res);
    const data = (res.body as { data?: { token_type?: string } }).data;
    expect(data?.token_type).toBe("Bearer");
  });

  it("POST /auth/login (wrong password) → 401 service ErrorBody (anti-enumeration)", async () => {
    const res = await http(gatewayUrl("/auth/login"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ identifier: CUSTOMER.identifier, password: "wrong-password-xyz" }),
    });
    expect(res.status).toBe(401);
    // login is public at the edge, so identity's ErrorBody passes through unchanged.
    await assertResponseMatchesSpec("identity", "post", "/auth/login", res);
  });

  it("GET /auth/me echoes the caller's role from the token (admin/customer/guard)", async () => {
    for (const [account, role] of [
      [ADMIN, "admin"],
      [CUSTOMER, "customer"],
      [GUARD, "guard"],
    ] as const) {
      const { access_token } = await loginRawCached(account);
      const res = await http(gatewayUrl("/auth/me"), { headers: bearer(access_token) });
      expect(res.status).toBe(200);
      await assertResponseMatchesSpec("identity", "get", "/auth/me", res);
      expect((res.body as { data?: { role?: string } }).data?.role).toBe(role);
    }
  });

  it("GET /auth/me is auth-required per the contract (tokenless → 401 at the edge)", async () => {
    // Expectation derived FROM the contract: /auth/me declares bearerAuth.
    expect(await requiresUserBearer("identity", "get", "/auth/me")).toBe(true);
    const res = await http(gatewayUrl("/auth/me"));
    expect(res.status).toBe(401);
    // Edge-originated rejection uses the gateway envelope, not the service ErrorBody.
    expect((res.body as { success?: boolean })?.success).toBe(false);
  });

  it("POST /auth/logout revokes the presented token (EmptyOk, then the token is rejected)", async () => {
    // Throwaway login so we don't revoke the cached token other tests reuse.
    const t = await loginRaw(CUSTOMER.identifier, CUSTOMER.password);
    const token = (t.body as { data: { access_token: string } }).data.access_token;

    const out = await http(gatewayUrl("/auth/logout"), { method: "POST", headers: bearer(token) });
    expect(out.status).toBe(200);
    await assertResponseMatchesSpec("identity", "post", "/auth/logout", out);

    // The blocklisted token must now be rejected at the edge.
    const after = await http(gatewayUrl("/auth/me"), { headers: bearer(token) });
    expect(after.status).toBe(401);
  });

  it("POST /auth/refresh rotates the pair; replaying the spent refresh token → 401 (reuse detection)", async () => {
    const t = await loginRaw(CUSTOMER.identifier, CUSTOMER.password);
    const refresh = (t.body as { data: { refresh_token: string } }).data.refresh_token;

    const rotated = await http(gatewayUrl("/auth/refresh"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refresh_token: refresh }),
    });
    expect(rotated.status).toBe(200);
    await assertResponseMatchesSpec("identity", "post", "/auth/refresh", rotated);

    // RFC 6749 §6 reuse detection: the spent token is no longer valid → 401 (family revoked).
    const replay = await http(gatewayUrl("/auth/refresh"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refresh_token: refresh }),
    });
    expect(replay.status).toBe(401);
    await assertResponseMatchesSpec("identity", "post", "/auth/refresh", replay);
  });
});

// Local cache so the role-matrix loop logs each shared account in only once (auth-tier rate limit).
const _tok = new Map<string, { access_token: string }>();
async function loginRawCached(a: { identifier: string; password: string }) {
  const hit = _tok.get(a.identifier);
  if (hit) return hit;
  const res = await loginRaw(a.identifier, a.password);
  const data = (res.body as { data: { access_token: string } }).data;
  _tok.set(a.identifier, data);
  return data;
}
