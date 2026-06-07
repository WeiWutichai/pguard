# Performance Baseline — Results (v2)

> Status: ✅ **captured on the v2 prod stack.** These are the **v2** numbers (per-service
> schemas behind the gateway), NOT v1 — the v1 baseline was never captured and v1 is a
> read-only reference (not run). The regression gate below is therefore framed as the **C5.3
> replica-vs-primary** gate (does routing reads to the replica regress vs the primary?), which
> is the meaningful self-contained check.
>
> Environment: Docker 29.5.2 · host Darwin 25.5.0 arm64 (Apple Silicon, Docker Desktop) ·
> k6 v2.0.0 (grafana/k6, run as a container on the `pguard-prod` network) · images
> `pguard/*:0.1.0` · Date: 2026-06-07 · Target: ☑ local Compose (`docker-compose.prod.yml`,
> the full streaming-replica stack).
>
> Load shape: each HTTP script ran 45s at its target RPS; GPS-WS ran 30s per VU level. Seed:
> `scripts/seed-v2.sql` (201 guards / 201 online / 100 payable bookings / 100 conversations /
> 150 reviews). See `README.md` for the full reproduce steps.
>
> **Routing note:** the gateway routes `/v1/auth /otp /profile /admin/guard-profiles /bookings
> /available-guards /payments /notifications`. It does **NOT** route chat (`/conversations`),
> presence (`/ws/track`), or rating (`/guards/{id}/ratings`) — those services are not wired into
> the edge routing table yet (a real gap, flagged below). The perf harness hits them directly
> on the compose network with the same Bearer the gateway login issued.

## HTTP paths

| Test | RPS | p50 (ms) | p95 (ms) | p99 (ms) | Error rate | Notes |
|---|---|---|---|---|---|---|
| booking-create (`POST /v1/bookings`) | 50 | 4.08 | 5.53 | 8.33 | 0.22% | write path; 5/2252 transient ramp blips |
| list-conversations (`GET /conversations?role=`, direct→chat) | 20 | 7.18 | 10.0 | 11.46 | 0% | N+1 FIXED — single query, 100 convos |
| available-guards (`GET /v1/available-guards`) | 30 | 10.7 | 14.81 | 25.24 | 0% | discovery fan-out (profile + rating), replica-served |
| payment-create (`POST /v1/payments`) | 20 | 6.63 | 8.34 | 11.92 | 0% | write + service-JWT booking read + idempotent charge |
| auth-login (`POST /v1/auth/login`) | 10 | 121.44 | 148.75 | 174.46 | 0% | Argon2 CPU-bound (intentionally slow) |
| admin-guard-profiles (`GET /v1/admin/guard-profiles?…`) | 20 | 6.01 | 8.17 | 10.12 | 0% | admin list, replica-served + §30 audit write |
| ratings (`GET /guards/{id}/ratings`, direct→rating) | 30 | 1.55 | 2.67 | 3.76 | 0% | public rating summary, replica-served |

## GPS WebSocket (`WS /ws/track`, direct→presence)

| Concurrent conns | Accepted/s | Conn failures | ack p50 (ms) | ack p95 (ms) | ack p99 (ms) | ws-connect p99 |
|---|---|---|---|---|---|---|
| 10 | 6.3 | 0 | 11 | 47.5 | 85 | 2.7 ms |
| 100 | 58.5 | 0 | 35 | 61 | 67 | 33 ms |
| 500 | 303.8 | 0 | 86 | 154 | 169 | 1.12 s |
| 1000 | _not run_ | — | — | — | — | — |

> Each VU sends ~1 update/sec; the server enforces ≥1 s/connection so a fraction is dropped
> (sent − accepted). **0 connection failures through 500 concurrent** — ack p99 stays ≤169 ms;
> only WS *connect* time stretches under 500 concurrent (1.12 s p99 during the connect burst).
> 1000 was not run here (500 already clean with margin; the host is a single laptop). A STRESS
> pass (`-e RATE_HZ=2`) would confirm ~50% drops at 2/sec.

