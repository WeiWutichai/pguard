# Phase 3 — calling service + MediaSoup SFU (work spec)

> For Claude Code. The biggest Phase 3 slice: WebRTC voice/video. Two parts —
> a Rust **calling** signaling service + the Node **mediasoup** SFU (the one allowed
> non-Rust exception). Port from v1 (read-only `../guard-dispatch/`). Don't merge.

## Architecture

```
mobile  ──WS /ws/call (signaling)──►  calling (Rust)  ──service-JWT──►  mediasoup (Node SFU)
                                         │                                  └─ WebRTC media (UDP 40000-49999)
                                         └─ call_logs (own schema) + emit pguard.events.calling.*
```
- **calling (Rust):** signaling, call state machine, authz, persistence, events.
- **mediasoup (Node):** media plane only (transports/producers/consumers). Never trusts
  the client directly — calling brokers it with a **service-JWT**.

## calling service (Rust) — layering

`api/` (WS + REST handlers) · `domain/` (pure call state machine) · `repo/` (call_logs schema) ·
`events/` (emit via outbox) · `models.rs`.

### Endpoints (port from v1 booking `calls/*`)

- `POST /calls/initiate` · `GET /calls/{id}` · `PUT /calls/{id}/accept` ·
  `PUT /calls/{id}/reject` · `PUT /calls/{id}/end` · `PUT /calls/{id}/connected`
- `GET /ws/call` — WebSocket signaling (SDP offer/answer + ICE relay). **Mobile auth =
  Bearer in the `Authorization` header on upgrade; never token in the URL query** (v1 rule).

### State machine (pure, in `domain/`)

`initiated → accepted → connected → ended` (+ `rejected`, `missed`/timeout from `initiated`).
Illegal transitions rejected. 100% unit-testable, no IO imports.

### Rules

- **Authz:** only the two participants of an active booking may call each other — verify
  via booking `/internal/bookings/{id}` with **service-JWT**. Reject strangers (IDOR).
- **Events (outbox):** emit `pguard.events.calling.initiated|accepted|rejected|ended` in
  the same tx as the state write. notification consumes (incoming-call / missed-call push).
- **Persistence:** `call_logs` (caller, callee, booking, timestamps, duration, end_reason)
  — own `calling` schema, migration under `contracts/db/migrations/calling/`. No cross-svc FK.
- **No sensitive data in WS URL** (conversation/call ids go in messages after open).
- No `.unwrap()` in request/WS path. OTel span per request + WS session + tx.
- `contracts/openapi/calling.yaml` (3.1) for the REST half; document the WS protocol in the file header.

## mediasoup (Node SFU)

- Port v1 `services/mediasoup/` (currently `index.js`). Keep Node; runtime stays minimal.
- **Service-JWT'd:** every control call from calling → mediasoup carries a service-JWT
  (`aud="pguard-internal"`); mediasoup verifies it (fix the v1 gap where internal calls were unauthenticated).
- Config via env: `MEDIASOUP_ANNOUNCED_IP`, UDP range `40000-49999`. Fail-fast on missing config.
- Docker: non-root user; expose only the UDP media range, not a host TCP port (per v1 container rules).

## Definition of Done

- `cargo clippy --all-targets -D warnings` ✅ · `cargo test --workspace` ✅
- Domain unit tests: every legal + illegal state transition; timeout→missed
- Authz test: non-participant initiate → rejected; integration: `calling.*` lands in outbox
- WS test: signaling relay offer/answer with Bearer-on-upgrade auth (token-in-URL rejected)
- mediasoup: a control endpoint rejects a missing/invalid service-JWT (test it); `npm ci` lint clean
- Update `PROGRESS.md` (tick + Completed-log row) · run the 3 review agents, fix findings · push PR #2, don't merge

## v1 reference (read-only)

- `../guard-dispatch/services/booking/src/` — `calls/*` handlers + call state machine + `call_logs` (migration 043).
- `../guard-dispatch/services/mediasoup/src/index.js` — SFU setup.
- v1 `CLAUDE.md` — MediaSoup port 3005, `/call/*`, UDP 40000-49999, `MEDIASOUP_ANNOUNCED_IP`, WS auth rules.
