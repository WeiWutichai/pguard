# @pguard/web-admin

pguard v2 web admin — Next.js 16 App Router, TypeScript strict. **v2 scaffold stub.**

Customer/guard operations console: guard onboarding, payments/refunds, ops
monitoring. Bilingual TH/EN.

## Run (dev)

```bash
pnpm install
pnpm dev
```

Then open http://localhost:3000. Health check: `GET /healthz` → `{"status":"ok","app":"web-admin"}`.

Other scripts: `pnpm build`, `pnpm start`, `pnpm lint`, `pnpm typecheck`.

> Do not run installers/builds as part of scaffolding — this skeleton intentionally
> ships without `node_modules`.

## Conventions (from `CLAUDE.md` › Web (Next.js))

- **App Router only** — no Pages Router.
- **TypeScript strict** — `strict: true` in `tsconfig.json`.
- **Cookie-based auth** — httpOnly, Secure, SameSite=Lax. **Never** store tokens
  in `localStorage`.
- **CSRF token** on every state-changing endpoint (POST/PUT/PATCH/DELETE).
- **All API calls go through the generated TS client** from `contracts/openapi`
  (lands in `src/api/generated/`, gitignored). See `src/api/README.md`.

## Layout

```
apps/web-admin/
├── app/
│   ├── layout.tsx        root layout (html lang, TH/EN switch — TODO)
│   ├── page.tsx          admin landing placeholder
│   └── healthz/route.ts  health check Route Handler
├── src/
│   ├── lib/              shared utilities (placeholder)
│   └── api/              generated TS client + wrappers (see src/api/README.md)
├── next.config.ts        typedRoutes; client routing notes
├── eslint.config.mjs     flat config extending next
└── tsconfig.json         strict; "@/*" -> "src/*"
```

## Environment

Copy `.env.example` to `.env.local` and fill in values. See the file for the
full list (`NEXT_PUBLIC_API_BASE_URL`, locale, internal gateway URL, CSRF header).
