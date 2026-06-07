// API-level helpers used by the specs to assert backend state without driving the UI.
import { request, type APIRequestContext } from "@playwright/test";

const BASE_URL = process.env.PGUARD_WEB_URL ?? "http://localhost:3100";

/**
 * POST the login through the web-admin same-origin `/v1` proxy (→ gateway → identity) and return
 * the HTTP status. Uses a throwaway, cookie-less context so it never collides with the admin
 * session and each call is an isolated credential check (200 = authenticated, 401 = rejected).
 *
 * Callers poll this SPACED (≤ ~1/s) because the gateway auth tier allows 5 requests / second / IP.
 */
export async function loginStatus(identifier: string, password: string): Promise<number> {
  const ctx: APIRequestContext = await request.newContext({ baseURL: BASE_URL });
  try {
    const res = await ctx.post("/v1/auth/login", {
      data: { identifier, password },
      failOnStatusCode: false,
    });
    return res.status();
  } finally {
    await ctx.dispose();
  }
}
