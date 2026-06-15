// The ONLY API surface for the browser (CLAUDE.md › Web): typed clients generated from the
// OpenAPI source of truth (`pnpm gen:api` → src/api/generated/*), wrapped with openapi-fetch.
// No hand-rolled fetch against backends anywhere in the app.
//
// Auth is cookie-based (httpOnly `access_token`, set by the gateway/identity on login) — never
// localStorage. `credentials: "include"` sends the cookie; the CSRF middleware adds
// `X-Requested-With` on state-changing calls (the gateway enforces it for cookie-auth). The
// browser hits a SAME-ORIGIN `/v1` (proxied to the gateway via next.config rewrite) so the
// cookies stay first-party.
import createClient, { type Middleware } from "openapi-fetch";

import type { paths as IdentityPaths } from "@/api/generated/identity";
import type { paths as ProfilePaths } from "@/api/generated/profile";
import type { paths as RatingPaths } from "@/api/generated/rating";
import type { paths as PaymentPaths } from "@/api/generated/payment";
import type { paths as BookingPaths } from "@/api/generated/booking";
import type { paths as PresencePaths } from "@/api/generated/presence";
import type { paths as CallingPaths } from "@/api/generated/calling";
import type { paths as ChatPaths } from "@/api/generated/chat";

/** Same-origin gateway prefix for the browser (proxied to the gateway). Overridable for an
 *  off-origin deployment via NEXT_PUBLIC_API_BASE_URL (then CORS + SameSite must allow it). */
const BROWSER_BASE = process.env.NEXT_PUBLIC_API_BASE_URL ?? "/v1";

/** Attach the CSRF marker on cookie-auth, state-changing requests (gateway requires it). */
const csrfMiddleware: Middleware = {
  onRequest({ request }) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      request.headers.set("X-Requested-With", "XMLHttpRequest");
    }
    return request;
  },
};

function browserClient<T extends object>() {
  const client = createClient<T>({
    baseUrl: BROWSER_BASE,
    credentials: "include", // send/receive the httpOnly auth cookies
  });
  client.use(csrfMiddleware);
  return client;
}

/** identity service (login / logout / me) — browser. */
export const identityApi = browserClient<IdentityPaths>();

/** profile service (admin guard-profiles list / approve / reject) — browser. */
export const profileApi = browserClient<ProfilePaths>();

/** rating service (admin reviews list + visibility toggle) — browser. */
export const ratingApi = browserClient<RatingPaths>();

/** presence service (admin live guard locations) — browser. */
export const presenceApi = browserClient<PresencePaths>();

/** payment service (caller payments; admin payments/refunds endpoints are not in the v2
 *  contract yet — see the wallet page). Client wired so it is ready when they land. */
export const paymentApi = browserClient<PaymentPaths>();

/** booking service (bookings lifecycle + admin bookings/pricing catalog). */
export const bookingApi = browserClient<BookingPaths>();

/** calling service (admin read-only call log — GET /admin/calls). */
export const callingApi = browserClient<CallingPaths>();

/** chat service (admin conversation list + per-conversation message read — admin-readable). */
export const chatApi = browserClient<ChatPaths>();
