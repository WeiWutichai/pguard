# Load + chaos — k6 + docker failure injection (Round 3-B)

Ceiling-finding load tests + failure-injection chaos for the pguard v2 stack. Builds on the
captured perf **baseline** (`v1-audit/perf-baseline/`) — those scripts stay as the regression
reference; this dir adds **breaking-point** ramps, a concurrent **mixed workload**, and a **chaos**
suite. Results: [`RESULTS.md`](RESULTS.md) (ceilings/bottlenecks) · [`CHAOS.md`](CHAOS.md) (resilience).

> ⚠️ **Local prod stack ONLY — never staging/production.** These are *breaking-point* + *failure-
> injection* tests. `run-ceiling.sh` reaches services by Docker DNS on the `pguard-prod` network
> (no host-port path, no staging target); `run-chaos.sh` stops/starts your local containers. There
> is deliberately no staging switch.

## Layout

| File | What |
|---|---|
| `ceiling-http.js` | one HTTP endpoint at a fixed arrival rate; `ENDPOINT=login\|discovery\|booking`, `TARGET=gateway\|direct` |
| `ceiling-ws.js` | N concurrent `/ws/track` GPS connections |
| `mixed-workload.js` | realistic concurrent busy hour (GPS + discovery + booking + chat + login) |
| `run-ceiling.sh` | ramp harness — prints one `CEILING_RESULT`/`CEILING_WS`/`MIXED` line per step, stops at the knee |
| `chaos/run-chaos.sh` | 5 failure-injection cases; prints `CHAOS_RESULT` lines; trap restores containers |
| `chaos/ws-observer.js` | WS lifecycle probe for the mid-stream-kill case |

The scripts **reuse the baseline `_common.js`** (login + base URLs) via a relative import — k6 runs
with the repo root mounted so `../../v1-audit/perf-baseline/scripts/_common.js` resolves. Nothing is
copied.

## Prerequisites

The local prod stack up, migrated, and seeded (the perf-baseline reproduce, verbatim):

```bash
# build + clean boot + migrate + seed — see v1-audit/perf-baseline/README.md §Reproduce
docker compose -f infra/docker/docker-compose.prod.yml up -d \
  postgres postgres-replica pgbouncer nats redis \
  identity profile booking payment rating chat presence api-gateway
tooling/scripts/migrate.sh
docker compose -f infra/docker/docker-compose.prod.yml exec -T postgres \
  psql -U pguard -d pguard < v1-audit/perf-baseline/scripts/seed-v2.sql
```

Seeded logins (`Password123!`): customer `0820000001`, guard `0810000001`, admin `0800000001`.

## Run — ceilings

```bash
tests/load/run-ceiling.sh all        # edge ladders (login/discovery/booking) + WS + mixed
tests/load/run-ceiling.sh direct     # rate-limit-bypassed BACKEND ladders (true Argon2/DB ceiling)
tests/load/run-ceiling.sh ws         # just the GPS-WS ladder
tests/load/run-ceiling.sh mixed      # just the busy-hour mix
# knobs: STEP_DUR=20s KNEE_MS=2000 ERR_KNEE=2.0 MIX_DUR=60s MIX_SCALE=1
```

The **edge** ladders knee at the gateway per-IP rate limit (auth ~10/s, api ~50/s) — that's the first
ceiling for single-source traffic, by design. The **direct** ladders find the real backend ceiling
(login cliffs ~30/s on Argon2 CPU; discovery ~100–200/s; booking ~1000/s). Full analysis + the
busy-hour contention numbers are in `RESULTS.md`.

## Run — chaos

```bash
tests/load/chaos/run-chaos.sh all    # all 5 cases (NATS / replica / redis / booking / WS-backend)
tests/load/chaos/run-chaos.sh 1      # just case 1 (NATS outage → outbox drain)
```

Each case stops a container (`docker stop -t 0`), probes, restarts it, and waits healthy; a trap
restarts anything still down on exit. Two real findings surfaced (gateway↔redis no-reconnect; no
read-replica fallback) — see `CHAOS.md` + PROGRESS.md. **A redis case (3) leaves the gateway's redis
connection wedged — restart `api-gateway` before relying on protected routes again** (that IS the
finding).
