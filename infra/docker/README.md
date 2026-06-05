<!-- pguard v2 — infra/docker README (SCAFFOLD STUB) -->

# infra/docker

Dev infrastructure compose + the generic Rust dev image for pguard v2.

## What's here

| File | Purpose |
|---|---|
| `docker-compose.yml` | **Infra only** — postgres · nats (JetStream) · redis · minio · otel-collector · tempo · loki · prometheus · grafana. |
| `Dockerfile.dev` | **Generic, reusable** Rust service dev image (`rust:1-slim`, `ARG SERVICE_NAME`). |

## Why the compose is infra-only

Per `CLAUDE.md` → Quickstart, application **Rust services run on the host via
`cargo run`** in dev — fast incremental rebuilds, `cargo-watch`, and direct
debugger attach. The compose file is just the stateful + observability backbone
those services connect to. A separate prod / integration compose can add the
services later.

## Usage

```bash
# from repo root
cp infra/.env.example infra/.env          # optional; defaults work out of the box
docker compose -f infra/docker/docker-compose.yml up -d

# then run a service on the host
cd services/notification && cargo run
```

### Ports (host)

| Service | Host port | Notes |
|---|---|---|
| postgres | 5432 | db `pguard` |
| nats | 4222 / 8222 | client / monitoring (`-js` JetStream) |
| redis | 6379 | |
| minio | 9000 / 9001 | S3 API / console |
| otel-collector | 4317 / 4318 | OTLP gRPC / HTTP |
| prometheus | 9090 | |
| grafana | **3001** | container 3000 remapped — host 3000 belongs to api-gateway |

## The generic dev image

`Dockerfile.dev` is shared by all services. Each service later gets a **thin
wrapper** that only sets `SERVICE_NAME`:

```dockerfile
# services/notification/Dockerfile.dev
FROM pguard/rust-dev
ARG SERVICE_NAME=notification
```

Build directly:

```bash
docker build -f infra/docker/Dockerfile.dev \
  --build-arg SERVICE_NAME=notification -t pguard/notification:dev .
```

## TODO

- **`Dockerfile.prod`** — multi-stage `cargo build --release` builder → **distroless**
  (`gcr.io/distroless/cc`) static runtime image. Phase 5 (Scale & harden).
- **pgbouncer + read replica** in the prod/integration compose
  (`CLAUDE.md` → Architecture decisions: DB scaling).
