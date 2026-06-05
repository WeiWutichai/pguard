// pguard v2 scaffold stub — Next.js config (App Router, TypeScript strict).
// TODO(CLAUDE.md › Web (Next.js)): All API calls go through the generated TS
// client produced from contracts/openapi (see src/api/README.md). Never hand-roll
// fetch calls to backend services from components.
// TODO(CLAUDE.md › Web (Next.js)): Cookie-based auth only (httpOnly, Secure,
// SameSite=Lax). Never store tokens in localStorage. CSRF token on state-changing
// endpoints.
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // App Router only (no Pages Router) — per CLAUDE.md.
  typedRoutes: true,
  reactStrictMode: true,
};

export default nextConfig;
