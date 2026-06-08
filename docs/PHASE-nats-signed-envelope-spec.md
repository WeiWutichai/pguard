# NATS hardening — signed event envelope (forged-event defense) — work spec

> For Claude Code (Terminal C). Close the gap the approval-event slice flagged: the NATS bus has
> **no producer authentication** — anything that can publish to a subject can forge a
> state-changing event (e.g. a fake `user.approved` that approves an account, or `user.compromised`
> that force-revokes one). Add an **HMAC-signed event envelope**: producers sign, consumers verify
> before applying; an unsigned/forged/tampered event is rejected and never acted on. App-level,
> self-contained — no NATS server reconfig needed. Branch off freshly synced main. Don't merge;
> don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # c7ff826
git worktree add ../pguard-nats-sign -b feat/nats-signed-envelope main
cd ../pguard-nats-sign
```

## Current state (verified)
- `packages/shared-events/src/lib.rs` `EventEnvelope<T>` = `{ event_id, event_type, occurred_at, correlation_id, traceparent?, payload }` — **no signature**. Consumers dedupe on `event_id` but trust the payload's authenticity implicitly.
- Producers build envelopes in the outbox tx (booking/payment/rating/calling/profile/chat); consumers apply them (notification/presence/payment/identity). Auth-transition consumers (`identity` ← `user.approved`/`user.compromised`) are the highest-value forgery targets.

## Scope

### A. shared-events — sign + verify (single source of truth)
- Add a detached **HMAC-SHA256 signature** over the canonical serialized envelope (stable field order — sign the bytes the consumer will verify; e.g. sign `event_id || event_type || occurred_at || correlation_id || payload_json`). Put it in an envelope field (`sig`) or a NATS header — pick one, document it, keep it consistent.
- `sign_envelope(&envelope, key) -> signature` and `verify_envelope(&envelope, sig, key) -> bool` (constant-time compare via `subtle`, mirror the OTP code-compare). Unit-test: round-trip ok; tampered payload/event_type/event_id fails; wrong key fails; missing sig fails.
- Key: a dedicated `EVENT_SIGNING_SECRET` (≥64 chars, `${VAR:?}` in compose) loaded once at startup (mirror `JwtConfig`). Don't overload an unrelated secret.

### B. Producers sign
- Every place that publishes to NATS (the outbox relay/`publish`) signs the envelope with the shared secret before it hits the wire. Centralize in the publish helper so no producer can forget. Keep it inside the existing producer span.

### C. Consumers verify (fail-closed)
- Every durable consumer (`identity` approved, `notification`, `presence` booking-links, `payment`, any others) **verifies the signature before applying** the event. Invalid/missing → log + **drop** (do NOT ack-and-apply; treat as poison — count a metric, don't crash the consumer). Verification runs **before** the dedupe/business logic.
- Wire it so a forged `user.approved` / `user.compromised` is rejected at the consumer boundary.

### D. Infra + contracts
- `EVENT_SIGNING_SECRET` via `${VAR:?}` in `infra/docker/docker-compose.prod.yml` + the dev `.env` list; note it in the env docs. Update `contracts/asyncapi/events.yaml` to document the signed envelope (the `sig` field/header + the verify requirement).

## Definition of Done
- `cargo clippy --all-targets -D warnings` ✅ · `cargo test --workspace` ✅.
- **Tests**: sign/verify round-trip; tamper (payload/type/id) → verify fails; wrong/missing key → fails; a consumer integration test that a **forged `user.approved` is dropped** (identity does NOT flip approval_status) and a **valid signed one is applied** (mirror the event-slice's gated e2e). Constant-time compare.
- All producers sign via the central helper; all consumers verify fail-closed before business logic; no consumer crashes on a bad sig (drop + metric).
- `EVENT_SIGNING_SECRET` externalized `${VAR:?}` (no default); asyncapi documents it.
- Update `PROGRESS.md` (tick "NATS signed envelope" + Completed-log row; reference it closes the event-slice security MEDIUM) · run the 3 review agents (security-reviewer especially) · own PR off main · **don't merge**.

## Reference (read-only)
- Envelope + topics: `packages/shared-events/src/lib.rs`. Producer/consumer patterns: `services/{calling,payment,profile}/src/events/*`, `services/{identity,presence,payment}/src/events/*`. Secret-loading pattern: `packages/shared-rust/src/config.rs` (`JwtConfig`/`ServiceJwtConfig`, ≥64-char check). Constant-time compare: the OTP code path (`subtle::ConstantTimeEq`).
- Architecture rule: CLAUDE.md "Service auth (internal) = Service-JWT" is the request-path analogue; this is its event-bus counterpart. The event-slice spec (`docs/PHASE-approval-event-slice-spec.md`) documents the exact MEDIUM this closes.
