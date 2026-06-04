# Performance Baseline (Phase 0.5 · B1)

> **Purpose:** capture v1 performance numbers **before** the v2 migration so every
> later phase can be gated on "p99 must stay within +20% of baseline." These are
> relative-comparison numbers, not production SLAs.

## What this measures

Six k6 scripts in `scripts/`, one per hot path identified in the audit:

| # | Script | Path | Load | What it stresses |
|---|---|---|---|---|
| 1 | `gps-websocket.js` | `WS /ws/track` | 10→100→500→1000 conns, 1 upd/s | WS fan-in + 1/s server rate-limit drop |
| 2 | `booking-create.js` | `POST /booking/requests` | 50 RPS · 2 min | write path + outbox |
| 3 | `list-conversations.js` | `GET /chat/conversations?role=customer` | 20 RPS · 1 min | **N+1 enrichment** (100 convos) |
| 4 | `available-guards.js` | `GET /booking/available-guards` | 30 RPS · 1 min | **5-JOIN Haversine** (200 guards/50km) |
| 5 | `payment-create.js` | `POST /booking/payments` | 20 RPS · 1 min | DB write contention (cost_summary coupling) |
| 6 | `auth-login.js` | `POST /auth/login/mobile` | 10 RPS · 1 min | **Argon2 verify** (CPU-bound sizing) |

All scripts hit the **nginx gateway** and share `scripts/_common.js` (login + auth headers).

## Environment (fill in when you run)

- Target: ☐ local Docker Compose (`docker-compose.yml`, single Postgres, no replica) ☐ staging
- Host specs: _CPU / RAM_
- Date captured: _YYYY-MM-DD_
- k6 version: _`k6 version`_

> **Note:** local Compose has a single Postgres with no read replica and no pgbouncer,
> so numbers are **optimistic vs production**. That is fine — v2 is measured on the
> same rig, so the *relative* delta is what the gate cares about.

## Prerequisites

1. **k6 installed** — `brew install k6` (macOS) or https://k6.io/docs/get-started/installation/
2. **v1 stack running** — `docker compose up -d` in `guard-dispatch/`, gateway reachable at `BASE_URL`.
3. **Seed data** (see below). Scripts have safe defaults but seeded data is required for #3, #4, #5 to produce meaningful numbers.

### Seeding (§Seeding)

**`scripts/seed.sql` does all of this in one idempotent, re-runnable pass** (validated
against the real Postgres parser). It creates exactly what the scripts need:

| Seeded | For | Detail |
|---|---|---|
| 1 customer (`0820000001`) + 1 guard (`0810000001`) | all scripts (login) | password `Password123!` (real Argon2id hash inlined) |
| 100 conversations on the customer (+ participants + a message each) | #3 list-conversations | exercises the N+1 enrichment |
| 200 approved, **online** guards w/ GPS within ~25 km of 13.7563,100.5018 | #4 available-guards | `auth.users` + `guard_profiles` + `tracking.guard_locations` |
| 100 customer-owned `request_id` (the conversation-backing requests) | #5 payment-create | reused as the payable pool |

Run it:

```bash
docker compose exec -T postgres-db \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < seed.sql
```

Then capture the request IDs for `payment-create.js`:

```bash
export REQUEST_IDS=$(docker compose exec -T postgres-db \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
  "SELECT id FROM booking.guard_requests WHERE description='k6-seed'" | paste -sd, -)
```

> ⚠️ Seed data only — never run `seed.sql` against a real/production database.

## Running

```bash
cd v1-audit/perf-baseline/scripts
export BASE_URL=http://localhost:8080 WS_URL=ws://localhost:8080
export TEST_PHONE=0820000001 TEST_PASSWORD='Password123!'
export GUARD_PHONE=0810000001 GUARD_PASSWORD='Password123!'

# 1) GPS WS — run once per concurrency level, record each row
for n in 10 100 500 1000; do k6 run -e STAGE_VUS=$n gps-websocket.js | tee gps_$n.txt; done

# 2–6) HTTP paths
k6 run booking-create.js
k6 run -e ROLE=customer list-conversations.js
k6 run available-guards.js
k6 run payment-create.js          # REQUEST_IDS exported from the seed step above
k6 run auth-login.js
```

Read p50/p95/p99 from k6's `http_req_duration` summary (and `gps_ack_latency_ms`
for #1). Transcribe into `results.md`.

## Output

Fill `results.md`. Those numbers become the regression gate referenced by every
phase exit criterion in `06-migration-plan.md`.
