# syntax=docker/dockerfile:1
# ─────────────────────────────────────────────────────────────────────────────
# pguard v2 — PRODUCTION image for any Rust service (shared, parameterized).
#
# One workspace → one build pattern, parameterized per binary (CLAUDE.md/spec).
# All 11 Rust services build from THIS file; compose passes `BIN` + `APP_PORT`
# per service (see docker-compose.prod.yml). Build a single service directly:
#
#   docker build -f infra/docker/rust-service.Dockerfile \
#     --build-arg BIN=pguard-api-gateway --build-arg APP_PORT=3000 \
#     -t pguard/api-gateway:0.1.0 .
#
# Hardening (CLAUDE.md → Docker rules):
#   ✅ multi-stage: build toolchain + source stay in builder, never in runtime
#   ✅ binary is `strip`ped in the build stage
#   ✅ runtime is debian:bookworm-slim, pinned (no :latest)
#   ✅ runs as non-root `appuser` (uid 10001), never root
#   ✅ EXPOSE only the service's internal port; HEALTHCHECK hits /healthz
#
# Dependency caching: cargo-chef computes a recipe from the whole workspace, so the
# `cook` layer is byte-identical across every service. Built on one host with the layer
# cache intact (compose build, or `--cache-from`), Docker reuses that layer for all 11
# images instead of recompiling deps per service.
# ─────────────────────────────────────────────────────────────────────────────

# Pinned toolchain (workspace rust-version = 1.80; build with a current stable).
ARG RUST_VERSION=1.83
ARG DEBIAN_RELEASE=bookworm

# ── chef: toolchain + cargo-chef, shared by planner & builder ──
FROM rust:${RUST_VERSION}-slim-${DEBIAN_RELEASE} AS chef
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       pkg-config libssl-dev ca-certificates binutils \
    && rm -rf /var/lib/apt/lists/*
RUN cargo install cargo-chef --locked --version ^0.1
WORKDIR /workspace

# ── planner: derive the dependency recipe (cache key is the dep graph, not the src) ──
FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

# ── builder: cook deps (cached & shared across services), then build the one binary ──
FROM chef AS builder
COPY --from=planner /workspace/recipe.json recipe.json
# Compile every dependency once — this layer is identical for all services and is the
# expensive bit; Docker's layer cache reuses it across the whole fleet.
RUN cargo chef cook --release --recipe-path recipe.json
COPY . .
ARG BIN
RUN test -n "${BIN}" || (echo "ERROR: --build-arg BIN=pguard-<svc> is required" && exit 1)
RUN cargo build --release --bin "${BIN}" \
    && strip "target/release/${BIN}" \
    && cp "target/release/${BIN}" /usr/local/bin/pguard-service

# ── runtime: slim, non-root, only the binary + TLS roots + healthcheck client ──
FROM debian:${DEBIAN_RELEASE}-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 appuser \
    && useradd --system --uid 10001 --gid appuser --no-create-home --home /nonexistent --shell /usr/sbin/nologin appuser

COPY --from=builder /usr/local/bin/pguard-service /usr/local/bin/pguard-service

# APP_PORT drives EXPOSE + HEALTHCHECK. The service binds a compiled-in const port;
# pass the matching value per service so the healthcheck targets the right port.
ARG APP_PORT=3000
ENV APP_PORT=${APP_PORT}
EXPOSE ${APP_PORT}

USER appuser

# Shell form so ${APP_PORT} expands from the env at runtime. /healthz is served by
# every service (verified across services/*/src).
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -fsS "http://localhost:${APP_PORT}/healthz" || exit 1

ENTRYPOINT ["/usr/local/bin/pguard-service"]
