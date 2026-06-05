# Phase 2 — Push-based mobile foundation + first slice (work spec)

> For Claude Code. `apps/mobile` is an empty Flutter+Riverpod scaffold. Phase 2's
> defining goal (CLAUDE.md): **WebSocket subscription replaces v1's 13-timer REST
> polling** for booking/assignment status. This slice builds the mobile foundation +
> ONE real-time vertical to prove the WS-push pattern. Visual source of truth = the 40
> design screens in `redesign-pguard/project/pguard/` (browse via Review Console.html).
> Port logic from v1 `../guard-dispatch/frontend/mobile/` (read-only). Don't merge.

## Part A — foundation (do once)

- **State:** Riverpod 2.x with `@riverpod` **codegen** (no Provider/ChangeNotifier). Controllers in `core/controllers/`, pure + testable without widgets.
- **Design tokens:** consume `apps/design-tokens/tokens.dart` (already exists) — no hardcoded colors. Build a shared `PGuardHeader` widget (green header pattern) — don't copy-paste markup.
- **Secure storage:** JWT access/refresh + PIN hash in `FlutterSecureStorage`; `SharedPreferences` only for non-sensitive prefs.
- **ApiClient (Dio):** base URL → api-gateway `/v1`; JWT interceptor auto-attaches Bearer; **proactive refresh** (refresh when `exp` < 2 min) + reactive 401 → `/v1/auth/refresh` retry; parse the `ApiResponse` envelope (`response.data['data']`).
- **WebSocket layer:** `core/network/sockets/` — connection lifecycle OUTSIDE any screen. Bearer token in the `Authorization` **header** on upgrade (never URL query). Auto-reconnect w/ exponential backoff (cap 60s); restart subscription on reconnect.

## Part B — first vertical slice (prove the pattern)

1. **Auth flow:** phone → OTP → PIN/login against `/v1` (otp + identity services). Tokens → secure storage. Land on the right dashboard by role. (UI per `Mobile - Auth.html` / `Mobile - Registration.html`.)
2. **Real-time booking status (the Phase 2 point):** the customer "waiting for guard / live job" screen subscribes over WebSocket to booking/assignment status transitions (accepted → en_route → arrived → … → completed). **No `Timer.periodic` polling.** UI per `Mobile - Customer App.html` / `Mobile - Active Standby.html`.
   - Backend already emits the lifecycle + has the assignment transitions; if a status WS endpoint isn't exposed yet on the gateway, note it as the one backend dependency and stub the client against the documented contract.

## Don't (CLAUDE.md Flutter rules)

- ❌ No Provider/ChangeNotifier for new features · ❌ no `Timer.periodic` for booking/assignment status · ❌ no business logic (countdown, proration) in screen state — put it in controllers · ❌ no god-screens > 800 LOC · ❌ tokens never in `SharedPreferences` or WS URL.

## Definition of Done

- `flutter analyze` clean · `flutter test` green (controller unit tests + ≥1 widget test). If the Flutter SDK isn't in the env, say so and fall back to `dart analyze` + structure review, don't fake it.
- Auth slice logs in against a running v2 stack (or documented mock) and stores tokens in secure storage
- The live-status screen updates from a WS message (demonstrate: no polling timer in the code path)
- Riverpod codegen runs (`build_runner`); generated files git-ignored per `.gitignore`
- Update `PROGRESS.md` (tick + Completed-log row) · run the review agents · push to a **new branch / its own PR** (this is a separate track from the backend PR #2) · don't merge or modify `../guard-dispatch/`

## Reference

- Designs: `redesign-pguard/project/pguard/Mobile - *.html` + `Design System.html` (open `Review Console.html` to browse). `Coverage Matrix.html` maps screens ↔ endpoints.
- v1 mobile (read-only): `../guard-dispatch/frontend/mobile/lib/` — `ApiClient`, `AuthProvider` (→ port to Riverpod), the screens being rebuilt. v1 `CLAUDE.md` mobile section = auth flow, secure storage, WS auth, PIN rules.
- Backend contracts: `contracts/openapi/*.yaml`; gateway routes `/v1/*`.
