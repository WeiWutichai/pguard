# web-admin — foundation + first slice (applicants/approvals) — work spec

> For Claude Code (Terminal B). `apps/web-admin` is a **stub** (layout + page + healthz only).
> Build the Next.js 16 App Router shell + cookie auth + the **applicants/approvals** page — the
> first real admin workflow, which ties into the approval→login event loop just shipped (admin
> approves a guard → `user.approved` → identity flips → the guard can log in on mobile).
> **Generated TS client from OpenAPI is the API surface — `tooling/codegen/generate.sh` exists.**
> Branch off freshly synced main. Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # c7ff826
git worktree add ../pguard-web-admin -b feat/web-admin-foundation main
cd ../pguard-web-admin
```

## Stack + rules (CLAUDE.md Web)
- Next.js 16 **App Router only** (no Pages Router), React 19, **TypeScript strict**.
- **Cookie-based auth** (httpOnly, Secure, SameSite=Lax) via the gateway — **never** localStorage. **CSRF**: send `X-Requested-With` on state-changing calls (the gateway + backends enforce it).
- **All API calls through the generated TS client** from `contracts/openapi/*` (run/extend `tooling/codegen/generate.sh`) — no raw `fetch`. Routes go through the gateway `/v1/*`.
- `lucide-react` icons only. Bilingual TH/EN via a `useLanguage()`-style i18n (keys in both langs). `cn()` (clsx + tailwind-merge) for conditional classes.

## Scope

### A. App shell
- Root layout: sidebar (nav items: Dashboard · Applicants · Guards · Customers · Map · Reviews · Wallet · Pricing — stub the ones not built this slice) + header (user menu, lang toggle, logout). `(dashboard)` route group. Auth provider reading the cookie session (`logged_in` marker + `/v1/auth/me`). Unauthenticated → login.

### B. Login
- Admin login form → gateway login (cookie path — tokens land in httpOnly cookies, **not** body). On success route to dashboard. Generic error (no user enumeration).

### C. Applicants / approvals page (the real workflow)
- List pending guard profiles via the profile admin endpoint (`GET /v1/admin/guard-profiles?approval_status=pending` — confirm in `contracts/openapi/profile.yaml`). Show name, submitted info, docs (keys present; uploads are a deferred backend follow-up — render what the contract returns). 
- **Approve** → `POST /v1/admin/guard-profiles/{user_id}/approve` (with `X-Requested-With`). On success the backend emits `user.approved` → identity flips → the applicant can now log in (the loop is already wired; the UI just triggers the approve). **Reject** → the reject endpoint.
- Optimistic row update with rollback on failure + error banner. Filter by status; stats from the list.

### D. Codegen + API client
- Generate the TS client into `apps/web-admin/src/api` from the OpenAPI specs (extend `tooling/codegen/generate.sh` if needed). Wrap with a thin `lib/api.ts` that attaches `X-Requested-With` + credentials:'include'. Document how to regenerate.

## Out of scope (later slices)
- Guards/Customers/Map/Reviews/Wallet/Pricing pages (stub nav, build later). Doc-upload viewing (backend follow-up).

## Definition of Done
- `pnpm install` + `pnpm build` ✅ (fix the scaffold: ensure a lockfile + `packageManager` field so the build is reproducible — this also unblocks the prod web-admin Docker image) · `pnpm lint` ✅ · `tsc --noEmit` strict ✅.
- The applicants page lists pending guards from the live contract shape and approve/reject hit the real endpoints with CSRF.
- All API access via the generated client (no raw `fetch`); auth via cookies (no localStorage); i18n TH/EN; lucide icons only.
- Update `PROGRESS.md` (tick web-admin foundation + Completed-log row) · run the review agents (code-reviewer + architecture-guardian; + a security pass on the cookie/CSRF flow) · own PR off main · **don't merge**.

## Reference (read-only)
- Contracts: `contracts/openapi/{identity,profile}.yaml` (login, `/auth/me`, admin guard-profiles approve/reject). Gateway auth/CSRF: `services/api-gateway/src/{auth.rs,domain/routing.rs}` (`PUBLIC_PATHS`, `X-Requested-With`, cookie names). Codegen: `tooling/codegen/{generate.sh,README.md}`. Scaffold: `apps/web-admin/{app,src,package.json}`.
- v1 UX to port (cite paths; adapt to v2 contracts + generated client): `../guard-dispatch/frontend/web/app/(dashboard)/applicants/*`, `components/{Sidebar,Header}.tsx`, `lib/{api,i18n}.ts`. CLAUDE.md (guard-dispatch) "Web Admin — Page Architecture" + "Applicant Flow" for the workflow — but follow the v2 OpenAPI for the wire, and note v2's guard approval emits an event (it doesn't directly flip the login flag).
