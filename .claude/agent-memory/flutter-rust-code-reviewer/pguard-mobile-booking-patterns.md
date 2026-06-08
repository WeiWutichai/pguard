---
name: pguard-mobile-booking-patterns
description: Booking flow architecture, money rules, Riverpod patterns, and API contract details for the customer booking slice (Phase 2 mobile slice B)
metadata:
  type: project
---

## API contract (v2 — leaner than original spec)

- No `/v1/pricing/services` endpoint — service categories are presentation-only (`SecurityService` enum in `service_catalog.dart`)
- `POST /v1/bookings` body: `{ address, scheduled_at, hours, guard_count }` — NO lat/lng
- `GET /v1/available-guards` — no params, returns approved guards with rating summary
- No `/assign` endpoint — v2 is first-come-accept
- Money fields on wire: exact decimal STRINGS (e.g. `"500.00"`), never floats
- `POST /v1/payments` body: `{ booking_id, amount, payment_method }` where `amount` = `amountString(payTotalSatang)`
- Error envelope: `{ error: { code, message } }` or `{ error: "string" }`
- Success envelope: `{ success, error, data }` — `ApiClient._unwrap()` extracts `data`

## Money rules

- All arithmetic in integer satang (1 baht = 100 satang)
- `Money.satangFromString(String?)` — parses decimal string to satang, tolerant of null/garbage → returns 0
- `Money.amountString(int satang)` — formats satang back to 2dp decimal string for wire
- `Money.format(int satang)` — display only, with ฿ symbol and thousands grouping
- `Money.total()` utility exists but `bookingSubtotalSatang` in the state computes inline
- Authoritative total is server-owned: `base_fee × hours × guard_count`; client derives `payTotalSatang = subtotal + tip` for the payment request; server re-verifies

## Riverpod architecture

- `bookingFlowControllerProvider` — `@Riverpod(keepAlive: true)`, `NotifierProvider<BookingFlowController, BookingFlowState>`
- Controller methods return `Future<bool>` (true = success, screen navigates)
- `_guard()` wrapper: sets busy=true → runs op → sets busy=false; catches ApiException and generic; early `return false` inside op also hits `_guard`'s cleanup
- `ServiceSelectionScreen.initState()` defers `reset()` via `Future.microtask()` to avoid modifying provider during build phase
- `CustomerHomeScreen` also calls `reset()` synchronously before pushing `/book` — double-reset is harmless but redundant

## Key files

- `lib/core/controllers/booking_flow_controller.dart` — all orchestration
- `lib/core/models/money.dart` — pure money helpers
- `lib/core/models/booking.dart` — Booking, BookingStatus, BookingLifecycle
- `lib/core/models/available_guard.dart` — discovery model
- `lib/core/models/payment.dart` — Payment, PaymentMethod, PaymentStatus
- `lib/core/location/location_service.dart` — abstract + offline default
- `lib/features/booking/widgets/map_picker.dart` — inline map picker (no native SDK)
- `lib/routing/app_router.dart` — go_router with session gate

## Known findings from Phase 2 slice B review (2026-06-05)

1. `map_picker.dart:_resolve()` — point-capture race: `_point` captured at line 63 (post-await) not at call time; stale name paired with newer point on rapid drag
2. `map_picker.dart:_resolve()` — concurrent geocode futures not de-duplicated; rapid taps/pans fire multiple in-flight geocodes that can resolve out-of-order
3. `payment_screen.dart:_SummaryCard` line 154 — display uses `state.hours`/`state.guardCount` but math uses `b.hours ?? hours`; if server normalizes these values the label multipliers will disagree with the subtotal
4. `booking_flow_controller.dart:bookingSubtotalSatang` — `b?.baseFee == null` guard means a booking with `baseFee` literally `null` returns `null` subtotal, but `Money.satangFromString(null)` returns 0, so a hypothetical non-null baseFee of `"0"` would produce a zero subtotal (not a bug per se, server should never return 0)
