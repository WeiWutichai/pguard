# Performance Baseline — Results

> Status: ⏳ **template — numbers not yet captured.** Run the scripts in `README.md`
> against v1, then fill the tables. Until filled, the "must not regress" gate is
> undefined and downstream phases cannot be gated.
>
> Environment: _fill_ · Date: _fill_ · k6: _fill_ · Target: ☐ local Compose ☐ staging
>
> ⚠️ **C5.3 re-run NOT executed here — Docker daemon unavailable.** The pgbouncer +
> read-replica wiring is in `infra/docker/docker-compose.prod.yml` (validated via
> `docker compose config`). The exact re-run + gate procedure is documented in the
> **C5.3 read-replica re-run** section at the bottom; run it on a real Docker host.

## HTTP paths

| Test | RPS | p50 (ms) | p95 (ms) | p99 (ms) | Error rate | Notes |
|---|---|---|---|---|---|---|
| booking-create (`POST /booking/requests`) | 50 | | | | | |
| list-conversations (`GET /chat/conversations`) | 20 | | | | | N+1, 100 convos |
| available-guards (`GET /booking/available-guards`) | 30 | | | | | 5-JOIN Haversine, 200 guards |
| payment-create (`POST /booking/payments`) | 20 | | | | | DB write contention |
| auth-login (`POST /auth/login/mobile`) | 10 | | | | | Argon2 CPU-bound |

## GPS WebSocket (`WS /ws/track`)

| Concurrent conns | Upd sent/s | Accepted/s | Dropped (rate-limit)/s | Conn failures | ack p50 (ms) | ack p95 (ms) | ack p99 (ms) |
|---|---|---|---|---|---|---|---|
| 10 | | | | | | | |
| 100 | | | | | | | |
| 500 | | | | | | | |
| 1000 | | | | | | | |

> Drop column should track the server-side 1-update/sec/connection limit
> (`tracking/src/handlers.rs`). Run a STRESS pass with `-e RATE_HZ=2` to confirm
> ~50% are dropped at 2/sec.

## Regression gate (derived)

Once filled, each phase exit criterion adds: **"p99 within +20% of baseline."**

| Path | Baseline p99 (ms) | +20% gate (ms) |
|---|---|---|
| booking-create | | |
| list-conversations | | |
| available-guards | | |
| payment-create | | |
| auth-login | | |

## Observations (fill after run)

- Slowest path: _e.g. available-guards p99 = … confirms Haversine 5-JOIN is the bottleneck_
- N+1 confirmed?: _list-conversations p99 vs convo count_
- Argon2 cost: _auth-login p99 → sets min CPU per identity-service replica_
- WS ceiling: _conn count where failures > 2% or ack p99 spikes_

## C5.3 read-replica re-run (gate)

> Re-run after the pgbouncer + read-replica wiring (C5.3). **Could not run here — Docker
> daemon unavailable.** Run on a real Docker host. Gate: **list/report/discovery p99 within
> +20% of the v1 baseline** (ideally *better* — those reads now hit the replica, and writes
> stop competing with them on the primary). booking-create / payment-create / auth-login are
> write/CPU paths and should be flat (pgbouncer adds a negligible hop).

```bash
# 1) Capture the v1 baseline first (if not already filled above): bring up v1 + seed, then
#    run the k6 scripts in README.md against it and fill the tables.
# 2) Bring up v2 prod with pgbouncer + the streaming replica:
cd infra/docker
export POSTGRES_PASSWORD=… REPLICATION_PASSWORD=… JWT_SECRET=… SERVICE_JWT_SECRET=… \
       CORS_ALLOWED_ORIGINS=… MINIO_ROOT_USER=… MINIO_ROOT_PASSWORD=… GRAFANA_ADMIN_PASSWORD=… \
       MEDIASOUP_ANNOUNCED_IP=… INET_SMS_USERNAME=… INET_SMS_PASSWORD=… INET_SMS_SENDER=…
docker compose -f docker-compose.prod.yml up -d            # primary + pgbouncer + postgres-replica + services
# confirm the replica is streaming:
docker exec pguard-prod-postgres        psql -U pguard -c "SELECT client_addr, state FROM pg_stat_replication;"
docker exec pguard-prod-postgres-replica psql -U pguard -c "SELECT pg_is_in_recovery();"  # → t
# 3) Re-run the read-heavy k6 scripts (the ones the replica serves) through the gateway and
#    compare p99 to the v1 baseline:
k6 run -e TARGET=http://localhost:3000 scripts/available-guards.js   # GET /v1/available-guards (discovery)
k6 run -e TARGET=http://localhost:3000 scripts/list-conversations.js # representative list read
# 4) Fill the table below; PASS if each is ≤ baseline p99 × 1.20.
```

| Read path (replica-served) | v1 baseline p99 (ms) | v2 (replica) p99 (ms) | +20% gate (ms) | PASS? |
|---|---|---|---|---|
| available-guards (discovery) | _fill_ | _fill_ | _baseline×1.2_ | ☐ |
| admin reviews / payments list | _fill_ | _fill_ | _baseline×1.2_ | ☐ |
| ratings summary | _fill_ | _fill_ | _baseline×1.2_ | ☐ |

> Routing reminder (what should land on the replica vs primary): list/report/discovery +
> data-export reads → `db_read` (replica); every write, single-resource read-after-write
> (get_booking/get_payment), and the money path stay on `db` (primary via pgbouncer).
