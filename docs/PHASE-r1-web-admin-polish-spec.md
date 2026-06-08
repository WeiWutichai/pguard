# Round 1 · web-admin polish — dashboard + activity + settings — work spec

> For Claude Code (Terminal C). web-admin has the shell + applicants + slice-2 pages. Make it look
> demo-complete: a real **dashboard** (overview cards + charts from live data), an **activity log**,
> and a **settings** page. Build only on endpoints that exist; document any aggregate gap (same
> discipline as slice 2). Branch off freshly synced main. Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # 2a40357
git worktree add ../pguard-web-polish -b feat/r1-web-admin-polish main
cd ../pguard-web-polish
```

## Scope

### A. Dashboard (`/dashboard`)
- Overview cards derived from **existing** endpoints (no invented aggregates): pending applicants (count from `admin/guard-profiles?approval_status=pending`), approved guards, customers (where available), reviews count + avg (from the reviews `stats`), online guards now (presence `/locations?online_only=true`), recent bookings/payments (from the list endpoints).
- A couple of **charts** (a small charting lib OR hand-rolled SVG — keep deps lean; if you add one, justify it): e.g. bookings/payments over recent window (from list timestamps), rating distribution (from reviews). Where a real time-series endpoint doesn't exist, derive from list data + label it, or render a documented-gap card — don't fake numbers.
- Loading/empty/error states; all via the generated client + `lib/api.ts` (cookie+CSRF); no raw fetch.

### B. Activity log (`/activity`) — add to nav
- Render recent admin-relevant events. If no audit/activity endpoint exists in v2 yet, build the page against whatever read endpoints do exist (recent approvals/reviews/payments) **or** ship it as a documented-gap page citing the missing audit endpoint (consistent with slice 2). Wire it into the sidebar.

### C. Settings (`/settings`) — add to nav
- Profile/account (from `/auth/me`), language toggle (reuse i18n), and app-level toggles that map to real endpoints; documented-gap for anything without backend support. Logout. No localStorage.

### D. Polish pass
- Consistent card/table/badge styling with the existing pages; lucide icons only; TH/EN i18n complete for all new strings; responsive; `cn()` for conditional classes. Update the sidebar nav for the new items.

## Definition of Done
- `pnpm build` ✅ · `pnpm lint` ✅ · `pnpm exec tsc --noEmit` strict ✅.
- Dashboard shows real derived numbers + at least one real chart (no fabricated data; gaps documented). Activity + Settings present and wired into nav. All data via generated client; cookie auth; CSRF on writes; lucide-only; i18n complete.
- Any new dependency justified + lockfile updated (keeps the prod image building).
- Update `PROGRESS.md` (tick web-admin polish + Completed-log row, listing any documented aggregate gaps for a future backend slice) · run the review agents (code-reviewer + architecture-guardian) · own PR off main · **don't merge**.

## Reference (read-only)
- Existing: `apps/web-admin/{app,src}` (foundation + slice 2 conventions — `lib/api.ts`, `components`, `i18n`, `api-gap-page.tsx`). Contracts for live numbers: `contracts/openapi/{profile,rating,payment,booking,presence,identity}.yaml`. The slice-2 documented-gap pattern is the model for missing aggregates.
- v1 UX reference (cite; adapt to v2 + generated client): `../guard-dispatch/frontend/web/app/(dashboard)/{page.tsx,activity,settings}/*`.
