# mobile — registration screens (Flutter + Riverpod) — work spec

> For Claude Code (Terminal B). Wire the Flutter registration flow to the **now-existing**
> backend (`POST /auth/register`, profile dual-auth via `profile_token`) — the piece
> `auth_controller.dart` itself flagged as *"reserved for the future registration endpoint."*
> That endpoint now exists (`contracts/openapi/identity.yaml` + `profile.yaml`). **Contracts are
> source of truth.** Branch off freshly synced main. Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # 03653b8
git worktree add ../pguard-mobile-reg -b feat/mobile-registration-ui main
cd ../pguard-mobile-reg
```

## Backend contract (already merged — build to this)
- `POST /otp/challenge` → `POST /otp/request` → `POST /otp/verify` ⇒ `phone_verified_token` (single-use). *(otp screens already exist: `features/auth/{phone_entry,otp_screen,pin_*}`.)*
- `POST /auth/register` `{ phone_verified_token, role: "guard"|"customer", pin_hash }` ⇒ **202** `{ user_id, profile_token }` — **no access/refresh tokens** (pending; can't log in until approved).
- `POST /profile/guard` / `POST /profile/customer` — accept the single-use `profile_token` (purpose-scoped) **or** `AuthUser`. Writes the profile; role already set by identity at register.
- `POST /auth/login` works only **after approval** (generic 401 while pending).

## What exists to reuse
- `auth_controller.dart` (phone→OTP→PIN cross-screen state; `loginWithPin`), `features/auth/*` screens, `secure_store.dart` (tokens/phone), `pin_hasher.dart`, `app_router.dart`, `api_client.dart`.

## Scope

### A. Extend the auth controller
- After OTP verify, store the `phone_verified_token` (secure storage). After PIN set, call **`POST /auth/register`** `{ phone_verified_token, role, pin_hash }`. On 202: stash `profile_token`, set session state = **pendingApproval** (never `authenticated`, never store access tokens at register).
- Role is chosen in a **role-selection screen** before register (or pass role into register). v2 = role-at-register (simpler than v1 progressive).
- Returning/approved user path: if register replies 409 ("log in instead") → try `loginWithPin`.

### B. Role selection screen
- After PIN setup → choose `guard` / `customer` → drives which profile form + the register `role`.

### C. Guard profile form
- Multi-step: personal (name, gender, DOB, experience, workplace) · 5 doc images (id_card, security_license, training_cert, criminal_check, driver_license) via `image_picker` (real picker, not simulated) · bank (name, account no — masked input, digits-only) → `POST /profile/guard` with the `profile_token` (multipart). On expiry, re-register/refresh path per contract.

### D. Customer profile form
- Single page: address (required, min length), company (optional), email (optional, `@`+`.` validate) → `POST /profile/customer` with `profile_token`.

### E. Pending screen
- After profile submit → `RegistrationPendingScreen(role)` showing the submitted summary + a "check status" action that attempts `loginWithPin` (success ⇒ approved ⇒ dashboard; else stays pending). No "edit" of a submitted profile.

## Rules (CLAUDE.md mobile)
- Never set `authenticated` after register (pending only); never store access tokens at register. Sensitive (tokens, PIN hash) in `FlutterSecureStorage`; pending flags in prefs (non-sensitive, masked bank no.). Riverpod `@riverpod`; pure flow logic in controller (unit-tested). Root screens wrapped to avoid back-gesture dead-ends. No god-screens >800 LOC.

## Definition of Done
- `flutter analyze` ✅ · `flutter test` ✅ · `build_runner` ok.
- **Controller tests**: register 202 → pendingApproval (no tokens stored); role threads into register + profile route; 409 → login path; profile submit uses `profile_token`; check-status → login-after-approval.
- Widget tests: role selection, guard multi-step validation, customer form validation, pending screen.
- Picks images with real `image_picker`; bank no. masked before any local persistence; full no. only to backend.
- Update `PROGRESS.md` (tick registration-mobile under Phase 4 + Completed-log row) · run the review agents (flutter-rust-code-reviewer + code-reviewer + architecture-guardian) · own PR off main · **don't merge**.

## Reference (read-only)
- Contracts: `contracts/openapi/identity.yaml` (`/auth/register`), `profile.yaml` (dual auth + `profileToken`). Existing flow: `apps/mobile/lib/core/controllers/auth_controller.dart` + `features/auth/*`.
- v1 UX to port (cite paths; adapt — v2 sets role at register, single-use profile_token, `/v1` paths): `../guard-dispatch/frontend/mobile/lib/screens/{role_selection,guard_registration,customer_registration,registration_pending}_screen.dart`. CLAUDE.md (guard-dispatch) "OTP Registration Flow" for the UX, but follow the v2 contract for the wire.
