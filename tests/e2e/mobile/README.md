# pguard mobile e2e — Patrol (wired + documented)

Patrol drives the **real** Flutter app on a device/emulator against the **live** backend
(`tooling/scripts/e2e-stack-up.sh`). The tests live in `apps/mobile/integration_test/`:

| Test | Flow | Needs backend? |
|---|---|---|
| `app_boot_test.dart` | app boots → phone-entry screen renders | no (smoke) |
| `register_login_flow_test.dart` | phone → OTP → PIN → role → register (202 pending) → (approve) → PIN login | yes |

The headline cross-service **approve → login** loop is already asserted end-to-end by the **web**
Playwright suite (`tests/e2e/web/applicants-approve.spec.ts`) against the same stack, so the mobile
suite focuses on the on-device onboarding UX.

## Status

**Wired, not run green here.** Three things must be in place to run it — none are available in this
environment, so per the spec this is *wire + document*:

1. **Native platform projects.** The app is pure-Dart at this phase (no `android/` / `ios/`). Run
   once: `cd apps/mobile && flutter create --platforms=android,ios .` (then re-apply
   `PLATFORM_PERMISSIONS.md`). Patrol builds a native test runner, so these must exist.
2. **An emulator/simulator.** Patrol's native automation has **no headless mode** — it needs an
   Android emulator or iOS simulator running. (`flutter devices` here shows only macOS/Chrome, which
   Patrol's native layer doesn't target.)
3. **A deterministic OTP** — see below.

## Run

```bash
# 1. backend up (SMS disabled → deterministic, no real SMS)
tooling/scripts/e2e-stack-up.sh

# 2. mobile deps + (one-time) native projects + Patrol native setup
cd apps/mobile
flutter pub get
flutter create --platforms=android,ios .         # one-time, if not already scaffolded

# 3. start an emulator, then run a test (Android emulator reaches the host gateway via 10.0.2.2)
dart run patrol_cli test -t integration_test/app_boot_test.dart
dart run patrol_cli test -t integration_test/register_login_flow_test.dart \
  --dart-define=PGUARD_API_HOST=http://10.0.2.2:3000 \
  --dart-define=PGUARD_E2E_OTP_CODE=123456          # see "OTP determinism"
```

## OTP determinism (the one backend hook still needed)

With `SMS_DISABLED=1` the otp service uses a `NoopSender`: a random 6-digit code is generated, only
its **sha256 hash** is stored (`otp.otp_codes.code_hash`), and the plaintext is never sent or
logged. `/otp/request` also **invalidates + replaces** any prior code, so you cannot simply
pre-seed a known hash before the app calls request. To make `/otp/verify` deterministic, add **one**
of:

- **(a) otp test affordance** — when SMS is disabled, return/fix the code (e.g. always `123456`, or
  echo it in the response under a test flag). Cleanest; then pass `--dart-define=PGUARD_E2E_OTP_CODE`.
- **(b) host-side hash hook** — after the app's `/otp/request`, overwrite the latest
  `otp.otp_codes.code_hash` for the test phone with `sha256('123456')`
  (`8d969eef6ecad3c29a3a873fba8e0f92c89acf97e4f53e7f85d6da99aa8ba9eb`), then enter `123456`.

`register_login_flow_test.dart` reads the code via `PGUARD_E2E_OTP_CODE` (`_obtainOtpCode`) so it's
ready the moment either hook exists.

## PIN login note

The mobile login sends `password = sha256(pin)` (see `core/controllers/pin_hasher.dart`); identity
Argon2-verifies that against `password_hash`. The seed (`seed-v2.sql`) stores `Argon2("Password123!")`,
**not** `Argon2(sha256(pin))`, so seeded accounts can't be logged in through the PIN flow. To test
PIN login directly, seed a user whose `password_hash = Argon2(sha256("123456"))` (generate the hash
once via the identity hasher) — or just register a fresh account through the flow above, which sets
the correct hash.

## Gateway gaps affecting on-device flows

The v2 gateway does not yet route **presence** (guard GPS / live status WS) or **chat**/**calling**
(documented in the api-gateway routing table + perf-baseline README). So the guard go-online GPS
stream, the customer live-status socket, and chat won't connect through the gateway until those
routes land. The onboarding (auth/otp/register/login) + booking-create flows above go through routed
services and are unaffected.
