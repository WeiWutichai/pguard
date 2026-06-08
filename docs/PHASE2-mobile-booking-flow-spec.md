# Phase 2 — mobile slice 2: customer booking flow (work spec, track B / Terminal 3)

> For Claude Code. Builds on the merged mobile foundation (Riverpod, ApiClient→/v1, WS,
> design-tokens, PGuardHeader, auth + live-status are already on `main`). Add the customer
> **book-a-guard happy path**. Frontend-only (apps/mobile) — runs safely in parallel with the
> backend data-export track. Visual truth: `Mobile - Customer App.html` (browse via Review Console).
> Branch off `main` in its own worktree. Don't merge; don't touch `../guard-dispatch/`.

## Setup (avoid clobbering the shared main checkout)

```bash
git checkout main && git pull
git worktree add ../pguard-mobile2 -b feat/mobile-booking-flow main
# work in ../pguard-mobile2
```

## Scope — customer booking happy path

Reuse the slice-1 foundation (controllers, ApiClient, tokens, go_router). Build the flow:

1. **Service selection** — load rates from `GET /v1/pricing/services`; cards per service (`฿base_fee`). (`ServiceSelectionScreen`)
2. **Booking form** — job type, location (GPS + map picker w/ reverse-geocode → place name; store lat/lng separately), hours, guard_count → `POST /v1/bookings` (body per `contracts/openapi/booking.yaml` `CreateRequestDto`: location_lat/lng, address, booked_hours, guard_count…). (`BookingScreen`)
3. **Guard discovery** — `GET /v1/available-guards?lat&lng&radius_km` → list cards (name, avatar, distance, **rating average + count** from the merged discovery, completed jobs) → pick → `POST /v1/bookings/{id}/assign` (or the assign route in the contract). (`GuardSearchingScreen`)
4. **Payment** — amount = `base_fee × hours × guard_count + tip`; method select → `POST /v1/payments` (`{request_id, amount, payment_method}`; money as string) → success screen. (`PaymentScreen` → `PaymentSuccessScreen`)
5. **Hand off to live-status** — after payment, go to the slice-1 live booking-status screen (WS feed). No new polling.

## Rules (CLAUDE.md Flutter)

- Riverpod `@riverpod` codegen; flow logic in `core/controllers/` (booking controller), pure + test-fakeable.
- All calls via the existing Dio `ApiClient` (Bearer + refresh); never raw `fetch`/`Dio`.
- Money displayed from server values; never recompute authoritative totals client-side (display math only).
- Design tokens only (no hardcoded colors); reuse `PGuardHeader`; no god-screens > 800 LOC.
- No `Timer.periodic` anywhere in the status path (live-status stays WS-driven).
- i18n TH/EN for new strings.

## Definition of Done

- `flutter analyze` clean · `flutter test` green (booking-flow controller unit tests incl. create→discover→assign→pay happy path against a fake ApiClient; a widget test for service-selection + guard-card rating display).
- `build_runner` codegen reproducible (`*.g.dart` git-ignored).
- Update `PROGRESS.md` (tick + Completed-log row) · run the review agents · own PR off main (sibling of the backend PR) · don't merge.

## Reference

- Designs: `redesign-pguard/project/pguard/Mobile - Customer App.html`, `Mobile Hirer Booking.html`, `Design System.html` (open `Review Console.html`). `Coverage Matrix.html` = screen↔endpoint map.
- Contracts: `contracts/openapi/{booking,payment}.yaml`; gateway `/v1/*`.
- v1 mobile (read-only): `../guard-dispatch/frontend/mobile/lib/screens/` — the v1 booking screens (`ServiceSelectionScreen`, `BookingScreen`, `GuardSearchingScreen`, `PaymentScreen`) to port the flow/UX from (rebuild in Riverpod, don't copy).
