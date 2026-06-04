# Phase 3 — Close the payment money path end-to-end (work spec)

> For Claude Code. payment is built but unreachable + has 3 follow-ups. Finish them so
> the first full vertical works: **book → accept → complete → pay → notify**, provable
> against running infra. Then move to rating. Don't edit `../guard-dispatch/`; don't commit unless asked.

## Scope (4 items, in order)

1. **Authoritative price column.** Money must be server-computed, never client-supplied.
   - Add `expected_total` (NUMERIC, Decimal-as-string on wire) to the payment/booking
     row, computed server-side: `base_fee × booked_hours × guard_count + tip`
     (pull `base_fee`/`hours`/`guard_count` from the authoritative booking read, not the
     request body). Reject a charge whose amount ≠ expected_total (± allow tip).
   - Migration under `contracts/db/migrations/<svc>/`. Keep scale ≤ 2dp guard.

2. **`booking.completed` consumer in payment.** This replaces v1's
   `review_completion()` doing proration inline (migration 036/042).
   - Subscribe to `pguard.events.booking.completed`. On receive: finalize proration
     (`actual_hours` clamped to `[0, booked_hours]`, refund = expected − final, round 2dp),
     write final_amount/refund_amount, set `refund_status='pending'` when refund > 0.
   - **Idempotent** by event `event_id` (consumer already has the pattern from notification).
   - Emit `pguard.events.payment.completed` / `payment.refund_processed` via the
     **transactional outbox** (same tx as the payment row update).

3. **Gateway `/v1/payments` route.** Right now `resolve("/v1/payments")` → NotFound.
   - Add the route in `services/api-gateway/src/domain/routing.rs` → payment service,
     JWT-at-edge (jti+trv+CSRF) like the other authed routes. Add a routing unit test
     that `/v1/payments` resolves to the payment upstream (flip the existing NotFound assert).

4. **End-to-end smoke.** With `infra/docker` up, exercise the path against real
   containers: create booking → accept → mark complete (emit booking.completed) →
   payment consumer finalizes → `payment.completed` event → notification logs + (mock) FCM.
   Add it as a DB/NATS-gated integration test (skip-if-no-infra guard like existing ones).

## Guardrails (CLAUDE.md)

- Money: `rust_decimal::Decimal` only, **serde as string** on the wire (no f64). utoipa `value_type = String`.
- Per-service schema ownership: payment writes payment schema only; read booking via
  its `/internal/bookings/{id}` with **service-JWT** (don't trust client, don't cross-write).
- Domain logic (proration, expected_total, finalizable-status guard) stays in `domain/`, pure + unit-tested.
- No `.unwrap()` in request/consumer path. OTel span per request + handler + tx.

## Definition of Done

- `cargo clippy --all-targets -D warnings` ✅ · `cargo test --workspace` ✅ (new tests green)
- Unit tests: expected_total computation, proration clamp/round, amount≠expected rejection, scale>2dp rejection
- Integration: booking.completed → payment finalize is **idempotent** (replay same event_id = no double refund); `/v1/payments` routes through gateway
- E2E smoke passes against `infra/docker`
- Update `PROGRESS.md` (tick + Completed-log row) · run the 3 review agents (security/arch/code) and fix findings before PR
- Push to the existing `feat/identity-booking` branch / PR #2 (or a follow-up branch) — don't merge

## v1 reference (read-only)

- proration + refund-on-completion: `../guard-dispatch/services/booking/src/service.rs`
  (`review_completion`, `compute_proration`, `prorate_payment_in_tx`) + v1 `CLAUDE.md`
  migration 036/039/042 notes (amount>0 validation, refund workflow).
- pricing formula: `total = base_fee × hours × guards + tip` (migration 037/038).
