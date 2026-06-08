# presence — GPS WebSocket ingestion + live location (backend slice) — work spec

> For Claude Code. Build the real-time GPS path that replaces v1's REST-polling BUG cluster.
> The `presence` service today is **210 LOC: only retention + history purge** — no ingestion,
> no live store, no WS. This slice adds GPS-over-WebSocket, the current-position store, online
> status, and the IDOR-safe read APIs. **Mirror `services/calling/src/api/ws.rs` for the WS
> pattern** (Bearer-on-upgrade, mpsc fan-out, participant/role gate). **Contracts are source of
> truth — write them first.** Branch off freshly synced main. Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # must be at 38e91e6 (Phase 5 complete + infra fix)
git worktree add ../pguard-presence -b feat/presence-gps-ws main
cd ../pguard-presence
```

## What already exists (don't rebuild)
- `contracts/db/migrations/presence/0001_init.sql` — `presence.location_history` (append-only) + BRIN retention index + (user_id, recorded_at) btree.
- `services/presence/src/{repo.rs (purge_older_than), retention.rs (90-day job), main.rs (health)}`.

## Scope

### A. Schema — add the current-position store (new migration `0002_*.sql`)
`presence.guard_locations` (one row per guard, UPSERT target): `guard_id UUID PRIMARY KEY`, `lat/lng DOUBLE PRECISION`, `accuracy_m/heading/speed REAL NULL`, `recorded_at TIMESTAMPTZ`, `is_online BOOLEAN NOT NULL DEFAULT false`. No cross-service FK (bare UUID, per CLAUDE.md Data rules). Index for the admin map / discovery freshness filter.

### B. GPS WebSocket ingress — `GET /ws/track` (the core)
- **Auth on upgrade = Bearer in `Authorization` header** (AuthUser extractor before upgrade). Token in URL query → **reject 401** (mirror calling). 
- **Role gate: `user.role == "guard"` BEFORE upgrade** — admin/customer GPS ingest is forbidden.
- Incoming `GpsUpdate { lat, lng, accuracy?, heading?, speed?, assignment_id? }`. **`validate()`**: lat −90..90, lng −180..180, **reject (0,0)**, accuracy 0..10000, heading 0..360, speed 0..500. Sanitize `NaN`/`Infinite`/out-of-range → treat as `None` (don't reject the whole update — iOS sends −1).
- **Server rate limit: max 1 GPS update/sec/connection** — drop excess silently.
- On valid update: `tokio::join!` ( upsert `guard_locations` (sets `is_online=true`, updates `recorded_at`) · insert `location_history` row · publish live position to **Redis pub/sub** for the admin map ). Redis publish failure = **log-and-continue** (DB write already succeeded; next tick re-publishes).
- **Ping/pong zombie reaper**: server ping every 30s; no pong within 10s → disconnect + `set_offline()`.
- **On disconnect (any cause): `set_offline()`** → `UPDATE guard_locations SET is_online=false`. 
- **Heartbeat** (client keep-alive msg): rate-limit max 1/10s/conn; the heartbeat skip must run **before** the GPS 1/sec check (don't let heartbeat eat the GPS slot). **Pong/heartbeat must NOT touch `recorded_at` and must NOT call any "set_online"** — keep-alive only, else a guard who lost GPS but holds the socket stays falsely green.
- Server ACK back to client `{ "type":"ack", "recorded_at": <ts> }` (non-null ts only after a real upsert — no trivial `{"status":"ok"}`).

### C. Read APIs (REST, IDOR-safe)
- `GET /locations` (admin only) — bulk live guard locations; `?online_only=true`; response carries `is_online`. **Never** let customer pull bulk.
- `GET /guards/{id}/location` (latest) + `GET /guards/{id}/history` — customer must have an **active booking** with that guard (`has_active_booking()` check via booking service / event-derived read); guard may read own; admin any. No unrelated-guard access (IDOR).
- **Freshness rule** (used by discovery): a guard counts as live only when `is_online=true AND recorded_at > now() - interval '5 min'`.

### D. Events (NATS) — significant transitions only, not raw GPS
Raw high-frequency GPS stays on **Redis pub/sub** (live map). Emit NATS only for booking-relevant presence facts if/when needed (e.g. derived en_route/arrived already live in booking — do NOT duplicate here). Keep this slice's NATS surface minimal; document the boundary.

### E. Contracts (write FIRST, before handlers)
- `contracts/asyncapi/presence-ws.yaml` — `/ws/track` channel: GpsUpdate (pub), Ack/Ping (sub), auth = Bearer-on-upgrade.
- `contracts/openapi/presence.yaml` — the 3 REST reads (`/locations`, `/guards/{id}/location`, `/guards/{id}/history`) with the authz notes.

## Layering (CLAUDE.md per-service)
`api/` (ws.rs + REST handlers, thin) · `domain/` (GpsUpdate::validate, freshness/online pure logic — 100% unit-testable, no DB/HTTP imports) · `repo/` (upsert/history/set_offline/reads — sqlx) · `events/` (Redis publish + any NATS) · `state.rs`. Reuse `shared::{auth, config, error, service_jwt}` + `observability`.

## Definition of Done
- `cargo clippy --all-targets -D warnings` ✅ · `cargo test --workspace` ✅.
- **Domain unit tests**: `GpsUpdate::validate` (boundaries, reject (0,0), NaN→None), freshness (5-min), online/offline transitions, rate-limit decision — all pure, no DB.
- WS: role-gate (non-guard 401), Bearer-only (query-token rejected), 1/sec drop, ping/pong reaper sets offline, disconnect sets offline, pong does NOT touch recorded_at.
- IDOR tests on the read APIs (customer w/o active booking → 403; bulk = admin only).
- Contracts committed (asyncapi + openapi) and match the handlers.
- Update `PROGRESS.md` (tick presence under Phase 2 deps + Completed-log row) · run the 3 review agents · own PR off main · **don't merge**.

## Reference (read-only)
- v2 WS pattern: `services/calling/src/api/ws.rs` + `domain/mod.rs` + `state.rs` (mpsc registry, peer gate). 
- v1 logic to port (cite v1 paths when you do): `../guard-dispatch/services/tracking/` — GPS validate, 1/sec limit, ping/pong zombie, `is_online` on upsert / `set_offline` on close, `set_online` must-not-touch-`recorded_at` (commit 1a8e56c), pong must-not-touch (dd2d223), heartbeat 1/10s before GPS check (57f0ddc/cac6973), `has_active_booking` IDOR. CLAUDE.md (guard-dispatch) "GPS Tracking Security" Do/Don't is the rule list.
- PDPA: `v1-audit/07-pdpa.md` §7.1/§7.3 (GPS sensitive; retention already built — don't regress it).
