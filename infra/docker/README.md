<!-- pguard v2 — infra/docker README (SCAFFOLD STUB) -->

# infra/docker

Dev infrastructure compose + the generic Rust dev image for pguard v2.

## What's here

| File | Purpose |
|---|---|
| `docker-compose.yml` | **Dev infra only** — postgres · nats (JetStream) · redis · minio · otel-collector · tempo · loki · prometheus · grafana. |
| `docker-compose.prod.yml` | **Production stack** — builds the per-service prod images + all backing services with strict network isolation. |
| `Dockerfile.dev` | **Generic, reusable** Rust service dev image (`rust:1-slim`, `ARG SERVICE_NAME`). |
| `rust-service.Dockerfile` | **Production** Rust image — shared multi-stage build (cargo-chef → strip → slim non-root runtime), parameterized per binary. |
| `web-admin.Dockerfile` | **Production** Next.js 16 image (standalone output → slim non-root runtime). |
| `../../services/mediasoup/Dockerfile` | **Production** Node SFU image (multi-stage, non-root, UDP-media-only). |

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

## Production images & compose (Phase 5)

### Convention (one shared Dockerfile, parameterized per binary)

The repo is a single cargo workspace, so all **11 Rust services** build from **one**
shared Dockerfile — `rust-service.Dockerfile` — selecting the binary via
`--build-arg BIN=pguard-<svc>` and the healthcheck/EXPOSE port via
`--build-arg APP_PORT=<port>`. This is the spec's "one shared build pattern,
parameterized per binary": there is no per-service Dockerfile to drift, and because
cargo-chef's dependency `recipe.json` is computed from the whole workspace, the
expensive **dep-compile (`cook`) layer is byte-identical across every service**. When
images are built on one host with the layer cache intact — e.g.
`docker compose -f docker-compose.prod.yml build`, or `docker build` with a shared
BuildKit/registry cache — that layer is compiled **once** and reused for all 11 images.
(Cold, cache-less sequential `docker build` calls each re-cook; add `--cache-from` or
build via compose to get the cross-service reuse.)

Each service still gets its own **image** (`pguard/<svc>:<tag>`), wired in
`docker-compose.prod.yml`.

### Hardening (CLAUDE.md Docker rules — all enforced)

- **Multi-stage** — build toolchain + source stay in the builder; the runtime image
  carries only the one stripped binary (+ ca-certificates + curl for the healthcheck).
- **`strip`ped** binary in the build stage.
- **Non-root** — runtime runs as `appuser` (uid 10001); web-admin/mediasoup run as the
  built-in `node` user.
- **Pinned** bases — `rust:1.83-slim-bookworm`, `debian:bookworm-slim`,
  `node:20-bookworm-slim`, and pinned tags for every infra image (no `:latest`).
- **`/healthz` HEALTHCHECK** on every Rust + web image (mediasoup hits its `/health`).
- **Network isolation** — in `docker-compose.prod.yml` **only the api-gateway publishes
  a host TCP port** (3000). Every other service/DB/Redis/MinIO/observability backend
  uses `expose` (cluster-internal). The mediasoup **UDP media range** (40000-49999) is
  the one documented exception — WebRTC requires a 1:1 host:container UDP mapping; its
  control plane stays internal.
- **Secrets via `${VAR:?}`** — no credential defaults, no `minioadmin`. Compose fails
  fast if a required secret is unset.

### Port map (container-internal)

| Service | Port | Service | Port |
|---|---|---|---|
| api-gateway | 3000 (edge), 9100 (metrics) | payment | 3006 |
| identity | 3001 | rating | 3007 |
| profile | 3002 | calling | 3008 |
| otp | 3003 | presence | 3009 |
| notification | 3004 | chat | 3010 |
| booking | 3005 | mediasoup | 3011 (ctrl) + 40000-49999/udp |

### Required secrets (no defaults)

`POSTGRES_PASSWORD` · `JWT_SECRET` · `SERVICE_JWT_SECRET` · `MINIO_ROOT_USER` ·
`MINIO_ROOT_PASSWORD` · `GRAFANA_ADMIN_PASSWORD` · `CORS_ALLOWED_ORIGINS` ·
`MEDIASOUP_ANNOUNCED_IP` · `INET_SMS_USERNAME`/`INET_SMS_PASSWORD`/`INET_SMS_SENDER`
(set `SMS_DISABLED=true` to skip the SMS gateway).

### Build & run

```bash
# from repo root — provide secrets first (e.g. an untracked infra/.env.prod)
set -a; source infra/.env.prod; set +a

# validate the compose (no daemon needed; fails fast on a missing secret)
docker compose -f infra/docker/docker-compose.prod.yml config -q

# build everything (or `build api-gateway` for one)
docker compose -f infra/docker/docker-compose.prod.yml build
docker compose -f infra/docker/docker-compose.prod.yml up -d

# build a single Rust service directly
docker build -f infra/docker/rust-service.Dockerfile \
  --build-arg BIN=pguard-api-gateway --build-arg APP_PORT=3000 \
  -t pguard/api-gateway:0.1.0 .
```

### Smoke & image-hygiene checks

```bash
# gateway healthz (publishes host 3000)
docker run -d --name gw -p 3000:3000 \
  -e JWT_SECRET=… -e SERVICE_JWT_SECRET=… -e CORS_ALLOWED_ORIGINS=https://admin.example \
  pguard/api-gateway:0.1.0
curl -fsS http://localhost:3000/healthz        # → 200

# non-root check (must print appuser / uid=10001)
docker run --rm pguard/api-gateway:0.1.0 id

# confirm no source/toolchain in the runtime image
docker run --rm pguard/api-gateway:0.1.0 sh -c 'ls /usr/local/cargo 2>/dev/null; which cargo gcc rustc 2>/dev/null; echo none'
```

## Still TODO

- **pgbouncer cutover (C5.3)** — the pooler is defined in `docker-compose.prod.yml`
  but app `DATABASE_URL`s still point at `postgres` directly. Flip host→`pgbouncer`,
  port→`6432` and verify the image pin when C5.3 lands.
- **Read replica** for report/list paths (`CLAUDE.md` → DB scaling).
- **ingress/nginx + TLS** in front of the gateway and web-admin (web-admin is
  internal-only in this compose; the gateway is the single host-published ingress).
- **FCM service-account secret** — mount `FCM_SERVICE_ACCOUNT_PATH` via a Docker/K8s
  secret (not baked into the image).
