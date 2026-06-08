# event slice — approval → login propagation (profile → identity) — work spec

> For Claude Code (Terminal C). Close the loop the registration slice deferred: admin approves
> a profile (profile schema), but **login is gated on `identity.users.approval_status`** — a
> different schema identity owns. Today an approved guard still can't log in. This slice wires
> a NATS event so identity flips its own `approval_status` on approval. **No cross-schema
> writes** — that's the whole point of doing it as an event. Branch off freshly synced main.
> Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # 03653b8
git worktree add ../pguard-approval-evt -b feat/approval-event-slice main
cd ../pguard-approval-evt
```

## The gap (verified)
- `services/profile/src/api/mod.rs::admin_approve_guard` → `repo::set_approval_status(Approved)` flips **`profile.guard_profiles.approval_status`** only.
- `services/identity/src/repo/mod.rs` login eligibility = `is_active AND identity.users.approval_status='approved'` — a **separate** column identity owns. Register set it `pending`. Nothing flips it → approved guard still gets generic 401.
- `packages/shared-events` has `USER_COMPROMISED` but **no `user.approved`** topic; identity has **no consumer** yet.

## Scope

### A. shared-events — new topic(s)
- Add `pub const USER_APPROVED: &str = "pguard.events.user.approved";` (and `USER_REJECTED` for symmetry). Payload: `{ user_id, role, approved_at }`. Document in `contracts/asyncapi/events.yaml`.

### B. profile — emit on approval (transactional outbox, atomic)
- In `admin_approve_guard` (and the customer-approve endpoint if/when present), within the **same tx** as `set_approval_status(Approved)`, write a `user.approved` outbox row (mirror the booking/calling outbox producer). Approve + event are atomic — never one without the other. (Reject → optional `user.rejected`; login already blocks pending/rejected, so approved is the required unblocker.)
- Profile still writes **only** its own schema + the outbox; it does **not** touch `identity.users`.

### C. identity — durable consumer flips its own column
- Add `services/identity/src/events/{mod.rs, consumer.rs}` (identity's first consumer — mirror `services/payment/src/events/consumer.rs` / `presence`). Durable JetStream consumer on `pguard.events.user.approved`.
- On event: `UPDATE identity.users SET approval_status='approved' WHERE id=$user_id` (identity writes its **own** schema — boundary held). **Idempotent**: dedupe on `EventEnvelope.event_id` (at-least-once); a redelivered/duplicate event is a safe no-op. Wire the consumer into `main.rs` startup.
- After this, `verify_credentials` sees `approved` → the user can log in. (Mobile's "check status → loginWithPin" now succeeds post-approval.)

### D. contracts
- `contracts/asyncapi/events.yaml` — document `user.approved` (+`user.rejected`): producer = profile, consumer = identity.

## Definition of Done
- `cargo clippy --all-targets -D warnings` ✅ · `cargo test --workspace` ✅.
- **Tests**: profile approve writes the outbox row atomically with the status flip (same tx; rollback ⇒ neither); identity consumer flips `users.approval_status` on `user.approved` and is **idempotent** on duplicate `event_id`; end-to-end (DB-gated, mirror the slice's pattern): register pending → login blocked → admin approve (event) → consumer flips → login allowed.
- **No cross-schema write** — profile never writes `identity.*`, identity never writes `profile.*` (architecture-guardian confirms; the event is the only coupling).
- Update `PROGRESS.md` (tick "approval→login event slice" + Completed-log row) · run the 3 review agents (architecture-guardian + security-reviewer + code-reviewer) · own PR off main · **don't merge**.

## Reference (read-only)
- Outbox producer + durable consumer pattern: `services/calling/src/events/*`, `services/payment/src/events/consumer.rs`, `services/presence/src/events/consumer.rs`; envelope + dedupe: `packages/shared-events/src/lib.rs` (`EventEnvelope.event_id`). Approve handler: `services/profile/src/api/mod.rs::admin_approve_guard`. Login gate: `services/identity/src/repo/mod.rs` (`verify_credentials` / eligibility).
- Architecture rule: CLAUDE.md "Inter-service comms = NATS JetStream events" + "no direct INSERT into another service's schema" — this slice is the canonical example.
