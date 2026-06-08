# Phase 2 — mobile slice 3: guard-side app (work spec, track B / Terminal ขวา)

> For Claude Code. Builds on the merged mobile foundation (Riverpod, ApiClient→/v1, WS,
> tokens, PGuardHeader; auth + customer booking flow are on main). Add the **guard side**:
> go online → receive a job → work it with hourly check-ins → complete. Frontend-only
> (apps/mobile) — safe in parallel with the backend track. Visual truth:
> `Mobile - Guard App.html`, `Mobile - Active Standby.html` (browse via Review Console).
> Branch off main in its own worktree. Don't merge; don't touch `../guard-dispatch/`.

## Setup

```bash
git worktree add ../pguard-guard -b feat/mobile-guard-app main   # base on local main (has foundation + booking)
# work in ../pguard-guard
```

## Scope — guard happy path

Reuse the slice-1/2 foundation (controllers, ApiClient, tokens, design tokens, PGuardHeader, WS layer).

1. **Guard dashboard + online/standby toggle** — toggle drives a `TrackingController` (Riverpod) that starts/stops GPS streaming over the presence WebSocket (Bearer-on-upgrade). Show connecting/online/offline + GPS accuracy. (`Mobile - Active Standby.html`)
2. **Incoming job** — list/detail of assigned bookings → **accept / decline** via `PUT /v1/bookings/{id}/accept|decline` (exist on the gateway). (`Mobile - Guard App.html`)
3. **Active job** — drive transitions `PUT /v1/bookings/{id}/en-route|arrived|start|complete` (all exist). Countdown to booked end from `started_at` + `booked_hours` (a **display-only** countdown in the controller — allowed; it is NOT status polling). Map to the customer location (`location_lat/lng` from the active-job payload).
4. **Hourly check-in (photo + GPS)** — at each hour boundary, capture a photo (`image_picker`) + current GPS and submit a progress report.
5. **Complete** → hand off / return to dashboard; live status already flows over WS.

## Backend dependencies (flag, don't block)

Two endpoints may not be exposed on the gateway yet — code against the documented contract,
prove with a fake feed, and list them clearly for the backend track to add:
- **Presence GPS WebSocket** (`/v1/ws/track` or similar) — presence service is only partially built (purge only). If absent, stub the `TrackingController` transport against the agreed frame shape.
- **Progress-report / hourly check-in endpoint** (photo + GPS upload) — may not exist in v2 booking yet. Stub against contract + flag.

## Don't (CLAUDE.md Flutter)

- ❌ No Provider/ChangeNotifier · ❌ no `Timer.periodic` for booking/assignment **status** (use WS) — the hour-boundary/countdown display timer is fine · ❌ no business logic (countdown/checkin scheduling math) in screen state → controllers · ❌ tokens in prefs/URL · ❌ god-screens > 800 LOC · design tokens only.

## Definition of Done

- `flutter analyze` clean · `flutter test` green (TrackingController online/offline + GPS-accuracy logic; active-job transition controller; check-in hour-boundary/missed logic; ≥1 widget test for the active-job screen).
- `build_runner` codegen reproducible (`*.g.dart` git-ignored).
- Backend deps documented in the PR description (presence WS, check-in endpoint).
- Update `PROGRESS.md` (tick + Completed-log row) · run the review agents · own PR off main · don't merge.

## Reference

- Designs: `redesign-pguard/project/pguard/Mobile - Guard App.html`, `Mobile - Active Standby.html`, `Mobile Guard.html`, `Design System.html` (open `Review Console.html`). `Coverage Matrix.html` = screen↔endpoint.
- Contracts: `contracts/openapi/booking.yaml` (transitions + active-job), gateway `/v1/*`.
- v1 mobile (read-only): `../guard-dispatch/frontend/mobile/lib/screens/guard/` — `active_job_screen`, `guard_job_detail_screen`, the GPS `TrackingProvider`, hourly progress-report logic (port the UX to Riverpod; don't copy).
