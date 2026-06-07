// pguard v2 scaffold stub — Next.js config (App Router, TypeScript strict).
// TODO(CLAUDE.md › Web (Next.js)): All API calls go through the generated TS
// client produced from contracts/openapi (see src/api/README.md). Never hand-roll
// fetch calls to backend services from components.
// TODO(CLAUDE.md › Web (Next.js)): Cookie-based auth only (httpOnly, Secure,
// SameSite=Lax). Never store tokens in localStorage. CSRF token on state-changing
// endpoints.
import type { NextConfig } from "next";

// Server-reachable gateway base (internal DNS in prod, e.g. http://api-gateway:3000). The
// browser talks to a SAME-ORIGIN `/v1` so the httpOnly auth cookies stay first-party (no CORS,
// no cross-site SameSite issues); this rewrite proxies `/v1/*` to the gateway. In a same-origin
// ingress deployment the ingress can own this instead — harmless either way.
const GATEWAY = process.env.PGUARD_API_BASE_URL ?? "http://localhost:3000";

// E2E-ONLY accommodation of a documented v2 gap: the gateway does NOT yet route the rating
// (reviews) or presence (locations) services (perf-baseline README + api-gateway routing table),
// so the same-origin `/v1` proxy can't reach them. When these are set (only in the e2e harness),
// route those two ADMIN prefixes straight to the services — which validate the SAME httpOnly
// `access_token` cookie — so the reviews + map pages exercise real data end-to-end. Unset in prod
// → the single `/v1`→gateway rule below is the only rewrite (behaviour identical to before).
const RATING_URL = process.env.PGUARD_RATING_URL;
const PRESENCE_URL = process.env.PGUARD_PRESENCE_URL;

const nextConfig: NextConfig = {
  // App Router only (no Pages Router) — per CLAUDE.md.
  typedRoutes: true,
  reactStrictMode: true,
  async rewrites() {
    const rules: { source: string; destination: string }[] = [];
    if (RATING_URL) {
      rules.push(
        { source: "/v1/admin/reviews", destination: `${RATING_URL}/admin/reviews` },
        { source: "/v1/admin/reviews/:path*", destination: `${RATING_URL}/admin/reviews/:path*` },
      );
    }
    if (PRESENCE_URL) {
      rules.push(
        { source: "/v1/locations", destination: `${PRESENCE_URL}/locations` },
        { source: "/v1/locations/:path*", destination: `${PRESENCE_URL}/locations/:path*` },
      );
    }
    // Everything else (and all of prod): same-origin `/v1` → gateway.
    rules.push({ source: "/v1/:path*", destination: `${GATEWAY}/v1/:path*` });
    return rules;
  },
  // Self-contained server bundle for the production Docker image: emits
  // `.next/standalone` (server.js + minimal node_modules) so the runtime stage
  // copies only what it needs — no dev deps, no full node_modules.
  // See infra/docker/web-admin.Dockerfile.
  output: "standalone",
  // Pin the file-tracing root to THIS app dir so standalone always emits the FLAT
  // layout (server.js at the bundle root) that web-admin.Dockerfile copies. Without
  // this, Next infers the root and could nest the output if a lockfile/workspace
  // file ever appears higher up. __dirname is the app dir at build time.
  outputFileTracingRoot: __dirname,
};

export default nextConfig;
