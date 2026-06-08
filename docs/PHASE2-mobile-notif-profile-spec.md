# Phase 2 — mobile slice 4: notifications + profile/settings (work spec, frontend)

> For Claude Code. Builds on the merged mobile foundation (Riverpod, ApiClient→/v1, WS,
> tokens, PGuardHeader; auth + customer booking + guard app are on main). Add the
> **notification centre** and **profile/settings** screens. Both backends already exist
> (notification service + identity `/me` + profile) — fully wireable, no backend deps, so
> this runs safely in parallel with the C5.3 backend track. Branch off main in its own
> worktree. Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull
git worktree add ../pguard-mobile-notif -b feat/mobile-notif-profile main
```

## Scope

### A. Notification centre
- List: `GET /v1/notification/notifications?unread_only&limit&offset` → `NotificationController` (Riverpod), pull-to-refresh.
- Unread badge: `GET /v1/notification/notifications/unread-count` → bell badge on the guard + customer dashboards (Stack + red count).
- Mark read: tap unread → `PUT /v1/notification/notifications/{id}/read` (optimistic); "read all" → `PUT /v1/notification/notifications/read-all`.
- Type→icon/colour map + relative-time formatting; empty state. (`Mobile - System.html` / `Mobile - More Screens.html`)

### B. Profile / settings
- Load `GET /v1/me` (identity) → name, phone, role, avatar, approval status. Guard extras via the guard-info endpoint if present.
- Edit: `PUT /v1/me` (name/email/avatar) — **phone is read-only** (login identifier; changing it needs re-OTP, out of scope).
- Logout → `POST /v1/auth/logout` then clear secure storage → back to auth.
- Language toggle (TH/EN) + theme if present. (`Mobile - Customer App.html` / `Mobile - Guard App.html` profile screens)

## Rules (CLAUDE.md Flutter)
- Riverpod `@riverpod` codegen; logic in `core/controllers/`. All calls via the existing `ApiClient`. Design tokens + `PGuardHeader`; no hardcoded colours. Tokens never in prefs/URL. No god-screens > 800 LOC. i18n TH/EN for new strings. No `Timer.periodic` (badge refreshes on screen focus / pull-to-refresh, not polling).

## Definition of Done
- `flutter analyze` clean · `flutter test` green (NotificationController list/unread/mark-read incl. optimistic + rollback; profile edit controller; ≥1 widget test for the notification list + badge).
- `build_runner` codegen reproducible (`*.g.dart` git-ignored).
- Update `PROGRESS.md` (tick + Completed-log row) · run the review agents · own PR off main · don't merge.

## Reference
- Designs: `redesign-pguard/project/pguard/Mobile - System.html`, `Mobile - More Screens.html`, `Mobile - Customer App.html`, `Mobile - Guard App.html`, `Design System.html` (open `Review Console.html`). `Coverage Matrix.html` = screen↔endpoint.
- Contracts: `contracts/openapi/{notification,identity,profile}.yaml`; gateway `/v1/*`.
- v1 mobile (read-only): `../guard-dispatch/frontend/mobile/lib/screens/notification_screen.dart`, profile/settings screens, `NotificationProvider` (port to Riverpod; don't copy).
