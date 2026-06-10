# Chaos / failure-injection results (Round 3-B)

> **What:** inject the failures the v2 design claims to tolerate and record ACTUAL behaviour vs the
> design intent. **Tooling:** plain `docker stop -t 0` (crash-like SIGKILL that *stays* down —
> the compose `restart: unless-stopped` policy would auto-resurrect a `docker kill`, fighting the
> test) + curl/psql/k6 probes. **No service code is touched** (findings below are filed, not fixed).
>
> **Reproduce:** `tests/load/chaos/run-chaos.sh all` (or `… <1-5>` for one case). A trap restarts
> every stopped container on exit. Environment = the local prod stack (same as RESULTS.md), 2026-06-10.

## Summary

| # | Injected failure | Designed behaviour | Observed | Verdict |
|---|---|---|---|---|
| 1 | NATS down → up | outbox holds, drains on recovery (at-least-once) | tx committed w/ NATS down; backlog held; **drained in 0 s** on recovery | ✅ as designed |
| 2 | postgres-replica down | read fallback? | replica-served reads **500 (no fallback)**; primary/writes fine | ⚠️ **finding** — hard dependency |
| 3 | redis down → up | gateway survives; auth degrades | gateway process survives; auth fail-closed 500 while down; **stays 500 after recovery** | 🐛 **finding** — no reconnect |
| 4 | booking (mid-tier) down | gateway 502, no cascade | `/bookings`+`/available-guards` **502**; identity+profile **200**; **no cascade**; recovers 404 | ✅ as designed |
| 5 | WS backend killed mid-stream | client Close + reconnect | client got **close+error** after 5 acks; **reconnect opened cleanly** | ✅ as designed |

---

## Case 1 — NATS outage → outbox drain (at-least-once) ✅

`CHAOS_RESULT case=nats accept_http=200 pending_during=1 pending_still=1 drained=YES (0s) final_pending=0`

- With NATS **down**, a guard accepting a `requested` booking (`POST /v1/bookings/{id}/accept`) still
  returned **200** — the business tx + outbox row commit independently of NATS (transactional outbox
  working as designed). The `job_accepted` row sat **pending** (`published_at IS NULL`) and stayed
  pending while NATS was down (the relay retried, couldn't publish).
- On NATS recovery the relay **drained the backlog within the first poll** (`final_pending=0`).
- **Verdict:** at-least-once delivery proven end-to-end. The outbox decouples writes from the broker,
  and no event is lost across a broker outage.

## Case 2 — postgres-replica down ⚠️ FINDING

`CHAOS_RESULT case=replica read_replica_up=200 read_replica_down=500 write_during=200 read_recovered=200 behaviour=NO_FALLBACK`

- A replica-served read (`/v1/available-guards`, routed to `DATABASE_READ_URL`) returned **500** while
  the replica was down — **there is no fallback to the primary**. Writes / primary-served paths were
  unaffected (booking-create stayed **200**). Reads recovered to **200** once the replica was back.
- **Designed?** The C5.3 design routes reads to the replica for scale; it never promised
  primary-fallback. So this is *honest current behaviour*, but a **resilience gap**: a replica outage
  takes down all replica-served reads (discovery, admin lists, ratings) even though the primary is
  healthy.
- **Finding (filed, not fixed here):** add read fallback (retry on primary when the replica connection
  fails) OR run ≥2 replicas + a read load-balancer so a single replica loss isn't total. → PROGRESS.

## Case 3 — redis down → up 🐛 FINDING (real bug)

`CHAOS_RESULT case=redis gateway_healthz=200 protected_during=500 login_during=200 protected_recovered=500 gateway_survived=YES`

- **While redis was down:** the gateway **process survived** (`/healthz` 200). Protected routes
  (`/v1/auth/me`) returned **500** — edge auth does jti/trv lookups in redis and **fail-closes** (correct:
  it must not admit a token it can't verify isn't revoked). Public login still returned **200** (no edge
  auth; rate-limit is fail-open).
- **After redis recovered (healthy):** protected routes **still 500**. Confirmed out-of-band: with every
  container healthy and a fresh valid token, `/v1/auth/me` and `/v1/available-guards` stayed **500** until
  the gateway was **restarted** — after which they immediately returned **200**.
- **Root cause:** the gateway opens a single multiplexed redis connection at startup; when redis
  restarts, that connection breaks and is **never re-established**, so edge auth errors indefinitely.
  Because `/healthz` doesn't probe redis, an orchestrator won't auto-heal it.
- **Severity:** high for resilience — a transient redis blip (restart, failover, OOM) silently bricks
  **all protected traffic** at the edge until a manual gateway restart. (Likely affects other services
  that hold a long-lived multiplexed redis connection too — to be checked.)
- **Finding (filed, not fixed here):** the redis client must reconnect (connection-manager with retry /
  recreate-on-error), and `/healthz` (or a `/readyz`) should reflect redis reachability so orchestration
  can restart a wedged instance. → PROGRESS item.

## Case 4 — booking (mid-tier) down → gateway 502, no cascade ✅

`CHAOS_RESULT case=booking booking_down_502=502 discovery=502 identity=200 profile=200 cascade=NONE recovered=404`

- With `booking` down, the gateway returned a clean **502** for `/v1/bookings/{id}` and
  `/v1/available-guards` (discovery is booking-owned) — the proxy's upstream-unreachable path, not a hang.
- **Unrelated services were unaffected:** `/v1/auth/me` (identity) and `/v1/profile/me` (profile) stayed
  **200** — **no cascade**. On recovery `/v1/bookings/{id}` returned **404** (service back; the probe id
  doesn't exist), i.e. fully recovered.
- **Verdict:** the gateway isolates a downed upstream as designed; failures don't propagate across the
  service boundary.

## Case 5 — WS-proxy backend killed mid-stream → client Close + reconnect ✅

`CHAOS_RESULT case=ws_backend_kill during=[opened=1 acks=5 closed=1 errored=1] reconnect=[opened=1 acks=3 closed=1 errored=0]`

- A client opened `/v1/ws/track` **through the gateway WS proxy**, received **5 acks**, then presence was
  killed mid-stream → the client observed a **close + error** (the proxy propagated the backend cut rather
  than hanging the socket).
- After presence recovered, a fresh client **opened cleanly and got acks** (`opened=1`, reconnect works).
- **Verdict:** the WS proxy surfaces a backend death to the client (Close/error) and the path is fully
  reconnectable — as designed for the mobile reconnecting-WS client.

---

## Findings filed to PROGRESS (NOT fixed in this slice — chaos must not touch service code)

1. **Gateway does not reconnect to redis after a redis restart** (case 3) — protected routes 500
   indefinitely until gateway restart; `/healthz` doesn't reflect it. *High.* Fix: reconnecting redis
   client + redis-aware readiness probe.
2. **No read fallback when the replica is down** (case 2) — all replica-served reads 500 on a single
   replica loss though the primary is healthy. *Medium.* Fix: primary-retry on replica failure and/or
   ≥2 replicas behind a read LB.