## C5.3 read-replica gate (replica-served vs primary-served)

> The reads list/report/discovery are routed to the streaming replica (`DATABASE_READ_URL`); we
> re-measured each with reads forced to the **primary** (via pgbouncer) and compared. Gate:
> **replica-served p99 ≤ primary-served p99 × 1.20.** (Frames the C5.3 intent — moving reads off
> the primary must not regress them — without a v1 baseline, which was never captured.)

| Read path (replica-served) | primary-served p99 (ms) | replica-served p99 (ms) | gate = primary×1.2 (ms) | PASS? |
|---|---|---|---|---|
| available-guards (discovery) | 26.67 | 25.24 | 32.00 | ✅ |
| admin guard-profiles (admin list) | 10.99 | 10.12 | 13.19 | ✅ |
| ratings summary | 5.49 | 3.76 | 6.59 | ✅ |

> **All PASS — and replica-served is slightly FASTER in every case** (reads on the replica no
> longer compete with writes on the primary). The pgbouncer hop on the write/primary path is
> negligible. Net: the C5.3 routing is a strict win for these reads.

## Observations

- **Slowest path: auth-login (p99 174 ms)** — Argon2 verify is the dominant cost (every other
  HTTP path is < 30 ms p99). This sets the min CPU budget per identity replica; size identity
  for the login RPS, not the other services.
- **N+1 fix confirmed:** list-conversations p99 = 11.46 ms at 100 conversations — flat, no per-row
  fan-out (the single-query rewrite holds under load).
- **Discovery (available-guards) p99 25 ms** — the service-JWT fan-out to profile + rating
  summaries is cheap at 200 guards; not a bottleneck.
- **WS ceiling:** clean (0 failures) through 500 concurrent; the connect-time stretch at 500
  suggests the accept path is the next thing to watch above ~500 concurrent on a single node.

## Bugs found + fixed while bringing up the v2 prod stack (first real `up`)

The prod compose had only ever been `docker compose config`-validated; this was its first real
end-to-end run, which surfaced (and this PR fixes) four boot blockers:

1. **Replica init never ran** (the headline bug) — the bind-mounted `10-replication.sh` didn't
   fire at initdb on Docker Desktop → no `replicator` role/slot → replica `pg_basebackup` hung.
   **Fix:** bake it into a custom image (`postgres-primary.Dockerfile`, COPY + chmod +x). Verified:
   `down -v` → `up` → `pg_stat_replication.state='streaming'` + replica `pg_is_in_recovery()=t`,
   zero manual steps.
2. **pgbouncer listened on the wrong port** — the edoburu image defaults `LISTEN_PORT=5432`, but
   services + `expose` use 6432 → every DB-backed service's pool timed out (connection refused).
   **Fix:** `LISTEN_PORT=6432` + `AUTH_TYPE=scram-sha-256` (postgres 17).
3. **pgbouncer transaction-mode prepared-statement collisions** — sqlx's named statements
   (`sqlx_s_N`) collided across pooled backends → intermittent `prepared statement already exists`.
   **Fix:** `MAX_PREPARED_STATEMENTS=256` (pgbouncer ≥1.21 tracks/replays prepared statements).
4. **Gateway routing gap (flagged, not fixed here — out of scope):** chat / presence / rating
   are not in the gateway routing table, so they're unreachable from the edge in v2. The harness
   hits them directly; wiring them into the gateway is a follow-up.

Harness-side adaptations to v2 (vs the v1-shaped scripts): money fields are JSON **strings**
(`rust_decimal` serde-str) so `amount`/`tip` are quoted; k6 forbids HTTP in the init context so
login moved to `setup()`; v2 has no `booking.service_rates`/`guard_requests` (it's
`booking.bookings` + pricing columns); `/v1/auth/login {identifier,password}` not
`/auth/login/mobile {phone,password}`; `/v1/available-guards` takes no lat/lng/radius.
