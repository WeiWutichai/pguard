# Load — ceiling & bottleneck results (Round 3-B)

> **What:** ramp each hot path until it breaks (not a baseline re-run) to find the real ceiling +
> the FIRST bottleneck, plus a concurrent busy-hour mix. Builds on the captured baseline
> (`v1-audit/perf-baseline/results.md`).
>
> **Environment:** Docker 29.5.2 · host Darwin arm64 (Apple-silicon laptop, Docker Desktop, single
> node) · k6 (grafana/k6:latest) run as a container ON the `pguard-prod` network · images
> `pguard/*:0.1.0` · full streaming-replica prod stack (`docker-compose.prod.yml`) · seed-v2
> (209 guard profiles · 123 requested / 103 accepted bookings) · Date 2026-06-10.
>
> **Reproduce:** `tests/load/run-ceiling.sh all` (gateway/edge ladders + WS + mixed) and
> `… run-ceiling.sh direct` (rate-limit-bypassed backend ladders). One CEILING_RESULT line per
> step; the ladder stops at the knee. **Single client IP** unless noted.

## Method — two vantage points

The gateway enforces a **per-IP fixed-window rate limit** (the v1 nginx zones, ported to the edge).
From a single client IP that limit is the FIRST thing that "breaks", so two passes are needed:

- **`TARGET=gateway`** (default) — the real client path *through the edge*. Knees at the rate limit.
- **`TARGET=direct`** — k6 hits the owning service on the compose network with the same Bearer,
  bypassing the edge limit (backends re-validate the token), to find the **true backend ceiling**.

## A. Edge ceilings (through the gateway — rate-limit-bound)

| Endpoint | last clean | p99 clean | knee | knee behaviour | binding limit |
|---|---|---|---|---|---|
| `POST /v1/auth/login` | **10 req/s** | 134 ms | 20 req/s | 48.8 % errors | auth tier ≈ **10 req/s/IP** |
| `GET /v1/available-guards` | **30 req/s** | 30 ms | 100 req/s | 47.8 % errors | api tier ≈ **50 req/s/IP** |
| `POST /v1/bookings` | **50 req/s** | 8.6 ms | 100 req/s | 49.2 % errors | api tier ≈ **50 req/s/IP** |

The knee is **429s, not 5xx** — the rate limit shedding excess load by design (brute-force / abuse
protection). p99 of the *served* requests stays flat right up to the limit. So the edge ceiling per
client IP is the rate limit, full stop; real backend capacity is much higher (below).

## B. Backend ceilings (direct to service — rate-limit bypassed)

| Endpoint (direct) | clean | first collapse | collapse signature | true bottleneck |
|---|---|---|---|---|
| `identity /auth/login` | 30 req/s @ p99 178 ms, 0 % | **60 req/s** | p99 **≈ 40 s**, **78 % err**, sustained rate fell to 14.6/s | **Argon2 verify = CPU** — hard cliff ~30–40 login/s on this node |
| `booking /available-guards` | 100 req/s @ p99 317 ms, 0 % | **300 req/s** | p99 ≈ 39 s, 7 % err, rate fell to 61/s | discovery **fan-out** (profile+rating service-JWT) + replica reads; ~100–200/s |
| `booking /bookings` (write) | 100→p99 6 ms · 300→5.3 ms · 600→4.7 ms · **1000→11.7 ms**, all 0 % | not reached ≤1000/s | — | cheap insert + outbox; **≥1000 writes/s**, not a constraint |

**Headline:** the auth path (Argon2, CPU-bound) is the tightest backend — it cliffs near **30 login/s**
on one node. Writes and discovery have far more headroom; booking writes scale to ~1000/s.

## C. GPS WebSocket ceiling (`/ws/track`, direct to presence)

| Concurrent conns | Accepted | Conn failures | ack p95 | ack p99 | ws-connect p99 |
|---|---|---|---|---|---|
| 100 | 1 489 | **0** | 53 ms | 58 ms | 15 ms |
| 300 | 4 607 | **0** | 118 ms | 134 ms | 71 ms |
| 500 | 7 682 | **0** | 133 ms | 162 ms | 90 ms |
| 800 | 12 396 | **0** | 197 ms | 304 ms | **1.10 s** |

**Zero connection failures through 800 concurrent** (baseline only went to 500). Ack latency stays
healthy; only the WS *connect/accept burst* stretches (1.1 s p99 at 800) — the accept path is the
thing to watch above ~800 on a single node, not the steady fan-in.

## D. Mixed workload — a realistic busy hour (concurrent, through the gateway)

`mixed-workload.js`: 120 GPS guards streaming + 20 discovery + 6 booking + 12 chat + 3 login req/s,
all at once for 60 s. Offered HTTP rate (~41/s) stays under the api/auth limits, so **0 errors** —
but the tail latency tells the contention story:

| Path | isolated p99 | **busy-hour p99** | inflation |
|---|---|---|---|
| login | 134 ms | **644 ms** | ~5× |
| discovery | 30 ms | **783 ms** | ~26× |
| booking | 9 ms | **253 ms** | ~28× |
| chat | 11 ms | **185 ms** | ~17× |
| GPS | 0 conn failures (4 492 acks) | — | — |

`http_req_failed = 0 %`. Under a concurrent mix on **one node** the system is **contention-bound**
(shared CPU + DB pool), not failing: p99 inflates 5–28× with zero errors. This is the core argument
for running ≥2 replicas of the CPU/fan-out services even at modest aggregate load.

## Bottleneck ranking (first to fall → last)

1. **Edge per-IP rate limit** — auth ~10/s, api ~50/s. First ceiling for single-source traffic (by
   design; distributes across IPs in reality).
2. **Argon2 CPU on `identity`** — true backend cliff ~30–40 login/s. The tightest real bottleneck.
3. **Discovery fan-out + replica reads** — ~100–200/s.
4. **Booking writes (~1000/s) and GPS-WS (≥800 concurrent)** — ample headroom; not the constraint.
5. Single-node **contention** under a concurrent mix — tail latency, not errors → scale horizontally.

## Comparison to baseline (`v1-audit/perf-baseline/results.md`)

Steady single-endpoint p99 matches the baseline within noise (auth ~134 ms vs 174 ms; discovery
~30 ms vs 25 ms; booking ~6–9 ms vs 8 ms; ratings/admin unchanged). The replica gate (C5.3) still
holds. This slice ADDS the breaking points (above) and the busy-hour contention numbers, which the
baseline did not capture.

## Scale recommendations (→ k8s HPA "tune from perf baseline")

| Service | Scale on | minReplicas | Why (measured) |
|---|---|---|---|
| `identity` | **CPU** (Argon2) | **2+** | login cliffs ~30/s/node; size replicas for peak login RPS |
| `booking` (owns discovery) | CPU / RPS | **2+** | discovery fan-out ceilings ~100–200/s; busy-hour p99 inflates ~26× on one node |
| `presence` | connection count (custom metric — see gap) | 2+ | WS ≥800/node clean, but accept burst stretches; spread connections |
| `payment`, `rating`, `profile`, `chat` | CPU / RPS | 2 (HA) | not load-bound here; replicate for availability, not throughput |

> ⚠️ **Never run this against staging/production** — it is a breaking-point test. `run-ceiling.sh`
> targets the local prod stack only (Docker DNS on `pguard-prod`); there is no staging target and
> no host-port path, by design.
