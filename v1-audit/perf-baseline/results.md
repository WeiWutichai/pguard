# Performance Baseline — Results

> Status: ⏳ **template — numbers not yet captured.** Run the scripts in `README.md`
> against v1, then fill the tables. Until filled, the "must not regress" gate is
> undefined and downstream phases cannot be gated.
>
> Environment: _fill_ · Date: _fill_ · k6: _fill_ · Target: ☐ local Compose ☐ staging

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
