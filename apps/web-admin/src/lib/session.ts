import "server-only";

import { cookies } from "next/headers";
import createClient from "openapi-fetch";

import type { components, paths as IdentityPaths } from "@/api/generated/identity";

/** The authenticated principal (`GET /auth/me` → `{ user_id, role, display_name?, email? }`). */
export type Me = components["schemas"]["Me"];

/** Server-reachable gateway base (internal DNS in prod). The generated path is `/auth/me`, so we
 *  append the gateway's `/v1` mount. */
const SERVER_BASE = `${process.env.PGUARD_API_BASE_URL ?? "http://localhost:3000"}/v1`;

/**
 * Resolve the session SERVER-SIDE by forwarding the incoming httpOnly `access_token` cookie to
 * the gateway `GET /auth/me`. Reading the cookie here (next/headers) makes the route dynamic; the
 * value is never exposed to the browser JS. Returns the user, or `null` when there's no usable
 * session (so the layout can redirect to /login without a flash of the dashboard).
 */
export async function getServerSession(): Promise<Me | null> {
  const store = await cookies();
  // Exact cookie-name fast path (skip the upstream call when there's plainly no session). The
  // gateway/identity remain the authoritative validators on the /auth/me call below.
  if (!store.has("access_token")) return null;
  const cookieHeader = store.toString();

  const client = createClient<IdentityPaths>({ baseUrl: SERVER_BASE });
  try {
    const { data, error } = await client.GET("/auth/me", {
      headers: { cookie: cookieHeader },
    });
    if (error || !data?.data) return null;
    return data.data;
  } catch {
    // Gateway unreachable / network error → treat as no session (the UI re-authenticates).
    return null;
  }
}
