# Cost Baseline (Phase 0.5 · B3)

> **Purpose:** record v1's infrastructure footprint so the v2 architecture's added
> cost (NATS, OpenTelemetry stack, pgbouncer, read replica, more services) can be
> estimated and justified before building. No production cloud deployment exists,
> so this documents the **resource footprint for planning**, not a billed cost.

## v1 container inventory (`docker-compose.yml`)

12 containers, no `mem_limit`/`cpus`/`deploy.resources` set — each runs best-effort
(a real finding: **no resource limits → noisy-neighbour + unbounded memory risk**).

| Container | Image | Role | Typical RAM¹ | CPU profile |
|---|---|---|---|---|
| web-admin | Next.js (built) | admin UI SSR | 150–300 MB | bursty (SSR) |
| nginx-gateway | nginx:1.27-alpine | edge proxy / TLS | 10–30 MB | low |
| rust-auth | (built) | auth, Argon2 | 30–80 MB | **CPU-bound on login** (Argon2) |
| rust-booking | (built) | booking/payment/rating/calling | 40–120 MB | DB-bound (Haversine, joins) |
| rust-tracking | (built) | GPS WS + history | 40–150 MB | conn-bound (WS fan-in) |
| rust-notification | (built) | push fan-out | 20–60 MB | low/bursty |
| rust-chat | (built) | chat WS + REST | 30–100 MB | DB-bound (N+1) |
| mediasoup-server | Node | WebRTC SFU | 80–250 MB | **CPU/bandwidth on calls** |
| postgres-db | postgres:16-alpine | single DB (all schemas) | 200–600 MB² | **SPOF**, I/O-bound |
| redis-cache | redis:7-alpine | cache | 20–80 MB | low |
| redis-pubsub | redis:7-alpine | pub/sub | 20–60 MB | low |
| minio | minio/minio:latest | S3 (images/docs/video) | 100–300 MB | I/O-bound |

¹ Estimates for a single-node dev/staging Compose under light load. **Capture real
numbers** with the command below and replace this column.
² Postgres RAM scales with `shared_buffers` + connections (v1 uses 6×20 = 120 max
conns across services → meaningful per-conn overhead; see audit C-pool finding).

### Capture real footprint (run on the host with the stack up)

```bash
docker stats --no-stream --format \
  'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}' > v1-footprint.txt
```

Idle baseline ≈ sum of the RAM column above ≈ **~0.8–2.3 GB RAM** for the whole
v1 stack on one node; comfortably fits a single 4 GB / 2 vCPU VM at dev/staging scale.

## v2 added infrastructure (from `CLAUDE.md` architecture)

v2 introduces cross-cutting infra that v1 doesn't have:

| New component | Why (CLAUDE.md decision) | Added RAM (rough) |
|---|---|---|
| NATS JetStream | inter-service events (replaces cross-schema writes) | 50–150 MB |
| OTel Collector | trace/metric pipeline | 50–120 MB |
| Tempo | distributed traces store | 100–300 MB |
| Loki | log aggregation | 100–300 MB |
| Prometheus | metrics | 150–400 MB |
| Grafana | dashboards | 80–200 MB |
| pgbouncer | connection pooling (fixes 6×20 SPOF) | 10–30 MB |
| Postgres read replica | report/list offload | +200–600 MB (≈ another primary) |

**Observability + messaging + DB scaling adds ≈ +0.7–2.4 GB RAM** on top of v1 —
i.e. roughly **+30–50% infra footprint** (more if traces/logs retention is generous),
matching the audit's estimate. The observability stack (Tempo/Loki/Prometheus/Grafana)
is the single biggest contributor and can run on a **separate node / be sampled** to
contain cost.

Service splits (auth→identity/profile/otp; booking→booking/payment/rating/calling;
+api-gateway) add process count but each replica is small (Rust, 30–120 MB); the
dominant new cost is the **observability + replica**, not the extra Rust binaries.

## Cost delta per phase (planning)

| Phase | Infra change | Est. footprint delta |
|---|---|---|
| 0.5 Baseline | none (read-only audit) | 0% |
| 0 Stabilize | none (tests/cleanup) | 0% |
| 1 Decouple notifications | **+NATS** + service-auth | +5–10% |
| 2 Push-based mobile | WS replaces polling (tracking already exists) | ~0% (load shifts, not adds) |
| 3 Split booking | +payment/rating/calling services | +5–10% (small Rust procs) |
| 4 Split auth + Riverpod | +identity/profile/otp services | +5–10% |
| 5 Scale & harden | **+OTel/Tempo/Loki/Prometheus/Grafana, +pgbouncer, +read replica** | +20–35% (the big one) |

**Recommendation:** the observability + replica cost lands almost entirely in Phase 5.
Earlier phases are cheap. Defer Tempo/Loki retention tuning and the replica until
Phase 5, and run the observability stack on a separate node so it doesn't compete
with request-serving containers.

## Status

⏳ Estimates only — replace the RAM columns with real `docker stats` output once the
stack is run. Exact monthly $ requires a target (cloud + instance type); document
that when a deployment target is chosen.
