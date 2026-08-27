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
import type { paths as NotificationPaths } from "@/api/generated/notification";

/** Same-origin gateway prefix for the browser (proxied to the gateway). Overridable for an
 *  off-origin deployment via NEXT_PUBLIC_API_BASE_URL (then CORS + SameSite must allow it). */
const BROWSER_BASE = process.env.NEXT_PUBLIC_API_BASE_URL ?? "/v1";

/**
 * Base for the refresh/logout calls that MUST carry the `refresh_token` cookie. Identity scopes
 * that cookie to `Path=/auth` (shared build_cookie), so the browser only attaches it to request
 * paths that begin with `/auth` — a call to `/v1/auth/refresh` would send NO refresh cookie and
 * identity would 401 "Missing refresh token". We therefore issue refresh/logout to a same-origin
 * `/auth/*` URL (next.config rewrites `/auth/:path*` → gateway `/v1/auth/:path*`), which the
 * Path=/auth cookie DOES match. Derived by stripping the trailing `/v1` from BROWSER_BASE so the
 * default same-origin deployment yields "" (→ "/auth/refresh"); an off-origin override yields the
 * host root (its ingress must expose `/auth/*`, same as the same-origin rewrite does).
 */
const AUTH_COOKIE_BASE = BROWSER_BASE.replace(/\/v1$/, "");

/** Attach the CSRF marker on cookie-auth, state-changing requests (gateway requires it). */
const csrfMiddleware: Middleware = {
  onRequest({ request }) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      request.headers.set("X-Requested-With", "XMLHttpRequest");
    }
    return request;
  },
};

// ── silent session refresh (fix: admin console hard-died every 15 min) ───────────────────────
// The access cookie's Max-Age == JWT_EXPIRY_MINUTES (15 in staging/prod). Without this, every API
// call after 15 min returned 401 forever (no refresh was wired, and even a hand-written one would
// have failed the Path=/auth cookie mismatch). We now transparently rotate on 401: a single shared
// refresh (deduped across concurrent 401s), then replay the original request once with the fresh
// cookie. A genuine refresh failure (7-day family expired / revoked / SESSION_SUPERSEDED) bounces
// to /login instead of a silent retry-forever banner.

/** Pre-session / session-lifecycle auth calls that must NOT trigger a refresh-retry: a 401 here is
 *  terminal (bad credentials / bad 2FA code / already logging out), and retrying `refresh` on a
 *  `refresh` 401 would recurse. Everything else (incl. /auth/me, /auth/sessions, /auth/2fa/setup)
 *  is eligible. Matched on the URL path so query strings don't defeat it. */
function isSessionLifecycleCall(url: string): boolean {
  let path = url;
  try {
    path = new URL(url, "http://x").pathname;
  } catch {
    /* relative/opaque URL → fall back to the raw string match below */
  }
  return (
    path.endsWith("/auth/login") ||
    path.endsWith("/auth/refresh") ||
    path.endsWith("/auth/logout") ||
    path.endsWith("/auth/2fa/verify")
  );
}

/** Dedupe concurrent refreshes: the first 401 kicks off ONE `POST /auth/refresh`; every other 401
 *  in flight awaits the same promise. Cleared when it settles so the next expiry can refresh again. */
let refreshInFlight: Promise<boolean> | null = null;
function refreshSession(): Promise<boolean> {
  if (!refreshInFlight) {
    refreshInFlight = identityAuthApi
      .POST("/auth/refresh", {})
      .then(({ error }) => !error)
      .catch(() => false)
      .finally(() => {
        refreshInFlight = null;
      });
  }
  return refreshInFlight;
}

/** One-shot bounce to /login on a confirmed refresh failure (dead session). Guarded so a burst of
 *  failing 401s can't stack navigations, and so we never loop while already on the login route. */
let redirectingToLogin = false;
function redirectToLogin() {
  if (typeof window === "undefined" || redirectingToLogin) return;
  if (window.location.pathname.startsWith("/login")) return;
  redirectingToLogin = true;
  window.location.assign("/login");
}

// Clones of in-flight requests, kept by openapi-fetch request id so a 401-retry can re-issue the
// EXACT request (method, headers incl. X-Requested-With, body) after refresh. Cloned in onRequest
// because the original body is consumed by the time onResponse runs.
const pendingClones = new Map<string, Request>();

const sessionRefreshMiddleware: Middleware = {
  onRequest({ request, id }) {
    try {
      pendingClones.set(id, request.clone());
    } catch {
      /* body not clonable (rare) → this request just won't be auto-retried */
    }
    return request;
  },
  async onResponse({ request, response, id }) {
    const original = pendingClones.get(id);
    pendingClones.delete(id);
    if (response.status !== 401 || isSessionLifecycleCall(request.url)) return response;

    const refreshed = await refreshSession();
    if (!refreshed) {
      redirectToLogin();
      return response;
    }
    if (!original) return response; // couldn't clone → surface the 401 (caller re-fetches)
    // Fresh access cookie is set; replay the original request once (credentials:include picks it up).
    try {
      return await fetch(original);
    } catch {
      return response;
    }
  },
};

function browserClient<T extends object>() {
  const client = createClient<T>({
    baseUrl: BROWSER_BASE,
    credentials: "include", // send/receive the httpOnly auth cookies
  });
  // Order matters: csrf first so its X-Requested-With header is present in the clone the refresh
  // middleware stashes for replay; refresh middleware second (its onResponse runs first, reverse order).
  client.use(csrfMiddleware);
  client.use(sessionRefreshMiddleware);
  return client;
}

/** identity service (login / logout / me) — browser. */
export const identityApi = browserClient<IdentityPaths>();

/**
 * Identity auth client for the two calls that must carry the Path=/auth refresh cookie
 * (`POST /auth/refresh`, `POST /auth/logout`). Points at AUTH_COOKIE_BASE (→ `/auth/*`) so the
 * cookie path matches. Deliberately WITHOUT the session-refresh middleware: refresh must not retry
 * itself, and logout should proceed even on a 401.
 */
export const identityAuthApi = createClient<IdentityPaths>({
  baseUrl: AUTH_COOKIE_BASE,
  credentials: "include",
});
identityAuthApi.use(csrfMiddleware);

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

/** notification service (admin broadcast bulk-send: composer/drafts/schedule/history + audience counts). */
export const notificationApi = browserClient<NotificationPaths>();
