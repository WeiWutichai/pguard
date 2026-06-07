# Performance Baseline (Phase 0.5 · B1) — v2 harness

> **Purpose:** capture **v2** performance numbers on the prod stack (per-service schemas behind
> the gateway, pgbouncer + streaming read replica) and evaluate the **C5.3 replica gate**. These
> are relative-comparison numbers, not production SLAs. The v1 baseline was never captured and v1
> is a read-only reference (not run), so the gate is framed as replica-served vs primary-served.
>
> Captured numbers live in `results.md`.

## What this measures

k6 scripts in `scripts/` (one per hot path), all v2:

| Script | Path (v2) | Load | Stresses |
|---|---|---|---|
| `auth-login.js` | `POST /v1/auth/login` (gateway) | 10 RPS | Argon2 verify (CPU) |
| `available-guards.js` | `GET /v1/available-guards` (gateway) | 30 RPS | discovery fan-out (profile+rating), replica |
| `booking-create.js` | `POST /v1/bookings` (gateway) | 50 RPS | write path + outbox |
| `payment-create.js` | `POST /v1/payments` (gateway) | 20 RPS | write + service-JWT booking read + idempotent charge |
| `list-conversations.js` | `GET /conversations?role=` (**direct→chat**) | 20 RPS | the N+1-FIXED list (single query) |
| `ratings.js` | `GET /guards/{id}/ratings` (**direct→rating**) | 30 RPS | public rating summary, replica (C5.3 gate) |
| `admin-guard-profiles.js` | `GET /v1/admin/guard-profiles` (gateway) | 20 RPS | admin list, replica + §30 audit (C5.3 gate) |
| `gps-websocket.js` | `WS /ws/track` (**direct→presence**) | 10→100→500 conns | WS fan-in + ≥1 s/conn drop |

`_common.js` logs in via `POST /v1/auth/login {identifier,password}` in `setup()` (k6 forbids HTTP
in the init context) and shares auth headers. **Routing gap:** the gateway does NOT route chat /
presence / rating in v2 — those scripts hit the service directly (the harness runs k6 *on the
compose network*, so `chat:3010` / `presence:3009` / `rating:3007` resolve by DNS).

## Reproduce (full, no manual SQL)

```bash
# 0) secrets (throwaway, local-only)
cp infra/.env.perf.example infra/.env.perf      # already gitignored
set -a; source infra/.env.perf; set +a

# 1) build (custom primary image + the Rust services exercised here)
docker compose -f infra/docker/docker-compose.prod.yml build \
  postgres api-gateway identity profile booking payment rating chat presence

# 2) clean boot — fresh `down -v` proves the replica-init fix (no manual steps)
docker compose -f infra/docker/docker-compose.prod.yml down -v
docker compose -f infra/docker/docker-compose.prod.yml up -d \
  postgres postgres-replica pgbouncer nats redis \
  identity profile booking payment rating chat presence api-gateway

# confirm the replica is streaming (no manual SQL was needed to get here):
docker exec pguard-prod-postgres         psql -U pguard -c "SELECT client_addr,state FROM pg_stat_replication;"   # → streaming
docker exec pguard-prod-postgres-replica psql -U pguard -tAc "SELECT pg_is_in_recovery();"                        # → t

# 3) migrate (idempotent; applies contracts/db/migrations/<svc>/*.sql to the primary → replica via WAL)
tooling/scripts/migrate.sh

# 4) seed the v2 schema
docker compose -f infra/docker/docker-compose.prod.yml exec -T postgres \
  psql -U pguard -d pguard < v1-audit/perf-baseline/scripts/seed-v2.sql

# 5) run k6 AS A CONTAINER ON THE COMPOSE NETWORK (reaches the gateway + the non-routed services)
SC="$PWD/v1-audit/perf-baseline/scripts"
run() { docker run --rm --network pguard-prod -v "$SC:/scripts:ro" \
  -e BASE_URL=http://api-gateway:3000 -e CHAT_URL=http://chat:3010 \
  -e RATING_URL=http://rating:3007 -e PRESENCE_WS=ws://presence:3009 -e DURATION=45s \
  grafana/k6:latest run --no-color --summary-trend-stats="avg,med,p(95),p(99),max,count" "/scripts/$1"; }

run auth-login.js; run available-guards.js; run booking-create.js; run payment-create.js
run list-conversations.js; run ratings.js; run admin-guard-profiles.js
for v in 10 100 500; do
  docker run --rm --network pguard-prod -v "$SC:/scripts:ro" -e PRESENCE_WS=ws://presence:3009 \
    -e BASE_URL=http://api-gateway:3000 -e STAGE_VUS=$v -e HOLD=30s \
    grafana/k6:latest run --no-color --summary-trend-stats="avg,med,p(95),p(99),max" /scripts/gps-websocket.js
done
```

Read `http_req_duration{name:…}` p99 (tag-scoped → excludes the setup login) + `http_req_failed`
and transcribe into `results.md`. For GPS-WS read `gps_ack_latency_ms` + `gps_connection_failures`.

### C5.3 gate (replica-served vs primary-served)

Run the read paths (available-guards / admin-guard-profiles / ratings) once as deployed
(replica-served), then again with reads forced to the primary (an override file pointing each
service's `DATABASE_READ_URL` at `pgbouncer:6432`), and compare p99. PASS if
replica p99 ≤ primary p99 × 1.20. (Procedure + numbers in `results.md`.)

> ⚠️ `seed-v2.sql` is synthetic perf data — never run it against a real database.
> Seeded accounts log in with `Password123!` (customer `0820000001`, guard `0810000001`,
> admin `0800000001`).
