---
name: P0 Critical Tests
description: Tests that block v2 launch — gleaned from v2-audit/04-tests.md
type: project
---

# P0 — must exist before launch

## Money path (zero coverage in v1)

### Payment proration (`services/payment/src/domain/proration.rs`)
- [ ] Full hours, no refund (booked = actual)
- [ ] Overtime clamps to booked (no auto-charge for extra hours worked)
- [ ] Partial hours = prorated refund
- [ ] Zero hours (started but never completed) — refund = full amount
- [ ] started_at > completed_at — returns zero (shouldn't happen but defense)
- [ ] Decimal precision: rate × hours doesn't introduce float drift

### Tip accumulation (`services/payment/src/domain/tip.rs`)
- [ ] First tip sets amount
- [ ] Second tip adds to first (never overwrites)
- [ ] Tip ≤ 0 rejected

### Refund state machine (`services/payment/src/domain/refund.rs`)
- [ ] pending → processed: must have reference (bank slip)
- [ ] pending → skipped: must have note
- [ ] processed → any: rejected (one-way)
- [ ] skipped → any: rejected
- [ ] Auto-set pending when refund_amount > 0 in prorate

## Safety path (zero coverage in v1)

### GPS validation (`services/presence/src/domain/gps_validate.rs`)
- [ ] Valid lat/lng inside bounds → accepted
- [ ] lat > 90, lat < -90 → rejected
- [ ] lng > 180, lng < -180 → rejected
- [ ] (0, 0) → rejected (null island defense)
- [ ] NaN, Inf in any field → rejected
- [ ] accuracy < 0 or > 10000 → rejected
- [ ] heading < 0 or > 360 → rejected (or null)
- [ ] speed < 0 or > 500 → rejected

### PIN lockout (`apps/mobile/lib/core/controllers/pin_lockout_state_machine.dart`)
- [ ] Attempts 1-4 → invalid + show remaining count
- [ ] Attempt 5 → 60s lockout
- [ ] Attempts 6-9 → 60s lockout each
- [ ] Attempt 10 → wipe (PIN hash cleared, biometric cleared, force re-OTP)
- [ ] Lockout persists across app restart (wall clock)
- [ ] Counter survives backup-restore asymmetry (init() defense)
- [ ] Successful PIN resets counter
- [ ] Concurrent validate calls serialized (no double-decrement)

## Auth path

### JWT validation (`services/identity/src/domain/jwt_verify.rs`)
- [ ] alg=none rejected
- [ ] Wrong signature rejected
- [ ] Wrong aud rejected
- [ ] Expired rejected
- [ ] Revoked jti (in Redis blocklist) rejected
- [ ] `trv` mismatch with user record rejected (force-revoke check)

### Refresh rotation (`services/identity/src/domain/refresh_chain.rs`)
- [ ] Original token after rotation: rejected
- [ ] Concurrent rotate (same token): exactly one succeeds, other gets reuse-detected
- [ ] Reuse detected → entire family revoked + compromise event emitted
- [ ] After 7-day TTL → rejected

## Authorization (IDOR — v1 had 0 tests for branches)

### Booking ownership
- [ ] customer can read own request
- [ ] customer cannot read other customer's request (403)
- [ ] assigned guard can read assigned request
- [ ] unassigned guard cannot read (403)
- [ ] admin can read any

### Chat participant
- [ ] participant can read messages
- [ ] non-participant gets 403
- [ ] admin bypasses participant check

### Tracking location
- [ ] guard can read own location only
- [ ] customer can read guard location only if active booking exists
- [ ] admin can read any

## Cross-service revocation (integration)

- [ ] POST /v1/auth/logout @ identity service
- [ ] Same jti subsequently rejected by booking service (401)
- [ ] Same jti subsequently rejected by chat service (401)
- [ ] Same jti subsequently rejected by presence service (401)
