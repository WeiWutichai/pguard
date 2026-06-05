<!-- pguard v2 mobile app. See ../../CLAUDE.md "Flutter (mobile)". -->

# pguard_mobile

Customer-side Flutter app for **pguard** — book on-demand security guards.
Bilingual **TH/EN**. State managed with **Riverpod 2.x (codegen)**.

> v2 of guard-dispatch. v1 is a read-only reference at `../../../guard-dispatch/`;
> never edit or copy it. See repo root `CLAUDE.md` for architecture decisions.

## Phase 2 — what's built

The push-based foundation + the first real-time vertical:

- **Foundation (Part A):** design-token theme (path package `pguard_design_tokens`),
  `FlutterSecureStorage` wrapper (tokens + PIN), Dio **ApiClient → `/v1`** with auto Bearer,
  **proactive refresh** (refresh when `exp` < 2 min) + reactive 401 retry (single-flight), and a
  reconnecting **WebSocket** layer (Bearer on the upgrade **header**, exponential backoff cap 60s).
- **Auth flow (Part B):** phone → captcha → OTP (live `/v1/otp/*`) → 6-digit PIN sign-in
  (`POST /v1/auth/login {identifier: phone, password: pin}`; v1's PIN-as-password). The PIN is also
  stored locally (salted SHA-256) for an **offline lock screen** with 60s lockout (5 wrong) + wipe
  (10 wrong). Role-based landing via `go_router`.
- **Live booking status (the Phase 2 point):** the customer job screen subscribes to a booking-status
  **WebSocket** and advances `accepted → en_route → arrived → … → completed` from server **push** —
  **no `Timer.periodic` polling** (v1's 13-timer anti-pattern is gone).

### Backend dependency (documented, not faked)

The api-gateway does not yet proxy WebSocket upgrades (it strips the `upgrade` header) and no
`/v1/ws/bookings/{id}` endpoint exists yet. The client codes against the agreed contract and is
fully covered by tests using a fake feed; mirror the calling service's WS auth (Bearer-on-upgrade,
participant-only) when the endpoint lands. Contract:

```
URL  : {wsBaseUrl}/ws/bookings/{id}
Auth : Authorization: Bearer <access>   (on the HTTP upgrade — never the URL query)
Frame: { "type":"booking_status", "booking_id", "status", "occurred_at", "guard_id"? }
```

## Run

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generate Riverpod *.g.dart (gitignored)
flutter analyze
flutter test
# Point at a running v2 stack (gateway on :3000). Android emulator → 10.0.2.2:
flutter run --dart-define=PGUARD_API_HOST=http://localhost:3000
```

For active codegen during development: `dart run build_runner watch --delete-conflicting-outputs`.

Generated `*.g.dart` files are **git-ignored** — run `build_runner` after a fresh checkout.

## Conventions (from CLAUDE.md "Flutter (mobile)")

- **Riverpod 2.x with `@riverpod` codegen.** No `Provider` / `ChangeNotifier`.
- **No `Timer.periodic` polling** for booking/assignment status — updates arrive over a
  **WebSocket** (`lib/core/network/sockets/`). (The OTP/lockout 1s countdowns are display-only.)
- **Pure logic** (state machines, lockout/countdown math) lives in `lib/core/controllers/`,
  testable without widgets — not in screen state.
- Tokens + PIN hash → `FlutterSecureStorage` only; never `SharedPreferences`, never the WS URL.
- Reuse the shared `PGuardHeader` widget — don't copy-paste header markup. No hardcoded colors —
  consume `package:pguard_design_tokens`.

## Layout

```
lib/
├── main.dart · app.dart           ProviderScope + MaterialApp.router
├── core/
│   ├── config/                    base URLs (/v1, ws), refresh leeway
│   ├── controllers/               pure + Riverpod controllers (auth, session, pin, booking-status)
│   ├── models/                    auth + booking lifecycle (pure)
│   ├── network/                   Dio ApiClient + JWT decode + sockets/ (WS lifecycle, no polling)
│   ├── storage/                   SecureStore (+ SessionStore/PinStore/AppStore interfaces)
│   └── providers.dart             DI (appStore, pguardApi, pinService, ws feed builder)
├── features/                      auth/ · home/ · booking/ · splash
├── routing/                       go_router with session-gate redirect
└── widgets/                       PGuardHeader, pin keypad/dots, OTP boxes, status stepper, buttons
test/                             unit/ (pure) · controllers/ · widget/ + support/fakes.dart
```

## Testing

```bash
flutter test    # 40 tests: pure policies, controllers (incl. WS-push proof), widget tests
```
