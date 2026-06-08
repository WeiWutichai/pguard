# web-admin slice 2 — guards · customers · reviews · pricing · wallet · map — work spec

> For Claude Code (Terminal C). The foundation slice built the shell + cookie auth + applicants
> page and left the other nav items as **stub pages** (`src/components/stub-page.tsx`). Fill them
> with the real admin workflows against the merged backend, reusing the foundation's `lib/api.ts`
> (cookie + CSRF) + generated client + `i18n` + `sidebar`. **Generated TS client from OpenAPI —
> extend `tooling/codegen/generate.sh` for the new services.** Branch off freshly synced main.
> Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # 14f687c
git worktree add ../pguard-web2 -b feat/web-admin-slice2 main
cd ../pguard-web2
```

## What exists to reuse (don't reinvent)
- `apps/web-admin/src/lib/api.ts` (cookie `credentials:'include'` + `X-Requested-With` CSRF), `src/lib/i18n.tsx`, `src/components/{sidebar,header,auth-provider}.tsx`, `src/api/generated/{identity,profile}.ts`. Stub pages already routed: `guards/customers/reviews/pricing/wallet/map`.

## Scope (each page = real data via the generated client, no raw fetch)
- **Guards** (`/guards`) — approved guards: `GET /v1/admin/guard-profiles?approval_status=approved` (profile). Detail modal (docs keys, bank masked per contract). 
- **Customers** (`/customers`) — approved customers (profile customer endpoints). Detail modal.
- **Reviews** (`/reviews`) — `GET /v1/admin/reviews` (rating, `listAdminReviews`) with rating/visibility/search filters; **visibility toggle** `PUT /v1/admin/reviews/{id}/visibility` — **optimistic + rollback** + error banner. Stats from the API's unfiltered `stats` (never compute from the filtered list).
- **Pricing** (`/pricing`) — service-rate CRUD: list (public `GET /v1/pricing/services`) + create/update/delete (admin, booking). After delete → **reload list** (not optimistic). `total = base_fee × hours × guards + tip` (no min/max/per-hour).
- **Wallet** (`/wallet`) — `GET /v1/admin/payments` + refunds (`GET /v1/admin/refunds?status=`, `PUT /v1/admin/refunds/{id}/process`) (payment). Refund process requires a reference; one-way transition.
- **Map** (`/map`) — admin live guard locations `GET /v1/locations?online_only=` (presence, admin-only bulk). Leaflet via **dynamic import `ssr:false`**; module-level icon cache; debounced search; conditional Popup. 3 statuses only (active/idle/offline).

## Rules (CLAUDE.md Web + foundation conventions)
- App Router · TS strict · cookie auth (no localStorage) · CSRF on writes · all calls via the generated client/`lib/api.ts` (no raw `fetch`) · `lucide-react` only · i18n TH/EN both keys · `cn()`. Extend `generate.sh` to emit clients for `rating/payment/booking/presence`; commit the generated files + document regen. Leaflet must be `ssr:false`.

## Definition of Done
- `pnpm build` ✅ · `pnpm lint` ✅ · `pnpm exec tsc --noEmit` strict ✅.
- Each page renders live data from its real endpoint; writes (visibility toggle, pricing CRUD, refund process) hit the contract with CSRF; reviews stats unfiltered; pricing reloads after delete; map gated admin-only + `ssr:false`.
- No raw `fetch`, no localStorage, i18n complete, lucide only.
- Update `PROGRESS.md` (tick web-admin slice 2 + Completed-log row) · run the review agents (code-reviewer + architecture-guardian + a security pass on the admin authz/CSRF) · own PR off main · **don't merge**.

## Reference (read-only)
- Contracts: `contracts/openapi/{profile,rating,payment,booking,presence}.yaml` (the admin/list/CRUD operationIds). Foundation: `apps/web-admin/src/{lib,components,api/generated}`. Codegen: `tooling/codegen/generate.sh`.
- v1 UX to port (cite paths; adapt to v2 contracts + generated client): `../guard-dispatch/frontend/web/app/(dashboard)/{guards,customers,reviews,pricing,wallet,map}/*`, `lib/{api,i18n}.ts`. CLAUDE.md (guard-dispatch) "Web Admin — Page Architecture" (Reviews/Pricing/Map sections) for the workflows — follow the v2 OpenAPI for the wire.
