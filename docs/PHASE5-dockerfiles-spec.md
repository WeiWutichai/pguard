# Phase 5 — production Dockerfiles + prod compose (work spec)

> For Claude Code. Today there's only `infra/docker/Dockerfile.dev` (one generic dev image)
> and `services/mediasoup/Dockerfile`. Add **per-service production images** for all 11 Rust
> services + web-admin, following CLAUDE.md Docker rules, plus a prod compose. This is
> **infra-only** (new Dockerfiles + compose) — it does NOT edit service source or shared
> crates, so it's low-conflict with the data-export backend track. Branch off main in its
> own worktree. Don't merge; don't touch `../guard-dispatch/`.

## Scope

### A. Rust services — multi-stage prod Dockerfile (×11)
`api-gateway, identity, profile, otp, notification, booking, payment, rating, calling, presence`
(+ any other Rust member). The repo is one cargo workspace → one shared build pattern,
parameterized per binary.

- **Builder stage:** `rust:1-slim` (pin a version) → build `cargo build --release --bin pguard-<svc>` (use the real bin names from each `Cargo.toml`). Use **cargo-chef** (or a deps-cache layer) so dependency compilation caches across services.
- **Runtime stage:** `debian:bookworm-slim` (or distroless) → copy ONLY the one stripped binary.
  - **`strip` the binary** in the build stage (CLAUDE.md rule).
  - **non-root `appuser`** (`USER appuser`) — never run as root.
  - `EXPOSE` only the service's internal port; `HEALTHCHECK` hitting `/healthz`.
  - no build toolchain, no source in the runtime image.
- Place at `infra/docker/<svc>.Dockerfile` (or `services/<svc>/Dockerfile.prod` — pick one convention, keep it consistent and documented in `infra/docker/README.md`).

### B. web-admin (Next.js 16) Dockerfile
- Multi-stage: `node:-slim` build (`pnpm build`, `output: 'standalone'`) → slim runtime copying `.next/standalone` + static; non-root; `HEALTHCHECK`.

### C. mediasoup
- Verify/align the existing `services/mediasoup/Dockerfile` to the same rules (non-root, pinned base, only the UDP media range exposed — no host TCP port).

### D. Production compose — `infra/docker/docker-compose.prod.yml`
- Pulls/builds the per-service prod images; **only the gateway (and nginx if present) publishes host ports** — every other service/DB/Redis/MinIO uses `expose`, not `ports` (CLAUDE.md network-isolation rule).
- All secrets via `${VAR:?error}` (fail fast on missing) — no defaults, no `minioadmin`.
- Wire the observability stack (otel-collector/tempo/loki/prometheus/grafana) + pgbouncer placeholder for C5.3.

## CLAUDE.md Docker rules (must hold)
- ✅ non-root `appuser` in every runtime stage · ✅ `strip` binaries · ✅ secrets via env `${VAR:?}` · ✅ no MinIO default creds · ✅ only gateway/nginx exposes host ports · ✅ pinned base images (no `:latest`).

## Definition of Done
- Every Rust service + web-admin + mediasoup has a prod Dockerfile that **builds** (`docker build` each, or `docker compose -f infra/docker/docker-compose.prod.yml build`).
- `docker compose -f infra/docker/docker-compose.prod.yml config` validates.
- A short smoke: build the gateway image, run it, `GET /healthz` → 200 (others optional if heavy).
- Image hygiene check: runtime images are non-root (`docker run --rm <img> id` shows appuser) and contain no source/toolchain.
- `infra/docker/README.md` documents the build/run commands + the convention.
- Update `PROGRESS.md` (tick + Completed-log row) · run the review agents (security cares about non-root/secrets) · own PR off main · don't merge.

## Reference (read-only)
- v1 had per-service Dockerfiles — `../guard-dispatch/services/*/Dockerfile*` + `docker-compose*.yml` (port the multi-stage/non-root/strip pattern; adapt to the v2 workspace bin names).
- CLAUDE.md → "Docker Security" Do/Don't + the network-isolation / `expose`-not-`ports` rule + `cost-baseline.md` (the container inventory).
